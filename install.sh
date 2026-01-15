#!/bin/bash
# 3X-UI 零交互安装 + 设置端口 2026 + 用户名 liang + BBR

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

# 安装 curl
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

# ===== 安装 3X-UI（跳过端口自定义交互） =====
echo "安装面板（选择不自定义端口）"
yes n | bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

# ===== 修改端口和账号 =====
echo "配置面板账号和端口"
x-ui setting <<EOF
$PORT
$USERNAME
$PASSWORD
EOF

x-ui restart

# ===== 开启 BBR =====
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
fi

# 输出信息
IP=$(curl -4s icanhazip.com || echo "服务器IP")
echo "======================================="
echo "✅ 安装完成"
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "======================================="
