#!/bin/bash
# 3X-UI 全自动安装脚本（官方提取方式最终版 - 正确 cd x-ui 子目录 + 权限设置）
# 端口: 2026   用户名: liang   密码: liang
# 包含 BBR 加速 + 自动最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置
PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 一键安装脚本 (端口: \033[32m$PORT\033[0m)"
echo -e "   用户名: \033[32m$USERNAME\033[0m   密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[[ $EUID -ne 0 ]] && { echo -e "\033[31m请以 root 权限运行！\033[0m"; exit 1; }

# 安装依赖
echo "安装必要依赖..."
if command -v apt &>/dev/null; then
    apt update -y && apt install -y wget curl tar ca-certificates
elif command -v yum &>/dev/null; then
    yum install -y wget curl tar ca-certificates
elif command -v dnf &>/dev/null; then
    dnf install -y wget curl tar ca-certificates
else
    echo -e "\033[31m无法自动安装依赖，请手动安装 wget curl tar\033[0m"
    exit 1
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
LATEST=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[[ -z "$LATEST" ]] && { echo -e "\033[31m无法获取最新版本，请检查网络\033[0m"; exit 1; }
echo -e "\033[32m检测到最新版本: $LATEST\033[0m"

# 架构
case $(uname -m) in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "\033[33m使用默认 amd64 架构\033[0m"; ARCH="amd64" ;;
esac

DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST}/x-ui-linux-${ARCH}.tar.gz"

# 安装目录
XUI_PATH="/usr/local/x-ui"

# 清理旧版
systemctl stop x-ui 2>/dev/null || true
rm -rf "$XUI_PATH" /usr/bin/x-ui 2>/dev/null

# 下载 & 提取（官方方式：cd /usr/local/ 后 tar 直接解压）
echo -e "\033[33m下载并解压...\033[0m"
cd /usr/local/
wget -N --no-check-certificate "$DOWNLOAD_URL" -O "x-ui.tar.gz" || { echo -e "\033[31m下载失败\033[0m"; exit 1; }
tar zxvf x-ui.tar.gz
rm -f x-ui.tar.gz

# 进入子目录 x-ui/ 设置权限
cd x-ui || { echo -e "\033[31m解压后未找到 x-ui 子目录，请检查 tar 包结构\033[0m"; exit 1; }

echo -e "\033[33m设置执行权限...\033[0m"
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true

# 安装服务文件（官方优先用解压出的）
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

# 设置用户名/密码/端口
echo -e "\033[33m设置面板账户...\033[0m"
./x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1

# 启动服务
systemctl restart x-ui
sleep 3

# 输出信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！3X-UI 已启动\033[0m"
echo -e "访问地址: \033[36mhttp://$IP:$PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "重要提示："
echo "  • 首次登录后 **立即** 修改面板路径（设置 → 面板设置 → 面板路径）防扫描"
echo "  • 检查服务状态：systemctl status x-ui"
echo "  • 卸载命令：/usr/local/x-ui/x-ui uninstall"
echo ""
