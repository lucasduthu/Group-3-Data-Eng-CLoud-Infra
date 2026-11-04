# ADR 0004 — Warehouse et maîtrise du scan

Statut : proposition à faire relire par Mathilde ; non fusionnée.

## Décision

Charger le working set de 7 tables en natif BigQuery ; conserver les sources externes du bronze. Garder les tables initiales comme baseline et comparer des variantes mensuelles, clusterisées et matérialisées. Fixer les fenêtres de temps et désactiver le cache. Appliquer un plafond par requête et distinguer octets traités / facturables.

## Alternatives

Tout lire en externe : moins de duplication du stockage, mais dépend des fichiers bronze et n'offre pas la même organisation native. Tout charger en natif : plus de tables et de stockage sans besoin métier démontré. Partitionnement quotidien : davantage de partitions minuscules dans ce lab. Clustering systématique : aucun gain de scan constaté sur les deux tests. Agrégation hebdomadaire : perd le jour et scanne davantage dans la variante testée.

## Conséquences

Le partitionnement réduit le scan de Q1 et Q2 ; le gain facturable reste limité par les minimums observés. Les vues ajoutent stockage et rafraîchissement : le gain quotidien de 12,46 % ne suffit pas à établir un bénéfice financier net. La vue hebdomadaire n'est pas recommandée pour la charge mesurée. Voir docs/warehouse-tuning.md et les job_id sources.

## Réexamen

Réévaluer si le volume, la fréquence des requêtes, la sélectivité produit ou le besoin de détail temporel change. À plus fort volume, comparer tailles des partitions, latence, slot-ms, coût de rafraîchissement et stockage. Ne pas généraliser les résultats du petit dataset.
