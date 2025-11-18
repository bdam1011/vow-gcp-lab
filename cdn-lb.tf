# ==================== External Load Balancer with CDN ====================
# 為 vow-web-official 服務建立可控制 CDN 開關的 External Load Balancer
# 階段式部署：先建立基礎架構，服務就緒後再啟用完整功能

# ==================== Random ID for Dummy Service ====================
resource "random_id" "dummy" {
  byte_length = 2
}

# ==================== Global Static IP ====================
# Global Static IP 位址 (不論 CDN 開關都會建立)
resource "google_compute_global_address" "vow_web_lb_ip" {
  name = "${local.env}-${local.apid}-vow-web-lb-ip"

  labels = local.labels
}

# SSL 憑證 (與 enable_backend_service 聯動，階段式部署)
resource "google_compute_managed_ssl_certificate" "vow_web_ssl" {
  count = var.enable_backend_service && var.ssl_certificate_type == "managed" ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-ssl"

  managed {
    domains = [var.service_domain]
  }
}

# 自簽 SSL 憑證 (備用方案，同樣與 enable_backend_service 聯動)
resource "tls_private_key" "vow_web_key" {
  count = var.enable_backend_service && var.ssl_certificate_type == "self_signed" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "vow_web_cert" {
  count = var.enable_backend_service && var.ssl_certificate_type == "self_signed" ? 1 : 0

  private_key_pem   = tls_private_key.vow_web_key[0].private_key_pem
  is_ca_certificate = false

  subject {
    common_name  = var.service_domain
    organization = "Cathay United Bank LAB"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_compute_ssl_certificate" "vow_web_self_signed" {
  count = var.enable_backend_service && var.ssl_certificate_type == "self_signed" ? 1 : 0

  name        = "${local.env}-${local.apid}-vow-web-ssl-self"
  certificate = tls_self_signed_cert.vow_web_cert[0].cert_pem
  private_key = tls_private_key.vow_web_key[0].private_key_pem

  lifecycle {
    create_before_destroy = true
  }
}

# ==================== Health Check ====================
# Health Check (條件式建立)
resource "google_compute_health_check" "vow_web_health_check" {
  count = var.enable_health_check ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-hc"

  http_health_check {
    port         = var.service_port
    request_path = var.health_check_path
  }

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 3
  unhealthy_threshold = 3
}

# ==================== Backend Service ====================
# Backend Service (條件式建立，只有當服務部署後才啟用)
resource "google_compute_backend_service" "vow_web_backend" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-backend"

  protocol  = "HTTP"
  port_name = "http"

  # 連接到 GKE 的 NEG (需要後續建立對應的 NEG)
  # 這裡先用 Place holder，實際部署時需要對應到 GKE Service 的 NEG

  # 條件式 Health Check
  health_checks = var.enable_health_check ? [google_compute_health_check.vow_web_health_check[0].id] : []

  # CDN 配置 (條件式)
  enable_cdn = var.enable_cdn

  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode       = "USE_ORIGIN_HEADERS"
      default_ttl      = var.cdn_cache_ttl
      client_ttl       = var.cdn_cache_ttl
      max_ttl          = var.cdn_cache_ttl
      negative_caching = true
    }
  }

  # 連接埠和連線池設定
  connection_draining_timeout_sec = 300

  # session_affinity = "NONE"
}

# ==================== URL Map ====================
# URL Map (路由規則)
resource "google_compute_url_map" "vow_web_url_map" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-url-map"

  default_service = var.enable_backend_service ? google_compute_backend_service.vow_web_backend[0].id : null
}

# ==================== Proxies ====================
# HTTP Proxy
resource "google_compute_target_http_proxy" "vow_web_http" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-http"

  url_map = google_compute_url_map.vow_web_url_map[0].id
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "vow_web_https" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow_web-https"

  url_map = google_compute_url_map.vow_web_url_map[0].id

  # 根據 SSL 憑證類型設定
  ssl_certificates = var.ssl_certificate_type == "managed" ? [google_compute_managed_ssl_certificate.vow_web_ssl[0].id] : [google_compute_ssl_certificate.vow_web_self_signed[0].id]
}

# ==================== Forwarding Rules ====================
# HTTP Forwarding Rule
resource "google_compute_global_forwarding_rule" "vow_web_http" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-http"

  target     = google_compute_target_http_proxy.vow_web_http[0].id
  port_range = "80"
  ip_address = google_compute_global_address.vow_web_lb_ip.address

  labels = local.labels
}

# HTTPS Forwarding Rule
resource "google_compute_global_forwarding_rule" "vow_web_https" {
  count = var.enable_backend_service ? 1 : 0

  name = "${local.env}-${local.apid}-vow-web-https"

  target     = google_compute_target_https_proxy.vow_web_https[0].id
  port_range = "443"
  ip_address = google_compute_global_address.vow_web_lb_ip.address

  labels = local.labels
}

# ==================== GKE Service (準備) ====================
# GKE Service 的 NEG (Network Endpoint Group) 會在服務部署時自動建立
# 這裡提供相關資訊供後續 Kubernetes 配置使用

# Firewall 規則：允許 Load Balancer 存取 GKE nodes
resource "google_compute_firewall" "vow_web_lb_to_gke" {
  name    = "${local.env}-${local.apid}-vow-web-lb-to-gke"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = [var.service_port]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]     # GCP Load Balancer IP ranges
  target_tags   = ["gke-${local.env}-${local.apid}-node"] # GKE node tag
}

# 取得 VPC 網路資訊
data "google_compute_network" "default" {
  name = "lab-vpc"
}

# ==================== 輸出資訊 ====================

# 輸出 Load Balancer IP
output "vow_web_load_balancer_ip" {
  description = "vow-web-official Load Balancer 的 Global IP 位址"
  value       = google_compute_global_address.vow_web_lb_ip.address
}

# 輸出 SSL 憑證狀態
output "vow_web_ssl_certificate_status" {
  description = "SSL 憑證狀態"
  value       = var.ssl_certificate_type == "managed" ? (length(google_compute_managed_ssl_certificate.vow_web_ssl) > 0 ? google_compute_managed_ssl_certificate.vow_web_ssl[0].certificate_id : "SSL 憑證未建立") : "使用自簽憑證"
}

# 輸出部署階段建議
output "deployment_stage_info" {
  description = "部署階段資訊和建議"
  value = {
    current_stage = var.enable_backend_service ? "完整功能已啟用" : "基礎架構已建立"
    next_steps = var.enable_backend_service ? [
      "CDN 已${var.enable_cdn ? "啟用" : "停用"}",
      "Health Check 已${var.enable_health_check ? "啟用" : "停用"}",
      "監控服務狀態"
      ] : [
      "1. 部署 vow-web-official 服務到 GKE",
      "2. 設定 terraform.tfvars: enable_backend_service = true",
      "3. 服務穩定後設定: enable_health_check = true",
      "4. 需要時設定: enable_cdn = true"
    ]
    ssl_domain        = var.service_domain
    health_check_path = var.health_check_path
  }
}
