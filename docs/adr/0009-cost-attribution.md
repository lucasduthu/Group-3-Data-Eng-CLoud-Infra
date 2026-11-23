# ADR-0009: Attribute cost with labels set by Terraform, and cap each query

- **Status:** accepted
- **Date:** 2026-11-10
- **Author:** Laura
- **Lesson:** L09

## Context

The project `data-engineering-i1` is shared by the whole class, and the billing account belongs to the
school. We have no access to the budget or the bill (`billing.resourcebudgets.read` refused). We still
need to know what our group spends and on what.

Measured over 30 days: 1,283 queries touched a `g03_` dataset, 5.7 GiB read and 14.2 GiB billed.
BigQuery bills at least 10 MiB per query, so we pay about 2.5 times what we read. One day,
6 November (Airflow runs and back-fill), is 70% of the billed bytes.

## Options considered

| Option | For | Against |
|---|---|---|
| **Labels declared in Terraform + `maximum_bytes_billed`** (ours) | Cheap, versioned, reviewed in PRs; storage attributed from day one | Labels on a dataset do not follow the queries: compute stays unattributed |
| One GCP project per team | Clean bill per team, no labels needed | The school owns the project; not ours to decide |
| Labels on every query job | Attributes compute, the main cost | Needs dbt and the load script changed and a new image |
| Split the bill by hand | Nothing to build | Guesswork; nobody can check it |

## Criteria

What we are allowed to do in a shared project, which cost is largest (compute), and how much effort
each option costs.

## Decision

Declare four common labels in Terraform on our 4 resources (`team=g03`, `course`, `environment`,
`managed_by`, plus `component`), label the Terraform state bucket by hand (`managed_by=manual`, it
cannot manage itself), keep the 1 GB per-query cap in dbt, and record that compute is not yet
attributed.

## Consequences

- Proof: plan 0 to add, 4 to change, 0 to destroy, then No changes.
- Limit measured: 0 of 1,283 queries carry `team=g03`. 88% carry only `dbt_invocation_id`, added by
  dbt; the other 155 have no label.
- Optimisation measured: `fct_order_items` partitioned by month and clustered by `p_id` reads
  11,439,680 then 1,000,888 bytes (11.4 times less), same results. But billed bytes go from 11,534,336
  to 10,485,760 because of the 10 MiB minimum: no money saved at our size.
- Labels only cover spending from 10 November; earlier spending cannot be attributed.
- Next step: make dbt set `team=g03` on its jobs (`query-comment` with `job-label`). That covers 88% of
  queries but needs the dbt image rebuilt.

## What would change our mind

- If we get our own project or billing access, use the bill directly and a budget alert sent to Laura.
- If a query reads more than 10 MiB on a regular basis, the partitioning gains start to show on the bill.

## Sources

- `notes/step9.md`
- `infra/terraform/locals.tf`
- `warehouse/finops/01` to `06`
- `notes/step9-bytes-per-day.txt`
