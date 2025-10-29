#!/bin/bash
#!/bin/bash
# 在 enp0s8 上從 192.168.56.150 開始遞增添加 IP，或刪除該範圍內的 IP
set -euo pipefail

IF="eth1"
NET_PREFIX="192.168.121"
START_OCTET=50
LAST_OCTET=163
MAX_COUNT=$((LAST_OCTET - START_OCTET + 1))

usage() {
  cat <<EOF
Usage:
  $0 -n NUM       # add NUM IPs starting at ${NET_PREFIX}.${START_OCTET}
  $0 delete       # remove configured IPs ${NET_PREFIX}.${START_OCTET}-${LAST_OCTET} from $IF
EOF
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "請以 root 或 sudo 執行此腳本"
  exit 1
fi

if [ $# -eq 0 ]; then
  usage
fi

if [ "$1" = "delete" ]; then
  for ((oct=START_OCTET; oct<=LAST_OCTET; oct++)); do
    ip_addr="${NET_PREFIX}.${oct}/24"
    if ip addr show dev "$IF" | grep -qw "${NET_PREFIX}.${oct}"; then
      if ip addr del "$ip_addr" dev "$IF" 2>/dev/null; then
        echo "Deleted $ip_addr from $IF"
      else
        echo "Failed to delete $ip_addr (may be in use)"
      fi
    fi
  done
  exit 0
fi

# 解析 -n
N=""
while getopts ":n:" opt; do
  case "$opt" in
    n) N="$OPTARG" ;;
    *) usage ;;
  esac
done

if [ -z "${N}" ]; then
  usage
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "-n 必須為正整數"
  exit 1
fi

if [ "$N" -lt 1 ] || [ "$N" -gt "$MAX_COUNT" ]; then
  echo "-n 必須介於 1 到 $MAX_COUNT 之間"
  exit 1
fi

for ((i=0; i<N; i++)); do
  octet=$((START_OCTET + i))
  ip_addr="${NET_PREFIX}.${octet}/24"
  if ip addr show dev "$IF" | grep -qw "${NET_PREFIX}.${octet}"; then
    echo "Skip existing ${NET_PREFIX}.${octet}"
  else
    if ip addr add "$ip_addr" dev "$IF" 2>/dev/null; then
      echo "Added $ip_addr to $IF"
    else
      echo "Failed to add $ip_addr"
    fi
  fi
done
 