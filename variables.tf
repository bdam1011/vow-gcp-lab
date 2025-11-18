# Load Balancer 和 CDN 控制變數

# 啟用 Load Balancer Backend Service
variable "enable_backend_service" {
  description = "啟用 Load Balancer Backend Service (服務部署後設為 true)"
  type        = bool
  default     = false
}

# 啟用 Health Check
variable "enable_health_check" {
  description = "啟用 Health Check 檢查 (服務準備就緒後設為 true)"
  type        = bool
  default     = false
}

# 啟用 Cloud CDN
variable "enable_cdn" {
  description = "啟用 Cloud CDN 功能 (產生費用，建議服務穩定後開啟)"
  type        = bool
  default     = false
}

# 服務域名
variable "service_domain" {
  description = "vow-web-official 服務的域名"
  type        = string
  default     = "vow.example.com"
}

# 服務端口
variable "service_port" {
  description = "vow-web-official 服務的端口"
  type        = number
  default     = 80
}

# 健康檢查路徑
variable "health_check_path" {
  description = "健康檢查的路徑"
  type        = string
  default     = "/health"
}

# SSL 憑證產生方式
variable "ssl_certificate_type" {
  description = "SSL 憑證類型 (managed = Google Managed, self_signed = 自簽憑證)"
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["managed", "self_signed"], var.ssl_certificate_type)
    error_message = "SSL 憑證類型必須是 'managed' 或 'self_signed'。"
  }
}

# CDN 快取時間設定
variable "cdn_cache_ttl" {
  description = "CDN 快取存活時間 (秒)"
  type        = number
  default     = 3600

  validation {
    condition     = var.cdn_cache_ttl > 0
    error_message = "CDN 快取時間必須大於 0 秒。"
  }
}