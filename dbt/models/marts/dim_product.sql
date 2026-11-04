-- GRAIN : un produit (p_id).
SELECT
    p.p_id,
    p.product_name,
    p.price,
    r.avg_rating,
    COALESCE(r.n_reviews, 0) AS n_reviews
FROM {{ ref('stg_product') }} AS p
LEFT JOIN {{ ref('int_product_ratings') }} AS r USING (p_id)
