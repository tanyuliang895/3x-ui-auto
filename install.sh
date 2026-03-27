#!/bin/bash
# X-UI + 一键网络优化生产级安装脚本
# 功能：
# 1. 自动等待 dpkg/apt 锁
# 2. 安装最新 X-UI 官方版本
# 3. 配置用户名/密码/端口
# 4. 启用 BBR v2 + fq + TCP/队列/MTU优化
# 用法：
# sudo bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/x-ui-auto/main/install.sh)

set -e

# ================== 配置参数 ==================
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
# =============================================

# ---------- 0. 等待 dpkg/apt 锁 ----------
echo "========== 0. 等待 dpkg/apt 锁释放 =========="
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
      fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "检测到其他 apt/dpkg 进程运行，等待 3 秒..."
    sleep 3
done

# ---------- 1. 安装依赖 ----------
echo "========== 1. 安装依赖 =========="
apt update -y
apt install -y curl wget tar sudo ethtool

# ---------- 2. 安装 X-UI ----------
echo "========== 2. 安装最新官方 X-UI =========="
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
echo "等待面板初始化..."
sleep 6

# ---------- 3. 配置面板账号/端口 ----------
echo "========== 3. 配置面板账号/端口 =========="
x-ui setting -username "$USERNAME"
x-ui setting -password "$PASSWORD"
x-ui setting -port "$PORT"
x-ui setting -webBasePath /

# ---------- 4. 启用 BBR v2 + 网络优化 ----------
echo "========== 4. 启用 BBR v2 + TCP/MTU优化 =========="
kernel_version=$(uname -r | cut -d'.' -f1-2)
version_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

if version_ge "$kernel_version" "4.9"; then
    echo "启用 BBR v2"
else
    echo "⚠️ 内核版本 $kernel_version < 4.9，不支持 BBR v2"
fi

# TCP 优化
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

# 网卡优化
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

# ---------- 5. 重启 X-UI 服务 ----------
echo "========== 5. 重启 X-UI 服务 =========="
systemctl restart x-ui || echo "x-ui 服务第一次安装未加载，稍后生效"

# ---------- 6. 完成提示 ----------
IP=$(curl -4s icanhazip.com || echo "服务器IP")
echo
echo "============== 安装完成 =============="
echo "访问地址: http://$IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "======================================"
echo
echo "⚠️ 建议重启服务器以确保 BBR 和 MTU 设置生效：sudo reboot"
echo "查看 BBR 状态：sysctl net.ipv4.tcp_congestion_control"
echo "查看网卡队列：ethtool -g $NIC"
echo "查看文件描述符：ulimit -n"
