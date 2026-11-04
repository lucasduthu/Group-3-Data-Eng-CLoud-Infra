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

## Phase 2 : sur les tables natives d'Emma (2026-11-04)

| Étape | Statut | Preuve |
|---|---|---|
| Merge de `main` | ✅ | `83d3981`, steps 3 et 4 intégrés sans conflit |
| Colonnes réelles de `g03_warehouse` | ✅ | `INFORMATION_SCHEMA.COLUMNS` : toutes les colonnes lues par les staging existent ; `order_date` en DATE sur `orders` et `order_items` |
| Écart trouvé | ✅ corrigé | `step5-defects.sql` visait `albert-de-msc2-26-g03.warehouse` → `data-engineering-i1.g03_warehouse` (`24c08f3`) |
| Accès en lecture à `g03_warehouse` | ✅ | Refusé au premier essai (`bigquery.tables.get`), ouvert par Emma |
| Requêtes de défauts | ✅ | `notes/step5-defects-results.txt` (`6b45f83`) |
| Remplissage des « À REMPLIR » | ✅ | `c1e861d` |
| `dim_date` | ✅ | Commandes du 2023-09-15 au 2026-09-14, couvertes par 2023-01-01 → 2027-12-31 |
| `dbt deps` | ✅ | dbt_utils, `package-lock.yml` inchangé |
| `dbt build` n°1 | ❌ | `assert_line_revenue_is_positive` : 30 lignes à 0 → 6 modèles sautés |
| Correction du modèle | ✅ | `1712c10`, test inchangé |
| `dbt build` n°2 | ✅ | PASS=44, WARN=1, ERROR=0, SKIP=0 (45 nœuds) |
| `dbt docs generate` | ✅ | `target/catalog.json` + `docs/lineage.md` (`014a254`) |
| PR | ✅ | [#4](https://github.com/lucasduthu/Group-3-Data-Eng-CLoud-Infra/pull/4), reviewer `eneumayer-lang` |
| Clone propre | ✅ | Clone neuf de `9a038ab` : `dbt deps` + `dbt build` → PASS=44, WARN=1, ERROR=0, SKIP=0, identique au build n°2 |
| Capture du lignage | ✅ | `docs/lineage.png` (vue graphe de `dbt docs serve`, Chrome headless 1600x1000) |
| Corrections de la review d'Emma | ✅ | Prix à 0 signalé, pas remplacé ; tests revus ; fraîcheur sur `ingest_date` |
| `dbt build` n°3 | ✅ | PASS=46, WARN=2 (6 noms NULL, 30 lignes à prix 0), ERROR=0, SKIP=0 (48 nœuds) ; 1 386 640 unités dans la source comme dans `fct_daily_demand` |

## Défauts trouvés

| Requête | Résultat | Effet sur les modèles |
|---|---|---|
| 1. Colonne parasite | `Unnamed__0` sur 6 des 7 tables | Jamais sélectionnée |
| 2. Avis vides | `r_desc` : 0 vide, 110 faits d'espaces, 27 NULL sur 111 322 ; `title` : 0 et 0 | `r_desc` → NULL ; `title` repris tel quel |
| 3. Commandes en double | 0 | `QUALIFY` retiré de `stg_orders` |
| 4. Lignes en double | 0 | `GROUP BY` retiré de `stg_order_items` |
| 5. Plusieurs adresses par défaut | 0 ; 0 acheteur sans adresse | `QUALIFY` retiré de `stg_addresses` |
| 6. Produits | 0 doublon, 6 noms NULL (0 vide, 0 blanc) | Pas de `NULLIF` ; test en warn sur `dim_product` |
| 7. Avis | Notes de 1 à 5, 0 doublon, 0 lien orphelin | Rien |
| 8. Plage de dates | 2023-09-15 → 2026-09-14 | Plage de `dim_date` gardée |
| 9. Lignes orphelines | 0 | Rien |

Les déduplications retirées restent protégées : les tests de grain bloquent le pipeline si un doublon apparaît.

## Test en échec et correction (pour l'oral)

- **Symptôme :** `assert_line_revenue_is_positive` renvoie 30 lignes, toutes avec `price_at_purchase = 0.0`, sur 5 produits.
- **Cause :** sur les 408 560 lignes, `price_at_purchase` vaut exactement `ROUND(product.price, 2)`. Ces 5 produits ont un prix catalogue sous 0,005, que l'arrondi ramène à 0,00. Les ventes sont réelles.
- **Première correction (`1712c10`, remplacée) :** `int_order_items` ajoutait `unit_price`, qui reprenait le prix catalogue quand le prix arrondi valait 0.
- **Correction après la review d'Emma :** plus aucun remplacement. `line_revenue = qty * price_at_purchase` (0 sur les 30 lignes), drapeau `is_zero_price_anomaly` jusqu'à `fct_order_items`, test `assert_line_revenue_is_positive` limité à `< 0 OR IS NULL` (error), nouveau test `assert_no_zero_price_lines` (warn, 30 lignes). Les lignes sont gardées.
- **Vérification :** 1 386 640 unités dans `order_items` comme dans `fct_daily_demand` ; 0 ligne `UNKNOWN`.
- **À signaler :** les prix catalogue de ces produits (de 0,0004 à 0,0047) paraissent anormaux. C'est un sujet pour la source, pas pour dbt.

## Chiffres des marts (`g03_dbt_md`)

| Table | Lignes |
|---|---|
| `fct_order_items` | 408 560 |
| `fct_daily_demand` | 365 512 |
| `dim_product` | 42 858 |
| `dim_date` | 1 826 |

## Clone propre (2026-11-04)

Le but : vérifier que la branche se construit sans rien de local (`dbt_packages`, `target`, `.user.yml`).

- `gh repo clone lucasduthu/Group-3-Data-Eng-CLoud-Infra` dans un dossier temporaire neuf, puis `git checkout step5/dbt-project` (commit `9a038ab`).
- Même image (`charlestng/dbt-bigquery:1.12.1`), mêmes identifiants (session gcloud montée en lecture seule, `DBT_USER=md`).
- `dbt deps` : dbt_utils 1.4.1 installé depuis `package-lock.yml`, sans étape manuelle.

| | Build n°2 (repo de travail) | Clone propre |
|---|---|---|
| PASS | 44 | 44 |
| WARN | 1 (6 noms de produit NULL) | 1 (le même) |
| ERROR | 0 | 0 |
| SKIP | 0 | 0 |
| Total | 45 | 45 |

Puis `dbt docs generate` et `dbt docs serve --host 0.0.0.0 --port 8080` dans ce clone ; la capture du graphe est dans `docs/lineage.png`.

## Fraîcheur des sources (2026-11-04, `notes/step5-freshness.txt`)

- `orders` est en **ERROR STALE** : les données du cours s'arrêtent au 2026-09-14 (51,7 jours avant le contrôle). Le contrôle échoue donc, et c'est attendu tant que le step 7 ne charge pas de jours récents.
- Pour `orders`, le contrôle porte sur `order_date`, un proxy (la date de commande, pas celle du chargement), car la table n'a aucune colonne de chargement. Les 5 tables qui ont `ingest_date` (`review`, `product_reviews`, `product`, `customer_shipping`, `shipping_details`) l'utilisent directement.
- Ces 5 tables sont en **WARN** : leur dernier chargement date du 2026-11-03 (1,7 jour), au-delà du seuil d'un jour. C'est aussi attendu sans le chargement quotidien du DAG du step 7.
