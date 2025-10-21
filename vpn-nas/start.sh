#!/bin/bash
set -e

STOP_FLAG="/tmp/vpn_stop_flag"
[ -f "${STOP_FLAG}" ] && rm -f "${STOP_FLAG}"

cleanup() {
  echo "🧹 停止シグナル受信、VPNとNASをクリーンアップ中..."
  touch "${STOP_FLAG}"
  pkill -9 xl2tpd || true
  pkill -9 pppd || true
  ipsec stop >/dev/null 2>&1 || true
  umount -f "${NAS_MOUNT_PATH}" >/dev/null 2>&1 || true
  echo "✅ クリーンに停止しました。"
  exit 0
}
trap cleanup SIGTERM SIGINT

echo "📡 VPN接続を開始..."
/scripts/vpn_connect.sh | while read -r line; do
  echo "$line"
  if echo "$line" | grep -q "✅ VPN接続成功"; then
    echo "🚦 VPN完全確立を検出、NASマウントに進みます..."
    echo "🗂 NASマウントを開始..."
    /scripts/mount_smb.sh &
  fi
  if echo "$line" | grep -q "✅ VPN接続完了"; then
    echo "🏁 VPN接続処理の終了を検出、監視を停止。"
    break
  fi
done

wait
