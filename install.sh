#!/bin/bash
# 3X-UI 全自动安装脚本（官方提取方式修复版 - 直接提取到 /usr/local/）
# 端口: 2026   用户: liang   密码: liang
# 自动 BBR + 最新版本 v2.8.7+
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
apt update -y && apt install -y wget curl tar ca-certificates || \
yum install -y wget curl tar ca-certificates || \
dnf install -y wget curl tar ca-certificates || true

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
rm -f x-ui.tar.gz 2>/dev/null

echo -e "\033[33m下载...\033[0m"
wget --no-check-certificate -O "x-ui.tar.gz" "$URL" || { echo -e "\033[31m下载失败\033[0m"; exit 1; }

# 清理旧安装
systemctl stop x-ui 2>/dev/null || true
rm -rf "$INSTALL_DIR" /usr/bin/x-ui 2>/dev/null

# 关键修复：官方方式 - 先 cd 到 /usr/local/，然后 tar 直接提取（会创建 /usr/local/x-ui/）
echo -e "\033[33m解压到 /usr/local/... \033[0m"
cd /usr/local/
tar zxvf /tmp/x-ui.tar.gz
rm -f /tmp/x-ui.tar.gz

# 现在目录结构是 /usr/local/x-ui/x-ui, /usr/local/x-ui/x-ui.sh 等
# 进入 x-ui 子目录进行权限设置
cd "$INSTALL_DIR/x-ui" || { echo -e "\033[31m进入 x-ui 子目录失败！请检查 tar 提取结构。\033[0m
