-- Consommation BigQuery observée par jour, pour les requêtes qui lisent un dataset g03_ (30 jours).
-- EXISTS : chaque requête est comptée une fois, même si elle lit plusieurs tables.
-- statement_type != 'SCRIPT' : on exclut les jobs parents des scripts, sinon leurs octets
-- seraient comptés deux fois (une fois au parent, une fois dans ses jobs enfants).
SELECT DATE(creation_time) AS day, COUNT(*) AS jobs,
       ROUND(SUM(total_bytes_processed)/POW(2,30), 3) AS gib_processed,
       ROUND(SUM(total_bytes_billed)/POW(2,30), 3) AS gib_billed
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS AS j
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND j.statement_type != 'SCRIPT'
  AND EXISTS (SELECT 1 FROM UNNEST(j.referenced_tables) t WHERE t.dataset_id LIKE 'g03_%')
GROUP BY day ORDER BY day;
