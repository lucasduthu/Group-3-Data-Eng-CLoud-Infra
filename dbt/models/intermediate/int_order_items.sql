-- order_items n'a pas de date propre : on prend celle de la commande.
-- Cette jointure est une décision, c'est pourquoi elle n'est pas en staging.
--
-- Prix unitaire : price_at_purchase vaut ROUND(product.price, 2) sur 100 % des 408 560 lignes (vérifié le 2026-11-04).
-- 5 produits ont un prix catalogue < 0,005 : l'arrondi les met à 0,00 sur 30 lignes. On ne remplace PAS ce prix
-- (ni par le prix catalogue, ni par une estimation) : le chiffre d'affaires reste fondé sur le prix réellement payé,
-- donc 0 pour ces lignes. is_zero_price_anomaly les signale, et le test assert_no_zero_price_lines (warn) les
-- remonte à chaque build. Les lignes sont gardées : les unités vendues comptent pour fct_daily_demand.
SELECT
    i.order_id,
    i.p_id,
    i.qty,
    i.price_at_purchase,
    i.price_at_purchase = 0 AS is_zero_price_anomaly,
    o.order_date,
    o.buyer_id
FROM {{ ref('stg_order_items') }} AS i
JOIN {{ ref('stg_orders') }}      AS o USING (order_id)
