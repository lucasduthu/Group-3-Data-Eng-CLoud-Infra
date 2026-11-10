-- Quels labels portent les requêtes sur les datasets g03_ ?
SELECT l.key, COUNT(*) AS jobs
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS AS j, UNNEST(j.labels) AS l
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND j.statement_type != 'SCRIPT'
  AND EXISTS (SELECT 1 FROM UNNEST(j.referenced_tables) t WHERE t.dataset_id LIKE 'g03_%')
GROUP BY l.key ORDER BY jobs DESC;
