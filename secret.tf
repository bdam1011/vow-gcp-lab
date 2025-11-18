locals {
  secretmanagers = {
    "${local.env}su${local.apid}g01" = { // cloudsql-username
      label = "cloudsql-username"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-util-keycloak"].email}"
      ]
    }
    "${local.env}sp${local.apid}g01" = { // cloudsql-password
      label = "cloudsql-password"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-util-keycloak"].email}"
      ]
    }
    "${local.env}sc${local.apid}g01" = { // cloudsql-ca
      label = "cloudsql-ca"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-util-keycloak"].email}"
      ]
    }
    "${local.env}sc${local.apid}g02" = { // cloudsql-client-cert
      label = "cloudsql-client-cert"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-util-keycloak"].email}"
      ]
    }
    "${local.env}sc${local.apid}g03" = { // cloudsql-client-key
      label = "cloudsql-client-key"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-svc-cms"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-svc-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-util-keycloak"].email}"
      ]
    }
    "${local.env}sp${local.apid}g02" = { // redis-auth
      label = "redis-auth"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-bff-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-bff-cms"].email}"
      ]
    }
    "${local.env}sc${local.apid}g04" = { // redis-ca
      label = "redis-ca"
      members = [
        "serviceAccount:${google_service_account.pod_sa["vow-bff-official"].email}",
        "serviceAccount:${google_service_account.pod_sa["vow-bff-cms"].email}"
      ]
    }
    "${local.env}sc${local.apid}g90" = {
      label = "truesight"
      members = [
        "serviceAccount:cloud-sre-poc-474602@appspot.gserviceaccount.com"
      ]
    }
    "${local.env}sc${local.apid}g91" = {
      label = "cteam"
      members = [
        "serviceAccount:cloud-sre-poc-474602@appspot.gserviceaccount.com"
      ]
    }
    "${local.env}sc${local.apid}g92" = {
      label = "notify-mail"
      members = [
        "serviceAccount:cloud-sre-poc-474602@appspot.gserviceaccount.com"
      ]
    }
  }
}

resource "google_secret_manager_secret" "manager_secret" {
  for_each  = local.secretmanagers
  project   = "cloud-sre-poc-474602"
  secret_id = each.key
  labels = {
    label = each.value.label
  }
  replication {
    user_managed {
      replicas { location = local.region }
    }
  }
}

resource "google_secret_manager_secret_iam_binding" "iam_binding" {
  for_each   = local.secretmanagers
  project    = "cloud-sre-poc-474602"
  secret_id  = google_secret_manager_secret.manager_secret["${each.key}"].secret_id
  role       = "roles/secretmanager.secretAccessor"
  members    = each.value.members
  depends_on = [google_secret_manager_secret.manager_secret]
}
### 針對shareservice project
# 暫時註解，因為外部專案的 secret 不存在
# resource "google_secret_manager_secret_iam_member" "dscsharedservicesg93_iam_binding" {
#   project   = local.env_acm_project_id
#   secret_id = "dscsharedservicesg93"
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:cloud-sre-poc-474602@appspot.gserviceaccount.com"
# }