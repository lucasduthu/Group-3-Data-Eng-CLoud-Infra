-- Source : warehouse.orders
-- Défaut corrigé : la colonne d'index pandas "Unnamed: 0" (présente sur toutes les lignes) n'est pas sélectionnée.
-- Défaut corrigé : À REMPLIR order_id en double (requête 3 de notes/step5-defects.sql) -> une ligne par order_id.
--                 Si 0 doublon : supprimer le QUALIFY et l'écrire ici.
SELECT
    order_id,
    buyer_id,
    payment_id,
    discount_id,
    order_date
FROM {{ source('marketplace', 'orders') }}
WHERE TRUE   -- certaines versions de BigQuery exigent un WHERE avant QUALIFY
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date DESC) = 1
