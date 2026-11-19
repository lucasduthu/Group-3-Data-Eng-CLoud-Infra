# ADR-0010 : Donner l'accès aux colonnes sensibles par leur classe, avec des policy tags

- **Statut :** accepted
- **Date :** 2026-11-19
- **Auteur :** Laura
- **Leçon :** L10

## Contexte

Le warehouse contient des coordonnées : `shipping_details.street_address` et `phone`, et dans le
bronze, `fname`, `lname`, `phone`, `email` de l'extraction `customer`. Seul `stg_addresses` lit
`shipping_details`, et uniquement `address_id` et `country` (vérifié dans le code dbt et par la
requête « qui lit quoi », `notes/step10-who-reads-what.txt`) : protéger la rue et le téléphone ne
casse pas le pipeline.

Contraintes du projet partagé `data-engineering-i1` : on ne peut pas créer de service account, et
l'école nous donne `datacatalog.categories.fineGrainedGet` au niveau du projet (vérifié par
`testIamPermissions`). Ce droit est exactement la « deuxième clé » qui permet de lire une colonne
taguée.

## Options considérées

| Option | Pour | Contre |
|---|---|---|
| Classer les colonnes, donner l'accès par classe (retenue) | une règle qui couvre aussi les futures tables ; auditable ; le message d'erreur dit quoi demander | deux autorisations à comprendre ; un tag mal configuré ne protège rien, sans le signaler |
| Une vue par consommateur | la bonne forme pour chacun, pas de tag | une vue à maintenir par consommateur, pour toujours ; la table d'origine reste lisible |
| Un dataset par niveau de sensibilité | simple, grossier, difficile à rater | les mêmes données copiées deux fois, deux choses à garder synchrones |
| Faire confiance aux gens | rien à construire | ce n'est pas un contrôle ; le journal d'audit finit par le prouver |

## Critères

- Tenir quand une table est ajoutée : seules la classification et le dataset séparé y arrivent sans
  travail par consommateur.
- Ne pas copier les données : élimine le dataset par sensibilité.
- Être vérifiable : le tag produit un refus explicite et journalisé, s'il est appliqué.

## Décision

Taxonomie `g03-classification` avec le tag `pii_contact` (nom imposé par l'API, qui refuse le point de
`pii.contact`), déclarés en Terraform (`infra/terraform/governance.tf`) avec `FINE_GRAINED_ACCESS_CONTROL`.
Le tag est posé sur `g03_warehouse.shipping_details.street_address` et `phone`
(`infra/policy-tags/g03_warehouse.shipping_details.json`). Seul le rôle « ingénieur » (Lucas) reçoit
`categoryFineGrainedReader` sur ce tag.

## Conséquences

- **Le refus n'a pas pu être démontré.** Notre propre lecture de `phone` a réussi
  (`notes/step10-refused.txt`), car le droit `fineGrainedGet` hérité au niveau du projet court-circuite
  le tag. C'est le cas que le cours décrit : une colonne bien classée et pourtant lisible par tous.
  Dans un projet par groupe, sans ce rôle hérité, la même configuration refuserait la lecture.
- Le tag tient tant que la table n'est pas recréée : `warehouse/load_native.sql`
  (`CREATE OR REPLACE … SELECT *`) le ferait disparaître. Le schéma tagué est versionné pour le
  réappliquer (`bq update --schema`).
- Le bronze n'est pas tagué (tables externes) : sa protection passe par les droits du bucket, réduits au
  step 10 (lecture retirée aux Viewers du projet).
- Ce qui nous ferait changer d'avis : si le rôle hérité ne peut pas être retiré, la classification ne
  protège rien ; il faudrait passer au dataset par niveau de sensibilité, avec des droits sur le
  dataset seulement, et accepter la copie des données.
