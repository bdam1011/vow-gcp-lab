# VOW 專案本地開發環境連線指南

## 專案概述

本指南提供 GCP 專案 `cloud-sre-poc-474602` 的完整本地開發環境連線說明，包含 Redis、Cloud SQL、Storage 等核心資源的連線配置。

### 環境資訊
- **專案 ID**: cloud-sre-poc-474602
- **環境**: Lab
- **地區**: asia-east1
- **APID**: ovs-cp-vow-01

> 📖 **專案總覽**: 查看 [README.md](./README.md) 了解完整的專案架構和資源狀態。
> ⚖️ **Load Balancer**: 如需配置負載平衡和 CDN，請參考 [LOAD_BALANCER_GUIDE.md](./LOAD_BALANCER_GUIDE.md)。

---

## 1. 本地 IDE 連線 Redis 開發指南

### ⚠️ 重要提醒
**Redis 不支援 Cloud SQL Proxy**，需要使用不同的連線方式。

### Redis 資源資訊
- **實例名稱**: lmrovscpvow01g01
- **連線模式**: PRIVATE_SERVICE_ACCESS
- **認證**: 啟用 (需要密碼)
- **傳輸加密**: SERVER_AUTHENTICATION (需要 TLS)
- **端口**: 6379

### 連線方法

#### 方法一：使用 Cloud IAP Tunnel (推薦)

```bash
# 1. 啟動 IAP tunnel 連線到 Redis 實例
gcloud compute start-iap-tunnel \
  lmrovscpvow01g01 \
  6379 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1 \
  --local-host-port=localhost:6379

# 2. 取得 Redis 認證密碼
REDIS_PASSWORD=$(gcloud secrets versions access latest \
  --secret=lspovscpvow01g02 \
  --project=cloud-sre-poc-474602)

# 3. 使用 Redis CLI 連線 (需要因為 TLS 加密)
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD --tls

# 或者使用支援 TLS 的 Redis 客戶端
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD --tls --sni lmrovscpvow01g01
```

#### 方法二：使用 Cloud Shell (簡單快速)

```bash
# 1. 開啟 Cloud Shell
# 2. 安裝 Redis CLI
sudo apt-get update && sudo apt-get install redis-tools

# 3. 取得 Redis 實例資訊
gcloud redis instances describe lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1 \
  --format="table(host,port,displayName)"

# 4. 取得認證密碼
REDIS_PASSWORD=$(gcloud secrets versions access latest \
  --secret=lspovscpvow01g02 \
  --project=cloud-sre-poc-474602)

# 5. 連線 (從 Cloud Shell 到 GCP 內部網路)
redis-cli -h $(gcloud redis instances describe lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1 \
  --format="value(host)") \
  -p 6379 -a $REDIS_PASSWORD --tls
```

#### 方法三：從 GKE Pod 連線 (測試用)

```bash
# 1. 連線到 GKE 叢集
gcloud container clusters get-credentials lgkovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1

# 2. 部署臨時測試 Pod
kubectl run redis-test --image=redis:7.2 -it --rm --restart=Never -- /bin/bash

# 3. 在 Pod 內連線
REDIS_IP=$(gcloud redis instances describe lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1 \
  --format="value(host)")

redis-cli -h $REDIS_IP -p 6379 -a YOUR_REDIS_PASSWORD --tls
```

### 應用程式連線範例

#### Python
```python
import redis
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE  # 開發環境設定

r = redis.Redis(
    host='localhost',  # 使用 IAP tunnel
    port=6379,
    password='YOUR_REDIS_PASSWORD',
    ssl=True,
    ssl_cert_reqs=None,
    decode_responses=True
)
```

---

## 2. 本地 IDE 連線 Cloud SQL 開發指南

### Cloud SQL 資源資訊
- **實例名稱**: lmrovscpvow01g01
- **資料庫版本**: PostgreSQL 17
- **連線端口**: 5432
- **網路**: 私有 IP
- **SSL**: TRUSTED_CLIENT_CERTIFICATE_REQUIRED

### 連線方法：Cloud SQL Auth Proxy

#### 安裝 Cloud SQL Auth Proxy

```bash
# Linux
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy
sudo mv cloud_sql_proxy /usr/local/bin/

# macOS
brew install cloud-sql-proxy

# Windows
# 下載: https://dl.google.com/cloudsql/cloud_sql_proxy_x64.exe
```

#### 啟動 Cloud SQL Proxy

```bash
# 1. 設定認證
gcloud auth application-default login

# 2. 啟動 Proxy
./cloud_sql_proxy \
  -instances=cloud-sre-poc-474602:asia-east1:lmrovscpvow01g01=tcp:5432

# 或者使用服務帳戶
./cloud_sql_proxy \
  -instances=cloud-sre-poc-474602:asia-east1:lmrovscpvow01g01=tcp:5432 \
  -credential_file=path/to/service-account-key.json
```

#### 取得資料庫認證資訊

```bash
# 取得資料庫使用者名稱
DB_USERNAME=$(gcloud secrets versions access latest \
  --secret=lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602)

# 取得資料庫密碼
DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret=lmrovscpvow01g02 \
  --project=cloud-sre-poc-474602)

# 取得 CA 憑證
DB_CA_CERT=$(gcloud secrets versions access latest \
  --secret=lmrovscpvow01g03 \
  --project=cloud-sre-poc-474602)

# 取得客戶端憑證
DB_CLIENT_CERT=$(gcloud secrets versions access latest \
  --secret=lmrovscpvow01g04 \
  --project=cloud-sre-poc-474602)

# 取得客戶端金鑰
DB_CLIENT_KEY=$(gcloud secrets versions access latest \
  --secret=lmrovscpvow01g05 \
  --project=cloud-sre-poc-474602)
```

#### 連線字串範例

##### psql 命令列
```bash
# 需要先建立憑證檔案
echo "$DB_CA_CERT" > ca-cert.pem
echo "$DB_CLIENT_CERT" > client-cert.pem
echo "$DB_CLIENT_KEY" > client-key.pem

psql "host=localhost port=5432 \
       dbname=your_database \
       user=$DB_USERNAME \
       password=$DB_PASSWORD \
       sslmode=verify-ca \
       sslrootcert=ca-cert.pem \
       sslcert=client-cert.pem \
       sslkey=client-key.pem"
```

##### Python (psycopg2)
```python
import psycopg2
from ssl import create_default_context

ctx = create_default_context(cafile="ca-cert.pem")
ctx.load_cert_chain("client-cert.pem", "client-key.pem")

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="your_database",
    user=DB_USERNAME,
    password=DB_PASSWORD,
    sslmode="verify-ca",
    sslcontext=ctx
)
```

---

## 3. 本地 IDE 連線 Storage Bucket 開發指南

### Storage Bucket 資源資訊
- **Bucket 名稱**: ovs-cp-vow-01-lab-chr
- **地區**: asia-east1
- **儲存類別**: REGIONAL
- **加密**: 使用 KMS 金鑰加密

### 連線方法

#### 方法一：使用 Google Cloud SDK

```bash
# 1. 安裝 gcloud CLI
# curl https://sdk.cloud.google.com | bash
# exec -l $SHELL

# 2. 初始化和認證
gcloud init
gcloud auth application-default login

# 3. 設定專案
gcloud config set project cloud-sre-poc-474602

# 4. 列出 Bucket 內容
gsutil ls gs://ovs-cp-vow-01-lab-chr/

# 5. 上傳檔案
gsutil cp local-file.txt gs://ovs-cp-vow-01-lab-chr/

# 6. 下載檔案
gsutil cp gs://ovs-cp-vow-01-lab-chr/remote-file.txt ./

# 7. 同步目錄
gsutil -m rsync -r ./local-dir gs://ovs-cp-vow-01-lab-chr/remote-dir
```

#### 方法二：應用程式 SDK 連線

##### Python (google-cloud-storage)
```python
from google.cloud import storage
from google.oauth2 import service_account

# 使用服務帳戶金鑰
credentials = service_account.Credentials.from_service_account_file(
    'path/to/service-account-key.json'
)

# 使用 Application Default Credentials
# credentials, _ = google.auth.default()

client = storage.Client(
    project='cloud-sre-poc-474602',
    credentials=credentials
)

bucket = client.bucket('ovs-cp-vow-01-lab-chr')

# 上傳檔案
blob = bucket.blob('remote-file.txt')
blob.upload_from_filename('local-file.txt')

# 下載檔案
blob = bucket.blob('remote-file.txt')
blob.download_to_filename('downloaded-file.txt')
```

##### Java (Cloud Storage)
```java
import com.google.cloud.storage.Bucket;
import com.google.cloud.storage.BucketInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;

Storage storage = StorageOptions.newBuilder()
    .setProjectId("cloud-sre-poc-474602")
    .build()
    .getService();

Bucket bucket = storage.get("ovs-cp-vow-01-lab-chr");

// 上傳檔案
bucket.create("remote-file.txt", Files.readAllBytes(Paths.get("local-file.txt")));

// 下載檔案
Blob blob = storage.get(BlobId.of("ovs-cp-vow-01-lab-chr", "remote-file.txt"));
blob.downloadTo(Paths.get("downloaded-file.txt"));
```

---

## 4. CMEK 加密說明

### CMEK (客戶管理加密金鑰) 對開發的影響

#### 🔍 重要觀念
**CMEK 加密不會影響應用程式連線和操作！**

#### CMEK 運作原理
- **透明加密**: CMEK 在 Google Cloud 基礎設施層級自動運作
- **應用程式無感知**: 開發人員無需修改程式碼
- **自動管理**: Google Cloud 自動處理加密/解密過程

#### CMEK 資源資訊
- **Key Ring**: lmkrovscpvow01g01
- **Crypto Key**: lkkrovscpvow01g01
- **地區**: asia-east1
- **防護等級**: HSM (硬體安全模組)

#### 受 CMEK 保護的資源
1. **Redis 實例**: lmrovscpvow01g01
2. **Cloud SQL 實例**: lmrovscpvow01g01
3. **Storage Bucket**: ovs-cp-vow-01-lab-chr

#### 開發人員需注意事項

##### 1. 權限管理
確保使用的服務帳戶具有適當權限：
```bash
# 檢查服務帳戶是否有 KMS 使用權限
gcloud kms keys get-iam-policy lkkrovscpvow01g01 \
  --location=asia-east1 \
  --keyring=lmkrovscpvow01g01 \
  --project=cloud-sre-poc-474602
```

##### 2. 無需額外配置
```python
# 正常的程式碼 - CMEK 是透明的
from google.cloud import storage

client = storage.Client(project='cloud-sre-poc-474602')
bucket = client.bucket('ovs-cp-vow-01-lab-chr')
# CMEK 加密自動發生，無需額外程式碼
```

##### 3. 錯誤處理
如果遇到權限問題：
```bash
# 確保有 Cloud KMS CryptoKey Encrypter/Decrypter 角色
gcloud projects add-iam-policy-binding cloud-sre-poc-474602 \
  --member="serviceAccount:your-service-account@cloud-sre-poc-474602.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

---

## 5. GKE 基礎連線設定

### 連線到 GKE 叢集

```bash
# 取得 GKE 叢集認證
gcloud container clusters get-credentials lgkovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1

# 設定 kubectl context
kubectl config use-context gke_cloud-sre-poc-474602_asia-east1_lgkovscpvow01g01

# 檢查叢集狀態
kubectl cluster-info
```

### Workload Identity 配置

```bash
# 綁定服務帳戶
gcloud iam service-accounts add-iam-policy-binding \
  lgk-vow-web-official@cloud-sre-poc-474602.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:cloud-sre-poc-474602.svc.id.goog[vow-web-official/lgk-vow-web-official]"

# 註解 Kubernetes Service Account
kubectl annotate serviceaccount \
  --namespace=vow-web-official \
  lgk-vow-web-official \
  iam.gke.io/gcp-service-account=lgk-vow-web-official@cloud-sre-poc-474602.iam.gserviceaccount.com
```

> 🚀 **應用程式部署**: 完整的 Load Balancer 和服務部署流程請參考 [LOAD_BALANCER_GUIDE.md](./LOAD_BALANCER_GUIDE.md)

---

## 6. 安全最佳實踐

### IAM 權限管理

#### 原則：最小權限原則
```bash
# 檢查目前權限
gcloud projects get-iam-policy cloud-sre-poc-474602

# 給予最小必要權限
gcloud projects add-iam-policy-binding cloud-sre-poc-474602 \
  --member="user:developer@cathaybk.com.tw" \
  --role="roles/viewer"
```

#### Secret Manager 存取控制
```bash
# 只給予必要的 Secret 存取權限
gcloud secrets add-iam-policy-binding lspovscpvow01g02 \
  --member="serviceAccount:your-service-account@cloud-sre-poc-474602.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### 網路安全

#### VPC Peering 設定
- Redis 和 Cloud SQL 使用 PRIVATE_SERVICE_ACCESS
- 透過 VPC Peering 連線到 Google Cloud 服務
- 確保防火牆規則正確配置

#### 防火牆規則
```bash
# 檢查防火牆規則
gcloud compute firewall-rules list \
  --filter="network=lab-vpc"

# 確保只允許必要的流量
```

### 資料加密

#### 保密性
- 所有資源都使用 CMEK 加密
- 傳輸過程使用 TLS 加密
- 密碼和憑證儲存在 Secret Manager

#### 最佳實踐
```bash
# 定期輪替 KMS 金鑰
gcloud kms keys update lkkrovscpvow01g01 \
  --location=asia-east1 \
  --keyring=lmkrovscpvow01g01 \
  --rotation-period=7776000s  # 90天

# 定期輪替 Secret Manager secrets
gcloud secrets versions enable ...  # 建立新版本
gcloud secrets versions disable ... # 停用舊版本
```

### 監控和日誌

#### Cloud Monitoring
```bash
# 設定警報
gcloud monitoring policies create --policy-from-file=alert-policy.yaml

# 檢查指標
gcloud monitoring metrics list
```

#### Cloud Logging
```bash
# 查看日誌
gcloud logging read "resource.type=redis_instance" \
  --project=cloud-sre-poc-474602 \
  --limit=50

# 設定日誌路由
gcloud logging sinks create my-sink \
  bigquery.googleapis.com/projects/cloud-sre-poc-474602/datasets/logs
```

---

## 7. 故障排除

### Redis 連線問題

#### 常見錯誤
```bash
# 錯誤: Connection refused
# 解決: 檢查 IAP tunnel 狀態和 Redis 實例狀態

# 錯誤: Authentication failed
# 解決: 檢查 Secret Manager 中的密碼是否正確

# 錯誤: TLS handshake failed
# 解決: 確認使用 --tls 參數和正確的 SNI 設定
```

#### 診斷指令
```bash
# 檢查 Redis 實例狀態
gcloud redis instances describe lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602 \
  --region=asia-east1

# 檢查 VPC Peering 狀態
gcloud compute networks peerings list \
  --network=lab-vpc
```

### Cloud SQL 連線問題

#### 常見錯誤
```bash
# 錯誤: Proxy connection failed
# 解決: 檢查 Cloud SQL Proxy 設定和服務帳戶權限

# 錯誤: SSL certificate verification failed
# 解決: 檢查 SSL 憑證是否正確配置
```

#### 診斷指令
```bash
# 檢查 Cloud SQL 實例狀態
gcloud sql instances describe lmrovscpvow01g01 \
  --project=cloud-sre-poc-474602

# 檢查 Proxy 日誌
tail -f /tmp/cloud-sql-proxy.log
```

### Storage Bucket 存取問題

#### 權限問題
```bash
# 檢查 IAM 權限
gcloud projects get-iam-policy cloud-sre-poc-474602

# 檢查 Bucket 權限
gsutil iam get gs://ovs-cp-vow-01-lab-chr
```

---

## 8. 聯絡資訊

如有問題，請聯繫：
- **技術中台部** - 數據中台發展科
- **SRE 團隊**

## 相關資源

- 📖 [專案總覽](./README.md) - 了解完整的專案架構
- ⚖️ [Load Balancer 部署](./LOAD_BALANCER_GUIDE.md) - 負載平衡和 CDN 配置
- 🔧 [服務部署範例](./vow-web-official-service-example.yaml) - Kubernetes Service 範例

---

**最後更新**: 2025-11-18
**文件版本**: 2.0 (優化版)