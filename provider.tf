terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.48.0"
    }
    google-beta = {
      source                = "hashicorp/google-beta"
      version               = "6.48.0"
      configuration_aliases = [google-beta.four64]
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }
}

provider "google" {
  project     = "cloud-sre-poc-474602"
  region      = local.region
  credentials = file("terraform-lab-creator-key.json")
}

provider "google-beta" {
  project     = "cloud-sre-poc-474602"
  region      = local.region
  credentials = file("terraform-lab-creator-key.json")
}

provider "google-beta" {
  project     = "cloud-sre-poc-474602"
  region      = local.region
  credentials = file("terraform-lab-creator-key.json")
  alias       = "four64"
}
# ==================== billing Provider ====================
variable "billing_account_id" {
  description = "The ID of the billing account to associate the Project with"
  default     = ""
}
# ========================================================