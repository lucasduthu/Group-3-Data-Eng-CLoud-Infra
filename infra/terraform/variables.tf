# Le groupe n'a pas de projet dédié : tout vit dans le projet partagé du cours
# (le projet "albert-de-msc2-26-g03" du guide n'existe pas, voir notes/step8.md).
variable "project_id" {
  type    = string
  default = "data-engineering-i1"
}

variable "region" {
  type    = string
  default="europe-west1"
}
