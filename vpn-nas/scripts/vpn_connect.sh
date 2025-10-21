#!/bin/bash
set -e

VPN_RETRY_INTERVAL="${VPN_RETRY_INTERVAL:-30}"
STOP_FLAG="/tmp/vpn_stop_flag"

generate_configs() {
  echo "⚙️ 設定ファイル生成中..."
  mkdir -p /etc/ipsec.d /var/run/xl2tpd

  cat >/etc/ipsec.conf <<-EOF
config setup
  charondebug="ike 1, knl 1, cfg 1"
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
}

connect_vpn() {
  echo "🚀 IPsec起動..."
  ipsec restart >/dev/null 2>&1 || true
  sleep 5
  if ! ipsec up vpn 2>&1 | grep -E "connection 'vpn'|failed|no response"; then
    echo "❌ IPsec接続失敗。${VPN_RETRY_INTERVAL}秒後に再試行します。"
    return 1
  fi

  echo "🚀 L2TPトンネル開始..."
  pkill -9 xl2tpd || true
  pkill -9 pppd || true
  xl2tpd -c /etc/xl2tpd/xl2tpd.conf &
  sleep 5
  echo "c vpn" > /var/run/xl2tpd/l2tp-control
  sleep 10

  if ip addr show ppp0 >/dev/null 2>&1; then
    echo "✅ VPN接続成功"
    ip addr show ppp0 | grep "inet " || true
    VPN_NET=$(ip -o -4 addr show ppp0 | awk '{print $4}' | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".0/24"}')
    echo "🛠 VPNネットワークルート追加: ${VPN_NET}"
    ip route add "${VPN_NET}" dev ppp0 2>/dev/null || true
    return 0
  else
    echo "❌ VPNインターフェース(ppp0)が見つかりません。"
    return 1
  fi
}

# メイン
generate_configs

until connect_vpn; do
  [ -f "${STOP_FLAG}" ] && exit 0
  sleep "${VPN_RETRY_INTERVAL}"
done

echo "✅ VPN接続完了"
touch "${STOP_FLAG}"

tail -f /dev/null
