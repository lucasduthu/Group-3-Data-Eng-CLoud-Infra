-- Source : warehouse.product
-- Défaut corrigé : noms de produit vides ou faits d'espaces (À REMPLIR, requête 6) -> NULL.
SELECT
    p_id,
    NULLIF(TRIM(p_name), '') AS product_name,
    price
FROM {{ source('marketplace', 'product') }}
