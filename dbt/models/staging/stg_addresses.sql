-- Sources : customer_shipping + shipping_details
-- Fan-out : un client peut avoir plusieurs adresses ; la règle de la donnée (is_default = 1) en choisit une.
-- Défaut corrigé : À REMPLIR clients avec plusieurs adresses par défaut (requête 5) -> plus petite address_id gardée.
-- Seul le pays est gardé : rue et téléphone (données personnelles) ne vont pas plus loin.
SELECT
    cs.c_id,
    sd.country
FROM {{ source('marketplace', 'customer_shipping') }} AS cs
JOIN {{ source('marketplace', 'shipping_details') }}  AS sd USING (address_id)
WHERE cs.is_default = 1
QUALIFY ROW_NUMBER() OVER (PARTITION BY cs.c_id ORDER BY cs.address_id) = 1
