# Private Service Connect for Cloud SQL
resource "google_compute_global_address" "private_ip_alloc" {
  provider      = google-beta
  project       = "cloud-sre-poc-474602"
  name          = "gcp-sql-private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.lab-vpc.id
  description   = "Private IP range for Cloud SQL private connections"
}

# VPC peering for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = google_compute_network.lab-vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  deletion_policy         = "ABANDON"
}