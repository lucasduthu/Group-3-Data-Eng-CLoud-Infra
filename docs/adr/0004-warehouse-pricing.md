# ADR-0004: Load the working set as native BigQuery tables and use monthly partitioning for date-filtered queries

- **Status:** accepted
- **Date:** 2026-11-04
- **Author:** Emma Neumayer
- **Lesson:** L04

## Context

The reporting working set contains 7 tables: orders, order_items,
review, product_reviews, product, customer_shipping and shipping_details.

These tables were available as external tables over the bronze Parquet
files. We loaded them as native tables in g03_warehouse to provide the
working set for analytics and dbt, while keeping the bronze sources.

We then compared queries on the unpartitioned native tables with queries
on monthly partitioned variants of orders and order_items. The result
cache was disabled and the date filters were kept identical.

The measurements below demonstrate the effect of partitioning on native
tables. They do not measure a performance difference between external
and native tables.

## Options considered

| Option | For | Against |
|---|---|---|
| Keep the working set as external tables | Avoids an additional native copy | Does not provide the native partitioning and clustering layout tested here |
| Load the working set as native tables and test monthly partitioning | Provides native tables for dbt; reduces bytes processed for Q1 and Q2 | Duplicates storage between bronze and warehouse; requires explicit refreshes |
| Use daily partitioning | Allows finer date-based pruning | Creates more small partitions for this dataset |
| Apply clustering systematically | Can reduce blocks scanned for selective filters | No additional scan reduction observed for Q2 and Q3 |
| Use materialized aggregates | Precomputes repeated aggregations | Adds storage and refresh costs; the weekly variant loses daily detail and scanned more bytes in the tested query |

## Criteria

We considered bytes processed, bytes billed, storage duplication,
maintenance effort and the required temporal detail.

Monthly partitioning reduced bytes processed substantially for the
date-filtered queries. Clustering provided no additional scan reduction
in the tested queries.

The daily materialized view provided a smaller additional reduction,
but we did not establish a net financial benefit after storage and
refresh costs. The weekly variant was not retained as the preferred
option for the measured workload.

## Decision

Load the 7-table working set as native BigQuery tables, keeping the
external bronze sources and the initial native tables as the baseline.

Use monthly partitioned variants of orders and order_items for the
date-filtered experiments. Apply a maximum_bytes_billed limit to queries
and distinguish bytes processed from bytes billed when assessing gains.

## Consequences

- Q1 bytes processed decreased from 9,805,440 to 3,373,224, a reduction of approximately 65.60%
- Q2 bytes processed decreased from 11,439,680 to 1,000,888, a reduction of approximately 91.25%
- Adding clustering to the partitioned order_items variant did not further reduce Q2 bytes processed
- Clustering did not reduce Q3 bytes processed in the tested workload
- The daily materialized view reduced Q2 bytes processed by a further 12.46% compared with the partitioned table
- The weekly materialized-view experiment returned identical results for the comparison query but processed more bytes than the corresponding weekly test table
- Q2 bytes billed decreased from 11,534,336 to 10,485,760, approximately 9.09%, despite the much larger reduction in bytes processed
- A query exceeding the tested 10 MiB billing cap was refused
- Native tables and experimental variants add storage and maintenance work; refreshing bronze files does not automatically refresh the native warehouse tables

The billing cap is a limit on an individual query, not a total project
budget. The experiments do not establish an equivalent reduction in
the project's actual bill.

### Conditions for reconsideration

Reassess this decision if data volume, query frequency, product-filter
selectivity or temporal-detail requirements change.

At higher volumes, measure partition sizes, execution time, slot-ms,
storage and materialized-view refresh costs before choosing a layout.
Queries without a suitable date filter may not benefit from partition
pruning.

### Evidence

- [Warehouse tuning report](../warehouse-tuning.md)
- [Query metrics](../../notes/step4-query-metrics.csv)
- [BigQuery jobs exported for Step 4](../../notes/step4-bigquery-jobs-2026-11-03.csv)