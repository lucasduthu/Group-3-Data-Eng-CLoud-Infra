# ADR-0002: Store bronze as Parquet in Cloud Storage, partitioned by month for orders

- **Status:** accepted
- **Date:** 2026-11-03
- **Author:** Laura
- **Lesson:** L02

## Context

Step 2 lands the raw export of Albert's Marketplace in `gs://albert-de-msc2-26-g03-bronze` (project
`data-engineering-i1`, europe-west1). The export is 27 CSV files, 197 MB in total. Two tables hold
secrets and are kept out of bronze: `customer` (`pwd`) and `payment_details` (`card_no`, `cvv`). That
leaves 25 tables, of which 5 are empty (`cart`, `cart_items`, `daily_deals`, `discount`, `returns`) and
produce no file: 20 tables are in the bucket.

The queries we expect almost always filter on a month of orders (monthly revenue, daily demand over a
period). `orders` and `order_items` cover 37 months. `order_items` has no date of its own, so it takes
the month of its order. The other tables have no useful business date.

## Options considered

| Option | For | Against |
|---|---|---|
| **Parquet (snappy), `orders` and `order_items` by month, others by load date** (ours) | Half the size of CSV, columnar reads, a month filter opens 1 folder out of 37 | A conversion step; `order_items` needs the order date joined in before writing |
| CSV as exported | No conversion, readable by anyone | 197 MB instead of 99 MB, every query reads every column, no types |
| Parquet, one folder per day | Finer pruning | About 1,100 folders of a few KB each: many tiny files, slower listing, no gain at our size |
| Parquet, not partitioned | Simplest layout | Every query reads all 3.12 MB of `order_items`, whatever the date filter |

## Criteria

Cost of reading (bytes scanned), storage size, and how easily the next layers can read it. At 197 MB
the volume is small, so the layout has to stay simple: we picked the coarsest partition that matches
how the data is queried.

## Decision

Store the bronze tables as Parquet with snappy compression. Partition `orders` and `order_items` by
order month (37 folders each), and the other tables by load date.

## Consequences

- Easier: 197 MB of CSV became 99 MB of Parquet (92 objects: 37 + 37 + 18 single-file tables). A query
  on one month of `order_items` read 77.29 KB instead of 3.12 MB (about 40 times less, cache off).
- Easier: a lifecycle rule moves the export to Nearline after 90 days and deletes the DLQ after 90 days.
- Harder: `order_items` must be joined to `orders` before writing, to get its month.
- To watch: the bucket only had the roles inherited from the shared project, so every viewer in the
  class could read it. Handled in step 10 (viewer read removed).
- To watch: `bq` runs in the US by default; every command needs `--location=europe-west1`.

## What would change our mind

- If daily queries on a single day become the main workload and a month grows past about 1 GB, move
  `orders` and `order_items` to daily partitions.
- If the professor allows `customer` and `payment_details` in bronze, they come in with secrets
  removed, not as-is.

## Sources

- `notes/step2.md` (sizes, counts, partition measure)
- `notes/step2-sizes.csv`
- `notes/step2-lifecycle-live.json`
