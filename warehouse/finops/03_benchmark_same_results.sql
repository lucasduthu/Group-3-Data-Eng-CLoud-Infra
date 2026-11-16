-- Compare les résultats du job "avant" et du job "après" (non caché) du benchmark step 9.
-- 0 ligne différente = mêmes résultats. Les tables de résultats expirent 24 h après la requête.
DECLARE t_before STRING;
DECLARE t_after STRING;
SET t_before = (
  SELECT FORMAT('`%s.%s.%s`', destination_table.project_id, destination_table.dataset_id, destination_table.table_id)
  FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
  WHERE job_id = 'job_axZV-paIKYWiSmzoPQCJouqLy3w8');
SET t_after = (
  SELECT FORMAT('`%s.%s.%s`', destination_table.project_id, destination_table.dataset_id, destination_table.table_id)
  FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
  WHERE job_id = 'job_-VSYAFt4Cp4mZj6QiW-FkZXRswF7');
EXECUTE IMMEDIATE FORMAT("""
  SELECT COUNT(*) AS lignes_differentes FROM (
    (SELECT * FROM %s EXCEPT DISTINCT SELECT * FROM %s)
    UNION ALL
    (SELECT * FROM %s EXCEPT DISTINCT SELECT * FROM %s))""",
  t_before, t_after, t_after, t_before);
