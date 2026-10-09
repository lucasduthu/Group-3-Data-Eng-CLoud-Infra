# ADR-0001: Build a cloud data warehouse (BigQuery) with a medallion layout

- **Status:** proposed
- **Date:** 2026-10-08
- **Author:** *(name of the member who defends this ADR)*
- **Lesson:** L01

## Context

Albert's Marketplace runs on **one PostgreSQL database of 25 tables** that
serves both the web shop and the analysts (source: course brief and lecture
diagram). The facts that matter:

- **Analysts query the production tables directly,** the same tables checkout
  writes to, and a nightly CSV export feeds their spreadsheets.
- **Reports disagree on revenue,** because revenue is recomputed in several
  places, from data read at different times.
- **The database also holds passwords and saved cards,** which analysts can
  therefore reach and export.
- **The tables keep only the current state** (order status, prices), so there
  is no history to analyse.
- **The ML team wants units sold per product, per country, per day,** which no
  system produces today.

Constraints: the data is almost entirely **structured** (orders, customers,
products, reviews); the consumers are **SQL analysts, spreadsheets and one ML
team**; **daily** freshness covers every need stated so far; the platform runs
on **Google Cloud** (course project, region `europe-west1`); the group has
SQL and Python skills but no team to run a cluster.

## Options considered

| Option | For | Against |
|---|---|---|
| **Data warehouse** | Fits structured data and SQL users; one governed place for metrics; managed service, nothing to operate | Less suited to large unstructured data; cost grows with scanned data if queries are careless |
| **Data lake** | Cheap storage; takes any format | No schema, no single definition of revenue, weak access control on files; analysts would need Spark or similar; risk of a "data swamp" |
| **Two-tier (lake + warehouse)** | Raw files kept cheaply, curated data in the warehouse | Two systems to keep in sync, two copies of the data, two places to secure; overhead not justified by 25 structured tables |
| **Lakehouse** | One copy on open formats; serves both BI and ML on files | Built for large mixed workloads (logs, images, big ML training sets) we do not have; more components and skills (table formats, Spark) for no current gain |

## Criteria

| Criterion | Warehouse | Lake | Two-tier | Lakehouse |
|---|---|---|---|---|
| **Workload** (BI, SQL reporting, one aggregated ML table) | ++ | − | + | + |
| **Data types** (structured tables, a little review text) | ++ | + | + | + |
| **Freshness** (daily is enough) | ++ | + | + | + |
| **Team and skills** (SQL, Python, no platform team) | ++ | − | − | − |
| **Cost** (small volume, pay per use) | + | ++ | − | − |
| **Governance** (exclude cards and passwords, one definition of revenue) | ++ | −− | + | + |

The warehouse wins or ties on every criterion except raw storage cost, which
is not a deciding factor at this volume.

## Decision

We build a **cloud data warehouse on BigQuery**, organised in **bronze, silver
and gold** layers. Raw extracts land in a **Cloud Storage bucket as the bronze
landing zone** only: no consumer reads those files directly; everything is
served from BigQuery.

## Consequences

**Easier**
- The shop's database is no longer queried by analysts: analytics stops
  competing with checkout.
- Revenue and units sold get **one definition**, written and tested once in
  gold.
- Cards and passwords are **excluded at ingestion**, so they never reach the
  analytical platform.
- History becomes possible: each extract is kept, so past prices and statuses
  are no longer lost.

**Harder**
- Data in the warehouse is **as fresh as the last load** (daily), not live.
- We now own pipelines: ingestion, transformations, tests and scheduling must
  run every day and alert when they fail.
- Analysts must move their queries and spreadsheets onto gold tables.

**To watch**
- **Query cost:** BigQuery bills by data scanned, so partition large tables by
  date and avoid `SELECT *`.
- **Scope creep:** if consumers start reading raw files in Cloud Storage
  directly, we have drifted into a two-tier architecture without deciding it.
- **New data types:** if logs, images or large ML training sets arrive, revisit
  this decision (lakehouse) in a new ADR.
