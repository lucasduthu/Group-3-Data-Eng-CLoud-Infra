-- Le chiffre d'affaires d'une ligne n'est jamais négatif ni NULL. Échoue (error) s'il renvoie au moins une ligne.
-- 0 est accepté : les 30 lignes à prix 0,00 (is_zero_price_anomaly) ont un CA de 0 et sont suivies
-- par assert_no_zero_price_lines (warn), pas par ce test.
{{ config(severity='error') }}
SELECT order_id, p_id, line_revenue
FROM {{ ref('fct_order_items') }}
WHERE line_revenue < 0 OR line_revenue IS NULL
