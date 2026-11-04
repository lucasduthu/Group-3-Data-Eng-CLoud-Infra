-- Création initiale ; reconstruit les tables. Coordonner les relances avec dbt.
CREATE SCHEMA IF NOT EXISTS `data-engineering-i1.g03_warehouse` OPTIONS(location='europe-west1');

-- Baseline non tunée : chaque mesure ultérieure se compare à ça.
-- order_date arrive du CSV en texte : on la type en DATE au chargement (le bronze, lui, reste brut).
-- Le COALESCE accepte "2024-03-15" comme "2024-03-15 10:22:00".
CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.orders` AS
SELECT * EXCEPT (order_date),
       COALESCE(SAFE_CAST(order_date AS DATE), DATE(SAFE_CAST(order_date AS TIMESTAMP))) AS order_date
FROM `data-engineering-i1.g03_bronze.orders_external`;

-- Contrôle du typage : doit renvoyer 0 (sinon, regarder le format réel avant de continuer)
SELECT COUNT(*) AS unparsed_dates FROM `data-engineering-i1.g03_warehouse.orders` WHERE order_date IS NULL;

-- order_items n'a pas de date : on la récupère sur la commande
CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.order_items` AS
SELECT i.order_id, i.p_id, i.qty, i.price_at_purchase, o.order_date
FROM `data-engineering-i1.g03_bronze.order_items_external` AS i
JOIN `data-engineering-i1.g03_warehouse.orders` AS o USING (order_id);

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.review` AS
SELECT * FROM `data-engineering-i1.g03_bronze.review_external`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.product_reviews` AS
SELECT * FROM `data-engineering-i1.g03_bronze.product_reviews_external`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.product` AS
SELECT * FROM `data-engineering-i1.g03_bronze.product_external`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.customer_shipping` AS
SELECT * FROM `data-engineering-i1.g03_bronze.customer_shipping_external`;

CREATE OR REPLACE TABLE `data-engineering-i1.g03_warehouse.shipping_details` AS
SELECT * FROM `data-engineering-i1.g03_bronze.shipping_details_external`;

-- Contrôle : 7 lignes, aucune à zéro (≈ 222 644 / 408 560 / 111 322 / 111 322 / 42 858 / 200 001 / 200 001)
SELECT 'orders' t, COUNT(*) n FROM `data-engineering-i1.g03_warehouse.orders`
UNION ALL SELECT 'order_items', COUNT(*) FROM `data-engineering-i1.g03_warehouse.order_items`
UNION ALL SELECT 'review', COUNT(*) FROM `data-engineering-i1.g03_warehouse.review`
UNION ALL SELECT 'product_reviews', COUNT(*) FROM `data-engineering-i1.g03_warehouse.product_reviews`
UNION ALL SELECT 'product', COUNT(*) FROM `data-engineering-i1.g03_warehouse.product`
UNION ALL SELECT 'customer_shipping', COUNT(*) FROM `data-engineering-i1.g03_warehouse.customer_shipping`
UNION ALL SELECT 'shipping_details', COUNT(*) FROM `data-engineering-i1.g03_warehouse.shipping_details`;
