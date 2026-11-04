-- GRAIN : un jour (date_day).
-- Plage vérifiée : les commandes vont du 2023-09-15 au 2026-09-14 (requête 8, 2026-11-04), couvertes par 2023-01-01 -> 2027-12-31.
SELECT
    d                          AS date_day,
    EXTRACT(YEAR FROM d)       AS year,
    EXTRACT(QUARTER FROM d)    AS quarter,
    EXTRACT(MONTH FROM d)      AS month,
    FORMAT_DATE('%Y-%m', d)    AS year_month,
    EXTRACT(ISOWEEK FROM d)    AS iso_week,
    FORMAT_DATE('%A', d)       AS day_name,
    EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend
FROM UNNEST(GENERATE_DATE_ARRAY('2023-01-01', '2027-12-31')) AS d
