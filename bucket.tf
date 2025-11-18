
locals {
  buckets = {
    "${local.apid}-${local.environments}-chr" = {
      location                    = local.region,
      force_destroy               = false,
      uniform_bucket_level_access = false,
      versioning                  = false,
      storage_class               = "REGIONAL"
      labels = {
        location = "",
        name     = ""
      },
      encryption = {
        enabled        = true
        encryption_key = google_kms_crypto_key.crypto_key_01.id
      },
      retention_policy = {
        enabled          = false
        retention_period = null, // The value must be less than 2,147,483,647 seconds.
        is_locked        = false
      },
      logging = {
        enabled           = false
        log_bucket        = null,
        log_object_prefix = null
      },
      website = {
        enabled          = false
        main_page_suffix = null,
        not_found_page   = null
      }
      iam_bindings = {
        "roles/storage.admin" = [
          "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
          "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}"
        ]
      }
    }
  }
}
resource "google_storage_bucket" "bucket" {
  for_each      = local.buckets
  name          = each.key
  project       = "cloud-sre-poc-474602"
  location      = each.value.location
  storage_class = each.value.storage_class

  force_destroy               = each.value.force_destroy
  uniform_bucket_level_access = each.value.uniform_bucket_level_access

  versioning {
    enabled = each.value.versioning
  }
  labels = merge(
    each.value.labels,
    {
      name          = lower(each.key)
      location      = lower(each.value.location)
      storage_class = lower(each.value.storage_class)
    }
  )

  dynamic "encryption" {
    for_each = each.value.encryption.enabled ? [1] : []
    content {
      default_kms_key_name = each.value.encryption.encryption_key
    }
  }

  dynamic "retention_policy" {
    for_each = each.value.retention_policy.enabled ? [1] : []
    content {
      retention_period = each.value.retention_policy.retention_period * 24 * 60 * 60 # Convert days to seconds
      is_locked        = each.value.retention_policy.is_locked
    }
  }
  ## 套用 VPC Service control 的專案需先將 logging 設定註解，bucket 創建出來後再解除註解後設定
  dynamic "logging" {
    for_each = each.value.logging.enabled ? [1] : []
    content {
      log_bucket        = each.value.logging.log_bucket
      log_object_prefix = each.value.logging.log_object_prefix
    }
  }

  dynamic "website" {
    for_each = each.value.website.enabled ? [1] : []
    content {
      main_page_suffix = each.value.website.main_page_suffix
      not_found_page   = each.value.website.not_found_page
    }
  }
}

resource "google_storage_bucket_iam_binding" "bucket_iam" {
  for_each = merge([
    for bucket_name, bucket in local.buckets : {
      for role, members in bucket.iam_bindings :
      "${bucket_name}/${role}" => {
        bucket  = bucket_name
        role    = role
        members = members
      }
    }
  ]...)
  bucket  = google_storage_bucket.bucket[each.value.bucket].name
  role    = each.value.role
  members = each.value.members
}

# 建立 Storage 服務帳戶身份
resource "google_project_service_identity" "gcp_sa_storage" {
  provider = google-beta
  project  = "cloud-sre-poc-474602"
  service  = "storage.googleapis.com"
}

# Bucket CMEK需要權限
resource "google_kms_crypto_key_iam_member" "crypto_key_of_Bucket" {
  crypto_key_id = google_kms_crypto_key.crypto_key_01.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${local.project_number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on = [
    google_kms_crypto_key.crypto_key_01,
    google_project_service_identity.gcp_sa_storage
  ]
}
