-- Source : warehouse.product_reviews
-- Aucun défaut constaté (À VÉRIFIER avec la requête 7) : sélection des deux clés.
SELECT
    p_id,
    review_id
FROM {{ source('marketplace', 'product_reviews') }}
