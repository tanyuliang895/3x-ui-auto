#!/bin/bash
# 3X-UI 一键安装脚本（用户名: liang, 密码: liang, 端口: 2026）
# 脚本作者：宇亮 @tanyuliang895@gmail.com
# 用法：bash <(curl -Ls <你的脚本地址>)

# 配置参数（根据你的需求硬编码）
USERNAME="liang"   # 用户名
PASSWORD="liang"   # 密码
PORT="2026"        # 面板端口

# 自动安装逻辑
set -e  # 任何错误立即终止
echo "🔧 正在安装 3X-UI (用户名: $USERNAME, 端口: $PORT)..."

# 依赖检查（自动安装 curl 和 socat）
if ! command -v curl &> /dev/null; then
  echo "安装依赖: curl..."
  if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update && sudo apt-get install -y curl socat
  elif [ -x "$(command -v yum)" ]; then
    sudo yum install -y curl socat
  else
    echo "❌ 错误：不支持的系统！请手动安装 curl 和 socat 后重试。"
    exit 1
  fi
fi

# 下载 3x-ui 安装脚本
echo "下载 3X-UI 官方安装脚本..."
curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" -o /tmp/3xui_install.sh
chmod +x /tmp/3xui_install.sh

# 执行安装脚本并自动填写信息
echo "执行 3X-UI 安装脚本..."
bash /tmp/3xui_install.sh <<EOF
y
$USERNAME
$PASSWORD
$PORT
EOF

# 启用 BBR TCP 加速
echo "启用 BBR TCP 加速..."
cat >/etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system

echo "BBR 状态检查:"
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr || true

# 输出访问信息
IP=$(curl -4s icanhazip.com)
echo -e "\n\033[32m✅ 安装完成！\033[0m"
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "BBR TCP 加速已启用"
