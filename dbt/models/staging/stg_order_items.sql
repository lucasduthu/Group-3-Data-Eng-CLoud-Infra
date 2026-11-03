-- Source : warehouse.order_items
-- Défaut corrigé : À REMPLIR couples (order_id, p_id) en double (requête 4) -> quantités additionnées en une ligne.
--                 Si 0 doublon : remplacer par un simple SELECT et l'écrire ici.
SELECT
    order_id,
    p_id,
    SUM(qty)                     AS qty,
    ANY_VALUE(price_at_purchase) AS price_at_purchase
FROM {{ source('marketplace', 'order_items') }}
GROUP BY order_id, p_id
