locals {
  pod_sa_list = [
    "vow-web-official",
    "vow-bff-official",
    "vow-svc-official",
    "vow-web-cms",
    "vow-bff-cms",
    "vow-svc-cms",
    "vow-util-keycloak"
  ]
}

resource "google_service_account" "pod_sa" { // GKE Pod
  for_each     = toset(local.pod_sa_list)
  project      = "cloud-sre-poc-474602"
  account_id   = "${local.env}gk-${each.key}"
  display_name = "${local.env}gk-${each.key}"
}