-- Lignes vendues à un prix de 0,00 (price_at_purchase arrondi à 0 depuis un prix catalogue < 0,005).
-- Severity warn : le build continue, mais le nombre de lignes (30 au 2026-11-04) apparaît dans chaque
-- résumé de build, pour que l'anomalie reste visible tant que la source ne l'a pas corrigée.
{{ config(severity='warn') }}
SELECT order_id, p_id, qty, price_at_purchase, line_revenue, order_date
FROM {{ ref('fct_order_items') }}
WHERE is_zero_price_anomaly
