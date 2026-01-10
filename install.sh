#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang + BBR 加速）
# 更新: 2026-01-10，集成 BBR v2 + fq 队列

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR 加速）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m\n"

# ======================== 启用 BBR 加速 ========================
echo -e "\033[36m启用 BBR v2 + fq 加速...\033[0m"

# 1. 检测并启用 BBR（兼容大部分内核 4.9+）
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi

# 2. 加载模块（如果内核支持）
modprobe tcp_bbr 2>/dev/null || true

# 3. 验证是否启用（输出结果给用户看）
echo "当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "当前队列算法: $(sysctl -n net.core.default_qdisc)"
echo -e "\033[32mBBR 加速已启用！\033[0m\n"

# ======================== 继续原安装流程 ========================

# 安装依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动安装"
fi

# 开放 80 端口
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 自动化
expect <<END_EXPECT
    set timeout -1
    spawn $TEMP_SCRIPT

    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }
    expect -re "(?i)Choose an option" { send "\\r" }
    expect -re "(?i)Do you have an IPv6.*skip" { send "\\r" }
    expect -re "(?i)(domain|域名)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re ".*" { send "\\r" }
    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 设置固定账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启服务
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！BBR 加速已开启\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[31mIP证书6天有效，生产建议用域名证书\033[0m"
