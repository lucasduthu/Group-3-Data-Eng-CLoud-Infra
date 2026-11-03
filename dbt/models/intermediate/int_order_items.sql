-- order_items n'a pas de date propre : on prend celle de la commande.
-- Cette jointure est une décision, c'est pourquoi elle n'est pas en staging.
SELECT
    i.order_id,
    i.p_id,
    i.qty,
    i.price_at_purchase,
    o.order_date,
    o.buyer_id
FROM {{ ref('stg_order_items') }} AS i
JOIN {{ ref('stg_orders') }}      AS o USING (order_id)
