# Step 5 · dbt (Mathilde)

## Phase 1 : préparation (en attendant les tables natives d'Emma)

| Étape | Statut | Preuve |
|---|---|---|
| Outils | ✅ | git, gh (`mathmdt`), gcloud sur `data-engineering-i1`, docker 28.5.1 |
| Branche | ✅ | `step5/dbt-project` créée depuis `main` à jour (`ac2829f`) |
| Copie du kit | ✅ | `dbt/` et `notes/step5-defects.sql` |
| Adaptation au projet partagé | ✅ | `profiles.yml` et `sources.yml` : projet `data-engineering-i1`, source `g03_warehouse`, dev `g03_dbt_md`, prod `g03_analytics` |
| `dbt debug` | ✅ | `Connection test: OK connection ok`, `All checks passed!` |
| `dbt deps` | ✅ | dbt_utils 1.4.1, `package-lock.yml` committé |
| `dbt parse` | ✅ | 12 modèles, 33 tests, 7 sources, aucun avertissement |
| Commit 1 | ✅ | `acb12a8` config du projet (vues / tables, cap 1 Go) |
| Commit 2 | ✅ | `1ba5c39` sources + freshness sur orders |
| Commit 3 | ✅ | `9899549` 6 modèles staging |
| Commit 4 | ✅ | `6aa9740` intermediate, marts, test singulier |
| Commit 5 | ✅ | `74c4287` requêtes de défauts |

## Choix techniques (pour l'oral)

- Projet dans le projet GCP partagé : tout est préfixé `g03_` pour ne jamais toucher aux ressources des autres groupes.
- `method: oauth` : dbt utilise la session gcloud de la personne qui le lance, aucune clé dans le repo.
- `maximum_bytes_billed` à 1 Go : une requête qui scannerait plus est refusée au lieu d'être facturée.
- Staging et intermediate en vues (pas de stockage, toujours à jour), marts en tables (lues souvent par le dashboard).
- Notes agrégées par produit avant la jointure (`int_product_ratings`) : évite le fan-out qui multiplierait les lignes de commande.
- Contrôle des secrets avant chaque commit : un seul résultat, le commentaire « Aucun secret ici » de `profiles.yml` (faux positif).

## Phase 2 : à faire quand les tables d'Emma sont prêtes

Défauts (chiffres « À REMPLIR »), plage de `dim_date`, `dbt build`, lineage, clone propre, PR.
