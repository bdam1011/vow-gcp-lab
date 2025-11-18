# Terraform 變數設定檔 - Lab 環境

# 計費帳戶 ID (如需要)
billing_account_id = ""

# ==================== Load Balancer 和 CDN 設定 ====================
# 階段式部署設定 - 避免服務未部署時的錯誤

# 服務域名
service_domain = "vow-web-official.lab.com.tw"

# Load Balancer Backend Service - 服務部署完成後設為 true
enable_backend_service = false

# Health Check - 服務提供 /health 端點後設為 true
enable_health_check = false

# Cloud CDN - 服務穩定後可開啟以獲得更好效能 (會產生費用)
enable_cdn = false

# SSL 憑證類型 (使用自簽憑證，與 enable_backend_service 聯動)
ssl_certificate_type = "self_signed"

# 服務設定
service_port      = 80
health_check_path = "/health"

# CDN 快取時間 (秒) - 當 enable_cdn = true 時生效
cdn_cache_ttl = 3600

# ==================== 部署階段說明 ====================
#
# 階段一：基礎架構建立 (現在)
# - enable_backend_service = false
# - enable_health_check = false
# - enable_cdn = false
# - 會建立：Global IP、SSL 憑證、Load Balancer 基礎架構
#
# 階段二：服務部署完成後
# - 部署 vow-web-official 到 GKE
# - 修改 terraform.tfvars：enable_backend_service = true
# - 執行 terraform apply
#
# 階段三：健康檢查啟用
# - 確認服務提供 /health 端點
# - 修改 terraform.tfvars：enable_health_check = true
# - 執行 terraform apply
#
# 階段四：CDN 啟用 (可選)
# - 服務穩定運行後
# - 修改 terraform.tfvars：enable_cdn = true
# - 執行 terraform apply
# - 注意：CDN 會產生流量費用
