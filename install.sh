#!/bin/bash
# X-UI 一键安装脚本（不升级系统）
# 自动启用 BBR 加速
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/x-ui-auto/main/install.sh)

# ================== 配置参数 ==================
USERNAME="liang"   # 用户名
PASSWORD="liang"   # 密码
PORT="2026"        # 端口
# ==============================================

set -e

echo "正在安装 X-UI（用户名: $USERNAME，端口: $PORT）"

# ================== 依赖检查 ==================
if ! command -v curl &>/dev/null; then
  echo "安装依赖: curl"
  if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl
  elif command -v yum &>/dev/null; then
    yum install -y curl
  else
    echo "错误：不支持的系统，请手动安装 curl"
    exit 1
  fi
fi

# ================== 安装 X-UI ==================
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

echo "等待面板初始化..."
sleep 6

# ================== 配置面板账号/端口 ==================
x-ui setting -username "$USERNAME"
x-ui setting -password "$PASSWORD"
x-ui setting -port "$PORT"
x-ui setting -webBasePath /

# ================== BBR 加速 ==================
enable_bbr() {
  echo "开始启用 BBR 加速..."

  kernel_version=$(uname -r | cut -d'.' -f1-2)

  version_ge() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
  }

  if ! version_ge "$kernel_version" "4.9"; then
    echo "当前内核版本 $kernel_version，不支持 BBR（需 ≥ 4.9）"
    return
  fi

  grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || \
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf

  grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || \
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

  sysctl -p >/dev/null 2>&1

  cc=$(sysctl -n net.ipv4.tcp_congestion_control)
  qdisc=$(sysctl -n net.core.default_qdisc)

  if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
    echo "BBR 加速已成功启用"
  else
    echo "BBR 启用失败（可能被 VPS 限制）"
  fi
}

enable_bbr

# ================== 安装完成提示 ==================
IP=$(curl -4s icanhazip.com || echo "服务器IP")
echo
echo "================ 安装完成 ================"
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "=========================================="
