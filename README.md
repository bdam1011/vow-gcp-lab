# VOW GCP Lab 專案

## 📋 專案概述

VOW GCP Lab 是一個完整的 Google Cloud Platform 部署環境，包含基礎架構、應用程式部署、Load Balancer 配置和監控系統。

### 🏗️ 已部署的基礎架構

- **GCP 專案**: `cloud-sre-poc-474602`
- **地區**: `asia-east1`
- **APID**: `ovs-cp-vow-01`

#### ✅ 核心資源
- **VPC 網路**: `lab-vpc` 已配置完成
- **GKE 叢集**: `lgkovscpvow01g01` 已部署
- **Cloud SQL**: PostgreSQL 17 實例 `lmrovscpvow01g01`
- **Redis**: 實例 `lmrovscpvow01g01` 已配置
- **Storage Bucket**: `ovs-cp-vow-01-lab-chr` 已建立
- **KMS 加密**: CMEK 金鑰已設定
- **IAM 服務帳戶**: 已建立必要的服務帳戶

#### 🔒 安全配置
- **CMEK 加密**: 所有資源使用客戶管理加密金鑰
- **TLS 加密**: 傳輸層加密已配置
- **Secret Manager**: 密碼和憑證安全儲存
- **VPC Peering**: 私有服務存取已設定
- **Workload Identity**: GKE 叢集已配置

## 🚀 快速開始

### 部署前準備

#### 系統需求
- **Terraform**: >= 1.5.0
- **Google Cloud SDK**: 最新版本
- **kubectl**: 與 GKE 版本相容

#### 必要的 Google Cloud APIs
```bash
# 啟用必要的 APIs
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sql-component.googleapis.com \
  redis.googleapis.com \
  storage-component.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  artifactregistry.googleapis.com
```

#### 服務帳戶設定
```bash
# 1. 執行腳本建立 terraform-lab-creator 服務帳戶
chmod +x create-terraform-sa.sh
./create-terraform-sa.sh

# 2. 設定環境變數
export GOOGLE_APPLICATION_CREDENTIALS="terraform-lab-creator-key.json"
```

### 新手入門
如果您是第一次接觸此專案，建議按照以下順序閱讀：

1. **[基礎架構配置](./VOW_開發指南.md)** - 了解完整的開發環境設定
2. **[Load Balancer 部署](./LOAD_BALANCER_GUIDE.md)** - 配置負載平衡和 CDN
3. **[GKE 服務部署](#gke-服務部署)** - 部署應用程式到 Kubernetes

### 快速導航

| 主題 | 文件 | 描述 |
|------|------|------|
| 🏠 **專案總覽** | README.md | 您正在閱讀的文件 |
| 💻 **開發環境** | [VOW_開發指南.md](./VOW_開發指南.md) | 本地開發環境連線指南 |
| ⚖️ **負載平衡** | [LOAD_BALANCER_GUIDE.md](./LOAD_BALANCER_GUIDE.md) | Load Balancer 與 CDN 部署指南 |

## 📚 核心文檔

### [VOW_開發指南.md](./VOW_開發指南.md)
完整的本地開發環境設定指南，包含：
- GCP 認證配置
- Redis 連線設定
- Cloud SQL 連線設定
- Storage 操作
- 基礎架構部署流程

### [LOAD_BALANCER_GUIDE.md](./LOAD_BALANCER_GUIDE.md)
Load Balancer 與 CDN 部署專用指南，包含：
- 四階段部署流程
- 健康檢查配置
- CDN 啟用步驟
- 成本控制策略

## 🔧 技術架構

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │────│      CDN        │────│   全球用戶      │
│   (全球存取)    │    │   (內容加速)    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
          │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GKE 叢集      │────│   Cloud SQL     │────│     Redis       │
│   (應用程式)    │    │   (主資料庫)    │    │   (快取資料庫)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
          │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Storage Bucket │────│  Secret Manager │────│   KMS 加密      │
│  (檔案儲存)     │    │  (密碼管理)     │    │   (金鑰管理)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 GKE 服務部署

### 部署應用程式到 GKE

使用提供的 [vow-web-official-service-example.yaml](./vow-web-official-service-example.yaml) 範例檔案：

```bash
# 1. 連線到 GKE 叢集
gcloud container clusters get-credentials lgkovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1

# 2. 部署服務
kubectl apply -f vow-web-official-service-example.yaml

# 3. 驗證部署狀態
kubectl get pods -n vow-web-official
kubectl get services -n vow-web-official

# 4. 檢查 NEG 狀態 (Load Balancer 整合所需)
kubectl describe service vow-web-official-service -n vow-web-official | grep "neg"
```

### 重要配置說明

- **NEG (Network Endpoint Group)**: 必須配置 `cloud.google.com/neg` annotation
- **健康檢查**: 服務需提供 `/health` 端點並返回 HTTP 200
- **服務端口**: 預設使用 port 80，可根據需求調整
- **資源限制**: 請根據實際需求調整 CPU 和 memory 設定

### 部署完成後

完成 GKE 服務部署後，請按照 [LOAD_BALANCER_GUIDE.md](./LOAD_BALANCER_GUIDE.md) 進行 Load Balancer 的階段式部署。

## 📝 文件維護狀態

| 文件 | 狀態 | 最後更新 |
|------|------|----------|
| README.md | ✅ 最新 | 2025-11-18 |
| VOW_開發指南.md | 🔄 整理中 | - |
| LOAD_BALANCER_GUIDE.md | 🔄 整理中 | - |

---

> 💡 **提示**: 此專案使用 CMEK (客戶管理加密金鑰) 確保所有資料的安全性。在進行任何操作前，請確保您具備適當的 IAM 權限。