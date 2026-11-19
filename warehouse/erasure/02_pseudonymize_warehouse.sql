-- Effacement RGPD par pseudonymisation, étape 2 : le warehouse.
-- Paramètres : @target (l'identifiant à effacer) et @salt (aléatoire, jamais enregistré).
-- Gardé : commandes, articles, note de l'avis (les chiffres ne bougent pas), liés à un pseudonyme.
-- Effacé : l'identifiant, la rue, le téléphone, le code postal, et le titre et le texte libre de l'avis
-- (colonne unclassified : elle peut contenir de quoi identifier la personne).
DECLARE pseudo STRING DEFAULT CONCAT('pseudo_', SUBSTR(TO_HEX(SHA256(CONCAT(@salt, @target))), 1, 24));

CREATE TEMP TABLE addr AS
SELECT address_id FROM `data-engineering-i1.g03_warehouse.customer_shipping` WHERE c_id = @target;

UPDATE `data-engineering-i1.g03_warehouse.shipping_details`
SET street_address = NULL, phone = NULL, zip = NULL
WHERE address_id IN (SELECT address_id FROM addr);

UPDATE `data-engineering-i1.g03_warehouse.review`
SET buyer_id = pseudo, r_desc = NULL, title = NULL
WHERE buyer_id = @target;

UPDATE `data-engineering-i1.g03_warehouse.customer_shipping` SET c_id = pseudo WHERE c_id = @target;
UPDATE `data-engineering-i1.g03_warehouse.orders`            SET buyer_id = pseudo WHERE buyer_id = @target;
UPDATE `data-engineering-i1.g03_warehouse.orders_p`          SET buyer_id = pseudo WHERE buyer_id = @target;

SELECT pseudo AS pseudonym, (SELECT COUNT(*) FROM addr) AS addresses_cleared;
