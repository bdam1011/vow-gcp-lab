#!/bin/bash

# Redis 快速連線腳本
# 使用 Cloud IAP Tunnel 快速連線到 Redis

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
LOCAL_PORT="6379"  # 預設本地連接埠

# 使用說明
show_usage() {
    echo "用法: $0 [選項] [本地連接埠]"
    echo
    echo "選項:"
    echo "  -d, --direct   使用 IAP 直接連線到 Redis"
    echo "  -b, --bastion  透過 Bastion VM 連線"
    echo "  -c, --cli      僅建立 IAP Tunnel，不自動連線 redis-cli"
    echo "  -t, --test     執行連線測試"
    echo "  -h, --help     顯示此說明"
    echo
    echo "範例:"
    echo "  $0                  # 使用預設方式（IAP 直接連線）連線 redis-cli"
    echo "  $0 -b               # 透過 Bastion VM 連線"
    echo "  $0 -d 6380          # 使用 IAP 直接連線，本地連接埠 6380"
    echo "  $0 -c               # 僅建立 IAP Tunnel"
    echo "  $0 -t               # 執行連線測試"
    echo
    echo "連線方式說明:"
    echo "  - IAP 直接連線：透過 gcloud compute start-iap-tunnel 直接建立到 Redis 的隧道"
    echo "  - Bastion VM 連線：透過 Bastion VM 作為跳板機連線到 Redis"
}

# 檢查前置需求
check_prerequisites() {
    # 檢查 gcloud
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${RED}錯誤: gcloud CLI 未安裝${NC}"
        echo "安裝方式: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # 檢查 redis-cli (如果不是 tunnel-only 模式)
    if [ "$MODE" != "tunnel_only" ] && ! command -v redis-cli >/dev/null 2>&1; then
        echo -e "${RED}錯誤: redis-cli 未安裝${NC}"
        echo "安裝方式:"
        echo "  Ubuntu/Debian: sudo apt-get install redis-tools"
        echo "  macOS: brew install redis"
        echo "  CentOS/RHEL: sudo yum install redis"
        exit 1
    fi

    # 檢查是否已登入
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        echo -e "${RED}錯誤: 請先執行 gcloud auth login${NC}"
        exit 1
    fi
}

# 檢查權限
check_permissions() {
    echo -e "${YELLOW}檢查必要權限...${NC}"

    # 檢查 IAP 權限
    ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    if ! gcloud projects get-iam-policy $PROJECT_ID \
        --flatten="bindings[].members" \
        --format="table(bindings.role, bindings.members)" \
        --filter="bindings.role:iap.tunnelResourceAccessor AND bindings.members:$ACCOUNT" 2>/dev/null | grep -q "iap.tunnelResourceAccessor"; then
        echo -e "${YELLOW}警告: 可能缺少 IAP Tunnel 權限${NC}"
        echo "請確認您具備 roles/iap.tunnelResourceAccessor 權限"
    fi

    # 檢查 Secret Manager 權限
    if ! gcloud secrets versions list $REDIS_SECRET --project=$PROJECT_ID --limit=1 2>/dev/null; then
        echo -e "${RED}錯誤: 無法存取 Redis 密碼 Secret${NC}"
        echo "請確認您具備 roles/secretmanager.secretAccessor 權限"
        exit 1
    fi

    echo -e "${GREEN}✓ 權限檢查通過${NC}"
}

# 取得認證資訊
get_credentials() {
    echo -e "${YELLOW}取得認證資訊...${NC}"

    # 取得密碼
    REDIS_PASSWORD=$(gcloud secrets versions access latest \
        --secret=$REDIS_SECRET \
        --project=$PROJECT_ID 2>/dev/null)

    if [ -z "$REDIS_PASSWORD" ]; then
        echo -e "${RED}錯誤: 無法取得 Redis 密碼${NC}"
        exit 1
    fi

    # 取得 CA 憑證
    CA_FILE="/tmp/redis-ca-${REDIS_INSTANCE}.crt"
    if ! gcloud secrets versions access latest \
        --secret=$REDIS_CA_SECRET \
        --project=$PROJECT_ID \
        --out-file=$CA_FILE 2>/dev/null; then
        echo -e "${RED}錯誤: 無法取得 Redis CA 憑證${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ 認證資訊取得成功${NC}"
    echo -e "${BLUE}密碼長度: ${#REDIS_PASSWORD}${NC}"

    # 檢查密碼格式
    if echo "$REDIS_PASSWORD" | base64 -d >/dev/null 2>&1; then
        echo -e "${YELLOW}注意: 密碼似乎是 base64 編碼格式${NC}"
        if echo "$REDIS_PASSWORD" | base64 -d | file - >/dev/null 2>&1; then
            echo -e "${YELLOW}檢測到二進制密碼，可能需要特殊處理${NC}"
        fi
    fi
}

# 取得 Redis IP
get_redis_host() {
    echo -e "${YELLOW}取得 Redis 實例資訊...${NC}"

    REDIS_HOST=$(gcloud redis instances describe $REDIS_INSTANCE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format="value(host)" 2>/dev/null)

    if [ -z "$REDIS_HOST" ]; then
        echo -e "${RED}錯誤: 無法取得 Redis 實例資訊${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Redis 主機: $REDIS_HOST${NC}"
}

# 檢查 Bastion VM 狀態
check_bastion_vm() {
    if ! gcloud compute instances describe $BASTION_VM \
        --zone=$BASTION_ZONE \
        --project=$PROJECT_ID >/dev/null 2>&1; then
        echo -e "${RED}錯誤: Bastion VM $BASTION_VM 不存在或無法存取${NC}"
        exit 1
    fi

    VM_STATUS=$(gcloud compute instances describe $BASTION_VM \
        --zone=$BASTION_ZONE \
        --project=$PROJECT_ID \
        --format="value(status)")

    if [ "$VM_STATUS" != "RUNNING" ]; then
        echo -e "${YELLOW}Bastion VM 狀態: $VM_STATUS，正在啟動...${NC}"
        gcloud compute instances start $BASTION_VM \
            --zone=$BASTION_ZONE \
            --project=$PROJECT_ID

        # 等待 VM 啟動
        echo -e "${YELLOW}等待 Bastion VM 完全啟動...${NC}"
        sleep 30
    fi

    echo -e "${GREEN}✓ Bastion VM 狀態: 正常運行${NC}"
}

# 建立 IAP 直接連線隧道
create_direct_tunnel() {
    # 檢查端口 6379 狀況並清理佔用進程
    check_port_6379_and_cleanup

    echo -e "${YELLOW}建立 IAP 直接連線隧道...${NC}"
    echo -e "${BLUE}Redis 實例: $REDIS_INSTANCE${NC}"
    echo -e "${BLUE}專案: $PROJECT_ID${NC}"
    echo -e "${BLUE}區域: $REGION${NC}"
    echo -e "${BLUE}本地連接埠: localhost:$LOCAL_PORT${NC}"
    echo

    # 檢查是否已有 tunnel 在運行
    TUNNEL_PID=$(pgrep -f "gcloud.*start-iap-tunnel.*$REDIS_INSTANCE.*$REDIS_PORT" || true)
    if [ -n "$TUNNEL_PID" ]; then
        echo -e "${YELLOW}偵測到現有的 IAP Tunnel (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}是否使用現有 tunnel? (y/n): ${NC}"
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            echo -e "${GREEN}使用現有 IAP Tunnel${NC}"
            return 0
        fi

        echo -e "${YELLOW}終止現有 tunnel...${NC}"
        kill $TUNNEL_PID
        sleep 2
    fi

    # 啟動新的 tunnel
    echo -e "${GREEN}啟動新的 IAP Tunnel...${NC}"
    echo -e "${BLUE}執行指令:${NC}"
    echo -e "${YELLOW}gcloud compute start-iap-tunnel $REDIS_INSTANCE $REDIS_PORT \\"
    echo "  --project=$PROJECT_ID \\"
    echo "  --region=$REGION \\"
    echo "  --local-host-port=localhost:$LOCAL_PORT${NC}"
    echo

    if [ "$MODE" = "tunnel_only" ]; then
        # 在背景執行 tunnel
        gcloud compute start-iap-tunnel $REDIS_INSTANCE $REDIS_PORT \
            --project=$PROJECT_ID \
            --region=$REGION \
            --local-host-port=localhost:$LOCAL_PORT &

        TUNNEL_PID=$!
        echo -e "${GREEN}IAP Tunnel 已在背景啟動 (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}使用 'kill $TUNNEL_PID' 終止 tunnel${NC}"

        # 等待 tunnel 建立完成
        echo -e "${YELLOW}等待 tunnel 建立...${NC}"
        for i in {1..30}; do
            if nc -z localhost $LOCAL_PORT 2>/dev/null; then
                echo -e "${GREEN}✓ Tunnel 建立成功${NC}"
                echo -e "${BLUE}現在可以透過 localhost:$LOCAL_PORT 連線到 Redis${NC}"
                return 0
            fi
            echo -e "${YELLOW}等待 tunnel 建立... ($i/30)${NC}"
            sleep 2
        done

        echo -e "${RED}✗ Tunnel 建立失敗${NC}"
        echo -e "${YELLOW}請檢查網路連線和權限設定${NC}"
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    else
        # 預設使用自動執行模式
        echo -e "${GREEN}自動建立 IAP Tunnel...${NC}"

        # 在背景執行 tunnel
        gcloud compute start-iap-tunnel $REDIS_INSTANCE $REDIS_PORT \
            --project=$PROJECT_ID \
            --region=$REGION \
            --local-host-port=localhost:$LOCAL_PORT &

        TUNNEL_PID=$!
        echo -e "${GREEN}IAP Tunnel 已在背景啟動 (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}使用 'kill $TUNNEL_PID' 終止 tunnel${NC}"

        # 等待 tunnel 建立完成
        echo -e "${YELLOW}等待 tunnel 建立...${NC}"
        for i in {1..30}; do
            if nc -z localhost $LOCAL_PORT 2>/dev/null; then
                echo -e "${GREEN}✓ Tunnel 建立成功${NC}"
                echo -e "${BLUE}現在可以透過 localhost:$LOCAL_PORT 連線到 Redis${NC}"
                return 0
            fi
            echo -e "${YELLOW}等待 tunnel 建立... ($i/30)${NC}"
            sleep 2
        done

        echo -e "${RED}✗ Tunnel 建立失敗${NC}"
        echo -e "${YELLOW}請檢查網路連線和權限設定${NC}"
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    fi
}

# 建立 Bastion VM 隧道
create_bastion_tunnel() {
    # 檢查端口 6379 狀況並清理佔用進程
    check_port_6379_and_cleanup

    echo -e "${YELLOW}檢查 Bastion VM 狀態...${NC}"
    check_bastion_vm

    echo -e "${YELLOW}建立 IAP Tunnel 到 Bastion VM...${NC}"
    echo -e "${BLUE}Bastion VM: $BASTION_VM${NC}"
    echo -e "${BLUE}專案: $PROJECT_ID${NC}"
    echo -e "${BLUE}區域: $BASTION_ZONE${NC}"
    echo -e "${BLUE}Redis: $REDIS_HOST:$REDIS_PORT${NC}"
    echo -e "${BLUE}本地連接埠: localhost:$LOCAL_PORT${NC}"
    echo

    # 檢查是否已有 tunnel 在運行
    TUNNEL_PID=$(pgrep -f "gcloud.*compute.*ssh.*$BASTION_VM.*$LOCAL_PORT" || true)
    if [ -n "$TUNNEL_PID" ]; then
        echo -e "${YELLOW}偵測到現有的 IAP Tunnel (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}是否使用現有 tunnel? (y/n): ${NC}"
        read -r response
        if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
            echo -e "${GREEN}使用現有 IAP Tunnel${NC}"
            return 0
        fi

        echo -e "${YELLOW}終止現有 tunnel...${NC}"
        kill $TUNNEL_PID
        sleep 2
    fi

    # 啟動新的 tunnel
    echo -e "${GREEN}啟動新的 IAP Tunnel...${NC}"
    echo -e "${BLUE}執行指令:${NC}"
    echo -e "${YELLOW}gcloud compute ssh $BASTION_VM \\"
    echo "  --project=$PROJECT_ID \\"
    echo "  --zone=$BASTION_ZONE \\"
    echo "  --tunnel-through-iap \\"
    echo "  --ssh-flag='-L $LOCAL_PORT:$REDIS_HOST:$REDIS_PORT' \\"
    echo "  --ssh-flag='-N' \\"
    echo "  --ssh-flag='-f'"
    echo

    if [ "$MODE" = "tunnel_only" ]; then
        # 在背景執行 tunnel
        gcloud compute ssh $BASTION_VM \
            --project=$PROJECT_ID \
            --zone=$BASTION_ZONE \
            --tunnel-through-iap \
            --ssh-flag="-L $LOCAL_PORT:$REDIS_HOST:$REDIS_PORT" \
            --ssh-flag="-N" \
            --ssh-flag="-f" &

        TUNNEL_PID=$!
        echo -e "${GREEN}IAP Tunnel 已在背景啟動 (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}使用 'kill $TUNNEL_PID' 終止 tunnel${NC}"

        # 等待 tunnel 建立完成
        echo -e "${YELLOW}等待 tunnel 建立...${NC}"
        for i in {1..30}; do
            if nc -z localhost $LOCAL_PORT 2>/dev/null; then
                echo -e "${GREEN}✓ Tunnel 建立成功${NC}"
                echo -e "${BLUE}現在可以透過 localhost:$LOCAL_PORT 連線到 Redis${NC}"
                return 0
            fi
            echo -e "${YELLOW}等待 tunnel 建立... ($i/30)${NC}"
            sleep 2
        done

        echo -e "${RED}✗ Tunnel 建立失敗${NC}"
        echo -e "${YELLOW}請檢查 Bastion VM 狀態和網路連線${NC}"
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    else
        # 預設使用自動執行模式
        echo -e "${GREEN}自動建立 IAP Tunnel...${NC}"

        # 在背景執行 tunnel
        gcloud compute ssh $BASTION_VM \
            --project=$PROJECT_ID \
            --zone=$BASTION_ZONE \
            --tunnel-through-iap \
            --ssh-flag="-L $LOCAL_PORT:$REDIS_HOST:$REDIS_PORT" \
            --ssh-flag="-N" \
            --ssh-flag="-f" &

        TUNNEL_PID=$!
        echo -e "${GREEN}IAP Tunnel 已在背景啟動 (PID: $TUNNEL_PID)${NC}"
        echo -e "${BLUE}使用 'kill $TUNNEL_PID' 終止 tunnel${NC}"

        # 等待 tunnel 建立完成
        echo -e "${YELLOW}等待 tunnel 建立...${NC}"
        for i in {1..30}; do
            if nc -z localhost $LOCAL_PORT 2>/dev/null; then
                echo -e "${GREEN}✓ Tunnel 建立成功${NC}"
                echo -e "${BLUE}現在可以透過 localhost:$LOCAL_PORT 連線到 Redis${NC}"
                return 0
            fi
            echo -e "${YELLOW}等待 tunnel 建立... ($i/30)${NC}"
            sleep 2
        done

        echo -e "${RED}✗ Tunnel 建立失敗${NC}"
        echo -e "${YELLOW}請檢查 Bastion VM 狀態和網路連線${NC}"
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    fi
}

# 連線 Redis
connect_redis() {
    echo -e "${YELLOW}連線到 Redis...${NC}"
    echo -e "${BLUE}連線資訊:${NC}"
    echo -e "  主機: localhost"
    echo -e "  連接埠: $LOCAL_PORT"
    echo -e "  透過: $CONNECTION_METHOD"
    echo -e "  目標: $REDIS_HOST:$REDIS_PORT"
    if [ -f "$CA_FILE" ]; then
        echo -e "  TLS: 啟用 (CA: $CA_FILE)"
    else
        echo -e "  TLS: 未啟用"
    fi
    echo

    # 執行 redis-cli
    if [ -f "$CA_FILE" ]; then
        REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \
            -h localhost \
            -p $LOCAL_PORT \
            --tls \
            --cacert $CA_FILE
    else
        REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \
            -h localhost \
            -p $LOCAL_PORT
    fi
}

# 執行測試
run_test() {
    echo -e "${GREEN}執行 Redis 連線測試...${NC}"

    if [ -f "./test-redis-connection.sh" ]; then
        ./test-redis-connection.sh
    else
        echo -e "${RED}測試腳本不存在: ./test-redis-connection.sh${NC}"
        exit 1
    fi
}

# 檢查端口 6379 並清理佔用的進程
check_port_6379_and_cleanup() {
    # 只檢查端口 6379，不檢查其他端口
    if [ "$LOCAL_PORT" != "6379" ]; then
        # 如果不是端口 6379，不需要檢查和清理
        return 0
    fi

    echo -e "${YELLOW}檢查端口 6379 使用狀況...${NC}"

    # 使用 ss 指令檢查端口 6379
    local port_info=$(ss -tulpn | grep ":6379 ")

    if [ -n "$port_info" ]; then
        echo -e "${RED}⚠️  端口 6379 已被佔用${NC}"
        echo -e "${BLUE}佔用進程資訊：${NC}"
        echo "$port_info"
        echo

        # 解析 PID
        local pid=$(echo "$port_info" | grep -o 'pid=[0-9]*' | cut -d'=' -f2 | head -1)

        if [ -n "$pid" ]; then
            echo -e "${YELLOW}發現佔用進程 PID: $pid${NC}"
            echo -e "${BLUE}要終止此進程以釋放端口 6379 嗎？ (y/n): ${NC}"
            read -r response

            if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
                echo -e "${YELLOW}正在終止進程 $pid...${NC}"
                kill "$pid"

                # 等待進程終止
                sleep 2

                # 再次檢查端口是否已釋放
                local check_port=$(ss -tulpn | grep ":6379 ")
                if [ -z "$check_port" ]; then
                    echo -e "${GREEN}✓ 端口 6379 已成功釋放${NC}"
                else
                    echo -e "${RED}✗ 無法釋放端口 6379，請手動檢查${NC}"
                    echo -e "${YELLOW}您可以使用以下指令手動終止進程：${NC}"
                    echo -e "${BLUE}sudo kill -9 $pid${NC}"
                    exit 1
                fi
            else
                echo -e "${YELLOW}取消終止進程，請手動處理端口衝突後再執行腳本${NC}"
                exit 1
            fi
        else
            echo -e "${RED}無法取得佔用進程的 PID${NC}"
            echo -e "${YELLOW}請手動檢查並終止佔用端口 6379 的進程${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ 端口 6379 可用${NC}"
    fi
}

# 清理函數
cleanup() {
    if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
        rm -f "$CA_FILE"
    fi
}

# 設定 trap
trap cleanup EXIT

# 預設模式和連線方式
MODE="connect"
CONNECTION_METHOD="Bastion VM 跳板"

# 解析參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--direct)
            CONNECTION_METHOD="IAP 直接連線"
            shift
            ;;
        -b|--bastion)
            CONNECTION_METHOD="Bastion VM 跳板"
            shift
            ;;
        -c|--cli)
            MODE="tunnel_only"
            shift
            ;;
        -t|--test)
            MODE="test"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo -e "${RED}錯誤: 未知選項 $1${NC}"
            show_usage
            exit 1
            ;;
        *)
            if [[ $1 =~ ^[0-9]+$ ]]; then
                LOCAL_PORT=$1
            else
                echo -e "${RED}錯誤: 無效的連接埠號碼 $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# 主要流程
main() {
    case $MODE in
        "test")
            run_test
            ;;
        "tunnel_only"|"connect")
            echo -e "${GREEN}=== Redis 快速連線腳本 ===${NC}"
            echo -e "${BLUE}連線方式: $CONNECTION_METHOD${NC}"
            echo

            check_prerequisites
            check_permissions
            get_credentials
            get_redis_host

            if [ "$CONNECTION_METHOD" = "IAP 直接連線" ]; then
                create_direct_tunnel
            else
                create_bastion_tunnel
            fi

            if [ "$MODE" = "connect" ]; then
                connect_redis
            fi
            ;;
    esac
}

# 執行主函數
main