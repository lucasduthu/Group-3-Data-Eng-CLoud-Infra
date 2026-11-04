-- Source : g03_warehouse.order_items
-- Doublons : 0 couple (order_id, p_id) en double (requête 4, 2026-11-04) -> simple sélection, pas d'agrégation ;
--            le test unique_combination_of_columns (_staging.yml) bloquera le pipeline si un doublon apparaît.
SELECT
    order_id,
    p_id,
    qty,
    price_at_purchase
FROM {{ source('marketplace', 'order_items') }}
