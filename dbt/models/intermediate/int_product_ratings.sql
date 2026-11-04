-- Fan-out des avis : un produit a N avis. On agrège AVANT toute jointure,
-- sinon chaque ligne de commande serait multipliée par le nombre d'avis.
SELECT
    pr.p_id,
    AVG(r.rating) AS avg_rating,
    COUNT(*)      AS n_reviews
FROM {{ ref('stg_product_reviews') }} AS pr
JOIN {{ ref('stg_review') }}          AS r USING (review_id)
GROUP BY pr.p_id
