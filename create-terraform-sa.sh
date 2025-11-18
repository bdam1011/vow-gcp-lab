#!/bin/bash

# 設定專案資訊
PROJECT_ID="cloud-sre-poc-474602"
SA_NAME="terraform-lab-creator"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="terraform-lab-creator-key.json"

echo "正在為專案 ${PROJECT_ID} 建立 Terraform Lab Creator Service Account..."

# 1. 建立服務帳戶
echo "步驟 1: 建立 ${SA_NAME} 服務帳戶..."
gcloud iam service-accounts create ${SA_NAME} \
    --project=${PROJECT_ID} \
    --display-name="Terraform Lab Creator" \
    --description="Service account for creating and managing Lab project resources"

if [ $? -eq 0 ]; then
    echo "✅ 服務帳戶建立成功"
else
    echo "❌ 服務帳戶建立失敗"
    exit 1
fi

# 2. 賦予專案層級權限
echo "步驟 2: 賦予專案管理權限..."

# 專案 IAM 管理
echo "  - 賦予 resourcemanager.projectIamAdmin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/resourcemanager.projectIamAdmin"

# 計費使用權限
echo "  - 賦予 billing.user..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/billing.user"

# 服務使用管理
echo "  - 賦予 serviceusage.serviceUsageAdmin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/serviceusage.serviceUsageAdmin"

# 3. 賦予網路管理權限
echo "步驟 3: 賦予網路管理權限..."

# 網路管理
echo "  - 賦予 compute.networkAdmin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.networkAdmin"

# 安全管理
echo "  - 賦予 compute.securityAdmin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.securityAdmin"

# 4. 賦予 GKE 管理權限
echo "步驟 4: 賦予 GKE 管理權限..."

# GKE 管理員
echo "  - 賦予 container.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/container.admin"

# GKE Hub 管理
echo "  - 賦予 gkehub.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/gkehub.admin"

# 5. 賦予資料庫和儲存權限
echo "步驟 5: 賦予資料庫和儲存權限..."

# Cloud SQL 管理
echo "  - 賦予 cloudsql.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/cloudsql.admin"

# Redis 管理
echo "  - 賦予 redis.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/redis.admin"

# Storage 管理
echo "  - 賦予 storage.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin"

# 6. 賦予安全和加密權限
echo "步驟 6: 賦予安全和加密權限..."

# KMS 管理
echo "  - 賦予 cloudkms.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/cloudkms.admin"

# Secret Manager 管理
echo "  - 賦予 secretmanager.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.admin"

# 服務帳戶管理
echo "  - 賦予 iam.serviceAccountAdmin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountAdmin"

# 7. 賦予監控和日誌權限
echo "步驟 7: 賦予監控和日誌權限..."

# 監控管理
echo "  - 賦予 monitoring.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/monitoring.admin"

# 日誌管理
echo "  - 賦予 logging.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/logging.admin"

# 8. 賦予容器映像管理權限
echo "步驟 8: 賦予容器映像管理權限..."

# Artifact Registry 管理 (用於容器映像管理)
echo "  - 賦予 artifactregistry.admin..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/artifactregistry.admin"

# 9. 建立服務帳戶金鑰
echo "步驟 9: 建立 Terraform 使用的金鑰檔案..."
gcloud iam service-accounts keys create ${KEY_FILE} \
    --project=${PROJECT_ID} \
    --iam-account=${SA_EMAIL} \
    --key-type=TYPE_GOOGLE_CREDENTIALS_FILE

if [ $? -eq 0 ]; then
    echo "✅ 金鑰檔案建立成功: ${KEY_FILE}"
    echo "⚠️  請妥善保管此金鑰檔案，不要提交到版本控制系統"
else
    echo "❌ 金鑰檔案建立失敗"
    exit 1
fi

# 10. 驗證設定
echo "步驟 10: 驗證服務帳戶權限..."
echo "正在測試服務帳戶的基本權限..."

# 測試專案存取
echo "  - 測試專案列表..."
gcloud auth activate-service-account --key-file=${KEY_FILE}
gcloud projects list | grep ${PROJECT_ID}

# 測試網路資源存取
echo "  - 測試網路資源存取..."
gcloud compute networks list --project=${PROJECT_ID}

# 11. 顯示完成資訊
echo ""
echo "🎉 terraform-lab-creator 服務帳戶建立完成！"
echo ""
echo "📋 建立資訊："
echo "   - 服務帳戶: ${SA_EMAIL}"
echo "   - 金鑰檔案: ${KEY_FILE}"
echo "   - 專案: ${PROJECT_ID}"
echo ""
echo "🔧 使用方式："
echo "   # 1. 將金鑰檔案設定到環境變數"
echo "   export GOOGLE_APPLICATION_CREDENTIALS=\"${KEY_FILE}\""
echo ""
echo "   # 2. 或者在 Terraform provider 中指定"
echo "   provider \"google\" {"
echo "     credentials = file(\"\${KEY_FILE}\")"
echo "     project     = \"${PROJECT_ID}\""
echo "   }"
echo ""
echo "⚠️  安全提醒："
echo "   - 請將 ${KEY_FILE} 添加到 .gitignore"
echo "   - 定期輪換服務帳戶金鑰"
echo "   - 監控服務帳戶的使用情況"
echo ""