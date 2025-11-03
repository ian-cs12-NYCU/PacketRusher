#!/bin/bash
#
# UE 管理工具 - 一鍵式管理腳本
# 用途：提供清理、驗證和狀態檢查的統一入口
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "UE 管理工具"
    echo ""
    echo "用法: $0 <command>"
    echo ""
    echo "可用命令:"
    echo "  status    - 檢查當前 UE 狀態"
    echo "  verify    - 驗證 UE 路由配置和連通性"
    echo "  fix       - 修復 UE 路由配置"
    echo "  cleanup   - 清理所有 val 介面和路由（需要 sudo）"
    echo "  reset     - 完整重置：清理 + 重新運行 PacketRusher"
    echo ""
    echo "範例:"
    echo "  $0 status          # 查看當前狀態"
    echo "  sudo $0 cleanup    # 清理所有介面"
    echo "  $0 verify          # 驗證配置"
}

check_status() {
    echo "=========================================="
    echo "UE 狀態檢查"
    echo "=========================================="
    echo ""
    
    INTERFACE_COUNT=$(ip addr show | grep -E "^[0-9]+: val" | wc -l)
    RULE_COUNT=$(ip rule show | grep -E "from 10.60" | wc -l)
    
    echo "當前狀態："
    echo "  - val 介面數量: $INTERFACE_COUNT"
    echo "  - 路由規則數量: $RULE_COUNT"
    echo ""
    
    if [ "$INTERFACE_COUNT" -eq 0 ]; then
        echo "❌ 沒有 UE 介面，請先運行 PacketRusher"
        echo ""
        echo "建議命令："
        echo "  cd /home/vagrant/PacketRusher"
        echo "  sudo ./packetrusher multi-ue-pdu -t -d --tunnel-vrf=false -n 10"
        return 1
    fi
    
    echo "前 10 個 UE 介面："
    ip addr show | grep -E "^[0-9]+: val" | head -10 | while read line; do
        IFACE=$(echo "$line" | grep -oP 'val[0-9]+')
        IP=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}')
        echo "  - $IFACE: $IP"
    done
    
    echo ""
    return 0
}

run_verify() {
    if [ -f "$SCRIPT_DIR/verify_ue_routes.sh" ]; then
        "$SCRIPT_DIR/verify_ue_routes.sh"
    else
        echo "❌ 找不到驗證腳本: $SCRIPT_DIR/verify_ue_routes.sh"
        exit 1
    fi
}

run_fix() {
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 修復需要 root 權限，請使用 sudo"
        exit 1
    fi
    
    if [ -f "$SCRIPT_DIR/fix_ue_routes.sh" ]; then
        "$SCRIPT_DIR/fix_ue_routes.sh"
    else
        echo "❌ 找不到修復腳本: $SCRIPT_DIR/fix_ue_routes.sh"
        exit 1
    fi
}

run_cleanup() {
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 清理需要 root 權限，請使用 sudo"
        exit 1
    fi
    
    if [ -f "$SCRIPT_DIR/cleanup_ue_quick.sh" ]; then
        "$SCRIPT_DIR/cleanup_ue_quick.sh"
    else
        echo "❌ 找不到清理腳本: $SCRIPT_DIR/cleanup_ue_quick.sh"
        exit 1
    fi
}

run_reset() {
    if [ "$EUID" -ne 0 ]; then 
        echo "❌ 重置需要 root 權限，請使用 sudo"
        exit 1
    fi
    
    echo "=========================================="
    echo "完整重置流程"
    echo "=========================================="
    echo ""
    
    # 步驟 1: 清理
    echo "步驟 1/2: 清理現有介面..."
    run_cleanup
    echo ""
    
    # 步驟 2: 提示重新運行 PacketRusher
    echo "步驟 2/2: 重新創建 UE"
    echo ""
    echo "請在另一個終端運行以下命令："
    echo ""
    echo "  cd /home/vagrant/PacketRusher"
    echo "  sudo ./packetrusher multi-ue-pdu -t -d --tunnel-vrf=false -n 10"
    echo ""
    echo "等待 UE 創建完成後，運行："
    echo "  $0 verify"
    echo ""
}

# 主程式
case "${1:-}" in
    status)
        check_status
        ;;
    verify)
        run_verify
        ;;
    fix)
        run_fix
        ;;
    cleanup)
        run_cleanup
        ;;
    reset)
        run_reset
        ;;
    -h|--help|help)
        show_usage
        ;;
    "")
        show_usage
        exit 1
        ;;
    *)
        echo "❌ 未知命令: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
