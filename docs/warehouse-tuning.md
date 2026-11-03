# Step 4 — Warehouse : mesures et décisions

Responsable : Emma · Review prévue : Mathilde

## Périmètre et provenance

Projet `data-engineering-i1`, région `europe-west1`, dataset `g03_warehouse`.
Preuves : export de 18 jobs fourni par Emma, captures/résultats de console partagés dans la conversation, guide technique du groupe. Les ressources cloud et le dépôt Git n'ont pas été inspectés directement lors de la préparation de ce dossier. Les scripts de création reconstituent les instructions utilisées ; ils n'ont pas été réexécutés ici.
Les heures du CSV sont UTC (Paris = UTC+1 à ces dates). Le nom du CSV est conservé tel que fourni.
Tous les 18 jobs exportés portent `cache_hit = false`.

## Chargement natif

| Table | Lignes observées |
|---|---:|
| orders | 222644 |
| order_items | 408560 |
| review | 111322 |
| product_reviews | 111322 |
| product | 42858 |
| customer_shipping | 200001 |
| shipping_details | 200001 |

`order_date` a été convertie de STRING en DATE ; zéro date nulle dans orders et order_items. Période orders : 2023-09-15 à 2026-09-14. order_items récupère la date par jointure sur order_id ; nombre total conservé (408560). Ce comptage seul ne prouve pas l'absence de doublons et d'orphelins qui se compenseraient ; contrôles de clés à prévoir dans dbt.

Les 7 sources `g03_bronze.<table>_external` restent externes pour la traçabilité du bronze. Le clickstream, la DLQ et les autres tables de l'export restent dans le bronze selon le guide : pas nécessaires au working set de ces 3 requêtes ni aux 7 sources warehouse prévues pour dbt. Leur inventaire réel complet reste à confirmer avant le rendu.

## Mesures exactes

| Test | Octets traités | Octets facturables | Coût théorique sur traités ($) | Coût nominal sur facturables ($) |
|---|---:|---:|---:|---:|
| Q1 baseline | 9,805,440 | 10,485,760 | 0.000067 | 0.000072 |
| Q2 baseline | 11,439,680 | 11,534,336 | 0.000078 | 0.000079 |
| Q3 baseline | 4,007,592 | 20,971,520 | 0.000027 | 0.000143 |
| Q1 partition | 3,373,224 | 10,485,760 | 0.000023 | 0.000072 |
| Q2 partition | 1,000,888 | 10,485,760 | 0.000007 | 0.000072 |
| Q2 partition + cluster | 1,000,888 | 10,485,760 | 0.000007 | 0.000072 |
| Q3 cluster | 4,007,592 | 20,971,520 | 0.000027 | 0.000143 |
| Q2 MV daily | 876,204 | 10,485,760 | 0.000006 | 0.000072 |
| Weekly test table | 1,039,080 | 10,485,760 | 0.000007 | 0.000072 |
| Weekly test MV | 6,309,660 | 10,485,760 | 0.000043 | 0.000072 |

Hypothèse pédagogique : **7,50 USD/Tio**, reprise du guide, sans vérification du tarif courant. Calcul : octets / 2^40 × 7,50. La colonne sur octets traités répond à la convention du guide ; celle sur octets facturables tient compte des minimums et arrondis observés. Aucune ne constitue une facture réelle : crédits, franchise, modèle de facturation et dépenses de stockage/rafraîchissement ne sont pas déduits ici. Valeurs détaillées à 9 décimales dans notes/step4-query-metrics.csv.

Le libellé console « Mo/ko » correspond ici aux conversions binaires (Mio/Kio) : 9805440 octets / 2^20 = 9,35. Les calculs de ratios utilisent les octets exacts.

## Tuning

- Q1 : 9805440 → 3373224 octets, ratio **2,9068×**, réduction **65,60 %**
- Q2 : 11439680 → 1000888 octets, ratio **11,4295×**, réduction **91,25 %**
- Q2 clustering additionnel : 1000888 → 1000888, ratio **1,0×**
- Q3 clustering : 4007592 → 4007592, ratio **1,0×**

Le filtre de dates permet l'élagage des partitions mensuelles. Les 37 partitions observées sont petites (premières : 0,28 à 0,77 Mio) : ce choix démontre l'élagage dans le lab ; il ne prouve pas une conception optimale à toute échelle. Le clustering ne réduit pas les octets dans ces requêtes sans filtre sélectif sur sa clé. Les tailles de blocs et les petits volumes limitent également son intérêt. Aucun gain de latence n'est affirmé.

Q1 conserve le même minimum facturable malgré la réduction des données lues. Q2 passe de 11534336 à 10485760 octets facturables : l'économie nominale est donc d'environ 9,09 %, bien inférieure aux 91,25 % de réduction des octets traités.

## Vues matérialisées

| Grain | Lignes initiales | Lignes agrégées | Collapse ratio arrondi |
|---|---:|---:|---:|
| Produit–jour | 408560 | 356981 | 1,14 |
| Produit–semaine | 408560 | 225345 | 1,81 |

Q2 quotidienne : 1000888 → 876204 octets, réduction **12,46 %**, même minimum facturable. La vue quotidienne conserve les filtres au jour près ; son faible collapse ratio ne justifie pas à lui seul son coût de stockage/maintenance.

Test séparé, semaines entières du dimanche 2025-06-15 inclus au dimanche 2025-09-14 exclu : table partitionnée 1039080 octets, vue hebdomadaire 6309660 octets (environ **6,07× plus**). Vue hebdomadaire non partitionnée ; l'organisation physique diffère donc aussi. Ce test ne mesure pas l'effet du seul grain. Contrôle EXCEPT DISTINCT dans les deux sens sur tous les produits : **0 écart**, valeur fournie par Emma (le CSV ne contient pas les résultats des requêtes).
Une réécriture automatique via une MV peut intervenir dans BigQuery : le plan d'exécution n'a pas été inspecté et l'utilisation des MV dans les jobs n'est pas prouvée ici. Les valeurs rapportées sont les volumes réellement enregistrés par les jobs.
Conserver la vue quotidienne pour les tests au jour près ; garder l'hebdomadaire comme expérience documentée, sans la recommander comme optimisation sur cette charge. Ne pas la supprimer automatiquement.

## Plafond

Limite testée : 10485760 octets (10 Mio).

```text
Query exceeded limit for bytes billed: 10485760. 18874368 or higher required.
```

La requête a été refusée. Le CSV exclut les jobs en erreur : cette preuve provient du message console transmis par Emma. Retour conseillé à 52428800 octets (50 Mio), à confirmer dans les paramètres. Le plafond est par requête et ne remplace pas un budget global.

## Reste avant intégration

- Confirmer le plafond de 50 Mio dans la console
- Vérifier l'inventaire des tables externes et la conformité avec le brief officiel
- Intégrer ce dossier au dépôt, examiner les changements et les noms de documentation existants
- Commit sur branche, push et PR avec Mathilde en reviewer
