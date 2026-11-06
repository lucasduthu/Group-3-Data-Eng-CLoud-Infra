# ADR-0006: Publier les images Docker sur Docker Hub

- **Status:** proposed
- **Date:** 2026-11-05
- **Author:** Emma Neumayer
- **Lesson:** Step 6 — Images Docker

## Context

L’équipe doit partager les images d’ingestion et de dbt pour leur
exécution locale et leur utilisation dans Airflow.

La création du dépôt Artifact Registry `g03-images` dans le projet
`data-engineering-i1`, région `europe-west1`, a échoué le 5 novembre 2026 :
le compte utilisé ne possède pas la permission
`artifactregistry.repositories.create`.

Les machines de l’équipe nécessitent des images compatibles avec
`linux/amd64` et `linux/arm64`.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| Google Artifact Registry | Intégration GCP et contrôle des accès par IAM | Création du dépôt bloquée par les permissions |
| Docker Hub | Publication possible avec le compte disponible, récupération par l’équipe | Dépendance externe, limites de téléchargement et visibilité publique des images |
| Images locales uniquement | Aucun registre nécessaire | Pas de récupération centralisée pour l’équipe et Airflow |

## Criteria

- **Accès immédiat :** Docker Hub est utilisable ; Artifact Registry nécessite une intervention sur les droits
- **Partage :** un registre permet à Lucas de récupérer les images sans les reconstruire
- **Compatibilité :** les deux architectures doivent être publiées
- **Traçabilité :** chaque version doit être associée à un commit et à un digest
- **Identifiants :** les secrets doivent rester hors des images publiées

## Decision

Publier `emmaneum/g03-ingest` et `emmaneum/g03-dbt` sur Docker Hub,
pour `linux/amd64` et `linux/arm64`.

Utiliser des tags `YYYY-MM-DD-<git-sha-court>`, ne pas les réaffecter
à une autre construction et fixer les exécutions reproductibles
par digest. Les références sont conservées dans `notes/step6-tag.txt`.

## Consequences

L’équipe peut récupérer les images sans reconstruire l’environnement
ni obtenir de nouveaux droits GCP.

Les images sont publiques : les identifiants restent externes et sont
fournis au lancement. Les applications s’exécutent avec un utilisateur
non root, UID 10001.

Docker Hub ajoute une dépendance externe et des limites de téléchargement.
Une migration vers Artifact Registry reste possible lorsque les droits
seront disponibles.

La procédure de conservation est manuelle : garder la version utilisée
par Airflow et les trois versions précédentes disponibles.
Vérifier les consommateurs avant toute suppression.

Les dépendances d’ingestion sont verrouillées. Les versions de Python,
dbt-core et dbt-bigquery sont fixées, mais les dépendances transitives
de dbt et les paquets système ne le sont pas entièrement.
Une reconstruction peut donc produire un autre digest.

Les tests après suppression des références locales et téléchargement
ont confirmé les mêmes digests, 163 commandes extraites et le bilan dbt
`PASS=46 WARN=2 ERROR=0`.

Preuves : `notes/step6-reproduce.txt`
Procédure : `docs/reproduce.md`