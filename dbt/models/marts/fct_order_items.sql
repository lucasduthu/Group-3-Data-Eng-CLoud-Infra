-- GRAIN : une ligne par produit dans une commande (order_id, p_id).
SELECT
    i.order_id,
    i.p_id,
    i.qty,
    i.price_at_purchase,
    i.qty * i.price_at_purchase    AS line_revenue,
    i.is_zero_price_anomaly,
    i.order_date,
    COALESCE(a.country, 'UNKNOWN') AS country,
    pr.avg_rating
FROM {{ ref('int_order_items') }}          AS i
LEFT JOIN {{ ref('stg_addresses') }}       AS a  ON a.c_id = i.buyer_id
LEFT JOIN {{ ref('int_product_ratings') }} AS pr USING (p_id)
