-- Combien de requêtes sur les datasets g03_ portent le label team=g03 ?
-- Les labels des datasets ne se propagent pas aux requêtes : seuls les labels de job attribuent le calcul.
SELECT COUNT(*) AS jobs,
       COUNTIF(EXISTS (SELECT 1 FROM UNNEST(j.labels) l WHERE l.key = 'team' AND l.value = 'g03')) AS jobs_labelled_team_g03,
       COUNTIF(ARRAY_LENGTH(j.labels) > 0) AS jobs_with_any_label
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS AS j
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND j.statement_type != 'SCRIPT'
  AND EXISTS (SELECT 1 FROM UNNEST(j.referenced_tables) t WHERE t.dataset_id LIKE 'g03_%');
