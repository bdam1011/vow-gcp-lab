resource "google_redis_instance" "redis_instance" {
  project        = "cloud-sre-poc-474602"
  name           = "${local.env}mr${local.apid}g01"
  tier           = "STANDARD_HA"
  memory_size_gb = 1

  authorized_network = google_compute_network.lab-vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  redis_version           = "REDIS_7_2"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  customer_managed_key    = google_kms_crypto_key.crypto_key_01.id
  redis_configs = {
    "notify-keyspace-events" : "Egx"
  }
  maintenance_policy {
    weekly_maintenance_window {
      day = "SATURDAY"
      start_time {
        hours   = 0
        minutes = 00
        seconds = 0
      }
    }
  }

  # 依賴 VPC peering 連線完成
  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
}

# DNS 記錄在 Lab 環境中可選，註解掉以避免依賴外部 DNS 服務
# resource "google_dns_record_set" "redis_recored_A" {
#   project      = local.env_network_project_id
#   name         = "${local.env}mr${local.apid}g01.${local.redis_domain}.gcp.uwccb."
#   type         = "A"
#   ttl          = 300
#   managed_zone = local.redis_domain
#   rrdatas      = [google_redis_instance.redis_instance.host]
#   depends_on = [
#     google_redis_instance.redis_instance
#   ]
# }

# Redis CMEK需要權限
resource "google_kms_crypto_key_iam_member" "crypto_key_of_redis" {
  crypto_key_id = google_kms_crypto_key.crypto_key_01.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-42680339479@cloud-redis.iam.gserviceaccount.com"
  depends_on = [
    google_kms_crypto_key.crypto_key_01
  ]
}