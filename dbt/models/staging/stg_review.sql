-- Source : g03_warehouse.review
-- Défaut corrigé : r_desc fait d'espaces sur 110 avis (0 vide, 27 déjà NULL, sur 111 322 ; requête 2, 2026-11-04) -> NULL.
-- title : 0 vide, 0 fait d'espaces (requête 2) -> repris tel quel.
-- Notes : toutes entre 1 et 5, 0 review_id en double (requête 7).
SELECT
    review_id,
    buyer_id,
    rating,
    NULLIF(TRIM(r_desc), '') AS review_text,
    title                    AS review_title
FROM {{ source('marketplace', 'review') }}
