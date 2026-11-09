terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3" # même contrainte que le lab du cours
    }
  }

  backend "gcs" {
    bucket = "albert-de-msc2-26-g03-tfstate"
    prefix = "platform"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
