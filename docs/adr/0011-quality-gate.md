# ADR-0011: Make the dbt test a real gate: a failing test stops the marts from being rebuilt

- **Status:** accepted
- **Date:** 2026-11-06
- **Author:** Group (found by Lucas during step 7, reviewed by Mathilde)
- **Lesson:** L07 (follows ADR-0005 and ADR-0007)

## Context

The DAG must not publish wrong numbers. In step 5 we wrote that the
relationships test on `order_items.p_id` "blocks the pipeline before the marts
are built". In step 7 we tested it with a poison row: an order line pointing to
a product that does not exist (`p_id = POISON-ORPHAN`), injected for 3 August.

A relationships test has two parents (`stg_order_items` and `stg_product`).
`dbt build` only makes a model wait for a test if the model descends from all
the test's parents. No model below `stg_order_items` depended on `stg_product`,
so the test ran in parallel with the marts and blocked nothing.

## Options considered

| Option | For | Against |
|---|---|---|
| A. `dbt run` then `dbt test` | The run goes red and the alert fires | The poison row is already in the mart (1 row) when the test fails: an alarm, not a gate |
| B. `dbt build`, as in the course guide | One command, tests run with models | Same result: poison row in the mart (1 row), because the test has two parents |
| **C. `dbt build` + `depends_on` `stg_product` in `int_order_items`** (ours) | The failing test skips the whole branch: 0 poison rows in the mart, the mart keeps its last good state | A dependency written by hand that someone could remove without knowing why |

## Criteria

Whether a wrong row can reach the table the dashboard reads. All three options
turn the run red and send the alert; only one keeps the mart clean.

## Decision

Keep `dbt build` and add `-- depends_on: {{ ref('stg_product') }}` to
`int_order_items` (commit `cfed22c`), so the relationships test runs before the
marts and a failure skips them.

## Consequences

- Proof with the same poison row: A gives 1 row in the mart, B gives 1, C gives
  0 (ERROR 1, SKIP 20; `fct_order_items` not rewritten, same `last_modified`).
- The image `emmaneum/g03-dbt:2026-11-06-cfed22c` carries the fix.
- Single-parent tests (`not_null`, `unique_combination_of_columns`) already
  blocked correctly.
- To watch: any new two-parent test needs the same check, or it will only be an
  alarm.

## What would change our mind

- If dbt changes how it attaches multi-parent tests, the `depends_on` line may
  become unnecessary.
- If we need to publish partial results when one branch fails, we would split
  the marts by branch.

## Sources

- `notes/step7.md` section 7.6
- `dbt/models/intermediate/int_order_items.sql`
- commit `cfed22c`
