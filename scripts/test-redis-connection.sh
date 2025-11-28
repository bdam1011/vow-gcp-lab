#!/bin/bash

# Redis 連線測試腳本
# 測試透過 IAP Tunnel 連線到 Redis 實例的完整流程

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 設定變數
PROJECT_ID="cloud-sre-poc-474602"
REGION="asia-east1"
REDIS_INSTANCE="lmrovscpvow01g01"
REDIS_PORT="6378"
REDIS_SECRET="lspovscpvow01g02"
REDIS_CA_SECRET="lscovscpvow01g04"
BASTION_VM="l-ovscpvow01-redis-bastion"
BASTION_ZONE="asia-east1-a"
TEST_LOCAL_PORT="6380"  # 專用於測試的連接埠

echo -e "${GREEN}=== Redis 連線測試腳本 ===${NC}"
echo "專案: $PROJECT_ID"
echo "區域: $REGION"
echo "Redis 實例: $REDIS_INSTANCE"
echo "Bastion VM: $BASTION_VM"
echo "測試連接埠: $TEST_LOCAL_PORT"
echo

# 函數：檢查 gcloud 是否已登入
check_gcloud_auth() {
    echo -e "${YELLOW}檢查 gcloud 認證狀態...${NC}"
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        echo -e "${RED}錯誤: 請先執行 gcloud auth login${NC}"
        exit 1
    fi
    ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo -e "${GREEN}已登入帳號: $ACCOUNT${NC}"
}

# 函數：檢查必要 API 是否啟用
check_apis() {
    echo -e "${YELLOW}檢查必要 APIs...${NC}"

    # 檢查 IAP API
    if ! gcloud services list --enabled --filter=name:iap.googleapis.com --format="value(name)" | grep -q "iap.googleapis.com"; then
        echo -e "${RED}錯誤: IAP API 未啟用${NC}"
        echo "請執行: gcloud services enable iap.googleapis.com"
        exit 1
    fi

    # 檢查 Secret Manager API
    if ! gcloud services list --enabled --filter=name:secretmanager.googleapis.com --format="value(name)" | grep -q "secretmanager.googleapis.com"; then
        echo -e "${RED}錯誤: Secret Manager API 未啟用${NC}"
        echo "請執行: gcloud services enable secretmanager.googleapis.com"
        exit 1
    fi

    # 檢查 Compute Engine API
    if ! gcloud services list --enabled --filter=name:compute.googleapis.com --format="value(name)" | grep -q "compute.googleapis.com"; then
        echo -e "${RED}錯誤: Compute Engine API 未啟用${NC}"
        echo "請執行: gcloud services enable compute.googleapis.com"
        exit 1
    fi

    # 檢查 Redis API
    if ! gcloud services list --enabled --filter=name:redis.googleapis.com --format="value(name)" | grep -q "redis.googleapis.com"; then
        echo -e "${RED}錯誤: Redis API 未啟用${NC}"
        echo "請執行: gcloud services enable redis.googleapis.com"
        exit 1
    fi

    echo -e "${GREEN}✓ 必要 APIs 已啟用${NC}"
}

# 函數：檢查權限
check_permissions() {
    echo -e "${YELLOW}檢查使用者權限...${NC}"
    ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

    # 檢查 IAP 權限
    if ! gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role, bindings.members)" --filter="bindings.role:iap.tunnelResourceAccessor AND bindings.members:$ACCOUNT" 2>/dev/null | grep -q "iap.tunnelResourceAccessor"; then
        echo -e "${YELLOW}警告: 可能缺少 IAP Tunnel 權限${NC}"
        echo "請聯絡專案管理員授予 roles/iap.tunnelResourceAccessor 權限"
    else
        echo -e "${GREEN}✓ IAP Tunnel 權限: 正常${NC}"
    fi

    # 檢查 Compute Engine 權限
    if ! gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role, bindings.members)" --filter="bindings.role:compute.instanceAdmin.v1 AND bindings.members:$ACCOUNT" 2>/dev/null | grep -q "compute.instanceAdmin.v1"; then
        echo -e "${YELLOW}警告: 可能缺少 Compute Engine 管理權限${NC}"
        echo "請聯絡專案管理員授予 roles/compute.instanceAdmin.v1 權限"
    else
        echo -e "${GREEN}✓ Compute Engine 權限: 正常${NC}"
    fi

    # 檢查 Secret Manager 權限
    echo -e "${YELLOW}測試 Secret Manager 存取...${NC}"
    if ! gcloud secrets versions list $REDIS_SECRET --project=$PROJECT_ID --limit=1 2>/dev/null; then
        echo -e "${RED}錯誤: 無法存取 Redis 密碼 Secret${NC}"
        echo "請確認您具備 roles/secretmanager.secretAccessor 權限"
        exit 1
    fi

    if ! gcloud secrets versions list $REDIS_CA_SECRET --project=$PROJECT_ID --limit=1 2>/dev/null; then
        echo -e "${RED}錯誤: 無法存取 Redis CA 憑證 Secret${NC}"
        echo "請確認您具備 roles/secretmanager.secretAccessor 權限"
        exit 1
    fi

    echo -e "${GREEN}✓ Secret Manager 權限: 正常${NC}"
    echo -e "${GREEN}✓ 權限檢查完成${NC}"
}

# 函數：檢查 Redis 實例狀態
check_redis_instance() {
    echo -e "${YELLOW}檢查 Redis 實例狀態...${NC}"

    if ! gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID >/dev/null 2>&1; then
        echo -e "${RED}錯誤: Redis 實例 $REDIS_INSTANCE 不存在或無法存取${NC}"
        exit 1
    fi

    REDIS_STATUS=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(state)")
    if [ "$REDIS_STATUS" != "READY" ]; then
        echo -e "${RED}錯誤: Redis 實例狀態為 $REDIS_STATUS，非 READY${NC}"
        exit 1
    fi

    REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(host)")
    REDIS_VERSION=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(redisVersion)")
    REDIS_TIER=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(tier)")

    echo -e "${GREEN}✓ Redis 實例狀態: $REDIS_STATUS${NC}"
    echo -e "${BLUE}  主機: $REDIS_HOST${NC}"
    echo -e "${BLUE}  連接埠: $REDIS_PORT${NC}"
    echo -e "${BLUE}  版本: $REDIS_VERSION${NC}"
    echo -e "${BLUE}  階層: $REDIS_TIER${NC}"
}

# 函數：檢查 Bastion VM 狀態
check_bastion_vm() {
    echo -e "${YELLOW}檢查 Bastion VM 狀態...${NC}"

    if ! gcloud compute instances describe $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID >/dev/null 2>&1; then
        echo -e "${RED}錯誤: Bastion VM $BASTION_VM 不存在或無法存取${NC}"
        echo "請確認 Bastion VM 已經建立"
        exit 1
    fi

    VM_STATUS=$(gcloud compute instances describe $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID --format="value(status)")
    VM_INTERNAL_IP=$(gcloud compute instances describe $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID --format="value(networkInterfaces[0].networkIP)")
    VM_MACHINE_TYPE=$(gcloud compute instances describe $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID --format="value(machineType)")

    if [ "$VM_STATUS" != "RUNNING" ]; then
        echo -e "${YELLOW}Bastion VM 狀態: $VM_STATUS，正在啟動...${NC}"
        gcloud compute instances start $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID

        # 等待 VM 啟動
        echo -e "${YELLOW}等待 Bastion VM 完全啟動...${NC}"
        sleep 30

        # 重新檢查狀態
        VM_STATUS=$(gcloud compute instances describe $BASTION_VM --zone=$BASTION_ZONE --project=$PROJECT_ID --format="value(status)")
        if [ "$VM_STATUS" != "RUNNING" ]; then
            echo -e "${RED}錯誤: Bastion VM 啟動失敗，狀態: $VM_STATUS${NC}"
            exit 1
        fi
    fi

    echo -e "${GREEN}✓ Bastion VM 狀態: $VM_STATUS${NC}"
    echo -e "${BLUE}  內部 IP: $VM_INTERNAL_IP${NC}"
    echo -e "${BLUE}  機器類型: $VM_MACHINE_TYPE${NC}"
}

# 函數：取得認證資訊
get_credentials() {
    echo -e "${YELLOW}取得 Redis 認證資訊...${NC}"

    # 取得密碼
    REDIS_PASSWORD=$(gcloud secrets versions access latest --secret=$REDIS_SECRET --project=$PROJECT_ID 2>/dev/null)
    if [ -z "$REDIS_PASSWORD" ]; then
        echo -e "${RED}錯誤: 無法取得 Redis 密碼${NC}"
        exit 1
    fi

    # 取得 CA 憑證
    CA_FILE="/tmp/redis-ca.crt"
    if ! gcloud secrets versions access latest --secret=$REDIS_CA_SECRET --project=$PROJECT_ID --out-file=$CA_FILE 2>/dev/null; then
        echo -e "${RED}錯誤: 無法取得 Redis CA 憑證${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ 認證資訊取得成功${NC}"
}

# 函數：IAP 直接連線不適用於 Memorystore Redis
test_direct_iap_tunnel() {
    echo -e "${YELLOW}跳過 IAP 直接連線測試${NC}"
    echo -e "${BLUE}說明: GCP Memorystore Redis 不支援 IAP 直接連線${NC}"
    echo -e "${BLUE}請使用 Bastion VM 連線方式${NC}"
    return 0
}

# 函數：測試透過 Bastion VM 的連線
test_bastion_tunnel() {
    echo -e "${YELLOW}測試透過 Bastion VM 的連線...${NC}"

    # 取得 Redis 主機
    REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(host)")

    # 檢查是否已有測試用的 tunnel 在運行
    TUNNEL_PID=$(pgrep -f "gcloud.*compute.*ssh.*$BASTION_VM.*$TEST_LOCAL_PORT" || true)
    if [ -n "$TUNNEL_PID" ]; then
        echo -e "${YELLOW}偵測到現有的測試用 Bastion Tunnel，終止中...${NC}"
        kill $TUNNEL_PID
        sleep 2
    fi

    # 啟動測試用的 tunnel
    echo -e "${GREEN}啟動測試用 Bastion Tunnel...${NC}"
    gcloud compute ssh $BASTION_VM \
        --project=$PROJECT_ID \
        --zone=$BASTION_ZONE \
        --tunnel-through-iap \
        --ssh-flag="-L $TEST_LOCAL_PORT:$REDIS_HOST:$REDIS_PORT" \
        --ssh-flag="-N" \
        --ssh-flag="-f" &

    TUNNEL_PID=$!
    echo -e "${BLUE}Tunnel PID: $TUNNEL_PID${NC}"

    # 等待 tunnel 建立完成
    echo -e "${YELLOW}等待 tunnel 建立...${NC}"
    for i in {1..30}; do
        if nc -z localhost $TEST_LOCAL_PORT 2>/dev/null; then
            echo -e "${GREEN}✓ Bastion Tunnel 建立成功${NC}"
            return 0
        fi
        echo -e "${YELLOW}等待 tunnel 建立... ($i/30)${NC}"
        sleep 2
    done

    echo -e "${RED}✗ Bastion Tunnel 建立失敗${NC}"
    kill $TUNNEL_PID 2>/dev/null || true
    return 1
}

# 函數：測試 Redis 連線
test_redis_connection() {
    local test_port=$1
    local connection_method=$2

    echo -e "${YELLOW}測試 Redis 連線 ($connection_method)...${NC}"

    if ! command -v redis-cli >/dev/null 2>&1; then
        echo -e "${RED}錯誤: redis-cli 未安裝${NC}"
        echo "請安裝 Redis CLI:"
        echo "  Ubuntu/Debian: sudo apt-get install redis-tools"
        echo "  macOS: brew install redis"
        echo "  CentOS/RHEL: sudo yum install redis"
        return 1
    fi

    # 測試連線
    if redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✓ Redis 連線成功 ($connection_method)！${NC}"
        return 0
    else
        echo -e "${RED}✗ Redis 連線失敗 ($connection_method)${NC}"
        return 1
    fi
}

# 函數：執行 Redis 基本測試
run_redis_tests() {
    local test_port=$1
    local connection_method=$2

    echo -e "${YELLOW}執行 Redis 基本測試 ($connection_method)...${NC}"

    # 取得 server 資訊
    echo -e "${GREEN}取得 Redis 伺服器資訊:${NC}"
    redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE INFO server | grep -E "(redis_version|os|arch|process_id|uptime_in_seconds)" || true

    echo
    echo -e "${GREEN}測試基本操作:${NC}"

    # 測試 SET/GET
    TEST_KEY="test_key_$(date +%s)"
    TEST_VALUE="hello_redis"

    redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE SET $TEST_KEY "$TEST_VALUE" >/dev/null

    RETRIEVED_VALUE=$(redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE GET $TEST_KEY)

    if [ "$RETRIEVED_VALUE" = "$TEST_VALUE" ]; then
        echo -e "${GREEN}✓ SET/GET 測試成功${NC}"
    else
        echo -e "${RED}✗ SET/GET 測試失敗${NC}"
        return 1
    fi

    # 清理測試資料
    redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_file DEL $TEST_KEY >/dev/null

    # 檢查記憶體使用
    echo
    echo -e "${GREEN}記憶體使用資訊:${NC}"
    redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE INFO memory | grep -E "(used_memory_human|used_memory_peak_human)" || true

    # 檢查連線數
    echo
    echo -e "${GREEN}連線資訊:${NC}"
    redis-cli -h localhost -p $test_port -a "$REDIS_PASSWORD" --tls --cacert=$CA_FILE INFO clients | grep -E "(connected_clients)" || true

    return 0
}

# 函數：清理測試環境
cleanup_test_environment() {
    echo -e "${YELLOW}清理測試環境...${NC}"

    # 清理測試用的 tunnels
    DIRECT_TUNNEL_PID=$(pgrep -f "gcloud.*start-iap-tunnel.*$REDIS_INSTANCE.*$REDIS_PORT.*$TEST_LOCAL_PORT" || true)
    if [ -n "$DIRECT_TUNNEL_PID" ]; then
        echo -e "${YELLOW}終止 IAP Tunnel (PID: $DIRECT_TUNNEL_PID)${NC}"
        kill $DIRECT_TUNNEL_PID 2>/dev/null || true
    fi

    BASTION_TUNNEL_PID=$(pgrep -f "gcloud.*compute.*ssh.*$BASTION_VM.*$TEST_LOCAL_PORT" || true)
    if [ -n "$BASTION_TUNNEL_PID" ]; then
        echo -e "${YELLOW}終止 Bastion Tunnel (PID: $BASTION_TUNNEL_PID)${NC}"
        kill $BASTION_TUNNEL_PID 2>/dev/null || true
    fi

    # 清理暫存檔案
    rm -f /tmp/redis-ca.crt

    echo -e "${GREEN}✓ 測試環境清理完成${NC}"
}

# 清理函數
cleanup() {
    cleanup_test_environment
}

# 主要執行流程
main() {
    # 設定 trap 確保清理
    trap cleanup EXIT

    echo -e "${GREEN}開始 Redis 連線測試...${NC}"
    echo

    check_gcloud_auth
    check_apis
    check_permissions
    check_redis_instance
    check_bastion_vm
    get_credentials

    echo
    echo -e "${GREEN}=== 開始連線測試 ===${NC}"
    echo

    # 說明 GCP Memorystore Redis 連線方式
    echo -e "${BLUE}=== GCP Memorystore Redis 連線說明 ===${NC}"
    echo -e "${YELLOW}IAP 直接連線不適用於 Memorystore Redis，因為它不是 Compute Engine 資源${NC}"
    echo -e "${GREEN}推薦使用 Bastion VM 連線方式${NC}"
    echo

    # 測試結果變數
    BASTION_TEST_PASSED=false

    # 測試 Bastion VM 連線
    echo -e "${BLUE}--- 測試: 透過 Bastion VM 連線 ---${NC}"
    if test_bastion_tunnel; then
        if test_redis_connection $TEST_LOCAL_PORT "Bastion VM"; then
            if run_redis_tests $TEST_LOCAL_PORT "Bastion VM"; then
                BASTION_TEST_PASSED=true
            fi
        fi
    fi

    echo
    echo -e "${GREEN}=== 測試結果總結 ===${NC}"

    if [ "$BASTION_TEST_PASSED" = true ]; then
        echo -e "${GREEN}✓ 透過 Bastion VM 連線: 測試通過${NC}"
        echo
        echo -e "${GREEN}🎉 Redis 連線設定正常！${NC}"
        echo -e "${BLUE}您可以使用以下方式連線到 Redis:${NC}"
        echo -e "${YELLOW}./scripts/redis-connect.sh -b${NC}"
    else
        echo -e "${RED}✗ 透過 Bastion VM 連線: 測試失敗${NC}"
        echo
        echo "請檢查以下項目:"
        echo "1. Redis 實例是否正常運作"
        echo "2. Bastion VM 是否正常運作"
        echo "3. 防火牆規則是否正確設定"
        echo "4. IAM 權限是否正確配置"
        echo "5. Redis 密碼認證資訊是否正確"
        echo
        echo "注意: GCP Memorystore Redis 需要正確的 authString 設定"
        echo "請確認 Redis 實例的密碼配置"
        exit 1
    fi
}

# 顯示使用說明
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "用法: $0 [選項]"
    echo
    echo "選項:"
    echo "  -h, --help     顯示此說明"
    echo
    echo "此腳本會測試 GCP Memorystore Redis 連線方式:"
    echo "1. 透過 Bastion VM 連線 - 推薦方式，透過 Bastion VM 作為跳板機"
    echo ""
    echo "注意: IAP 直接連線不適用於 Memorystore Redis"
    echo
    exit 0
fi

# 執行主函數
main