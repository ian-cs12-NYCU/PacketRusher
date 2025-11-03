## Cleanup and Management (PacketRusher scripts)

This document covers the scripts provided in the `scripts/` directory for checking UE status and cleaning up network resources created by PacketRusher.

### UE Status Check Script

Check the current status and count of active simulated UEs:

```bash
./scripts/show_ue_status.sh
```

With connectivity testing:

```bash
# Test connectivity to 8.8.8.8 (default)
./scripts/show_ue_status.sh --ping

# Test connectivity to a custom target
./scripts/show_ue_status.sh --ping --target 1.1.1.1

# Increase ping count for more accurate results
./scripts/show_ue_status.sh --ping --count 5

# Short form options
./scripts/show_ue_status.sh -p -t 1.1.1.1 -c 10
```

Features:
- Total UE count
- Detailed UE information (interface, IP, state, VRF, routing, table)
- Optional connectivity testing (supports VRF and non-VRF)
- Customizable ping target and count
- Real-time RX/TX traffic monitoring via `ue_tx_rx_monitor.py` (shows packets/sec and bytes/sec)

#### UE TX/RX monitor — output columns

When you run `./scripts/ue_tx_rx_monitor.py` it prints a table with the following columns:

- Interface: UE interface name (e.g. `val0000000001`).
- RX pkts: cumulative number of received packets on the interface (since the interface started).
- r/s: receive packets per second (instantaneous rate calculated from the sample delta).
- RX Δ: number of bytes received during the sample interval (human-readable, e.g. `1.2KB`).
- rb/s: receive bytes per second (instantaneous bytes/s calculated from the sample delta).
- RX B: cumulative received bytes (human-readable total since interface start).
- TX pkts: cumulative number of transmitted packets on the interface.
- t/s: transmit packets per second (instantaneous rate).
- TX Δ: number of bytes transmitted during the sample interval (human-readable).
- tb/s: transmit bytes per second (instantaneous bytes/s).
- TX B: cumulative transmitted bytes (human-readable total since interface start).

Notes:
- Rates (`r/s`, `rb/s`, `t/s`, `tb/s`) are computed as (delta / interval). Default interval is 1 second and can be changed with `-i`.
- Delta columns (`RX Δ`, `TX Δ`) show the bytes transferred during the last sample and are presented in a human-friendly unit.
- Cumulative columns (`RX pkts`, `RX B`, `TX pkts`, `TX B`) are monotonically increasing counters read from `/sys/class/net/<iface>/statistics`.


Example output and usage details are shown when running the script with `--help`.

### UE Interface Cleanup Script

Use this script to remove all PacketRusher-related network resources (interfaces, VRFs, rules, tables):

```bash
sudo ./scripts/cleanup_ue_interfaces.sh
```

What it cleans:
- `val<MSIN>` interfaces (TUN devices for each UE)
- `vrf<MSIN>` VRF devices (when VRF mode enabled)
- IP rules created for UE traffic
- Routing tables used for UE isolation (tables 2..200)

The script reports summary statistics and provides troubleshooting recommendations if residual items remain.

### Common workflow

```bash
# 1. Check current UE status
./scripts/show_ue_status.sh

# 2. Optionally test connectivity
./scripts/show_ue_status.sh --ping

# 3. Run PacketRusher tests
sudo ./packetrusher multi-ue-pdu -t -d --tunnel-vrf=false -n 10

# 4. Stop PacketRusher (Ctrl+C)

# 5. Clean up network resources
sudo ./scripts/cleanup_ue_interfaces.sh

# 6. Verify cleanup
./scripts/show_ue_status.sh
```

### Troubleshooting tips

- If resources remain, run the cleanup script again.
- Ensure PacketRusher is not running; if it is, stop it (`pkill -9 packetrusher`) and retry cleanup.
- Manual checks:

```bash
ip link show | grep val
ip link show type vrf | grep vrf
ip rule show | grep 10.60
for i in {2..200}; do ip route show table $i 2>/dev/null | grep -q . && echo "Table $i has routes"; done
```

---

For more details about each script, run them with `--help` or read the source under `scripts/`.
