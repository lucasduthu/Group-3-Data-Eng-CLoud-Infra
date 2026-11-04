-- order_items n'a pas de date propre : on prend celle de la commande.
-- Cette jointure est une décision, c'est pourquoi elle n'est pas en staging.
--
-- Prix unitaire : price_at_purchase vaut ROUND(product.price, 2) sur 100 % des 408 560 lignes (vérifié le 2026-11-04).
-- 5 produits ont un prix catalogue < 0,005 : l'arrondi les met à 0,00 sur 30 lignes, et leur chiffre d'affaires
-- tomberait à 0 (test assert_line_revenue_is_positive). Pour ces lignes seulement, on reprend le prix catalogue
-- non arrondi. Les lignes sont gardées : les unités vendues comptent pour fct_daily_demand.
SELECT
    i.order_id,
    i.p_id,
    i.qty,
    i.price_at_purchase,
    IF(i.price_at_purchase = 0, p.price, i.price_at_purchase) AS unit_price,
    o.order_date,
    o.buyer_id
FROM {{ ref('stg_order_items') }} AS i
JOIN {{ ref('stg_orders') }}      AS o USING (order_id)
LEFT JOIN {{ ref('stg_product') }} AS p USING (p_id)
