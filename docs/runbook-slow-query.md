# Runbook — Requête lente ou scan anormal

1. Identifier le job, la requête et la période métier ; relever octets traités/facturables, cache_hit, durée et plan d'exécution
2. Vérifier la table source et le filtre direct sur order_date ; comparer aux octets de référence de warehouse-tuning.md
3. Vérifier les partitions dans INFORMATION_SCHEMA.PARTITIONS et les colonnes sélectionnées ; éviter SELECT * pour l'analyse
4. Vérifier les changements de volumes et les jointures multiplicatives ; un clustering sans filtre sélectif ne garantit pas un gain
5. Pour une MV, vérifier son état de rafraîchissement et son utilisation dans le plan ; conserver les mêmes bornes métier
6. Tester une seule modification à la fois, cache désactivé et plafond adapté ; vérifier que les résultats sont équivalents
7. Si le plafond bloque : consulter l'estimation, corriger le scan ou justifier explicitement une hausse ; ne pas supprimer la limite par défaut

Ne recréer aucune table warehouse partagée sans coordination avec Mathilde/dbt. Préférer les variantes de test g03 et documenter le job_id.
