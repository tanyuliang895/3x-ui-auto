#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + liang/liang + BBR）
# 最终版 - 用 -exact 强制匹配 + 简化结构，绕过 Tcl [y/n] 解析坑

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR 加速）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m\n"

# 启用 BBR
echo -e "\033[36m启用 BBR v2 + fq 加速...\033[0m"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
modprobe tcp_bbr 2>/dev/null || true
echo "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "当前队列算法: $(sysctl -n net.core.default_qdisc)"
echo -e "\033[32mBBR 加速已启用！\033[0m\n"

# 安装依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    { echo -e "\033[31m依赖安装失败，请手动安装 curl expect\033[0m"; exit 1; }
fi

# 开放 80 端口
echo "开放 80 端口（用于 IP SSL）..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载官方安装脚本失败，请检查网络\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

echo "开始自动化安装（expect 部分）... 请耐心等待日志输出"

expect <<END_EXPECT
    set timeout 180
    log_user 1

    spawn bash /tmp/3x-ui-install.sh

    expect -exact "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " { send "y\r" }
    expect -exact "Please set up the panel port: " { send "$PORT\r" }

    expect -exact "Choose an option (default 2 for IP): " { send "\r" }
    expect -exact "Choose SSL certificate setup method:" { send "2\r" }

    expect -exact "Do you have an IPv6 address to include? (leave empty to skip): " { send "\r" }

    expect -exact "Port to use for ACME HTTP-01 listener (default 80): " { send "80\r" }
    expect -exact "Port * is in use." { send "81\r" }
    expect -exact "Enter another port for acme.sh standalone listener (leave empty to abort): " { send "81\r" }
    expect -exact "Port * is in use." { send "82\r" }
    expect -exact "Port * is in use." { send "83\r" }

    expect -re "\\[y/n\\]: " { send "n\r" }
    expect -re ".*: " { send "\r" }
    expect -exact "Would you like to set this certificate for the panel? (y/n): " { send "y\r" }
    expect -exact "Would you like to modify --reloadcmd for ACME? (y/n): " { send "n\r" }
    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" 2>/dev/null

echo "等待 x-ui 服务启动并设置账号..."
for i in {1..40}; do
    if /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1
        echo "账号设置成功！"
        break
    fi
    echo "等待 x-ui 命令可用... ($i/40)"
    sleep 3
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttps://你的服务器IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m   密码: \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[31mIP证书仅6天有效，建议换域名证书\033[0m"
echo -e "\033[32mBBR 已启用\033[0m"
