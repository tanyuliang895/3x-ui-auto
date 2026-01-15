#!/bin/bash
# 3X-UI 全自动安装脚本（最终官方兼容版 - 正确 cd x-ui 子目录）
# 端口: 2026   用户: liang   密码: liang
# 自动 BBR + 最新版
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
    echo "安装依赖..."
    apt update -y && apt install -y wget tar ca-certificates || \
    yum install -y wget tar ca-certificates || \
    dnf install -y wget tar ca-certificates || { echo -e "\033[31m依赖安装失败\033[0m"; exit 1; }
fi

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 最新版本
LATEST_VERSION=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$LATEST_VERSION" ] && { echo -e "\033[31m获取版本失败\033[0m"; exit 1; }
echo -e "\033[32m最新版本: $LATEST_VERSION\033[0m"

# 架构
case $(uname -m) in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "\033[33m未知架构，使用 amd64\033[0m"; ARCH="amd64" ;;
esac

URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_VERSION}/x-ui-linux-${ARCH}.tar.gz"

INSTALL_DIR="/usr/local/x-ui"

cd /tmp
rm -rf x-ui x-ui*.tar.gz 2>/dev/null

echo -e "\033[33m下载...\033[0m"
wget --no-check-certificate -O "x-ui.tar.gz" "$URL" || { echo -e "\033[31m下载失败\033[0m"; exit 1; }

# 清理旧安装
systemctl stop x-ui 2>/dev/null || true
rm -rf "$INSTALL_DIR" 2>/dev/null

echo -e "\033[33m解压...\033[0m"
tar zxvf "x-ui.tar.gz"
rm -f "x-ui.tar.gz"

# 关键：移动并进入子目录 x-ui/
if [ -d "x-ui" ]; then
    mv x-ui "$INSTALL_DIR"
    cd "$INSTALL_DIR/x-ui" || { echo -e "\033[31m进入 x-ui 子目录失败\033[0m"; exit 1; }
else
    echo -e "\033[31m解压后未找到 x-ui/ 文件夹\033[0m"
    exit 1
fi

# 现在在正确目录下设置权限
echo -e "\033[33m设置权限...\033[0m"
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true

# 服务文件（从子目录复制）
echo -e "\033[33m安装 systemd 服务...\033[0m"
if [ -f "x-ui.service.debian" ]; then
    cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
elif [ -f "x-ui.service.rhel" ]; then
    cp -f x-ui.service.rhel /etc/systemd/system/x-ui.service
else
    wget -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/master/x-ui.service.debian
fi

chmod 644 /etc/systemd/system/x-ui.service
systemctl daemon-reload
systemctl enable x-ui >/dev/null 2>&1

# 设置账户
echo -e "\033[33m设置用户名/密码/端口...\033[0m"
/usr/local/x-ui/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 启动
systemctl restart x-ui
sleep 3

# 输出
IP=$(curl -s4 icanhazip.com || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m\n"
echo "建议：登录面板后立即修改面板路径 (webBasePath)"
echo "检查状态：systemctl status x-ui"
echo "卸载：/usr/local/x-ui/x-ui uninstall"
echo ""
