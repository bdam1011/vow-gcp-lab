
# 建立 Lab 環境的 VPC 和子網路
resource "google_compute_network" "lab-vpc" {
  name                    = "${local.environments}-vpc"
  auto_create_subnetworks = false
  project                 = "cloud-sre-poc-474602"
}

resource "google_compute_subnetwork" "gke-subnet" {
  name                     = "gke-tier44"
  ip_cidr_range            = "10.128.0.0/20"
  region                   = local.region
  network                  = google_compute_network.lab-vpc.id
  project                  = "cloud-sre-poc-474602"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "gke-pod44"
    ip_cidr_range = "10.132.0.0/14"
  }

  secondary_ip_range {
    range_name    = "gke-svc44"
    ip_cidr_range = "10.136.0.0/14"
  }
}

resource "google_compute_subnetwork" "web-tier-lb-subnet" {
  name                     = "web-tier-lb"
  ip_cidr_range            = "10.128.16.0/20"
  region                   = local.region
  network                  = google_compute_network.lab-vpc.id
  project                  = "cloud-sre-poc-474602"
  private_ip_google_access = true
}