# 本地變量定義：Cloud SQL 配置
locals {
  cloud_sql_instances = {
    "${local.env}cs${local.apid}g01" = {
      database_version    = "POSTGRES_17"
      tier                = "db-custom-2-3840"
      disk_size           = 20
      encryption_key_name = google_kms_crypto_key.crypto_key_01.id
    }
  }
}

# 動態創建 Cloud SQL 實例
resource "google_sql_database_instance" "cloud_sql_psql_instances" {
  for_each            = local.cloud_sql_instances
  project             = "cloud-sre-poc-474602"
  name                = each.key
  database_version    = each.value.database_version
  encryption_key_name = each.value.encryption_key_name
  # TODO: 生產環境應使用 Secret Manager 管理密碼
  # root_password       = data.google_secret_manager_secret_version.sql_password.secret_data
  root_password       = "CUB@87936999" # Lab 環境臨時密碼，建議定期更換
  region              = local.region
  deletion_protection = true

  settings {
    tier              = each.value.tier
    availability_type = "REGIONAL"
    disk_size         = each.value.disk_size
    edition           = "ENTERPRISE"
    # IP 配置，使用私有網路
    ip_configuration {
      ssl_mode                                      = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.lab-vpc.id
      enable_private_path_for_google_cloud_services = true
    }

    # 設定數據庫標誌 (Database Flags)
    dynamic "database_flags" {
      for_each = [
        { name = "log_temp_files", value = "0" },
        { name = "log_duration", value = "on" },
        { name = "log_disconnections", value = "on" },
        { name = "log_lock_waits", value = "on" },
        { name = "log_connections", value = "on" },
        { name = "log_checkpoints", value = "on" },
        { name = "log_statement", value = "ddl" },
        { name = "cloudsql.enable_pgaudit", value = "on" },
        { name = "pgaudit.log", value = "read,write,function,role,ddl,misc" },
        { name = "max_connections", value = "1000" }
      ]
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    # 啟用查詢洞察功能 (Insights Config)
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    # 設定維護窗口 (Maintenance Window)
    maintenance_window {
      day          = 6  # 星期天 UTC 時間（台灣時間 +8 小時）
      hour         = 17 # 台灣時間凌晨1點（UTC+8）
      update_track = "canary"
    }

    # 禁止維護期間 (Deny Maintenance Period)
    deny_maintenance_period {
      start_date = "2024-10-11"
      end_date   = "2025-01-09"
      time       = "16:00:00"
    }

    # 備份配置 (Backup Configuration)
    backup_configuration {
      enabled                        = true
      start_time                     = "17:00" # 台灣時間凌晨1點（UTC+8）
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      location                       = local.region

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      settings[0].disk_size,
      settings[0].deny_maintenance_period,
    ]
  }
  depends_on = [
    google_project_service.project_services,
    google_service_networking_connection.private_vpc_connection
  ]
}

# 動態創建 DNS 記錄集 (DNS Record Set) - 暫時註解以避免權限問題
# resource "google_dns_record_set" "cloud_sql_dns_records" {
#   for_each     = google_sql_database_instance.cloud_sql_psql_instances
#   project      = local.env_network_project_id
#   name         = "${each.key}.${local.cloudsql_domain}.gcp.uwccb."
#   type         = "A"
#   ttl          = 300
#   managed_zone = local.cloudsql_domain
#   rrdatas      = [each.value.ip_address.0.ip_address]
#   depends_on = [
#     google_sql_database_instance.cloud_sql_psql_instances,
#     google_kms_crypto_key_iam_member.crypto_key_of_sql
#   ]
# }
# Cloud SQL Service Account for CMEK
resource "google_project_service_identity" "gcp_sa_cloud_sql" {
  provider = google-beta.four64
  project  = "cloud-sre-poc-474602"
  service  = "sqladmin.googleapis.com"
}
# Cloud SQL CMEK需要權限
resource "google_kms_crypto_key_iam_member" "crypto_key_of_sql" {
  crypto_key_id = google_kms_crypto_key.crypto_key_01.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-42680339479@gcp-sa-cloud-sql.iam.gserviceaccount.com"
  depends_on = [
    google_kms_crypto_key.crypto_key_01
  ]
}