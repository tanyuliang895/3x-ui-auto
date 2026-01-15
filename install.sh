#!/bin/bash
# 3X-UI 完全自动化安装脚本（端口:2026, 用户名:liang, 密码:liang, BBR, 防火墙, 开机自启）

set -e

USERNAME="liang"
PASSWORD="liang"
PORT="2026"

echo "======================================="
echo "  正在安装 3X-UI"
echo "  用户名: $USERNAME"
echo "  端口:   $PORT"
echo "======================================="

# 必须 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户运行"
  exit 1
fi

# 安装依赖 curl
if ! command -v curl >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
  else
    echo "请手动安装 curl"
    exit 1
  fi
fi

# 安装 3X-UI（自动选择不自定义端口）
echo "安装面板（跳过端口自定义交互）"
yes n | bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

# 配置端口和账号
echo "配置面板账号和端口"
x-ui setting <<EOF
$PORT
$USERNAME
$PASSWORD
EOF

x-ui restart

# 放行防火墙端口（适配 ufw / firewalld / iptables）
if command -v ufw >/dev/null 2>&1; then
  ufw allow $PORT/tcp
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=$PORT/tcp
  firewall-cmd --reload
else
  iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
fi

# 开启 BBR
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
fi

# 开机自启 3X-UI
systemctl enable x-ui

# 输出访问信息
IP=$(curl -4s icanhazip.com || echo "服务器IP")
echo "======================================="
echo "✅ 安装完成"
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "======================================="
