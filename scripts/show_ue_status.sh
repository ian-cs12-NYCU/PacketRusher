#!/bin/bash
#
# UE 狀態查詢腳本
# 用途：顯示當前所有 UE 的詳細狀態信息
#

# 解析命令行參數
PING_TEST=false
PING_TARGET="8.8.8.8"
PING_COUNT=3

show_usage() {
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -p, --ping          測試每個 UE 介面的網路連通性 (ping 8.8.8.8)"
    echo "  -t, --target <IP>   指定 ping 目標 (預設: 8.8.8.8)"
    echo "  -c, --count <N>     ping 次數 (預設: 3)"
    echo "  -h, --help          顯示此幫助信息"
    echo ""
    echo "範例:"
    echo "  $0                  # 僅顯示狀態"
    echo "  $0 -p               # 顯示狀態並測試連通性"
    echo "  $0 -p -t 1.1.1.1    # 測試連通性到 1.1.1.1"
    echo "  $0 -p -c 5          # 每個介面 ping 5 次"
    exit 0
}

# 解析參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ping)
            PING_TEST=true
            shift
            ;;
        -t|--target)
            PING_TARGET="$2"
            shift 2
            ;;
        -c|--count)
            PING_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "未知選項: $1"
            echo "使用 -h 或 --help 查看幫助"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "PacketRusher UE 狀態查詢"
echo "=========================================="
echo ""

if [ "$PING_TEST" = true ]; then
    echo "🔍 連通性測試: 啟用 (目標: $PING_TARGET, 次數: $PING_COUNT)"
    echo ""
fi

# 統計總數
VAL_COUNT=$(ip addr show | grep -E "^[0-9]+: val[0-9]+" | wc -l)
VRF_COUNT=$(ip link show type vrf 2>/dev/null | grep -E "^[0-9]+: vrf[0-9]+" | wc -l || echo 0)
RULE_COUNT=$(ip rule show | grep -E "from 10.60" | wc -l)
TABLE_COUNT=0

for TABLE_ID in {2..200}; do
    if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
        TABLE_COUNT=$((TABLE_COUNT + 1))
    fi
done

echo "📊 系統總覽："
echo "  - 檢測到 UE 數量: $VAL_COUNT"
echo "  - VRF 介面數量: $VRF_COUNT"
echo "  - 路由規則數量: $RULE_COUNT"
echo "  - 使用中的路由表: $TABLE_COUNT"
echo ""

if [ "$VAL_COUNT" -eq 0 ]; then
    echo "❌ 沒有檢測到活動的 UE"
    echo ""
    echo "要創建 UE，請運行："
    echo "  cd /home/vagrant/PacketRusher"
    echo "  sudo ./packetrusher multi-ue-pdu -t -d --tunnel-vrf=false -n 10"
    exit 0
fi

# 顯示詳細的 UE 信息
echo "=========================================="
echo "UE 詳細信息"
echo "=========================================="
echo ""

COUNTER=1
ip addr show | grep -E "^[0-9]+: val[0-9]+" | while read line; do
    IFACE=$(echo "$line" | grep -oP 'val[0-9]+')
    MSIN=$(echo "$IFACE" | grep -oP '\d+')
    
    # 獲取 IP 地址
    IP=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}')
    
    # 獲取介面狀態
    STATE=$(ip link show "$IFACE" 2>/dev/null | grep -oP 'state \K\w+' || echo "UNKNOWN")
    
    # 檢查對應的 VRF
    VRF_NAME="vrf$MSIN"
    HAS_VRF="否"
    if ip link show type vrf 2>/dev/null | grep -q "$VRF_NAME"; then
        HAS_VRF="是"
    fi
    
    # 檢查路由規則
    RULE_EXISTS="否"
    if [ -n "$IP" ]; then
        IP_ADDR=$(echo "$IP" | cut -d'/' -f1)
        if ip rule show | grep -q "from $IP_ADDR"; then
            RULE_EXISTS="是"
        fi
    fi
    
    # 檢查路由表
    TABLE_ID=""
    ROUTE_COUNT=0
    if ip rule show | grep -q "from $IP_ADDR"; then
        TABLE_ID=$(ip rule show | grep "from $IP_ADDR" | grep -oP 'lookup \K\d+' | head -1)
        if [ -n "$TABLE_ID" ]; then
            ROUTE_COUNT=$(ip route show table "$TABLE_ID" 2>/dev/null | wc -l)
        fi
    fi
    
    echo "UE #$COUNTER (MSIN: $MSIN)"
    echo "  介面名稱: $IFACE"
    echo "  IP 地址: ${IP:-未分配}"
    echo "  介面狀態: $STATE"
    echo "  VRF 介面: $HAS_VRF"
    echo "  路由規則: $RULE_EXISTS"
    if [ -n "$TABLE_ID" ]; then
        echo "  路由表 ID: $TABLE_ID (包含 $ROUTE_COUNT 條路由)"
    else
        echo "  路由表 ID: 無"
    fi
    
    # 執行 ping 測試（如果啟用）
    if [ "$PING_TEST" = true ] && [ -n "$IP_ADDR" ]; then
        echo -n "  連通性測試: "
        
        # 根據是否有 VRF 來決定 ping 命令
        if [ "$HAS_VRF" = "是" ]; then
            # 使用 VRF 執行 ping
            PING_RESULT=$(ip vrf exec "$VRF_NAME" ping -c "$PING_COUNT" -W 2 "$PING_TARGET" 2>/dev/null | grep -oP '\d+% packet loss' || echo "100% packet loss")
        else
            # 使用 source IP 執行 ping
            PING_RESULT=$(ping -I "$IP_ADDR" -c "$PING_COUNT" -W 2 "$PING_TARGET" 2>/dev/null | grep -oP '\d+% packet loss' || echo "100% packet loss")
        fi
        
        LOSS=$(echo "$PING_RESULT" | grep -oP '^\d+')
        if [ "$LOSS" = "0" ]; then
            # 取得平均延遲
            if [ "$HAS_VRF" = "是" ]; then
                AVG_RTT=$(ip vrf exec "$VRF_NAME" ping -c "$PING_COUNT" -W 2 "$PING_TARGET" 2>/dev/null | grep -oP 'rtt min/avg/max/mdev = [\d.]+/\K[\d.]+' || echo "N/A")
            else
                AVG_RTT=$(ping -I "$IP_ADDR" -c "$PING_COUNT" -W 2 "$PING_TARGET" 2>/dev/null | grep -oP 'rtt min/avg/max/mdev = [\d.]+/\K[\d.]+' || echo "N/A")
            fi
            echo "✅ 成功 (丟包率: ${LOSS}%, 平均延遲: ${AVG_RTT}ms)"
        elif [ "$LOSS" = "100" ]; then
            echo "❌ 失敗 (丟包率: 100%)"
        else
            echo "⚠️  部分成功 (丟包率: ${LOSS}%)"
        fi
    fi
    
    echo ""
    
    COUNTER=$((COUNTER + 1))
    
    # 限制顯示數量
    if [ "$COUNTER" -gt 20 ]; then
        REMAINING=$((VAL_COUNT - 20))
        if [ "$REMAINING" -gt 0 ]; then
            echo "... 還有 $REMAINING 個 UE (僅顯示前 20 個)"
        fi
        break
    fi
done

echo "=========================================="
echo "路由表使用情況"
echo "=========================================="
echo ""

SHOWN=0
for TABLE_ID in {2..200}; do
    if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
        ROUTE_COUNT=$(ip route show table "$TABLE_ID" 2>/dev/null | wc -l)
        echo "Table $TABLE_ID: $ROUTE_COUNT 條路由"
        SHOWN=$((SHOWN + 1))
        
        if [ "$SHOWN" -ge 10 ]; then
            REMAINING=$((TABLE_COUNT - SHOWN))
            if [ "$REMAINING" -gt 0 ]; then
                echo "... 還有 $REMAINING 個路由表在使用中"
            fi
            break
        fi
    fi
done

echo ""
echo "=========================================="
echo "管理操作"
echo "=========================================="
echo ""
echo "可用命令："
echo "  - 清理所有 UE: sudo ./scripts/cleanup_ue_interfaces.sh"
echo "  - 查看此狀態: ./scripts/show_ue_status.sh"
echo "  - 測試連通性: ./scripts/show_ue_status.sh --ping"
echo ""

# 如果執行了 ping 測試，顯示摘要
if [ "$PING_TEST" = true ]; then
    echo "=========================================="
    echo "連通性測試摘要"
    echo "=========================================="
    echo ""
    echo "測試目標: $PING_TARGET"
    echo "Ping 次數: $PING_COUNT"
    echo ""
    echo "💡 提示："
    echo "  - 如果測試失敗，請確認 PacketRusher 與核心網路連接正常"
    echo "  - 可以使用不同目標測試: ./scripts/show_ue_status.sh -p -t 1.1.1.1"
    echo "  - 增加 ping 次數以獲得更準確結果: ./scripts/show_ue_status.sh -p -c 10"
    echo ""
fi
