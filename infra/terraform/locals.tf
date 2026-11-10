# Convention de labels du groupe 3 (step 9). Quatre clés communes + component par ressource.
# team        : à qui revient le coût dans le projet partagé data-engineering-i1
# course      : le cours qui finance la dépense
# environment : course (pas de prod réelle)
# managed_by  : terraform, pour distinguer ce qui est déclaré de ce qui est créé à la main
locals {
  common_labels = {
    team        = "g03"
    course      = "msa-dat09-02"
    environment = "course"
    managed_by  = "terraform"
  }
}
