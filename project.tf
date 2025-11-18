locals {
  project_name = "${lower(local.apid_full_name)}-${lower(local.environments)}"
  parent_id    = ""
  activate_apis = [
    "containerscanning.googleapis.com",
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouderrorreporting.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudscheduler.googleapis.com",
    "dns.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkmanagement.googleapis.com",
    "osconfig.googleapis.com",
    "redis.googleapis.com",
    "run.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "sqladmin.googleapis.com",
    "recommender.googleapis.com",
    "cloudfunctions.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "gkehub.googleapis.com",
    "anthos.googleapis.com",
    "containersecurity.googleapis.com"
  ]
}
# 使用現有專案，不需要建立新專案
resource "google_project_service" "project_services" {
  for_each                   = toset(local.activate_apis)
  project                    = "cloud-sre-poc-474602"
  service                    = each.value
  disable_on_destroy         = true
  disable_dependent_services = true
}