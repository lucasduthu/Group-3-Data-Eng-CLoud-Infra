-- Références avant optimisation ; désactiver le cache des résultats.

-- Q1 baseline : chiffre d'affaires mensuel sur 12 mois
SELECT
  DATE_TRUNC(order_date, MONTH) AS month,
  ROUND(SUM(qty * price_at_purchase), 2) AS revenue
FROM `data-engineering-i1.g03_warehouse.order_items`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 12 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY month
ORDER BY month;

-- Q2 baseline : top 10 produits par quantité vendue
SELECT
  p_id,
  SUM(qty) AS units
FROM `data-engineering-i1.g03_warehouse.order_items`
WHERE order_date >= DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH)
  AND order_date <= DATE '2026-09-14'
GROUP BY p_id
ORDER BY units DESC, p_id
LIMIT 10;

-- Q3 baseline : note moyenne par produit
SELECT
  pr.p_id,
  ROUND(AVG(r.rating), 2) AS avg_rating,
  COUNT(*) AS n_reviews
FROM `data-engineering-i1.g03_warehouse.review` AS r
JOIN `data-engineering-i1.g03_warehouse.product_reviews` AS pr
  ON r.review_id = pr.review_id
GROUP BY pr.p_id
HAVING COUNT(*) > 50
ORDER BY avg_rating DESC, pr.p_id;