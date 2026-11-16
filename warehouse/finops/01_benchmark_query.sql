-- Requête du benchmark step 9, lancée à l'identique avant et après le partitionnement
SELECT p_id, SUM(qty) AS units
FROM `data-engineering-i1.g03_analytics.fct_order_items`
WHERE order_date >= DATE '2026-06-14'
GROUP BY p_id ORDER BY units DESC LIMIT 10;
