#!/bin/bash
# 3X-UI 全自动安装脚本（最终官方提取方式版 - 直接在 /usr/local/ 解压，避免 mv 导致的路径问题）
# 端口: 2026   用户名: liang   密码: liang
# 包含 BBR 加速 + 自动获取最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 一键全自动安装 (端口: \033[32m$PORT\033[0m)"
echo -e "   用户名: \033[32m$USERNAME\033[0m   密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root
[[ $EUID -ne 0 ]] && { echo -e "\033[31m必须以 root 运行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
apt update -y && apt install -y wget tar ca-certificates || yum install -y wget tar ca-certificates || dnf install -y wget tar ca-certificates || true

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 最新版本
LATEST=$(curl -s https://api.github.com/repos/MHSanaei/3x-ui/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[[ -z "$LATEST" ]] && { echo -e "\033[31m获取版本失败\033[0m"; exit 1; }
echo -e "\033[32m最新版本: $LATEST\033[0m"

# 架构
case $(uname -m) in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) ARCH="amd64" ;;
esac

URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST}/x-ui-linux-${ARCH}.tar.gz"

XUI_DIR="/usr/local/x-ui"

# 清理旧版
systemctl stop x-ui 2>/dev/null || true
rm -rf "$XUI_DIR" /usr/bin/x-ui 2>/dev/null

# 官方方式：直接在 /usr/local/ 解压（自动创建 x-ui/ 文件夹）
echo -e "\033[33m下载并解压到 /usr/local/... \033[0m"
cd /usr/local/
wget --no-check-certificate -O x-ui.tar.gz "$URL" || { echo -e "\033[31m下载失败\033[0m"; exit 1; }
tar zxvf x-ui.tar.gz
rm -f x-ui.tar.gz

# 进入 x-ui 子目录（现在是 /usr/local/x-ui/）
cd x-ui || { echo -e "\033[31m未找到 x-ui 子目录！\033[0m"; exit 1; }

echo -e "\033[33m设置权限...\033[0m"
chmod +x x-ui x-ui.sh bin/xray-linux-* 2>/dev/null || true

# 服务文件
echo -e "\033[33m安装服务...\033[0m"
if [ -f x-ui.service.debian ]; then
    cp x-ui.service.debian /etc/systemd/system/x-ui.service
elif [ -f x-ui.service.rhel ]; then
    cp x-ui.service.rhel /etc/systemd/system/x-ui.service
else
    wget -O /etc/systemd/system/x-ui.service https://raw.githubusercontent.com/MHSanaei/3x-ui/master/x-ui.service.debian
fi

chmod 644 /etc/systemd/system/x-ui.service
systemctl daemon-reload
systemctl enable x-ui >/dev/null 2>&1

# 设置账户
echo -e "\033[33m设置账户...\033[0m"
./x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1

# 启动
systemctl restart x-ui
sleep 3

# 输出
IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装成功！\033[0m"
echo -e "面板: \033[36mhttp://$IP:$PORT\033[0m"
echo -e "用户: \033[32m$USERNAME\033[0m"
echo -e "密码: \033[32m$PASSWORD\033[0m"
echo ""
echo "建议：登录后修改面板路径防扫描"
echo "状态: systemctl status x-ui"
echo "卸载: /usr/local/x-ui/x-ui uninstall"
echo ""
