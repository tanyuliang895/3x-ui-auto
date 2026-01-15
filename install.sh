#!/bin/bash
# 3X-UI 一键全自动安装脚本（最终修复版 - 正确提取结构 + 官方风格）
# 默认端口: 2026    用户名: liang    密码: liang
# 自动启用 BBR + 最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置（可改）
DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m请用 root 执行！\033[0m"; exit 1; }

# 依赖
if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
    echo "安装依赖 (wget tar)..."
    apt-get update -y && apt-get install -y wget tar ca-certificates || \
    yum install -y wget tar ca-certificates || \
    dnf install -y wget tar ca-certificates || { echo -e "\033[31m依赖安装失败\033[0m"; exit 1; }
fi

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用\033[0m"

# 最新版本
LATEST_VERSION=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$LATEST_VERSION" ] && { echo -e "\033[31m获取版本失败\033[0m"; exit 1; }
echo -e "\033[32m最新版本: $LATEST_VERSION\033[0m"

# 架构
case $(uname -m) in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "\033[31m不支持架构 $(uname -m)，默认 amd64\033[0m"; ARCH="amd64" ;;
esac

URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_VERSION}/x-ui-linux-${ARCH}.tar.gz"
echo -e "\033[32m下载: $URL\033[0m"

# 下载 & 安装目录
INSTALL_DIR="/usr/local/x-ui"
TMP_DIR="/tmp"
cd "$TMP_DIR"
rm -rf x-ui* 2>/dev/null

wget --no-check-certificate -O "x-ui.tar.gz" "$URL"

[ ! -s "x-ui.tar.gz" ] && { echo -e "\033[31m下载失败\033[0m"; exit 1; }

# 清理旧版 + 提取（官方方式：不 strip，产生 x-ui/ 文件夹）
echo -e "\033[33m解压...\033[0m"
rm -rf "$INSTALL_DIR" /usr/bin/x-ui 2>/dev/null
tar zxvf "x-ui.tar.gz"
rm -f "x-ui.tar.gz"

# 移动到 /usr/local/x-ui 并进入 x-ui 子目录
mv x-ui "$INSTALL_DIR"
cd "$INSTALL_DIR/x-ui" || { echo -e "\033[31m提取后未找到 x-ui 子目录\033[0m"; exit 1; }

# 权限（在 x-ui/ 目录下执行）
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null
echo -e "\033[32m权限设置完成\033[0m"

# systemd 服务（从解压出的文件复制）
if [ -f "x-ui.service.debian" ]; then
    cp x-ui.service.debian /etc/systemd/system/x-ui.service
elif [ -f "x-ui.service.rhel" ]; then
    cp x-ui.service.rhel /etc/systemd/system/x-ui.service
else
    echo -e "\033[33m未找到服务文件，从官方下载 debian 版...\033[0m"
    wget -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/master/x-ui.service.debian
fi

chmod 644 /etc/systemd/system/x-ui.service
systemctl daemon-reload
systemctl enable x-ui >/dev/null 2>&1

# 设置账户 & 端口
echo -e "\033[33m设置账户/端口...\033[0m"
"$INSTALL_DIR/x-ui" setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 启动
systemctl restart x-ui
sleep 3

# 输出
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的IP")
echo -e "\n\033[32m安装成功！\033[0m"
echo -e "面板地址: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m\n"
echo "建议："
echo "  • 登录后立即改面板路径 (设置 → 面板设置 → 面板路径)"
echo "  • 检查状态: systemctl status x-ui"
echo "  • 卸载: $INSTALL_DIR/x-ui uninstall"
echo ""
