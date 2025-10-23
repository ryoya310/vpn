#!/bin/bash
set -e

mount_nas() {
  if mount | grep -q "//${NAS_HOST}/${NAS_SHARE}"; then
    echo "✅ NAS (${NAS_HOST}/${NAS_SHARE}) は既にマウント済み"
  else
    echo "🔄 NASマウント試行中..."
    mkdir -p "${NAS_MOUNT_PATH}"
    mount -t cifs "//${NAS_HOST}/${NAS_SHARE}" "${NAS_MOUNT_PATH}" \
      -o "username=${NAS_USER},password=${NAS_PASS},vers=${NAS_VERS:-2.1},iocharset=utf8,nounix,noserverino" \
      && echo "✅ NASマウント成功: ${NAS_MOUNT_PATH}" \
      || echo "⚠️ NASマウント失敗"
  fi
}

monitor_nas() {
  echo "🔁 NAS監視ループ開始..."
  while true; do
    sleep "${VPN_RETRY_INTERVAL}"

    # 1️⃣ まずマウント状態確認
    if ! mount | grep -q "${NAS_MOUNT_PATH}"; then
      echo "⚠️ NAS切断検出（アンマウント状態）、再マウント中..."
      mount_nas
      continue
    fi

    # 2️⃣ 次に実際の疎通確認（中身が見えるか？）
    if ! ls "${NAS_MOUNT_PATH}" >/dev/null 2>&1; then
      echo "⚠️ NAS応答なし、再マウント試行中..."
      umount -f "${NAS_MOUNT_PATH}" >/dev/null 2>&1 || true
      mount_nas
      continue
    fi

    # 3️⃣ オプションでNASホスト自体にping確認
    if ! ping -c 1 -W 1 "${NAS_HOST}" >/dev/null 2>&1; then
      echo "⚠️ NASホストに到達できません。VPN不安定の可能性。"
    fi
  done
}

mount_nas
monitor_nas
