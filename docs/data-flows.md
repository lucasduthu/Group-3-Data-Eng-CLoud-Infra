# Data flows

One row per flow: where the data comes from, what it is, who uses it, how often
it moves, and in which format. This is the platform **as it exists today**,
before any change by the data team.

| # | Source | Data | Consumer | Frequency | Format | Notes |
|---|---|---|---|---|---|---|
| 1 | Web shop (customers) | Orders, order lines, payments | PostgreSQL (shop database) | Real time, per transaction | SQL inserts and updates | Checkout writes here; rows are updated in place (order status) |
| 2 | Web shop (customers) | Customer accounts, passwords, saved cards | PostgreSQL | Real time | SQL rows | Personal and payment data; same database as everything else |
| 3 | Web shop (customers) | Product reviews: rating and free text | PostgreSQL | Real time | SQL rows, free text | Free text may contain personal data |
| 4 | Back office *(assumption)* | Products, prices, categories | PostgreSQL | Ad hoc | SQL rows | Prices are overwritten, so past prices are lost |
| 5 | PostgreSQL | Any of the 25 tables | Analysts | Ad hoc, business hours | SQL query results | Analysts query the production tables directly |
| 6 | PostgreSQL | Nightly export: orders and revenue | Business spreadsheets | Daily batch, overnight | CSV | Leaves the database with no access control |
| 7 | Spreadsheets and analyst queries | Revenue reports | Management | Recurring *(assumption: weekly / monthly)* | Spreadsheets, slides | Reports disagree on revenue |
| 8 | *Not built yet* | Units sold per product, per country, per day | ML team | Daily (requested) | None today | The need the platform must serve first |

## Under the matrix, answer

**Which flows carry personal data?**
Flows 1, 2 and 3 write personal data (names, addresses, emails, passwords,
saved cards, review text). Flows 5 and 6 then carry it out to analysts and to
CSV files, because they read the same tables. Flow 8 must not: units per
product, country and day needs no customer identifier.

**Which consumers read directly from a system that also serves customers?**
The analysts (flow 5) query the PostgreSQL database that checkout writes to,
and the nightly CSV export (flow 6) also runs against it. Both compete with the
shop for the same database.

**Where could the same figure be computed twice, in two different ways?**
Revenue. It is computed in analysts' SQL against live tables (flow 5) and in
spreadsheets from the nightly CSV snapshot (flows 6 and 7). The two read the
data at different times and can apply different rules (gross or net of VAT,
refunds, cancelled orders). This is why the reports disagree. Units sold per
product is at the same risk as soon as the ML team builds its own version.
