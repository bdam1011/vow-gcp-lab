locals {
  ap_group_iam_bindings = {
    viewer = {
      role    = "roles/viewer"
      members = ["group:${local.ap_group}"]
    }
    iam_securityReviewer = {
      role = "roles/iam.securityReviewer"
      members = [
        "group:${local.ap_group}"
      ]
    }
    cloudsupport_techSupportEditor = {
      role    = "roles/cloudsupport.techSupportEditor"
      members = ["group:${local.ap_group}"]
    }
  }
}
# ap_group需要的相關iam設定
resource "google_project_iam_binding" "ap_group_iam_bindings" {
  for_each = local.ap_group_iam_bindings
  project  = "cloud-sre-poc-474602"
  role     = each.value.role
  members  = each.value.members
}

# Cloud Function build權限
resource "google_project_iam_member" "cloudbuild_developer" {
  for_each = toset([
    "serviceAccount:42680339479-compute@developer.gserviceaccount.com"
  ])
  project = "cloud-sre-poc-474602"
  role    = "roles/cloudbuild.builds.builder"
  member  = each.key
}

# Cloud Function & cloud run使用connector網路權限
resource "google_project_iam_member" "vpcaccess_user" {
  for_each = toset([
    "serviceAccount:service-42680339479@gcf-admin-robot.iam.gserviceaccount.com",
    "serviceAccount:service-42680339479@serverless-robot-prod.iam.gserviceaccount.com"
  ])
  project = "cloud-sre-poc-474602"
  role    = "roles/vpcaccess.user"
  member  = each.key
}

# Cloud SQL client
resource "google_project_iam_member" "cloudsql_client" {
  for_each = toset([
    "vow-svc-official",
    "vow-svc-cms",
    "vow-util-keycloak"
  ])
  project    = "cloud-sre-poc-474602"
  role       = "roles/cloudsql.client"
  member     = "serviceAccount:${google_service_account.pod_sa[each.key].email}"
  depends_on = [google_project_service.project_services]
}

# Cloudtrace Agent
resource "google_project_iam_member" "Cloudtrace_Agent" {
  for_each = toset([
    "vow-web-official",
    "vow-bff-official",
    "vow-svc-official",
    "vow-web-cms",
    "vow-bff-cms",
    "vow-svc-cms",
    "vow-util-keycloak"
  ])
  project    = "cloud-sre-poc-474602"
  role       = "roles/cloudtrace.agent"
  member     = "serviceAccount:${google_service_account.pod_sa[each.key].email}"
  depends_on = [google_project_service.project_services]
}