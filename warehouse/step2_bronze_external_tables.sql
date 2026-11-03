-- Step 2 · Tables externes BigQuery sur le bronze (à lancer dans la console BigQuery)
-- Une table externe = une définition : les fichiers restent dans le bucket, BigQuery les lit à chaque requête.

-- 1. Le dataset (une seule fois)
CREATE SCHEMA IF NOT EXISTS `data-engineering-i1.g03_bronze`
OPTIONS (location = 'europe-west1');

-- 2. orders (partition : month)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.orders_external`
WITH PARTITION COLUMNS (month STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/orders/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/orders'
);

-- 3. order_items (partition : month)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.order_items_external`
WITH PARTITION COLUMNS (month STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/order_items/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/order_items'
);

-- 4. review (partition : ingest_date)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.review_external`
WITH PARTITION COLUMNS (ingest_date STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/review/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/review'
);

-- 5. product_reviews (partition : ingest_date)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.product_reviews_external`
WITH PARTITION COLUMNS (ingest_date STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/product_reviews/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/product_reviews'
);

-- 6. product (partition : ingest_date)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.product_external`
WITH PARTITION COLUMNS (ingest_date STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/product/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/product'
);

-- 7. customer_shipping (partition : ingest_date)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.customer_shipping_external`
WITH PARTITION COLUMNS (ingest_date STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/customer_shipping/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/customer_shipping'
);

-- 8. shipping_details (partition : ingest_date)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g03_bronze.shipping_details_external`
WITH PARTITION COLUMNS (ingest_date STRING)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://albert-de-msc2-26-g03-bronze/bronze/export/shipping_details/*'],
  hive_partition_uri_prefix = 'gs://albert-de-msc2-26-g03-bronze/bronze/export/shipping_details'
);

-- 9. Contrôle : 7 lignes, aucune à zéro. Valeurs attendues d'après le cours :
--    orders ≈ 222 644 · order_items ≈ 408 560 · review ≈ 111 322 · product_reviews ≈ 111 322
--    product ≈ 42 858 · customer_shipping ≈ 200 001 · shipping_details ≈ 200 001
SELECT 'orders' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.orders_external`
UNION ALL SELECT 'order_items' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.order_items_external`
UNION ALL SELECT 'review' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.review_external`
UNION ALL SELECT 'product_reviews' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.product_reviews_external`
UNION ALL SELECT 'product' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.product_external`
UNION ALL SELECT 'customer_shipping' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.customer_shipping_external`
UNION ALL SELECT 'shipping_details' AS table_name, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.shipping_details_external`;

-- 10. Les partitions de orders (une ligne par mois)
SELECT month, COUNT(*) AS n FROM `data-engineering-i1.g03_bronze.orders_external` GROUP BY month ORDER BY month;

-- 11. Mesure pour l'ADR : effet du partitionnement (relever « Bytes processed » dans Job information, cache désactivé)
-- 11a. Sans filtre sur la partition : lit tous les fichiers
SELECT COUNT(*), SUM(price_at_purchase) FROM `data-engineering-i1.g03_bronze.order_items_external`;
-- 11b. Avec filtre sur la partition : ne lit qu'un mois (remplacer par un mois qui existe)
SELECT COUNT(*), SUM(price_at_purchase) FROM `data-engineering-i1.g03_bronze.order_items_external` WHERE month = '2026-08';
