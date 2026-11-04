# Ingestion failure modes

What happens when each road into bronze breaks, what we do about it, and what
we do not handle. Sources: the code in `ingestion/` and the measurements in
`notes/step3.md` (2026-11-03). **Tested** means we caused the failure and
recorded the output; **by design** means it follows from the code but was not
caused on purpose.

Delivery guarantee for every road: **at-least-once**. A failure can produce a
duplicate, never a silent loss of data that was already read. Duplicates are
removed in silver (`order_id` for orders, `event_id` for clickstream).

## Orders extractor (`ingestion/extract_orders.py`)

Incremental on `order_id`; the cursor lives in the bucket at
`bronze/_state/extract_orders.json`.

| Failure | What happens | Status |
|---|---|---|
| Database unreachable | 5 attempts, waits of 2, 4, 8, 16 s, then the run aborts. The cursor does not move (223 174 before and after). | **Tested** |
| Crash after the Parquet write, before the cursor write | The next run reads the same batch again: duplicate rows in bronze, removed in silver. | By design |
| Bucket write fails | The exception stops the run before the cursor write; the next run starts from the same cursor. | By design |
| Backlog larger than `BATCH_LIMIT` (50 000) | Caught up over several runs, or in one run with a higher limit. Run 1: 50 000 rows; run 2 with `BATCH_LIMIT=250000`: 173 118 rows; run 3: 7 new rows. | **Tested** |
| Machine or container restarts | The cursor is in the bucket, not on the machine, so the next run resumes where the last one stopped. | By design |
| Interval mode run twice for the same day | Same object path (`extract_date=<day>/orders.parquet`), so the second run replaces the first. | By design, not run yet (step 7) |

## Customer extractor (`ingestion/extract_customer.py`)

Full snapshot per day with an explicit column list (`c_id, fname, lname,
phone, email`).

| Failure | What happens | Status |
|---|---|---|
| Database unreachable | Same retry policy as the orders extractor, then abort; nothing written. | By design |
| A new column appears in `customer` (for example a secret) | Not extracted: only the listed columns are selected. Adding it to bronze is a code change and a review. | By design |
| Run twice the same day | Fixed path per day, the second run replaces the first. | By design |
| `pwd` reaching bronze | Excluded by the column list. The BigQuery table `g03_bronze.customer_extract_external` has no `pwd` column (`ingestion/proof/customer_columns.txt`). | **Tested** |

## Clickstream consumer (`ingestion/consume_clickstream.py`)

Offsets are committed only after the batch (valid and rejected events) is
written to the bucket.

| Failure | What happens | Status |
|---|---|---|
| Invalid JSON, wrong type, unknown `schema_version` | The message goes to `bronze/_dlq/clickstream/` with its raw text, the reason and the rejection time; the consumer keeps running. 3 broken events sent, 3 rows in `g03_bronze.clickstream_dlq` (`ingestion/proof/dlq.txt`), and the consumer wrote 2 more batches afterwards. | **Tested** |
| Invalid `event_time` (for example `"hier"`) | Rejected to the DLQ. Before `rfc3339-validator` was added, it was accepted and would have created a `dt=hier` folder. | **Tested** (unit test of `validate`) |
| Stop with Ctrl-C or SIGTERM | The last batch is written, then offsets are committed. Exit code 0. | **Tested** |
| Crash after the write, before the commit | The batch is read again on restart: duplicates, removed in silver on `event_id`. | By design |
| Bucket write fails | No commit, so the events stay in Kafka and are read again after restart. | By design |
| Late event | Written as a new file in the folder of the day it happened (`dt` = date of `event_time`); no existing file is rewritten. | By design |
| Kafka error on a message | Logged, the loop continues. | By design |

## Not handled

- **Updates and deletes on orders already read.** The cursor only sees new
  `order_id` values, so a changed or cancelled order keeps its first version in
  bronze.
- **An order committed with an `order_id` below the cursor** (a slower
  transaction that took a lower id) is skipped.
- **Changes to a customer during the day.** The snapshot keeps the state at run
  time only.
- **Parquet types written before 2026-11-03 18:11 UTC.** `qty` and `order_id`
  are `double` in the first 4 clickstream files and `int64` afterwards. A
  batch without any `added_to_cart` or `order_placed` event has no `qty` or
  `order_id` column at all. A table over all of `bronze/clickstream/` must
  read these columns as `FLOAT64` or declare its schema.
- **The Airbyte connector is not deployed** (see ADR-0003): `card_no` and `cvv`
  are kept out because `payment_details` is not extracted at all.
