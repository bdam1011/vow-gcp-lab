locals {
  repo = {
    image = {
      mode = "STANDARD_REPOSITORY"
    },
    chart = {
      mode = "STANDARD_REPOSITORY"
    }
  }
}
# Lab 環境不需要跨環境的 GAR 拉取功能

resource "google_artifact_registry_repository" "apid_repo" {
  for_each      = local.repo
  project       = "cloud-sre-poc-474602"
  location      = local.region
  repository_id = each.key
  description   = each.key
  format        = "DOCKER"
  kms_key_name  = google_kms_crypto_key.crypto_key_01.id
  mode          = each.value.mode

  vulnerability_scanning_config {
    enablement_config = "INHERITED"
  }

  dynamic "docker_config" {
    for_each = each.value.mode == "STANDARD_REPOSITORY" ? [1] : []
    content {
      immutable_tags = true
    }
  }
  # 清理策略
  cleanup_policies {
    id     = "keep-5-versions" # 全部會保留5個版本
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  cleanup_policies {
    id     = "delete-older-than-90days" #任何image超過90天的會刪掉
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "7776000s"
    }
  }
  depends_on = [
    google_kms_crypto_key_iam_member.crypto_key_of_gar
  ]
}
# GAR Service Account for CMEK 這個Resource目前只有在beta才有2025/11/17
resource "google_project_service_identity" "gcp_sa_gar" {
  provider = google-beta.four64
  project  = "cloud-sre-poc-474602"
  service  = "artifactregistry.googleapis.com"
}
# CMEK需要權限
resource "google_kms_crypto_key_iam_member" "crypto_key_of_gar" {
  crypto_key_id = google_kms_crypto_key.crypto_key_01.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-42680339479@gcp-sa-artifactregistry.iam.gserviceaccount.com"
  depends_on = [
    google_kms_crypto_key.crypto_key_01,
    google_project_service_identity.gcp_sa_gar
  ]
}