# Acceptance criteria: daily-demand star schema (step 5)

What must be true of the data before the marts are handed to the ML team and
the dashboard. One criterion per row, written as a business rule, with the dbt
test that checks it.

- **error:** the test fails `dbt build`. In step 7, a staging failure stops the
  pipeline before any mart is rebuilt.
- **warn:** the build goes on, and the count is shown in the run summary.

Last run: `dbt build` on 2026-11-04 (16:20 UTC), from the working copy, after
Emma's review of PR #4. 48 nodes: PASS=46, WARN=2, ERROR=0, SKIP=0.
`dbt source freshness` the same day: 1 error, 5 warn (see "Source freshness").

## Orders and order lines

| # | Criterion | Test | Severity | Last result |
|---|---|---|---|---|
| 1 | Every order has an identifier, and no order appears twice. | `unique` + `not_null` on `stg_orders.order_id` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L7) | error | Pass |
| 2 | Every order has an order date. | `not_null` on `stg_orders.order_date` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L9) and on `fct_order_items.order_date` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L18) | error | Pass |
| 3 | A product appears at most once in an order. | `unique_combination_of_columns (order_id, p_id)` on `stg_order_items` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L14) and on `fct_order_items` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L6) | error | Pass |
| 4 | Every order line refers to a product in the catalogue. | `not_null` + `relationships → stg_product` on `stg_order_items.p_id` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L19); `relationships → dim_product` on `fct_order_items.p_id` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L11) | error | Pass |
| 5 | An order line has at least one unit. | `accepted_range (min 1)` + `not_null` on `fct_order_items.qty` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L25) | error | Pass |
| 6 | An order line's revenue is `qty * price_at_purchase`, never negative and never missing. 0 is allowed (see the decision below). | Singular test [`assert_line_revenue_is_positive.sql`](../dbt/tests/assert_line_revenue_is_positive.sql) (`line_revenue < 0 OR line_revenue IS NULL`) + `not_null` on `fct_order_items.line_revenue` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L33) | error | Pass |
| 6b | Every line sold at a price of 0.00 is flagged, and listed at every build. | `not_null` on `fct_order_items.is_zero_price_anomaly` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L36); singular test [`assert_no_zero_price_lines.sql`](../dbt/tests/assert_no_zero_price_lines.sql) | **warn** | **WARN 30**, see the decision below |
| 7 | Every order date is a day of the calendar. | `relationships → dim_date` on `fct_order_items.order_date` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L18) | error | Pass |
| 8 | Every order line has a country. | `not_null` on `fct_order_items.country` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L31) | error | Pass (see gap C) |

## Daily demand (the ML table)

| # | Criterion | Test | Severity | Last result |
|---|---|---|---|---|
| 9 | There is one figure per product, per country, per day. | `unique_combination_of_columns (p_id, country, order_date)` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L48); `unique` + `not_null` on `demand_key` ([L52](../dbt/models/marts/_marts.yml#L52)) | error | Pass |
| 10 | Every daily figure has a number of units. | `not_null` on `fct_daily_demand.units` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L54) | error | Pass |
| 11 | Every daily figure refers to a product in the catalogue. | `relationships → dim_product` on `fct_daily_demand.p_id` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L56) | error | Pass |

## Products, reviews, customers, calendar

| # | Criterion | Test | Severity | Last result |
|---|---|---|---|---|
| 12 | A product appears once in the catalogue. | `unique` + `not_null` on `stg_product.p_id` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L43) and on `dim_product.p_id` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L66) | error | Pass |
| 13 | A product has a name. | `not_null` on `dim_product.product_name` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L68) | **warn** | **WARN 6**, see the decision below |
| 14 | A review appears once, and its rating is between 1 and 5. | `unique` + `not_null` on `stg_review.review_id`, `accepted_range 1–5` on `stg_review.rating` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L31) | error | Pass |
| 15 | A product's average rating is between 1 and 5 when it has reviews. | `accepted_range 1–5` on `dim_product.avg_rating`, `where avg_rating IS NOT NULL`, in [`_marts.yml`](../dbt/models/marts/_marts.yml#L73) | error | Pass |
| 16 | A customer has a single default address. | `unique` + `not_null` on `stg_addresses.c_id` in [`_staging.yml`](../dbt/models/staging/_staging.yml#L49) | error | Pass |
| 17 | A calendar day appears once. | `unique` + `not_null` on `dim_date.date_day` in [`_marts.yml`](../dbt/models/marts/_marts.yml#L85) | error | Pass |

## Decisions

### 30 order lines with a price of 0.00: keep the price paid, flag the lines

- **What we saw:** the first `dbt build` failed criterion 6 (then `line_revenue
  <= 0`) on 30 lines. All of them have `price_at_purchase = 0.00`, on 5
  products.
- **Why:** on all 408,560 lines, `price_at_purchase` is exactly
  `ROUND(product.price, 2)`. These 5 products have a catalogue price below
  0.005 (from 0.0004 to 0.0047), so rounding to two decimals turns it into
  0.00.
- **Decision (after Emma's review of PR #4):**
  - The price is **not replaced**. `line_revenue = qty * price_at_purchase`,
    so it is 0 on these 30 lines. No estimated amount is created.
  - `is_zero_price_anomaly` (boolean, TRUE when `price_at_purchase = 0`) is
    added in `int_order_items` and carried to `fct_order_items`.
  - The lines are kept, so units sold still match the source: 1,386,640 in
    `order_items` and in `fct_daily_demand`.
  - Criterion 6 now fails only on a negative or NULL revenue (error). The 30
    lines are reported by `assert_no_zero_price_lines` (warn), so the count
    shows in every build summary.
- **Not chosen:**
  - Taking the unrounded catalogue price (the first fix): the revenue would no
    longer be what was paid, and the defect would disappear from the marts.
  - Dropping the lines: units would be lost from the ML table.
  - Setting the price to NULL: it would break criterion 6 and hide the units'
    revenue in sums.
- **When it should become an error:** if the count grows above 30, or if a
  line has a price of 0.00 for a product whose catalogue price is at least
  0.005 (that would no longer be a rounding effect).
- **Open point:** catalogue prices below one cent look wrong for these
  products. This is for the source owner to check.

### 6 products without a name: warn, not error

- **What we saw:** 6 of 42,858 products have `p_name` NULL. None is empty or
  blank (defect query 6, `notes/step5-defects-results.txt`).
- **Decision:** the name stays NULL, and the `not_null` test on
  `dim_product.product_name` has severity `warn`.
- **Why:** a missing name does not change units or revenue. Making it an
  error would block the ML table for a label. Making up a name would hide the
  defect from the source owner.
- **When it should become an error:** if the dashboard has to show every
  product by name, or if the count grows.

## Source freshness

Checked by `dbt source freshness`, not by `dbt build`. Thresholds for every
checked table: warn after 1 day, error after 2 days. The step 7 DAG loads once
a day, so 1 day means one missed run and 2 days means the marts are out of
date.

| # | Criterion | Load column | Last result (2026-11-04) |
|---|---|---|---|
| 18 | Orders were loaded less than a day ago. | **Proxy:** `order_date`, the order date, not the load date. `orders` has no load column. | **ERROR STALE**: last order 2026-09-14, 51.7 days old |
| 19 | `review`, `product_reviews`, `product`, `customer_shipping` and `shipping_details` were loaded less than a day ago. | `ingest_date`, the real load date (Hive partition from bronze) | **WARN**: loaded 2026-11-03, 1.7 days old |

- `order_items` has no check: it has no load column and is reloaded together
  with `orders`.
- Both results are expected while the data is the course's historical
  extract. They should pass once the step 7 DAG loads recent days. Output:
  [`notes/step5-freshness.txt`](../notes/step5-freshness.txt).
- **Rule:** a table with a real load column is checked on it. A table without
  one may use a business date only as a proxy, with a comment in
  [`sources.yml`](../dbt/models/sources.yml) saying so.

## Not covered by a test yet

These are true today (checked by query on 2026-11-04), but no test would catch
a regression.

| # | Criterion | Today | Why it matters |
|---|---|---|---|
| A | Every order has a known customer (`orders.buyer_id` exists in the customers). | Not tested. 0 buyers without a default address (defect query 5). | An unknown buyer would get country `UNKNOWN` without any test failing. |
| B | Every order line belongs to an existing order. | Not tested. Emma's load builds `order_items` with an inner join on `orders`. | `int_order_items` uses an inner join: lines without an order would disappear silently. |
| C | Every order line has a real country, not `UNKNOWN`. | 0 `UNKNOWN` lines. The `not_null` test cannot fail, because of `COALESCE(country, 'UNKNOWN')`. | Units without a country are useless to the ML team. |
