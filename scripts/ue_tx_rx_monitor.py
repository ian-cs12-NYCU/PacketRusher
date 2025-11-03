#!/usr/bin/env python3
"""
UE traffic monitor

Shows real-time transmitted (TX) and received (RX) packets and bytes per PacketRusher
UE interface (val<MSIN>). Reads statistics from /sys/class/net/<iface>/statistics and
prints a table with rates.

Usage:
    ./scripts/ue_tx_monitor.py [-i INTERVAL] [-n COUNT] [--interfaces val1 val2 ...]

Options:
    -i, --interval  Poll interval in seconds (default: 1)
    -n, --count     Number of samples to show (default: 0 -> run until Ctrl-C)
    --interfaces    Space-separated list of interfaces to monitor (default: auto-detect val*)
    -h, --help      Show help

Examples:
    ./scripts/ue_tx_monitor.py
    ./scripts/ue_tx_monitor.py -i 2
    ./scripts/ue_tx_monitor.py --interfaces val0000000001 val0000000002

"""
import argparse
import glob
import os
import sys
import time
from collections import defaultdict


def detect_val_interfaces():
    paths = glob.glob('/sys/class/net/val*')
    ifaces = [os.path.basename(p) for p in paths]
    return sorted(ifaces)


def read_stat(iface, stat):
    path = f'/sys/class/net/{iface}/statistics/{stat}'
    try:
        with open(path, 'r') as f:
            return int(f.read().strip())
    except Exception:
        return None


def format_rate(delta, interval):
    if interval <= 0:
        return '0/s'
    per_s = delta / interval
    # choose unit for packets (just /s) and bytes (/s with human readable)
    return f'{per_s:,.1f}/s'


def human_bytes(n):
    try:
        n = float(n)
    except Exception:
        return 'N/A'
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(n) < 1024.0:
            return f"{n:3.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}PB"


def print_table(rows, timestamp, sample):
    # rows: list of tuples (iface, rx_pkts_total, rps, rxb_human, rbps, rx_bytes_total,
    #                        tx_pkts_total, tps, txb_human, tbps, tx_bytes_total)
    print('\n' + '=' * 120)
    print(f'Time: {timestamp}   Sample: {sample}')
    print('-' * 120)
    header = f"{'Interface':<20}{'RX pkts':>10}{'r/s':>10}{'RX Δ':>12}{'rb/s':>10}{'RX B':>12}{'TX pkts':>10}{'t/s':>10}{'TX Δ':>12}{'tb/s':>10}{'TX B':>12}"
    print(header)
    print('-' * 120)
    for r in rows:
        iface = r[0]
        rxp, rps, rxb_human, rbps, rxb = r[1], r[2], r[3], r[4], r[5]
        txp, tps, txb_human, tbps, txb = r[6], r[7], r[8], r[9], r[10]
        print(f"{iface:<20}{rxp:>10}{rps:>10}{rxb_human:>12}{rbps:>10}{rxb:>12}{txp:>10}{tps:>10}{txb_human:>12}{tbps:>10}{txb:>12}")
    print('=' * 120)


def main():
    parser = argparse.ArgumentParser(description='Monitor UE tx packets/bytes per val interface')
    parser.add_argument('-i', '--interval', type=float, default=1.0, help='poll interval seconds')
    parser.add_argument('-n', '--count', type=int, default=0, help='number of samples to show (0 = infinite)')
    parser.add_argument('--interfaces', nargs='*', help='interfaces to monitor (default: auto-detect val*)')
    args = parser.parse_args()

    if args.interfaces:
        ifaces = args.interfaces
    else:
        ifaces = detect_val_interfaces()

    if not ifaces:
        print('No val interfaces found. Exit.')
        sys.exit(1)

    # Filter valid existing interfaces
    ifaces = [i for i in ifaces if os.path.exists(f'/sys/class/net/{i}')]
    if not ifaces:
        print('No valid interfaces found after filtering. Exit.')
        sys.exit(1)

    print(f'Monitoring {len(ifaces)} interface(s): {", ".join(ifaces)}')
    print('Press Ctrl-C to stop')

    prev = {}
    for iface in ifaces:
        rxp = read_stat(iface, 'rx_packets') or 0
        rxb = read_stat(iface, 'rx_bytes') or 0
        txp = read_stat(iface, 'tx_packets') or 0
        txb = read_stat(iface, 'tx_bytes') or 0
        prev[iface] = (rxp, rxb, txp, txb)

    sample = 0
    try:
        while True:
            time.sleep(args.interval)
            sample += 1
            rows = []
            timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
            for iface in ifaces:
                # read rx and tx
                rxp = read_stat(iface, 'rx_packets')
                rxb = read_stat(iface, 'rx_bytes')
                txp = read_stat(iface, 'tx_packets')
                txb = read_stat(iface, 'tx_bytes')
                if None in (rxp, rxb, txp, txb):
                    rows.append((iface, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A'))
                    continue
                rprev_p, rprev_b, tprev_p, tprev_b = prev.get(iface, (rxp, rxb, txp, txb))
                drp = rxp - rprev_p
                drb = rxb - rprev_b
                dtp = txp - tprev_p
                dtb = txb - tprev_b
                rps = format_rate(drp, args.interval)
                rbps = format_rate(drb, args.interval)
                tps = format_rate(dtp, args.interval)
                tbps = format_rate(dtb, args.interval)
                rows.append((iface, rxp, rps, human_bytes(drb), rbps, human_bytes(rxb), txp, tps, human_bytes(dtb), tbps, human_bytes(txb)))
                prev[iface] = (rxp, rxb, txp, txb)

            print_table(rows, timestamp, sample)

            if args.count and sample >= args.count:
                break

    except KeyboardInterrupt:
        print('\nStopped by user')


if __name__ == '__main__':
    main()
