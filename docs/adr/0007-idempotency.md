# ADR-0007: Make each daily run idempotent: the day comes from Airflow, the load is a MERGE on order_id

- **Status:** accepted
- **Date:** 2026-11-06
- **Author:** Lucas
- **Lesson:** L07

## Context

The DAG `marketplace_g03_daily` runs once a day: `extract_orders` (Postgres to
Parquet), `load_orders` (Parquet to `g03_warehouse.orders`), `dbt_build`. Each
task is a Docker image run by the DockerOperator, with 2 retries and a Slack
alert on failure.

A run will be retried, replayed by hand, and back-filled for past days. If a
replay adds rows instead of replacing them, revenue is counted twice and nobody
sees it, because the run is green.

## Options considered

| Option | For | Against |
|---|---|---|
| **Day from `data_interval`, per-day stage table, MERGE on `order_id`** (ours) | A replay rewrites the same day; back-fill is replaying old days | A MERGE costs more than an append; one stage table per day to clean up |
| INSERT (append) | Simplest, cheapest load | Every retry or replay duplicates the day |
| Day from `date.today()` | No templating | A replay of 1 August loads today instead; back-fill is impossible |
| Delete the day then insert | Idempotent too | Two statements: a crash between them leaves the day empty |

## Criteria

Correctness after a retry or a replay, ability to back-fill, and cost. At our
volume (about 160 orders a day) the MERGE cost does not matter.

## Decision

Each run receives its day from Airflow (`data_interval`,
`CronDataIntervalTimetable`), loads it into its own stage table
`orders_stage_YYYYMMDD`, and MERGEs it into `orders` on `order_id`. One run at
a time (`max_active_runs` 1).

## Consequences

- Proof: the same day run twice gives 163 rows, then 163 (n = distinct
  `order_id`).
- Back-fill 1 to 7 August: predicted 163 / 147 / 181 / 154 / 161 / 172 / 145 =
  1,123 from Postgres before running; actual counts identical, 0 gap, total
  stays 222,644.
- Failure found: a scheduled run and a back-fill run shared one stage table and
  raced; one run replaced the other's stage between load and MERGE. Fixed with
  one stage per day. With two non-empty days the race would have merged the
  wrong day, in green.
- Not yet proven: the fix under 4 runs in parallel (the machine could not keep
  up). Until then, back-fill with `--max-active-runs 1`.
- In Airflow 3.3, plain `"@daily"` gives an empty interval; the extractor would
  have read 0 rows in a green run. Hence the explicit timetable.

## What would change our mind

- If late orders arrive days after their order date, the run must also
  reprocess a window of past days, not only its own.
- If volume grows to the point where a MERGE per day is slow, partition
  `orders` by day and replace the day's partition instead.

## Sources

- `notes/step7.md`
- `notes/step7-backfill.md`
- `orchestration/dags/marketplace_g03.py`
- `docs/runbooks/failed-run.md`
