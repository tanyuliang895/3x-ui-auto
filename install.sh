#!/bin/bash
# 3X-UI 一键安装脚本（用户名: liang, 密码: liang, 端口: 2026）
# 用法：
# bash <(curl -Ls https://raw.githubusercontent.com/你的仓库/3x-ui-auto/main/install.sh)

set -e

# ====== 固定参数 ======
USERNAME="liang"
PASSWORD="liang"
PORT="2026"

echo "======================================="
echo "  正在安装 3X-UI"
echo "  用户名: $USERNAME"
echo "  端口:   $PORT"
echo "======================================="

# ====== 必须是 root ======
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行该脚本"
  exit 1
fi

# ====== 安装 curl ======
if ! command -v curl >/dev/null 2>&1; then
  echo "安装 curl..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
  else
    echo "❌ 不支持的系统，请手动安装 curl"
    exit 1
  fi
fi

# ====== 安装 3X-UI ======
echo "开始安装 3X-UI..."
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

# ====== 等待服务生成 ======
sleep 2

# ====== 配置 3X-UI 面板 ======
echo "配置面板账号与端口..."

x-ui setting <<EOF
$PORT
$USERNAME
$PASSWORD
EOF

x-ui restart

# ====== 开启 BBR 加速 ======
echo "检测并开启 BBR..."

enable_bbr() {
  if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo "BBR 已开启，跳过"
    return
  fi

  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

  sysctl -p >/dev/null 2>&1

  if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo "✅ BBR 启用成功"
  else
    echo "⚠️ BBR 启用失败（可能是内核不支持）"
  fi
}

enable_bbr

# ====== 输出访问信息 ======
IP=$(curl -4s icanhazip.com || echo "你的服务器IP")

echo "======================================="
echo "✅ 安装完成"
echo "访问地址: http://$IP:$PORT"
echo "用户名:   $USERNAME"
echo "密码:     $PASSWORD"
echo "======================================="
