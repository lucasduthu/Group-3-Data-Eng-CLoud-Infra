# Step 8 · Your platform, declared — Lucas (review : Laura)

Toutes les preuves ci-dessous ont été produites le 2026-11-09 sur le Mac de Lucas
(Terraform 1.17.1 en local, 1.16.4 en CI, provider `hashicorp/google` 8.10.0, compte
`lduthu@albertschool.com` via les ADC). Code : [`infra/terraform/`](../infra/terraform/).

## Écarts par rapport au guide, et pourquoi

| Guide | Réalité | Preuve |
|---|---|---|
| projet `albert-de-msc2-26-g03` | **`data-engineering-i1`** (projet partagé du cours, n° 671557693556) | BigQuery : `Not found: Project albert-de-msc2-26-g03` ; le bucket bronze a `projectNumber: 671557693556` |
| datasets `bronze`, `warehouse`, `analytics` | **`g03_bronze`, `g03_warehouse`, `g03_analytics`** (préfixe de groupe dans le projet partagé) | `bq ls` du projet, utilisés par le DAG du step 7 |
| `google_service_account.airbyte_writer` + `google_storage_bucket_iam_member` | **non déclarés** : le service account n'a jamais existé (step 3, route 3) et nous n'avons pas le droit de le créer | `testIamPermissions` sur le projet : seuls `bigquery.datasets.create`, `storage.buckets.create` et `storage.buckets.list` sont accordés ; `iam.serviceAccounts.create` et `iam.serviceAccounts.list` sont refusés. La policy IAM du bucket ne contient aucun service account. |
| `Plan: 6 to import` | **`Plan: 4 to import`** (bucket + 3 datasets) | `step8-plan-1.txt` |
| commandes `gcloud storage …` | mêmes appels d'API via le client Python `google-cloud-storage` | Le compte `gcloud` actif de la machine est en `Reauthentication failed` (déjà noté au step 7). Les ADC, que Terraform utilise aussi, fonctionnent. |

Conformément à la consigne (« ne vous battez pas avec ça »), aucune IAM projet ni clé de service
account n'est déclarée.

## 8.1 Bucket de state

`gs://albert-de-msc2-26-g03-tfstate`, créé une seule fois à la main dans `data-engineering-i1` :

```
name: albert-de-msc2-26-g03-tfstate | location: EUROPE-WEST1 | project number: 671557693556
uniform_bucket_level_access: True | public_access_prevention: enforced
versioning_enabled: True
```

J'ai ajouté `public_access_prevention: enforced`, absent du guide : un state peut contenir des
secrets, et le bucket bronze a déjà cette protection. Le bucket de state n'est **pas** déclaré dans
Terraform : il héberge le state de cette configuration.

## 8.2 → 8.4 Adopter l'existant

- `versions.tf` : `required_version >= 1.9`, provider `~> 8.3` (résolu en 8.10.0), backend `gcs`
  avec `prefix = "platform"`.
- `main.tf` : la configuration du guide, recopiée telle quelle pour le bucket (lifecycle du step 2,
  identique à `infra/lifecycle.json`).
- `imports.tf` : 4 blocs `import`. Je les laisse en place : ils sont ignorés une fois appliqués et
  documentent l'adoption.

Le **premier** plan donnait directement `Plan: 4 to import, 0 to add, 0 to change, 0 to destroy`
([`step8-plan-1.txt`](step8-plan-1.txt)), sans diff sur `description`, `labels` ou
`default_table_expiration_ms`. Les datasets n'ont aucun de ces attributs et leurs ACL (`access`)
sont calculées : comme on ne les déclare pas, le provider ne cherche pas à les modifier.
`-generate-config-out` n'a donc pas servi.

Pour être sûr de n'appliquer que les imports, j'ai appliqué un plan enregistré
(`plan -out` → `apply <plan>`) :

```
Apply complete! Resources: 4 imported, 0 added, 0 changed, 0 destroyed.
```

puis `terraform plan` → `No changes. Your infrastructure matches the configuration.`
([`step8-no-changes.txt`](step8-no-changes.txt)).

## 8.5 Ce qui est commité, ce qui ne l'est pas

```
$ git status --short --ignored infra/terraform
A  infra/terraform/.terraform.lock.hcl
A  infra/terraform/imports.tf
A  infra/terraform/main.tf
A  infra/terraform/variables.tf
A  infra/terraform/versions.tf
!! infra/terraform/.terraform/
$ git log --all --oneline -- infra/terraform/terraform.tfstate | wc -l
0
```

Aucun `*.tfstate` local : le state vit uniquement dans
`gs://albert-de-msc2-26-g03-tfstate/platform/default.tfstate`, et chaque écriture crée une
génération (versioning). Le `.terraform.lock.hcl` contient les hashes `h1:` de `linux_amd64`
(la CI), `darwin_arm64` et `darwin_amd64` (`terraform providers lock -platform=…`).

## 8.6 CI

`.github/workflows/terraform.yml` : `fmt -check`, `init -backend=false`, `validate` sur toute PR qui
touche `infra/**`. Aucun secret nécessaire.

CI_SECTION

## 8.7 Drift provoqué, détecté, tranché

1. **Modification hors Terraform** : label `drift-test=mathilde` posé sur le bucket bronze
   (équivalent de `gcloud storage buckets update --update-labels`).

2. **Détection.** Premier constat : **`terraform plan` ne voit rien** et répond `No changes`
   ([`step8-drift-plan.txt`](step8-drift-plan.txt)). Depuis le provider google 5.0, `labels` n'est
   plus autoritaire : Terraform ne gère que les clés déclarées dans le code, et un label posé à côté
   n'apparaît que dans `effective_labels`. Ajouter `labels = {}` n'y change rien (testé). La dérive
   ne se voit qu'avec `terraform plan -refresh-only`
   ([`step8-drift-refresh-only.txt`](step8-drift-refresh-only.txt)) :

   ```
   # google_storage_bucket.bronze has changed
     ~ effective_labels            = {
         + "drift-test" = "mathilde"
       }
   ```

   Le diff `- "drift-test" = "mathilde" -> null` annoncé par le guide n'apparaît donc pas avec ce
   provider. **Conséquence pratique : un `plan` propre ne prouve pas l'absence de labels posés à la
   main.** Pour les auditer, il faut lancer `-refresh-only`.

3. **Décision : 3a, écraser.** `drift-test` est un label de test sans valeur métier. Depuis le L08,
   c'est le code qui fait foi (`infra/README.md`), et les vrais labels arriveront par le code au L09.
   L'adopter (3b) aurait inscrit dans `main.tf` un label poubelle.

   Comme Terraform ne supprime que les clés qu'il connaît, l'écrasement se fait en deux temps :
   1. déclarer `labels = { "drift-test" = "mathilde" }` puis `apply` (1 change, valeur identique
      sur GCP : Terraform prend la clé en charge) ;
   2. retirer la ligne puis `apply`, ce qui donne exactement le diff du guide
      ([`step8-drift-overwrite.txt`](step8-drift-overwrite.txt)) :

   ```
   ~ labels                      = {
       - "drift-test" = "mathilde" -> null
     }
   Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
   No changes. Your infrastructure matches the configuration.
   ```

   Labels du bucket relus ensuite via l'API : `{}`.

## 8.8 Checklist

- [x] **`terraform plan` → No changes sur le vrai projet** (`data-engineering-i1`), avant et après
  le drift.
- [x] **State dans le bucket versionné, aucun tfstate dans l'historique git** (§8.1, §8.5).
- [x] **Provider épinglé, `.terraform.lock.hcl` commité** (`~> 8.3`, verrouillé en 8.10.0).
- [x] **PR avec fmt et validate verts** (§8.6).
- [x] **Drift : sortie du plan et décision** (§8.7 : 3a, avec le piège des labels non autoritaires).

## Ce qui reste, et pour qui

| Qui | Quoi |
|---|---|
| Laura | Review. Point à trancher : garder ou supprimer `imports.tf` après merge (ignoré dans les deux cas). |
| Groupe | Le service account Airbyte et son IAM sur le bucket ne sont pas dans Terraform faute de droits. Si le prof nous ouvre `iam.serviceAccounts.create`, ajouter les deux ressources du guide (création, pas import). |
| Chacun | Lancer Terraform depuis `infra/terraform` avec les ADC (`gcloud auth application-default login`). Le verrou GCS (`default.tflock`) empêche deux `apply` simultanés. |
