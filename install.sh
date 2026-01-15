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
  echo "安装依赖: curl socat..."
  if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update && sudo apt-get install -y curl socat ufw
  elif [ -x "$(command -v yum)" ]; then
    sudo yum install -y curl socat firewalld
  else
    echo "❌ 错误：不支持的系统！请手动安装 curl 和 socat 后重试。"
    exit 1
  fi
fi

# 执行安装命令
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
$USERNAME
$PASSWORD
$PORT
EOF

# 配置面板监听所有网卡 (0.0.0.0)
CONFIG_FILE="/etc/x-ui/config.yaml"
if [ -f "$CONFIG_FILE" ]; then
  echo "配置面板监听地址为 0.0.0.0..."
  sed -i 's/^address: .*/address: 0.0.0.0/' "$CONFIG_FILE"
  x-ui restart
fi

# 启用 BBR
echo "启用 BBR TCP 加速..."
cat >/etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system

# 防火墙开放端口
echo "开放防火墙端口 $PORT..."
if command -v ufw &> /dev/null; then
  ufw allow $PORT/tcp
  ufw reload
elif command -v firewall-cmd &> /dev/null; then
  firewall-cmd --permanent --add-port=$PORT/tcp
  firewall-cmd --reload
fi

# 输出访问信息
IP=$(curl -4s icanhazip.com)
echo -e "\n\033[32m✅ 安装完成！\033[0m"
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "BBR TCP 加速已启用"
echo "面板已绑定 0.0.0.0，防火墙端口已开放"
echo "脚本作者：宇亮 @tanyuliang895@gmail.com"
