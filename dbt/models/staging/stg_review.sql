-- Source : warehouse.review
-- Défaut corrigé : r_desc et title vides ou faits d'espaces (À REMPLIR : X vides, Y blancs, requête 2) -> NULL.
SELECT
    review_id,
    buyer_id,
    rating,
    NULLIF(TRIM(r_desc), '') AS review_text,
    NULLIF(TRIM(title), '')  AS review_title
FROM {{ source('marketplace', 'review') }}
