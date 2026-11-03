-- GRAIN : un jour (date_day).
-- Plage À ADAPTER : elle doit couvrir toutes les order_date (requête 8 de notes/step5-defects.sql).
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
