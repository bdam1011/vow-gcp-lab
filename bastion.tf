# ==================== Bastion VM for Redis Access ====================
# 建立 Bastion VM 作為跳板機，用於存取 VPC 內的 Redis 實例

# Bastion VM 服務帳戶
resource "google_service_account" "bastion_sa" {
  account_id   = "${local.env}-${local.apid}-bastion-sa"
  display_name = "Redis Bastion Service Account"
  project      = local.project_id
}

# 授予服務帳戶 Redis 存取權限
resource "google_project_iam_member" "bastion_redis_access" {
  project = local.project_id
  role    = "roles/redis.viewer"
  member  = "serviceAccount:${google_service_account.bastion_sa.email}"
}

# 授予服務帳戶 Secret Manager 存取權限（用於取得 Redis 憑證）
resource "google_project_iam_member" "bastion_secret_access" {
  project = local.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.bastion_sa.email}"
}

# Bastion VM 啟動腳本 - 安裝必要工具
locals {
  bastion_startup_script = <<-EOT
    #!/bin/bash
    set -e

    # 更新系統
    apt-get update

    # 安裝必要工具
    apt-get install -y redis-tools curl wget jq

    # 安裝 Google Cloud SDK（如果沒有預裝）
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
      apt-get install -y apt-transport-https ca-certificates gnupg
      curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
      apt-get update
      apt-get install -y google-cloud-sdk
    fi

    # 建立Redis連線測試腳本
    cat > /home/redis_test.sh << 'EOF'
    #!/bin/bash
    # 取得Redis認證資訊並測試連線

    PROJECT_ID="${local.project_id}"
    REDIS_INSTANCE="${local.env}mr${local.apid}g01"
    REDIS_SECRET="${local.env}sp${local.apid}g02"
    REDIS_CA_SECRET="${local.env}sc${local.apid}g04"

    echo "=== Redis 連線測試 ==="

    # 取得密碼
    REDIS_PASSWORD=$(gcloud secrets versions access latest \\
        --secret=$REDIS_SECRET \\
        --project=$PROJECT_ID)

    # 取得 CA 憑證
    gcloud secrets versions access latest \\
        --secret=$REDIS_CA_SECRET \\
        --project=$PROJECT_ID \\
        --out-file=/tmp/redis-ca.crt

    # 取得 Redis IP
    REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE \\
        --region=${local.region} \\
        --project=$PROJECT_ID \\
        --format="value(host)")

    echo "Redis 主機: $REDIS_HOST"
    echo "Redis 連接埠: 6378"

    # 測試連線
    if REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \\
        -h $REDIS_HOST \\
        -p 6378 \\
        --tls \\
        --cacert /tmp/redis-ca.crt \\
        ping; then
        echo "✓ Redis 連線成功"
    else
        echo "✗ Redis 連線失敗"
        exit 1
    fi

    # 清理
    rm -f /tmp/redis-ca.crt
    EOF

    chmod +x /home/redis_test.sh
    chown $(whoami):$(whoami) /home/redis_test.sh

    echo "Bastion VM 設定完成"
  EOT
}

# 建立 Bastion VM
resource "google_compute_instance" "bastion_vm" {
  name         = "${local.env}-${local.apid}-redis-bastion"
  machine_type = "e2-micro"
  zone         = "${local.region}-a"
  project      = local.project_id

  tags = ["bastion-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gke-subnet.name
    network_ip = "10.128.0.100" # 固定內部 IP
  }

  service_account {
    email  = google_service_account.bastion_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = local.bastion_startup_script
  }

  labels = local.labels

  # 允許現場更新，避免重新建立時中斷連線
  lifecycle {
    create_before_destroy = true
  }
}

# Bastion VM 防火牆規則 - 允許 IAP SSH
resource "google_compute_firewall" "bastion_allow_iap" {
  name    = "${local.env}-${local.apid}-bastion-allow-iap"
  network = google_compute_network.lab-vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP IP 範圍
  target_tags   = ["bastion-vm"]

  description = "允許 IAP 存取 Bastion VM SSH"
}

# Redis 防火牆規則 - 僅允許從 Bastion VM 存取
resource "google_compute_firewall" "bastion_to_redis" {
  name    = "${local.env}-${local.apid}-bastion-to-redis"
  network = google_compute_network.lab-vpc.name

  allow {
    protocol = "tcp"
    ports    = ["6378"]
  }

  source_tags = ["bastion-vm"]
  description = "僅允許 Bastion VM 存取 Redis"
}

# 定義開發者清單
locals {
  developers = [
    "user:00597438@lab.cathaybkdev.com.tw",
    "user:00599089@lab.cathaybkdev.com.tw"
  ]
}

# IAP Tunnel 權限給開發者
resource "google_project_iam_member" "iap_tunnel_developer" {
  for_each = toset(local.developers)
  project  = local.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

# Compute Engine 權限給開發者（建立和操作 VM）
resource "google_project_iam_member" "compute_developer" {
  for_each = toset(local.developers)
  project  = local.project_id
  role     = "roles/compute.instanceAdmin.v1"
  member   = each.value
}

# 輸出 Bastion VM 資訊
output "bastion_vm_name" {
  description = "Bastion VM 名稱"
  value       = google_compute_instance.bastion_vm.name
}

output "bastion_vm_zone" {
  description = "Bastion VM 所在區域"
  value       = google_compute_instance.bastion_vm.zone
}

output "bastion_vm_internal_ip" {
  description = "Bastion VM 內部 IP"
  value       = google_compute_instance.bastion_vm.network_interface[0].network_ip
}

output "bastion_service_account" {
  description = "Bastion VM 服務帳戶"
  value       = google_service_account.bastion_sa.email
}
