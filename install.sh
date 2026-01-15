#!/bin/bash
# 3x-ui 生产级一键安装脚本（无 expect）
# 固定 Release 版本 + 参数化 + 域名 HTTPS + certbot 自动续期
# Author: tanyuliang895

set -e

### ========= 默认参数 =========
PORT="${PORT:-2026}"
USER="${USER:-liang}"
PASS="${PASS:-liang}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
VERSION="${VERSION:-v2.7.8}"

INSTALL_DIR="/usr/local/x-ui"
BIN="$INSTALL_DIR/x-ui"

echo "=== 3x-ui 安装参数 ==="
echo "端口: $PORT"
echo "用户: $USER"
echo "域名: ${DOMAIN:-未设置(IP HTTPS)}"
echo "版本: $VERSION"
echo

### ========= 基础依赖 =========
apt update -y
apt install -y curl unzip socat cron ufw

### ========= BBR =========
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p
fi

### ========= 防火墙 =========
ufw allow 80 || true
ufw allow "$PORT" || true
ufw reload || true

### ========= 下载固定 Release =========
echo "下载 3x-ui $VERSION"
mkdir -p "$INSTALL_DIR"
curl -L \
"https://github.com/MHSanaei/3x-ui/releases/download/$VERSION/x-ui-linux-amd64.tar.gz" \
-o /tmp/x-ui.tar.gz

tar -xzf /tmp/x-ui.tar.gz -C "$INSTALL_DIR"
chmod +x "$BIN"

### ========= systemd =========
cat >/etc/systemd/system/x-ui.service <<EOF
[Unit]
Description=3x-ui Panel
After=network.target

[Service]
ExecStart=$BIN
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable x-ui

### ========= 基础配置 =========
$BIN setting -username "$USER" -password "$PASS"
$BIN setting -port "$PORT"

### ========= HTTPS =========
if [[ -n "$DOMAIN" && -n "$EMAIL" ]]; then
  echo "配置域名 HTTPS: $DOMAIN"
  apt install -y certbot

  systemctl stop x-ui || true
  certbot certonly --standalone \
    -d "$DOMAIN" \
    --agree-tos \
    -m "$EMAIL" \
    --non-interactive

  $BIN cert \
    --domain "$DOMAIN" \
    --key "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
    --cert "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

  systemctl start x-ui

  echo "配置 certbot 自动续期"
  cat >/etc/cron.d/certbot-renew <<EOF
0 3 * * * root certbot renew --quiet --post-hook "systemctl restart x-ui"
EOF
else
  echo "未设置域名，使用 IP HTTPS（短期证书）"
fi

systemctl restart x-ui

### ========= 完成 =========
echo
echo "=== 安装完成 ==="
echo "面板地址: https://${DOMAIN:-你的IP}:$PORT"
echo "用户名: $USER"
echo "密码: $PASS"
echo "版本: $VERSION"
echo "BBR: $(sysctl -n net.ipv4.tcp_congestion_control)"
