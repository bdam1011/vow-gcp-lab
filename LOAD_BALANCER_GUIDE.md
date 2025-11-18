# VOW Web Official Load Balancer 與 CDN 部署指南

## 概述

本指南專注於 vow-web-official 服務的 External Load Balancer 和 Cloud CDN 配置，採用階段式部署策略，確保服務安全、高效地對外提供。

> 💡 **前置準備**: 在開始之前，請先閱讀 [VOW_開發指南.md](./VOW_開發指南.md) 了解基礎架構配置和開發環境設定。

## 檔案結構

- `variables.tf` - Load Balancer 和 CDN 控制變數
- `cdn-lb.tf` - 主要的 Load Balancer 和 CDN 配置
- `terraform.tfvars` - 階段式部署設定
- `vow-web-official-service-example.yaml` - Kubernetes Service 配置範例

## 部署階段

### 🔸 階段一：基礎架構建立 (現在可執行)

**目標：** 建立 Load Balancer 基礎架構，不會有健康檢查錯誤

**設定：**
```hcl
# terraform.tfvars
enable_backend_service = false
enable_health_check = false
enable_cdn = false
```

**執行：**
```bash
terraform plan
terraform apply
```

**建立資源：**
- ✅ Global Static IP
- ✅ SSL 憑證 (Google Managed)
- ✅ Load Balancer 基礎架構
- ✅ Forwarding Rules (HTTP/HTTPS)
- ✅ Firewall 規則

**取得資訊：**
```bash
terraform output vow_web_load_balancer_ip
terraform output deployment_stage_info
```

---

### 🔸 階段二：服務部署完成後

**目標：** 啟用 Load Balancer Backend Service

**前提條件：**
- vow-web-official 服務已部署到 GKE
- 服務正常運行在指定端口 (預設 80)

**修改設定：**
```hcl
# terraform.tfvars
enable_backend_service = true
```

**部署 Kubernetes 服務：**
```bash
kubectl apply -f vow-web-official-service-example.yaml
```

**驗證服務：**
```bash
kubectl get pods -n vow-web-official
kubectl get svc -n vow-web-official
```

**執行 Terraform：**
```bash
terraform plan
terraform apply
```

---

### 🔸 階段三：健康檢查啟用

**目標：** 啟用 Health Check 確保服務品質

**前提條件：**
- 服務提供健康檢查端點 `/health`
- 端點返回 HTTP 200 OK

**修改設定：**
```hcl
# terraform.tfvars
enable_health_check = true
```

**執行：**
```bash
terraform plan
terraform apply
```

---

### 🔸 階段四：CDN 啟用 (可選)

**目標：** 啟用 Cloud CDN 提升效能

**注意：** CDN 會產生流量費用！

**修改設定：**
```hcl
# terraform.tfvars
enable_cdn = true
cdn_cache_ttl = 3600  # 1小時快取
```

**執行：**
```bash
terraform plan
terraform apply
```

## 重要設定說明

### 域名設定
```hcl
service_domain = "vow-web-official.cathaybk.com.tw"  # 請修改為實際域名
```

### SSL 憑證選項
- `managed`: Google Managed SSL 憑證 (推薦)
- `self_signed`: 自簽憑證 (測試用)

### 健康檢查
```hcl
health_check_path = "/health"  # 確保服務提供此端點
```

### CDN 快取設定
```hcl
cdn_cache_ttl = 3600  # 快取 1 小時 (秒)
```

## 成本控制

### 停用功能以節省費用
- **CDN**: 設定 `enable_cdn = false`
- **健康檢查**: 設定 `enable_health_check = false`

### 費用說明
- **Global Static IP**: 免費 (保留中)
- **SSL 憑證**: 免費 (Google Managed)
- **Load Balancer**: 按流量和資料處理量收費
- **CDN**: 按 CDN 流量收費 (通常比 Load Balancer 貴)

## 故障排除

### 常見問題

1. **Health Check 失敗**
   - 檢查服務是否提供 `/health` 端點
   - 確認服務在指定端口正常運行
   - 暫時設定 `enable_health_check = false`

2. **SSL 憑證錯誤**
   - 檢查域名 DNS 設定
   - 確認域名指向 Load Balancer IP
   - 使用自簽憑證測試：`ssl_certificate_type = "self_signed"`

3. **服務無法存取**
   - 檢查 GKE Service 是否正確建立 NEG
   - 確認 Firewall 規則允許 Load Balancer 存取
   - 驗證 Backend Service 配置

### 檢查指令
```bash
# 檢查 Load Balancer 狀態
gcloud compute forwarding-rules list

# 檢查 SSL 憑證
gcloud compute ssl-certificates list

# 檢查 Backend Service
gcloud compute backend-services list

# 檢查 GKE Service NEG
kubectl get service -n vow-web-official -o yaml
```

## 安全考量

1. **網路安全**: Firewall 規則只允許 Load Balancer IP 範圍存取 GKE nodes
2. **SSL/TLS**: 使用 Google Managed SSL 憑證確保加密通訊
3. **存取控制**: 考慮加入 IAP (Identity-Aware Proxy) 或 Cloud Armor

## 監控建議

1. **Cloud Monitoring**: 設定 Load Balancer 指標監控
2. **健康檢查**: 監控健康檢查狀態
3. **CDN 效能**: 監控快取命中率和延遲
4. **成本監控**: 設定預算警報

## 聯絡資訊

如有問題，請聯繫：
- **技術中台部** - 數據中台發展科
- **SRE 團隊**

## 相關資源

- 📖 [專案總覽](./README.md) - 了解完整的專案架構
- 💻 [開發環境設定](./VOW_開發指南.md) - 本地開發環境配置
- 🔧 [GKE 服務部署](./vow-web-official-service-example.yaml) - Kubernetes Service 範例

---

**最後更新**: 2025-11-18
**文件版本**: 2.0 (優化版)