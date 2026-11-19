# Step 10 : classification des colonnes et accès par classe.
# La taxonomie et ses tags vivent dans la même région que les datasets (europe-west1).

resource "google_data_catalog_taxonomy" "g03" {
  region                 = var.region
  display_name           = "g03-classification"
  description            = "Classification des colonnes du groupe 3 (step 10). Projet partagé : nom préfixé g03."
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

# pii.contact : la colonne identifie une personne ou permet de la contacter (rue, téléphone).
resource "google_data_catalog_policy_tag" "pii_contact" {
  taxonomy     = google_data_catalog_taxonomy.g03.id
  display_name = "pii_contact"
  description  = "Identifie ou permet de contacter une personne : rue, téléphone."
}

# Matrice d'accès : seul le rôle « ingénieur » lit pii.contact. Lucas tient ce rôle pour le projet.
# Les autres membres, analystes compris, sont refusés sur ces colonnes, même avec bigquery.admin.
resource "google_data_catalog_policy_tag_iam_member" "engineer_reads_pii_contact" {
  policy_tag = google_data_catalog_policy_tag.pii_contact.name
  role       = "roles/datacatalog.categoryFineGrainedReader"
  member     = "user:lduthu@albertschool.com"
}
