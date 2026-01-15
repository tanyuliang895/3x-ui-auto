#!/bin/bash
# 3X-UI 一键安装脚本（用户名: liang, 密码: liang, 端口: 2024） + BBR加速 + 随机面板路径
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/你的仓库/main/install.sh)

set -e

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "错误：请使用 root 用户运行此脚本！"
   exit 1
fi

# 配置参数
USERNAME="liang"
PASSWORD="liang"
PORT="2024"
BASEPATH=$(tr -dc a-z0-9 </dev/urandom | head -c 8)  # 随机8位面板路径，如 /a1b2c3d4

echo "开始安装 3X-UI（用户名: $USERNAME，端口: $PORT，面板路径: /$BASEPATH） + BBR加速"

# 1. 启用 BBR 加速
echo "正在启用 BBR 加速..."
cat > /etc/sysctl.d/bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1
modprobe tcp_bbr || true
echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf || true
echo "BBR 已启用（重启后完全生效）。当前状态："
sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr && echo "bbr" || echo "未生效（可能需重启）"

# 2. 安装必要依赖
echo "安装依赖（curl、wget、tar、openssl、socat）..."
if command -v apt-get >/dev/null 2>&1; then
    apt update -y && apt install -y curl wget tar openssl socat
elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    if command -v yum >/dev/null 2>&1; then PM=yum; else PM=dnf; fi
    $PM install -y curl wget tar openssl socat
else
    echo "错误：不支持的系统包管理器！"
    exit 1
fi

# 3. 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)  XUI_ARCH="amd64" ;;
    aarch64) XUI_ARCH="arm64" ;;
    *)       echo "错误：不支持的架构 $ARCH" ; exit 1 ;;
esac

# 4. 获取最新版本并下载
echo "获取最新版本..."
LATEST_VERSION=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
if [[ -z "$LATEST_VERSION" ]]; then
    echo "错误：获取版本失败，请检查网络！"
    exit 1
fi
echo "最新版本：v$LATEST_VERSION"

DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/v${LATEST_VERSION}/x-ui-linux-${XUI_ARCH}.tar.gz"
wget -O x-ui.tar.gz "$DOWNLOAD_URL"
tar xzf x-ui.tar.gz
rm -f x-ui.tar.gz
mv x-ui /usr/local/
chmod +x /usr/local/x-ui/x-ui
chmod +x /usr/local/x-ui/bin/xray-linux-*

# 5. 创建 systemd 服务
cat > /etc/systemd/system/x-ui.service << 'EOF'
[Unit]
Description=3X-UI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable x-ui --now
sleep 10  # 等待面板初始化

# 6. 设置面板参数
/usr/local/x-ui/x-ui setting -username "$USERNAME"
/usr/local/x-ui/x-ui setting -password "$PASSWORD"
/usr/local/x-ui/x-ui setting -port "$PORT"
/usr/local/x-ui/x-ui setting -webBasePath "/$BASEPATH"
/usr/local/x-ui/x-ui restart

# 7. 获取公网 IP 并输出信息
IP=$(curl -4s ifconfig.me || curl -4s icanhazip.com || echo "未知")
echo -e "\n\033[32m安装完成！\033[0m"
echo "访问地址: http://$IP:$PORT/$BASEPATH/"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "面板路径: /$BASEPATH (已随机生成，提高安全性)"
echo "注意："
echo "   - 当前为 HTTP 访问，如需 HTTPS 请手动配置证书后启用。"
echo "   - BBR 已启用，建议重启服务器后 lsmod | grep bbr 检查。"
echo "   - 如需卸载：x-ui uninstall"
