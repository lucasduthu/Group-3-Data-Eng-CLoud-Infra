-- Source : g03_warehouse.orders
-- Défaut corrigé : la colonne d'index pandas "Unnamed__0" (présente sur toutes les lignes) n'est pas sélectionnée.
-- Doublons : 0 order_id en double (requête 3 de notes/step5-defects.sql, 2026-11-04) -> pas de déduplication ;
--            le test unique sur order_id (_staging.yml) bloquera le pipeline si un doublon apparaît.
-- order_date est déjà en DATE (typée au chargement par Emma, warehouse/load_native.sql).
SELECT
    order_id,
    buyer_id,
    payment_id,
    discount_id,
    order_date
FROM {{ source('marketplace', 'orders') }}
