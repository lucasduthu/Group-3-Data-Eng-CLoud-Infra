-- Le chiffre d'affaires d'une ligne est toujours positif. Échoue s'il renvoie au moins une ligne.
SELECT order_id, p_id, line_revenue
FROM {{ ref('fct_order_items') }}
WHERE line_revenue <= 0
