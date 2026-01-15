#!/bin/bash
# 3X-UI 一键全自动安装脚本（修复版 - 正确处理提取路径）
# 默认端口: 2026    用户名: liang    密码: liang
# 自动启用 BBR + 获取最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置参数（可修改）
DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口默认: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：请使用 root 权限运行！\033[0m"
    exit 1
fi

# 安装依赖
if ! command -v curl &> /dev/null || ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
    echo "安装必要依赖..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y curl wget tar ca-certificates
    elif command -v yum &> /dev/null; then
        yum install -y curl wget tar ca-certificates
    elif command -v dnf &> /dev/null; then
        dnf install -y curl wget tar ca-certificates
    else
        echo -e "\033[31m不支持的系统，请手动安装 curl wget tar。\033[0m"
        exit 1
    fi
fi

# 启用 BBR
echo -e "\n\033[33m启用 BBR 加速...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 获取最新版本
LATEST_VERSION=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$LATEST_VERSION" ]]; then
    echo -e "\033[31m[✗] 无法获取最新版本\033[0m"
    exit 1
fi
echo -e "\033[32m[✓] 最新版本: $LATEST_VERSION\033[0m"

# 架构
ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64) DOWNLOAD_ARCH="amd64" ;;
    aarch64|arm64) DOWNLOAD_ARCH="arm64" ;;
    *) echo -e "\033[31m[✗] 不支持的架构: $ARCH (默认用 amd64)\033[0m" && DOWNLOAD_ARCH="amd64" ;;
esac

DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_VERSION}/x-ui-linux-${DOWNLOAD_ARCH}.tar.gz"
echo -e "\033[32m[✓] 下载: $DOWNLOAD_URL\033[0m"

# 下载 & 提取（关键修复：使用 --strip-components=1 避免嵌套 x-ui/ 文件夹）
cd /tmp
rm -f x-ui-linux-*.tar.gz 2>/dev/null
wget -N --no-check-certificate "$DOWNLOAD_URL" -O "x-ui.tar.gz"

FILE_SIZE=$(stat -c%s "x-ui.tar.gz" 2>/dev/null || stat -f%z "x-ui.tar.gz" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 10000000 ]; then
    echo -e "\033[31m[✗] 下载文件太小或失败 ($FILE_SIZE bytes)\033[0m"
    exit 1
fi

echo -e "\033[33m解压到 /usr/local/x-ui/...\033[0m"
mkdir -p /usr/local/x-ui
tar -zxvf "x-ui.tar.gz" --strip-components=1 -C /usr/local/x-ui/
rm -f "x-ui.tar.gz"

cd /usr/local/x-ui/

# 权限设置（现在路径正确）
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true
echo -e "\033[32m[✓] 权限设置完成\033[0m"

# Systemd 服务（模仿官方：优先用解压出的文件）
if [ -f "x-ui.service.debian" ]; then
    cp x-ui.service.debian /etc/systemd/system/x-ui.service
elif [ -f "x-ui.service.rhel" ]; then
    cp x-ui.service.rhel /etc/systemd/system/x-ui.service
else
    # 备用：从 GitHub 下载 debian 版（常见于 Ubuntu/Debian）
    wget -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/master/x-ui.service.debian
fi

chmod 644 /etc/systemd/system/x-ui.service
systemctl daemon-reload
systemctl enable x-ui >/dev/null 2>&1

# 设置用户名/密码/端口
echo -e "\033[33m设置用户名/密码/端口...\033[0m"
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 启动服务
systemctl start x-ui
sleep 3

# 最终信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "提示："
echo "  • 首次登录后立即修改面板路径 (webBasePath) 以防扫描"
echo "  • 在面板内申请 SSL (推荐 Cloudflare DNS)"
echo "  • 检查状态：systemctl status x-ui"
echo "  • 卸载：/usr/local/x-ui/x-ui uninstall"
echo ""
