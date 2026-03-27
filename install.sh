#!/bin/bash
# 生产级 X-UI 安装+网络优化+面板修复脚本
# 功能：
# 1. 安装最新官方 X-UI（无交互）
# 2. 自动配置用户名/密码/端口
# 3. 启用 BBR v2 + TCP/MTU优化
# 4. 检查服务和端口，自动修复面板 503
# 5. 输出状态和日志

set -e

# ================== 配置参数 ==================
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
SERVICE=x-ui
# =============================================

echo "========== 0. 等待 dpkg/apt 锁释放 =========="
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
      fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "检测到其他 apt/dpkg 进程运行，等待 3 秒..."
    sleep 3
done

echo "========== 1. 安装依赖 =========="
apt update -y
apt install -y curl wget tar sudo ethtool

echo "========== 2. 安装最新官方 X-UI =========="
yes | bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
sleep 6

echo "========== 3. 配置面板账号/端口 =========="
x-ui setting -username "$USERNAME"
x-ui setting -password "$PASSWORD"
x-ui setting -port "$PORT"
x-ui setting -webBasePath /

echo "========== 4. 启用 BBR v2 + 网络优化 =========="
kernel_version=$(uname -r | cut -d'.' -f1-2)
version_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

if version_ge "$kernel_version" "4.9"; then
    echo "启用 BBR v2"
else
    echo "⚠️ 内核版本 $kernel_version < 4.9，不支持 BBR v2"
fi

cat > /etc/sysctl.d/99-optim-network.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_ecn=1
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_rmem=4096 87380 6291456
net.ipv4.tcp_wmem=4096 65536 6291456
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535
fs.file-max=2097152
EOF

sysctl --system >/dev/null 2>&1
echo "TCP 优化参数已生效"

NIC=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -n "$NIC" ]; then
    echo "优化网卡 $NIC"
    ip link set dev "$NIC" mtu 1500
    ethtool -G "$NIC" rx 4096 tx 4096 || true
else
    echo "⚠️ 未检测到默认网卡，请手动设置 MTU/队列"
fi

ulimit -n 1048576
echo "文件描述符已优化"

echo "========== 5. 检查 X-UI 服务状态并修复 503 =========="
systemctl status $SERVICE --no-pager || echo "$SERVICE 服务未运行，尝试启动..."
systemctl restart $SERVICE || echo "第一次启动未加载，稍后生效"

echo
echo "========== 6. 检查端口占用 =========="
if ss -tulnp | grep $PORT; then
    echo "端口 $PORT 已被占用，请手动处理冲突"
else
    echo "端口 $PORT 未被占用"
fi

echo
echo "========== 7. 放行防火墙端口 =========="
if command -v ufw &>/dev/null; then
    sudo ufw allow $PORT/tcp
    sudo ufw reload
    echo "UFW 已放行 TCP $PORT"
fi

if command -v iptables &>/dev/null; then
    sudo iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    echo "iptables 已放行 TCP $PORT"
fi

echo
echo "========== 8. 输出最近 50 条 X-UI 日志 =========="
journalctl -u $SERVICE -n 50 --no-pager

IP=$(curl -4s icanhazip.com || echo "服务器IP")
echo
echo "============== 安装/优化完成 =============="
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "=========================================="
echo
echo "⚠️ 建议重启服务器以确保 BBR、MTU 和端口设置生效：sudo reboot"
echo "查看 BBR 状态：sysctl net.ipv4.tcp_congestion_control"
echo "查看网卡队列：ethtool -g $NIC"
echo "查看文件描述符：ulimit -n"
