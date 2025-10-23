#!/bin/bash
set -e

NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"

cleanup() {
  echo "🧹 停止シグナル受信、VPNとNASをクリーンアップ中..."
  mount --make-rprivate "${NAS_MOUNT_PATH}" 2>/dev/null || true
  fuser -km "${NAS_MOUNT_PATH}" >/dev/null 2>&1 || true
  umount -l -f "${NAS_MOUNT_PATH}" >/dev/null 2>&1 || true
  pkill -9 xl2tpd pppd || true
  ipsec stop >/dev/null 2>&1 || true
  echo "✅ クリーンに停止しました。"
  exit 0
}
trap cleanup SIGTERM SIGINT

echo "📡 VPN接続を開始..."
/scripts/vpn_connect.sh > /tmp/vpn_connect.log 2>&1 &
VPN_PID=$!

echo "🔍 vpn_connect.sh PID: ${VPN_PID}"

( tail -Fn0 /tmp/vpn_connect.log | while read -r line; do
    echo "$line"
    if echo "$line" | grep -q "✅ VPN接続成功"; then
      echo "🚦 VPN完全確立を検出、NASマウントに進みます..."
      /scripts/mount_smb.sh &
    fi
  done
) &

# VPNプロセスを待機して、切断されたら終了
wait ${VPN_PID}
cleanup
