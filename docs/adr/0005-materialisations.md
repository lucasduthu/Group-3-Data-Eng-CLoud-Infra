# ADR-0005: Build staging and intermediate models as views, marts as tables, with the grain tested

- **Status:** accepted
- **Date:** 2026-11-04
- **Author:** Mathilde
- **Lesson:** L05

## Context

dbt turns the 7 native warehouse tables into the gold layer that answers the
business question: units sold per product, per country, per day. Models live in
three layers: staging (rename, cast, clean), intermediate (joins and
aggregates), marts (what the dashboard reads). Each layer can be a view
(computed at query time) or a table (stored, rebuilt at each run).

Two facts drive the choice. The marts are read every day by the dashboard, and
the data only changes once a day. Reviews multiply rows if they are joined to
order lines directly: one order line with three reviews becomes three lines,
and revenue is counted three times.

## Options considered

| Option | For | Against |
|---|---|---|
| **Staging and intermediate as views, marts as tables** (ours) | No storage for the cleaning layers, always in step with the source; marts are fast and cheap to read | A full rebuild at each run; marts are only as fresh as the last run |
| Everything as tables | Every layer can be inspected and is fast to read | Stores the same data three times and rebuilds everything at each run |
| Everything as views | Nothing to store or rebuild | Every dashboard query re-runs all the joins and pays the scan again |
| Incremental marts | Only new rows are processed | We must define what "new" means for late rows; not needed at 408,560 lines |

## Criteria

Read cost for the dashboard, storage, freshness (daily is enough), and how easy
it is to prove the numbers are right.

## Decision

Staging and intermediate are views, marts are tables (`dbt/dbt_project.yml`).
Reviews are aggregated per product before the join (`int_product_ratings`), and
the grain of each mart is written as a test that fails the build.

## Consequences

- Grains tested: `fct_order_items` one row per (`order_id`, `p_id`);
  `fct_daily_demand` one row per (`p_id`, `country`, `order_date`);
  `dim_product` per `p_id`; `dim_date` per `date_day`.
- Proof: 408,560 order lines in the source and 408,560 rows in
  `fct_order_items`; 1,386,640 units in both `order_items` and
  `fct_daily_demand`. Build: PASS 46, WARN 2, ERROR 0.
- The defect queries found no duplicates, so the "just in case" deduplications
  were removed. The grain tests stop the pipeline if a duplicate appears later.
- 30 lines have a price of 0 (catalogue prices under 0.005, rounded down). They
  are kept and flagged (`is_zero_price_anomaly`, warn test), not replaced.
- Since step 9, `fct_order_items` is also partitioned by month and clustered by
  `p_id`. The dbt image used by Airflow must be rebuilt to keep this.

## What would change our mind

- If a consumer needs data fresher than daily, move the marts to incremental
  and decide how to treat late rows.
- If the marts grow past what a daily full rebuild can do in the run window,
  same answer.

## Sources

- `notes/step5.md`
- `dbt/dbt_project.yml`
- `docs/lineage.md`
- `notes/step5-defects-results.txt`
