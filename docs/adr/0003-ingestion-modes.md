# ADR-0003: Ingest with our own extractors and a Kafka consumer, without a connector

- **Status:** proposed
- **Date:** 2026-11-03
- **Author:** Mathilde
- **Lesson:** L03

## Context

Step 3 asks for three automatic roads into the bronze bucket
`gs://albert-de-msc2-26-g03-bronze`: a connector, a custom extractor and a
Kafka consumer with a dead-letter queue, and no secret column (`pwd`,
`card_no`, `cvv`) in bronze. Facts from `notes/step3.md` (2026-11-03):

- **Source database:** PostgreSQL on a laptop, 29 tables, `wal_level = logical`.
  `orders` holds about 223 000 rows with an increasing integer `order_id`.
  `customer` (130 786 rows) has a random string key `c_id`, and contains
  `pwd`; `payment_details` contains `card_no` and `cvv`.
- **Clickstream:** topic `clickstream`, `schema_version` 1, three event types
  whose fields differ (`order_placed` has `items` and no `p_id` or `qty`).
- **Permissions:** the Airbyte destination needs a service account
  (`g03-airbyte-writer`) with an HMAC key. In the shared project
  `data-engineering-i1` our accounts cannot create a service account or read
  the project IAM (`iam.serviceAccounts.list` and `getIamPolicy` denied).

## Options considered

| Option | For | Against |
|---|---|---|
| **Airbyte connector, PostgreSQL to GCS** (route 1) | No code; many tables at once; CDC possible since `wal_level = logical` | Needs a service account and an HMAC key we are not allowed to create; secret columns must be unticked by hand on each stream |
| **Own extractors in Python** (route 3) | Raw SQL with an explicit column list, so a secret column is never copied by default; cursor and retries we can test; runs with our own gcloud login, no new service account | We maintain the code; no CDC: updates and deletes are not seen |
| **Kafka consumer, offsets committed before the write** | Simpler loop | At-most-once: a failed write loses the batch (the `l11-review` lab trap) |
| **Kafka consumer, offsets committed after the write** | At-least-once: a failure gives duplicates, never a loss | Duplicates to remove in silver on `event_id` |

## Criteria

| Criterion | Airbyte connector | Own extractors + consumer (commit after write) |
|---|---|---|
| **Feasible with our permissions** | −− (service account refused) | ++ |
| **Secret columns kept out** | + if every stream is configured by hand | ++ explicit column list, `payment_details` not extracted |
| **Failure behaviour we can prove** | − (inside the tool) | ++ retry, cursor and DLQ tested |
| **Changes captured** | ++ with CDC | − inserts only for `orders`, daily snapshot for `customer` |
| **Effort** | ++ | − |

Permissions decide it: the connector cannot be deployed in the shared project.

## Decision

We ingest with **our own extractors**: `orders` incrementally on `order_id`
with the cursor stored in the bucket, `customer` as a daily snapshot of an
explicit column list without `pwd`. Clickstream goes through **our consumer**,
which validates each event against a JSON Schema, sends invalid ones to
`bronze/_dlq/` and commits offsets only after the write.

## Consequences

**Easier**
- No secret column in bronze: `g03_bronze.customer_extract_external` has no
  `pwd` (`ingestion/proof/customer_columns.txt`), and `payment_details` is not
  read.
- Failures are visible and tested: 4 retries then abort with the cursor
  unchanged; 3 broken events found in `g03_bronze.clickstream_dlq`
  (`ingestion/proof/dlq.txt`) while the consumer kept running.
- The DAG of step 7 can replay a day: interval mode writes one fixed path per
  day.

**Harder**
- **Updates and deletes on orders are not captured**, and customer changes
  within a day are lost.
- Silver must remove duplicates (`order_id`, `event_id`), the price of
  at-least-once.
- Only `orders` and `customer` are extracted; other tables need their own
  extractor.

**To watch**
- If we get the right to create a service account, revisit the connector with
  CDC in a new ADR.
- Clickstream Parquet types: `qty` and `order_id` were `double` before
  2026-11-03 18:11 UTC and `int64` after (see `docs/ingestion-failure-modes.md`).
