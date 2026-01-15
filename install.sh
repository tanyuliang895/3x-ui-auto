#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互、固定端口 2026 + 账号 liang/liang + BBR + 证书申请）
# 需要证书版 - 覆盖 80 端口确认 + 根路径

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR + 证书申请）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m\n"

# BBR 加速
echo -e "\033[36m启用 BBR...\033[0m"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
modprobe tcp_bbr 2>/dev/null || true
echo "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "\033[32mBBR 已开启！\033[0m\n"

# 依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖..."
    apt update -y && apt install -y curl expect 2>/dev/null || yum install -y curl expect 2>/dev/null || dnf install -y curl expect 2>/dev/null
fi

# 开放 80 端口（证书必须）
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 保留证书申请，覆盖 80 端口确认
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 菜单 - 回车选默认 2 (IP证书)
    expect
