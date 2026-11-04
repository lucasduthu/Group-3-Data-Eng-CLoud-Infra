-- Source : g03_warehouse.product
-- Défaut vérifié : 6 produits sur 42 858 sans nom (requête 6, 2026-11-04) ; ce sont 6 NULL, 0 vide, 0 fait d'espaces.
--                  Pas de nettoyage à faire : les NULL restent NULL (test not_null en warn sur dim_product.product_name).
-- 0 p_id en double (requête 6).
SELECT
    p_id,
    p_name AS product_name,
    price
FROM {{ source('marketplace', 'product') }}
