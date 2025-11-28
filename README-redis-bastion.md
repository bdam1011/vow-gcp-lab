# Redis Bastion VM 連線指南

## 概述

本文檔說明如何透過 Cloud IAP Tunnel 安全連線到 GCP Memorystore Redis 實例。

**重要說明**: GCP Memorystore Redis 不支援 IAP 直接連線，因為它不是 Compute Engine 資源。

**推薦連線方式**: 透過 Bastion VM 連線 - 使用 Bastion VM 作為跳板機連線到 Redis

## 架構說明

### 網路架構

```
┌─────────────────┐    IAP Tunnel    ┌─────────────────┐
│   Local Machine│ ◄──────────────► │  Redis Instance │
│   (redis-cli)   │                  │   (Private)     │
└─────────────────┘                  └─────────────────┘
          ▲                                   ▲
          │                                   │
          │    IAP Tunnel                      │ Private Service Access
          │                                   │
          ▼                                   ▼
┌─────────────────┐    IAP Tunnel    ┌─────────────────┐
│   Local Machine│ ◄──────────────► │   Bastion VM    │
│   (redis-cli)   │                  │   (Jump Host)   │
└─────────────────┘                  └─────────────────┘
```

### 安全設計

- **IAM 權限控制**：最小權限原則，僅授予必要的存取權限
- **IAP 存取**：所有連線都透過 Identity-Aware Proxy 進行身份驗證
- **TLS 加密**：Redis 連線使用 TLS 加密傳輸
- **VPC 防火牆**：嚴格的防火牆規則，僅允許必要的流量
- **Secret Manager**：認證資訊安全儲存在 Secret Manager

## 前置需求

### 1. 安裝必要工具

#### Google Cloud SDK
```bash
# Ubuntu/Debian
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install google-cloud-sdk

# macOS
brew install google-cloud-sdk

# Windows
# 下載並安裝: https://cloud.google.com/sdk/docs/install
```

#### Redis CLI
```bash
# Ubuntu/Debian
sudo apt-get install redis-tools

# macOS
brew install redis

# CentOS/RHEL
sudo yum install redis

# Windows
# 下載並安裝: https://redis.io/download
```

### 2. gcloud 認證
```bash
gcloud auth login
gcloud config set project cloud-sre-poc-474602
gcloud config set region asia-east1
```

### 3. 網路工具（用於測試）
```bash
# Ubuntu/Debian
sudo apt-get install netcat-openbsd

# macOS
brew install nmap
```

## 連線方式

### 方法一：IAP 直接連線（推薦）

這是最簡單的連線方式，直接透過 IAP Tunnel 連線到 Redis。

#### 快速連線
```bash
# 使用預設設定連線
./scripts/redis-connect.sh

# 指定本地連接埠
./scripts/redis-connect.sh 6380

# 僅建立 Tunnel，不自動啟動 redis-cli
./scripts/redis-connect.sh -c
```

#### 手動連線
```bash
# 1. 取得 Redis 認證資訊
REDIS_PASSWORD=$(gcloud secrets versions access latest \
    --secret=lspovscpvow01g02 \
    --project=cloud-sre-poc-474602)

gcloud secrets versions access latest \
    --secret=lscovscpvow01g04 \
    --project=cloud-sre-poc-474602 \
    --out-file=/tmp/redis-ca.crt

# 2. 建立 IAP Tunnel
gcloud compute start-iap-tunnel lmrovscpvow01g01 6378 \
    --project=cloud-sre-poc-474602 \
    --region=asia-east1 \
    --local-host-port=localhost:6379

# 3. 在另一個終端機連線 Redis
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \
    -h localhost \
    -p 6379 \
    --tls \
    --cacert /tmp/redis-ca.crt
```

### 方法二：透過 Bastion VM 連線

適用於需要額外網路存取控制或需要安裝特定工具的場景。

#### 快速連線
```bash
# 透過 Bastion VM 連線
./scripts/redis-connect.sh -b

# 透過 Bastion VM 連線，並指定本地連接埠
./scripts/redis-connect.sh -b 6380
```

#### 手動連線
```bash
# 1. 取得 Redis 認證資訊（同上）

# 2. 取得 Redis 主機 IP
REDIS_HOST=$(gcloud redis instances describe lmrovscpvow01g01 \
    --region=asia-east1 \
    --project=cloud-sre-poc-474602 \
    --format="value(host)")

# 3. 建立 IAP Tunnel 到 Bastion VM
gcloud compute ssh lmrovscpvow01-redis-bastion \
    --project=cloud-sre-poc-474602 \
    --zone=asia-east1-a \
    --tunnel-through-iap \
    --ssh-flag="-L 6379:$REDIS_HOST:6378" \
    --ssh-flag="-N" \
    --ssh-flag="-f"

# 4. 連線 Redis（在另一個終端機）
REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \
    -h localhost \
    -p 6379 \
    --tls \
    --cacert /tmp/redis-ca.crt
```

## 測試連線

### 執行完整測試
```bash
# 執行所有連線測試
./scripts/test-redis-connection.sh
```

### 快速測試
```bash
# 測試特定連線方式
./scripts/redis-connect.sh -t  # 測試模式
```

## 常用 Redis 操作

### 基本指令
```bash
# 檢查連線狀態
ping

# 查看伺服器資訊
info server

# 查看記憶體使用
info memory

# 查看連線數
info clients

# 查看所有資料庫
info keyspace
```

### 資料操作
```bash
# 設定鍵值
SET mykey "Hello Redis"

# 取得鍵值
GET mykey

# 刪除鍵
DEL mykey

# 查看所有鍵
KEYS *

# 查看特定模式的鍵
KEYS user:*
```

## 故障排除

### 常見問題

#### 1. IAP Tunnel 建立失敗
**錯誤訊息**：`ERROR: (gcloud.compute.start-iap-tunnel) PERMISSION_DENIED`

**解決方案**：
```bash
# 檢查 IAP 權限
gcloud projects get-iam-policy cloud-sre-poc-474602 \
    --flatten="bindings[].members" \
    --format="table(bindings.role, bindings.members)" \
    --filter="bindings.role:iap.tunnelResourceAccessor"

# 確認具備 roles/iap.tunnelResourceAccessor 權限
```

#### 2. Redis 連線失敗
**錯誤訊息**：`Connection refused` 或 `Authentication failed`

**解決方案**：
```bash
# 檢查 Redis 實例狀態
gcloud redis instances describe lmrovscpvow01g01 \
    --region=asia-east1 \
    --project=cloud-sre-poc-474602

# 檢查 Secret 存取權限
gcloud secrets versions list lspovscpvow01g02 \
    --project=cloud-sre-poc-474602

# 檢查防火牆規則
gcloud compute firewall-rules list \
    --project=cloud-sre-poc-474602 \
    --filter="name~redis"
```

#### 3. TLS 憑證問題
**錯誤訊息**：`SSL certificate problem`

**解決方案**：
```bash
# 重新取得 CA 憑證
gcloud secrets versions access latest \
    --secret=lscovscpvow01g04 \
    --project=cloud-sre-poc-474602 \
    --out-file=/tmp/redis-ca.crt

# 檢查憑證是否有效
openssl x509 -in /tmp/redis-ca.crt -text -noout
```

#### 4. Bastion VM 無法啟動
**錯誤訊息**：`Instance may not exist`

**解決方案**：
```bash
# 檢查 VM 狀態
gcloud compute instances describe lmrovscpvow01-redis-bastion \
    --zone=asia-east1-a \
    --project=cloud-sre-poc-474602

# 手動啟動 VM
gcloud compute instances start lmrovscpvow01-redis-bastion \
    --zone=asia-east1-a \
    --project=cloud-sre-poc-474602
```

### 日誌除錯

#### 查看作業日誌
```bash
# Cloud Logging 中的 Redis 日誌
gcloud logging read "resource.type=redis_instance" \
    --project=cloud-sre-poc-474602 \
    --limit 10 \
    --format "table(timestamp,severity,textPayload)"

# Bastion VM 的作業日誌
gcloud compute instances get-serial-port-output lmrovscpvow01-redis-bastion \
    --zone=asia-east1-a \
    --project=cloud-sre-poc-474602 \
    --port 1
```

## 安全最佳實務

### 1. 權限管理
- 定期檢查 IAM 權限設定
- 使用群組而非個人帳號進行權限管理
- 遵循最小權限原則

### 2. 網路安全
- 監控防火牆規則的變更
- 定期審查連線日誌
- 使用 VPC Service Controls 限制資料外流

### 3. 認證安全
- 定期輪換 Redis 密碼
- 使用強密碼政策
- 監控 Secret Manager 的存取日誌

### 4. 監控告警
```bash
# 設定 Redis 效能監控
gcloud monitoring policies create \
    --notification-channels=<CHANNEL_ID> \
    --condition-display-name="Redis High Memory Usage" \
    --condition-filter='metric.type="redis.googleapis.com/instance/memory/usage"' \
    --condition-aggregations-alignmentPeriod="60s" \
    --condition-aggregations-perSeriesAlignerALIGN_MEAN \
    --condition-trigger-threshold-value=0.8 \
    --condition-trigger-threshold-comparison=COMPARISON_GT
```

## 效能最佳化

### 1. 連線池設定
- 使用連線池減少連線建立成本
- 設定適當的連線超時時間
- 監控連線使用情況

### 2. Redis 設定最佳化
```bash
# 檢查 Redis 設定
gcloud redis instances describe lmrovscpvow01g01 \
    --region=asia-east1 \
    --project=cloud-sre-poc-474602 \
    --format="value(redisConfigs)"
```

### 3. 監控指標
- 記憶體使用率
- 連線數
- 命令執行延遲
- 網路頻寬使用

## 緊急聯絡資訊

- **專案 ID**: `cloud-sre-poc-474602`
- **Redis 實例**: `lmrovscpvow01g01`
- **Bastion VM**: `lmrovscpvow01-redis-bastion`
- **區域**: `asia-east1`
- **聯絡人**: 系統管理團隊

## 版本資訊

- **文檔版本**: 1.0
- **最後更新**: 2025-11-25
- **適用版本**: Redis 7.2, Google Cloud SDK 最新版

---

**注意**: 本文檔僅適用於開發和測試環境，生產環境請遵循相關安全政策。