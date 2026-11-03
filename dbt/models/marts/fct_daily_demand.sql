-- GRAIN : un produit, dans un pays, un jour (p_id, country, order_date).
-- La table demandée par l'équipe ML.
SELECT
    {{ dbt_utils.generate_surrogate_key(['p_id', 'country', 'order_date']) }} AS demand_key,
    p_id,
    country,
    order_date,
    SUM(qty)          AS units,
    SUM(line_revenue) AS revenue
FROM {{ ref('fct_order_items') }}
GROUP BY p_id, country, order_date
