-- Dans les paramètres console : cache désactivé, région europe-west1.
-- 1. Régler Maximum bytes billed = 10485760 (10 Mio).
SELECT * FROM `data-engineering-i1.g03_warehouse.order_items`;
-- Refus observé :
-- Query exceeded limit for bytes billed: 10485760. 18874368 or higher required.
-- 2. Après le test, régler Maximum bytes billed = 52428800 (50 Mio).
-- Le retour à 50 Mio a été demandé ; confirmation finale à effectuer dans la console.
