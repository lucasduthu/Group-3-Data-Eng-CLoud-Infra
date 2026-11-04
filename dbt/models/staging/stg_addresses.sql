-- Sources : customer_shipping + shipping_details
-- Fan-out : un client peut avoir plusieurs adresses ; la règle de la donnée (is_default = 1) en choisit une.
-- Défaut vérifié : 0 client avec plusieurs adresses par défaut (requête 5, 2026-11-04) -> pas de déduplication ;
--                  le test unique sur c_id (_staging.yml) bloquera le pipeline si un client en a deux.
-- 0 acheteur sans adresse par défaut (requête 5 bis) : le 'UNKNOWN' de fct_order_items ne sert aujourd'hui à rien.
-- Seul le pays est gardé : rue et téléphone (données personnelles) ne vont pas plus loin.
SELECT
    cs.c_id,
    sd.country
FROM {{ source('marketplace', 'customer_shipping') }} AS cs
JOIN {{ source('marketplace', 'shipping_details') }}  AS sd USING (address_id)
WHERE cs.is_default = 1
