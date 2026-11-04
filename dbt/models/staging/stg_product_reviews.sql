-- Source : g03_warehouse.product_reviews
-- Aucun défaut constaté : 0 avis lié à un produit inconnu (requête 7, 2026-11-04) -> sélection des deux clés.
SELECT
    p_id,
    review_id
FROM {{ source('marketplace', 'product_reviews') }}
