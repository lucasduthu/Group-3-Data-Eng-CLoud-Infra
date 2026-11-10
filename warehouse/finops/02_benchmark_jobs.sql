-- Retrouve les jobs du benchmark du 10 novembre : job_id, octets exacts, cache_hit
SELECT job_id, creation_time, cache_hit, total_bytes_processed, total_bytes_billed
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE DATE(creation_time) = '2026-11-10'
  AND statement_type = 'SELECT'
  AND query LIKE '%fct_order_items%'
  AND query LIKE '%2026-06-14%'
ORDER BY creation_time;
