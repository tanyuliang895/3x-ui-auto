#!/bin/bash
# 3X-UI 全自动一键安装脚本（官方兼容修复版 - 正确处理 x-ui/ 子目录）
# 默认端口: 2026    用户名: liang    密码: liang
# 自动 BBR + 最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置参数
DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装 (端口: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户: \033[32m$USERNAME\033[0m   密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖安装
echo "检查并安装依赖..."
if command -v apt &>/dev/null; then
    apt update -y && apt install -y wget curl tar ca-certificates
elif command -v yum &>/dev/null; then
    yum install -y wget curl tar ca-certificates
elif command -v dnf &>/dev/null; then
    dnf install -y wget curl tar ca-certificates
else
    echo -e "\033[31m不支持的系统，请手动安装 wget curl tar\033[0m"
    exit 1
fi

# BBR 启用
echo -e "\n\033[33m启用 BBR 加速...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
echo -e "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用\033[0m"

# 获取最新版本
LATEST_VERSION=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[ -z "$LATEST_VERSION" ] && { echo -e "\033[31m无法获取版本\033[0m"; exit 1; }
echo -e "\033[32m最新版本: $LATEST_VERSION\033[0m"

# 架构检测
case $(uname -m) in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "\033[33m未知架构 $(uname -m)，默认 amd64\033[0m"; ARCH="amd64" ;;
esac

URL="https://github.com/MHSanaei/3x-ui/releases/download/$LATEST_VERSION/x-ui-linux-$ARCH.tar.gz"

# 安装目录
INSTALL_PATH="/usr/local/x-ui"
TMP_FILE="/tmp/x-ui.tar.gz"

cd /tmp
rm -f x-ui.tar.gz x-ui 2>/dev/null

echo -e "\033[33m下载安装包...\033[0m"
wget --no-check-certificate -O "$TMP_FILE" "$URL" || { echo -e "\033[31m下载失败，请检查网络\033[0m"; exit 1; }

# 清理旧安装（安全起见）
systemctl stop x-ui 2>/dev/null || true
rm -rf "$INSTALL_PATH" /usr/bin/x-ui 2>/dev/null

echo -e "\033[33m解压...\033[0m"
tar zxvf "$TMP_FILE"

# 官方方式：产生 x-ui/ 文件夹，然后移动
if [ -d "x-ui" ]; then
    mv x-ui "$INSTALL_PATH"
else
    echo -e "\033[31m解压后未找到 x-ui/ 文件夹\033[0m"
    exit 1
fi

rm -f "$TMP_FILE"

cd "$INSTALL_PATH/x-ui" || { echo -e "\033[31m进入 x-ui 子目录失败\033[0m"; exit 1; }

# 关键：在这里设置权限（文件就在当前目录）
echo -e "\033[33m设置执行权限...\033[0m"
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true

# systemd 服务文件（优先用解压出的）
echo -e "\033[33m安装服务文件...\033[0m"
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

# 设置用户名密码端口
echo -e "\033[33m设置账户信息...\033[0m"
"$INSTALL_PATH/x-ui/x-ui" setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 启动
systemctl restart x-ui
sleep 3

# 完成信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户: \033[32m$USERNAME\033[0m"
echo -e "密码: \033[32m$PASSWORD\033[0m"
echo ""
echo "推荐操作："
echo "  • 登录后 → 设置 → 面板设置 → 修改面板路径 (webBasePath)"
echo "  • 检查服务: systemctl status x-ui"
echo "  • 卸载命令: $INSTALL_PATH/x-ui uninstall"
echo ""
