#!/bin/bash
#
# UE 介面完整清理腳本
# 用途：清理所有 PacketRusher 創建的 val 介面、VRF 介面、路由規則和路由表
#

set -e

echo "=========================================="
echo "UE 介面完整清理腳本"
echo "=========================================="
echo ""

# 檢查是否有 root 權限
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 此腳本需要 root 權限，請使用 sudo 執行"
    exit 1
fi

# 統計當前狀態
INTERFACE_COUNT=$(ip addr show | grep -E "^[0-9]+: val[0-9]+" | wc -l)
VRF_COUNT=$(ip link show type vrf 2>/dev/null | grep -E "^[0-9]+: vrf[0-9]+" | wc -l || echo 0)
RULE_COUNT=$(ip rule show | grep -E "from 10.60" | wc -l)
ROUTE_TABLE_COUNT=0

# 計算有內容的路由表數量
for TABLE_ID in {2..200}; do
    if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
        ROUTE_TABLE_COUNT=$((ROUTE_TABLE_COUNT + 1))
    fi
done

echo "當前狀態："
echo "  - val 介面數量: $INTERFACE_COUNT"
echo "  - VRF 介面數量: $VRF_COUNT"
echo "  - 路由規則數量: $RULE_COUNT"
echo "  - 使用中的路由表: $ROUTE_TABLE_COUNT"
echo ""

# 估算 UE 數量 (每個 UE 通常有一個 val 介面)
if [ "$INTERFACE_COUNT" -gt 0 ]; then
    echo "📊 檢測到約 $INTERFACE_COUNT 個未清理的 UE"
    echo ""
fi

if [ "$INTERFACE_COUNT" -eq 0 ] && [ "$VRF_COUNT" -eq 0 ] && [ "$RULE_COUNT" -eq 0 ] && [ "$ROUTE_TABLE_COUNT" -eq 0 ]; then
    echo "✅ 系統已經清理乾淨，無需執行清理操作"
    exit 0
fi

read -p "是否繼續清理？(yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "取消清理操作"
    exit 0
fi

echo ""
echo "=========================================="
echo "步驟 1: 清理路由規則"
echo "=========================================="

# 獲取所有相關的路由規則並刪除
echo "正在刪除 10.60.x.x 相關的路由規則..."
RULES_DELETED=0

# 使用 while 循環持續刪除，直到沒有匹配的規則
while ip rule show | grep -q "from 10.60"; do
    # 獲取第一條匹配的規則
    RULE=$(ip rule show | grep "from 10.60" | head -1)
    
    if [ -n "$RULE" ]; then
        # 提取 from IP 和 table
        FROM_IP=$(echo "$RULE" | grep -oP 'from \K[0-9.]+')
        TABLE=$(echo "$RULE" | grep -oP 'lookup \K[0-9]+')
        
        if [ -n "$FROM_IP" ] && [ -n "$TABLE" ]; then
            echo "  刪除規則: from $FROM_IP lookup $TABLE"
            ip rule del from "$FROM_IP" table "$TABLE" 2>/dev/null || true
            RULES_DELETED=$((RULES_DELETED + 1))
        fi
    else
        break
    fi
    
    # 防止無限循環
    if [ $RULES_DELETED -gt 1000 ]; then
        echo "  ⚠️  警告：已刪除超過 1000 條規則，停止操作"
        break
    fi
done

echo "  ✓ 已刪除 $RULES_DELETED 條路由規則"
echo ""

echo "=========================================="
echo "步驟 2: 清理路由表"
echo "=========================================="

echo "正在清理所有自定義路由表..."
TABLES_CLEANED=0

# 清理 table 2-200 (自定義表範圍)
for TABLE_ID in {2..200}; do
    # 檢查路由表是否有內容
    if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
        echo "  清理 table $TABLE_ID"
        ip route flush table "$TABLE_ID" 2>/dev/null || true
        TABLES_CLEANED=$((TABLES_CLEANED + 1))
    fi
done

echo "  ✓ 已清理 $TABLES_CLEANED 個路由表"
echo ""

echo "=========================================="
echo "步驟 3: 刪除 VRF 網路介面"
echo "=========================================="

echo "正在刪除所有 VRF 介面..."
VRF_DELETED=0

# 獲取所有 VRF 介面名稱
VRF_INTERFACES=$(ip link show type vrf 2>/dev/null | grep -oP '^\d+: \Kvrf[0-9]+' || true)

if [ -z "$VRF_INTERFACES" ]; then
    echo "  ℹ️  沒有找到 VRF 介面"
else
    for VRF_INTERFACE in $VRF_INTERFACES; do
        echo "  刪除 VRF 介面: $VRF_INTERFACE"
        # 先關閉介面再刪除
        ip link set "$VRF_INTERFACE" down 2>/dev/null || true
        ip link del "$VRF_INTERFACE" 2>/dev/null || true
        VRF_DELETED=$((VRF_DELETED + 1))
    done
    echo "  ✓ 已刪除 $VRF_DELETED 個 VRF 介面"
fi

echo ""

echo "=========================================="
echo "步驟 4: 刪除 val 網路介面"
echo "=========================================="

echo "正在刪除所有 val 介面..."
INTERFACES_DELETED=0

# 獲取所有 val 介面名稱
VAL_INTERFACES=$(ip addr show | grep -oP '^\d+: \Kval[0-9]+' || true)

if [ -z "$VAL_INTERFACES" ]; then
    echo "  ℹ️  沒有找到 val 介面"
else
    for INTERFACE in $VAL_INTERFACES; do
        echo "  刪除介面: $INTERFACE"
        # 先關閉介面再刪除
        ip link set "$INTERFACE" down 2>/dev/null || true
        ip link del "$INTERFACE" 2>/dev/null || true
        INTERFACES_DELETED=$((INTERFACES_DELETED + 1))
    done
    echo "  ✓ 已刪除 $INTERFACES_DELETED 個介面"
fi

echo ""

echo "=========================================="
echo "步驟 5: 驗證清理結果"
echo "=========================================="

# 重新統計
REMAINING_INTERFACES=$(ip addr show | grep -E "^[0-9]+: val[0-9]+" | wc -l)
REMAINING_VRF=$(ip link show type vrf 2>/dev/null | grep -E "^[0-9]+: vrf[0-9]+" | wc -l || echo 0)
REMAINING_RULES=$(ip rule show | grep -E "from 10.60" | wc -l)
REMAINING_ROUTES=0

for TABLE_ID in {2..200}; do
    if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
        REMAINING_ROUTES=$((REMAINING_ROUTES + 1))
    fi
done

echo "清理結果："
echo "  - 剩餘 val 介面: $REMAINING_INTERFACES"
echo "  - 剩餘 VRF 介面: $REMAINING_VRF"
echo "  - 剩餘路由規則: $REMAINING_RULES"
echo "  - 有內容的路由表: $REMAINING_ROUTES"
echo ""

# 總結
TOTAL_CLEANED=$((INTERFACES_DELETED + VRF_DELETED + RULES_DELETED + TABLES_CLEANED))
echo "📈 清理統計："
echo "  - 已刪除 val 介面: $INTERFACES_DELETED"
echo "  - 已刪除 VRF 介面: $VRF_DELETED"
echo "  - 已刪除路由規則: $RULES_DELETED"
echo "  - 已清空路由表: $TABLES_CLEANED"
echo "  - 總計清理項目: $TOTAL_CLEANED"
echo ""

if [ "$REMAINING_INTERFACES" -eq 0 ] && [ "$REMAINING_VRF" -eq 0 ] && [ "$REMAINING_RULES" -eq 0 ] && [ "$REMAINING_ROUTES" -eq 0 ]; then
    echo "✅ 清理完成！系統已恢復乾淨狀態"
    echo ""
    echo "現在可以重新運行 PacketRusher 創建新的 UE："
    echo "  cd /home/vagrant/PacketRusher"
    echo "  sudo ./packetrusher multi-ue-pdu -t -d --tunnel-vrf=false -n 10"
    exit 0
else
    echo "⚠️  清理後仍有殘留項目"
    
    if [ "$REMAINING_VRF" -gt 0 ]; then
        echo ""
        echo "剩餘的 VRF 介面："
        ip link show type vrf 2>/dev/null | grep -E "^[0-9]+: vrf" | head -10
    fi
    
    if [ "$REMAINING_INTERFACES" -gt 0 ]; then
        echo ""
        echo "剩餘的 val 介面："
        ip addr show | grep -E "^[0-9]+: val[0-9]+" | head -10
    fi
    
    if [ "$REMAINING_RULES" -gt 0 ]; then
        echo ""
        echo "剩餘的路由規則："
        ip rule show | grep "from 10.60" | head -10
    fi
    
    if [ "$REMAINING_ROUTES" -gt 0 ]; then
        echo ""
        echo "仍有內容的路由表："
        for TABLE_ID in {2..200}; do
            if ip route show table "$TABLE_ID" 2>/dev/null | grep -q .; then
                echo "  Table $TABLE_ID: $(ip route show table "$TABLE_ID" 2>/dev/null | wc -l) 條路由"
            fi
        done | head -10
    fi
    
    echo ""
    echo "建議："
    echo "  1. 重新運行此腳本: sudo $0"
    echo "  2. 如果問題持續，請手動檢查殘留的網路配置"
    exit 1
fi
