#!/bin/bash
set -e

# ==============================
#  L2TP/IPsec VPN + NAS 自動接続
# ==============================

VPN_RETRY_INTERVAL="${VPN_RETRY_INTERVAL:-30}"
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas}"
STOP_FLAG="/tmp/vpn_stop_flag"

# --- 停止シグナルの捕捉（docker stop対応） ---
# shellcheck disable=SC2329
cleanup() {
  echo "🧹 停止シグナル受信: VPN終了処理中..."
  touch "${STOP_FLAG}"
  pkill -9 xl2tpd || true
  pkill -9 pppd || true
  ipsec stop >/dev/null 2>&1 || true
  umount -f "${NAS_MOUNT_PATH}" >/dev/null 2>&1 || true
  echo "✅ クリーンに停止完了。"
  exit 0
}
trap cleanup SIGTERM SIGINT

echo "🔍 Starting L2TP/IPsec client..."
mkdir -p /etc/ipsec.d /var/run/xl2tpd "${NAS_MOUNT_PATH}"

# --- 設定生成 ---
cat >/etc/ipsec.conf <<-EOF
config setup
  charondebug="ike 1, knl 1, cfg 0"
conn vpn
  keyexchange=ikev1
  authby=psk
  type=transport
  ike=aes128-sha1-modp1024!
  esp=aes128-sha1!
  keyingtries=%forever
  ikelifetime=8h
  keylife=1h
  left=%defaultroute
  leftprotoport=17/1701
  right=${VPN_HOST}
  rightprotoport=17/1701
  rightid=%any
  leftid=%any
  auto=add
EOF

cat >/etc/ipsec.secrets <<-EOF
%any ${VPN_HOST} : PSK "${VPN_PSK}"
EOF

cat >/etc/xl2tpd/xl2tpd.conf <<-EOF
[global]
port = 1701
[lac vpn]
lns = ${VPN_HOST}
ppp debug = no
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
require chap = yes
refuse pap = yes
autodial = yes
EOF

cat >/etc/ppp/options.l2tpd.client <<-EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-mschap-v2
noccp
noauth
mtu 1280
mru 1280
defaultroute
usepeerdns
lock
noipdefault
persist
holdoff 10
name ${VPN_USER}
password ${VPN_PASS}
EOF

echo "🚀 IPsec起動..."
ipsec restart
sleep 5
ipsec up vpn || { echo "❌ IPsec接続失敗"; exit 1; }

echo "🚀 L2TPトンネル開始..."
pkill -9 xl2tpd || true
pkill -9 pppd || true
xl2tpd -c /etc/xl2tpd/xl2tpd.conf &
sleep 5
echo "c vpn" > /var/run/xl2tpd/l2tp-control
sleep 10

echo "📡 Network interfaces:"
ip addr show | grep -E "ppp|inet " || true

# --- VPNネットワーク追加 ---
if ip addr show ppp0 >/dev/null 2>&1; then
  VPN_IP=$(ip -o -4 addr show ppp0 | awk '{print $4}' | cut -d/ -f1)
  if [ -n "$VPN_IP" ]; then
    echo "🛠 VPNルート追加: ${VPN_IP}/32"
    ip route add "${VPN_IP}/32" dev ppp0 || true
  else
    echo "⚠️ VPN IPが取得できませんでした。"
  fi
else
  echo "❌ ppp0が見つかりません。再試行..."
  sleep "${VPN_RETRY_INTERVAL}"
  bash /start.sh
fi

# --- NASマウント ---
echo "🔄 NASマウント試行中..."
mount -t cifs "//${NAS_HOST}/${NAS_SHARE}" "${NAS_MOUNT_PATH}" \
  -o "username=${NAS_USER},password=${NAS_PASS},vers=${NAS_VERS},iocharset=utf8,nounix,noserverino" \
  && echo "✅ NASマウント成功: ${NAS_MOUNT_PATH}" \
  || echo "⚠️ NASマウント失敗"

# --- 自動監視ループ ---
echo "🔁 自動監視ループ開始（${VPN_RETRY_INTERVAL}s間隔）..."
while [ ! -f "${STOP_FLAG}" ]; do
  sleep "${VPN_RETRY_INTERVAL}"

  # VPN監視
  if ! ip addr show ppp0 >/dev/null 2>&1; then
    echo "⚠️ VPN切断を検出。再接続を試行..."
    pkill -9 xl2tpd || true
    pkill -9 pppd || true
    ipsec stop >/dev/null 2>&1 || true
    sleep 3
    bash /start.sh
  fi

  # NAS監視
  if ! mount | grep -q "${NAS_MOUNT_PATH}"; then
    echo "⚠️ NASがマウントされていません。再マウント中..."
    mount -t cifs "//${NAS_HOST}/${NAS_SHARE}" "${NAS_MOUNT_PATH}" \
      -o "username=${NAS_USER},password=${NAS_PASS},vers=${NAS_VERS},iocharset=utf8,nounix,noserverino" \
      && echo "✅ NAS再マウント成功" \
      || echo "❌ NAS再マウント失敗"
  fi
done

echo "🛑 STOPフラグ検出、終了します。"
exit 0
