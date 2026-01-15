#!/bin/bash
# 3X-UI 一键全自动安装脚本（2026最新兼容版）
# 默认端口: 2026    用户名: liang    密码: liang
# 自动启用 BBR 加速 + 获取最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置参数（可自行修改）
DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口默认: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：请使用 root 权限运行此脚本！\033[0m"
    exit 1
fi

# 安装必要依赖
if ! command -v curl &> /dev/null || ! command -v socat &> /dev/null || ! command -v wget &> /dev/null; then
    echo "安装必要依赖 (curl wget socat ca-certificates)..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y curl wget socat ca-certificates
    elif command -v yum &> /dev/null; then
        yum install -y curl wget socat ca-certificates
    elif command -v dnf &> /dev/null; then
        dnf install -y curl wget socat ca-certificates
    else
        echo -e "\033[31m不支持的系统，请手动安装 curl wget socat 后重试。\033[0m"
        exit 1
    fi
fi

# 启用 BBR
echo -e "\n\033[33m正在启用 BBR 加速...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 获取最新版本号（使用 GitHub API，避免缓存问题）
LATEST_VERSION=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "\033[31m[✗] 无法获取最新版本，请检查网络或 GitHub API 限制\033[0m"
    exit 1
fi

echo -e "\033[32m[✓] 检测到最新版本: $LATEST_VERSION\033[0m"

# 架构检测
ARCH=$(uname -m)
case $ARCH in
    x86_64|x64|amd64) DOWNLOAD_ARCH="amd64" ;;
    armv8|arm64|aarch64) DOWNLOAD_ARCH="arm64" ;;
    s390x) DOWNLOAD_ARCH="s390x" ;;
    *) echo -e "\033[31m[✗] 不支持的架构: $ARCH，使用 amd64 作为默认\033[0m" && DOWNLOAD_ARCH="amd64" ;;
esac

DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_VERSION}/x-ui-linux-${DOWNLOAD_ARCH}.tar.gz"

echo -e "\033[32m[✓] 下载地址: $DOWNLOAD_URL\033[0m"

# 下载文件
cd /tmp
wget -N --no-check-certificate -O "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz" "$DOWNLOAD_URL"

# 检查文件大小（应大于10MB）
FILE_SIZE=$(stat -c%s "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz" 2>/dev/null || stat -f%z "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz" 2>/dev/null)
if [[ -z "$FILE_SIZE" || "$FILE_SIZE" -lt 10000000 ]]; then
    echo -e "\033[31m[✗] 下载失败或文件损坏 (大小: ${FILE_SIZE:-未知} 字节)，请检查网络或尝试使用代理\033[0m"
    rm -f "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz"
    exit 1
fi

# 安装 3X-UI（参考官方逻辑）
echo -e "\n\033[33m开始安装 3X-UI...\033[0m"

# 解压到 /usr/local/
mkdir -p /usr/local/x-ui/
tar -zxvf "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz" -C /usr/local/x-ui/
rm -f "x-ui-linux-${DOWNLOAD_ARCH}.tar.gz"

cd /usr/local/x-ui/

# 权限
chmod +x x-ui bin/xray-linux-* x-ui.sh

# 设置 service（systemd）
cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=x-ui
After=network.target

[Service]
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui

# 设置用户名、密码、端口
echo -e "\033[33m设置用户名/密码/端口...\033[0m"
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 重启服务
/usr/local/x-ui/x-ui restart

# 输出最终信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me)
echo -e "\n\033[32m安装完成！3X-UI 已就绪\033[0m"
echo -e "访问地址: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo -e "\n提示："
echo "  • 建议安装后立即登录面板修改路径（webBasePath）提高安全性"
echo "  • 可在面板内或运行 'x-ui' 命令手动申请 SSL 证书"
echo "  • BBR 加速已开启，如需检查：sysctl net.ipv4.tcp_congestion_control"
echo "  • 如需卸载：/usr/local/x-ui/x-ui uninstall"
echo ""
