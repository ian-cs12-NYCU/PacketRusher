# UE Packet Monitor

Script: `scripts/ue_packet_monitor.py`

監控特定 UE（由源 IP 地址指定）發出的所有封包，顯示目標地址。

## 功能

- **交互式 UE 選擇** - 列出所有活動的 UE 介面，讓用戶選擇
- **兩種顯示模式**:
  - **簡單模式** (預設): `IP.src ---> IP.dst [Protocol]`
  - **5-tuple 模式**: `IP:Port ---> IP:Port [Protocol]`
- **支持 IPv4 和 IPv6**
- **支持 TCP/UDP 協議檢測**
- **實時輸出** - 對齊的欄位，易於閱讀

## 安裝

腳本需要 `tshark` 工具：

```bash
sudo apt-get install tshark
```

## 用法

### 基本命令

#### 交互式 UE 選擇（推薦）
```bash
sudo ./scripts/ue_packet_monitor.py --select
```

這將列出所有活動的 UE，讓你選擇要監控的 UE。

#### 指定 IP 地址
```bash
sudo ./scripts/ue_packet_monitor.py --src-ip 10.60.100.1
```

### 顯示模式

#### 簡單模式（預設）
```bash
sudo ./scripts/ue_packet_monitor.py --select
```
輸出示例：
```
     #  Source IP            Destination IP   Protocol
----------------------------------------------------------
     1  10.60.100.1     ---> 1.1.1.1          [ICMP]
     2  10.60.100.1     ---> 1.1.1.1          [ICMP]
     3  10.60.100.1     ---> 8.8.8.8          [TCP]
```

#### 5-tuple 模式（包括端口和協議）
```bash
sudo ./scripts/ue_packet_monitor.py --select --5-tuple
```
輸出示例：
```
     #  Source                      Destination             Protocol
----------------------------------------------------------------------
     1  10.60.100.1            ---> 1.1.1.1                 [ICMP]
     2  10.60.100.1:12345      ---> 8.8.8.8:443             [TCP]
     3  10.60.100.1:5678       ---> 8.8.4.4:53              [UDP]
```

### 其他選項

#### 指定網卡
```bash
sudo ./scripts/ue_packet_monitor.py --src-ip 10.60.100.1 --interface val0000000001
```

#### 限制封包數量
```bash
# 捕獲 100 個封包後停止
sudo ./scripts/ue_packet_monitor.py --src-ip 10.60.100.1 --count 100
```

#### 調試模式
```bash
sudo ./scripts/ue_packet_monitor.py --select --debug
```
顯示 tshark 命令和正在使用的篩選器。

## 支持的協議

- ICMP (協議 1)
- TCP (協議 6)
- UDP (協議 17)
- ICMPv6 (協議 58)
- 其他協議顯示協議號

## 故障排除

### 看不到任何封包

1. **確認 IP 地址正確**：
   ```bash
   ip addr show val0000000001
   ```

2. **確認有實際流量**（用另一個終端 ping）：
   ```bash
   ping 1.1.1.1  # 從 UE 發送 ping
   ```

3. **驗證 tcpdump 是否工作**：
   ```bash
   sudo tcpdump -i val0000000001 'src 10.60.100.1'
   ```

4. **檢查是否有防火牆或 QoS 問題**

### 權限錯誤

腳本需要 root 權限才能捕獲封包。始終用 `sudo` 運行：
```bash
sudo ./scripts/ue_packet_monitor.py --select
```

## 比較 ue_tx_rx_monitor.py

| 功能 | ue_tx_rx_monitor.py | ue_packet_monitor.py |
|------|-------------------|----------------------|
| 監控對象 | 所有介面的 RX/TX 統計 | 特定 UE 的應用層目標 |
| 顯示方式 | 速率 (packets/sec, bytes/sec) | 詳細的源/目標地址 |
| 用途 | 性能監控 | 流量分析 |
| 協議細節 | 不顯示 | 顯示協議和端口 |

## 範例

### 監控 Ping 流量
```bash
# 終端 1: 運行監控
sudo ./scripts/ue_packet_monitor.py --select

# 終端 2: 發送 ping
ping 1.1.1.1
```

### 監控 DNS 查詢
```bash
# 終端 1: 運行監控並顯示 5-tuple
sudo ./scripts/ue_packet_monitor.py --src-ip 10.60.100.1 --5-tuple

# 終端 2: 進行 DNS 查詢
nslookup example.com
```

### 監控並保存結果
```bash
# 捕獲 1000 個封包並保存到文件
sudo ./scripts/ue_packet_monitor.py --select --count 1000 > packet_log.txt
```

## 技術細節

- 使用 `tshark` 進行封包捕獲和篩選
- 使用 `stdbuf` 強制行緩衝以確保實時輸出
- 使用顯示過濾器 (display filter) 而不是 BPF 過濾器，以支持 RAW IP 介面
- 自動檢測 val* 介面和其分配的 IP

## 相關文件

- `ue_tx_rx_monitor.py` - 實時 RX/TX 統計監控
