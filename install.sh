#!/bin/bash
# 3X-UI 全自动安装脚本（2026最新版 - 处理强制 SSL + IP证书 + 多端口尝试）
# 端口: 2026 | 用户: liang | 密码: liang | BBR 启用
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装 (端口: \033[32m$PORT\033[0m | 用户/密码: liang/liang)"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m请用 root 执行！\033[0m"; exit 1; }

# 依赖 + expect
echo "安装依赖 curl expect socat ca-certificates..."
apt update -y && apt install -y curl expect socat ca-certificates >/dev/null 2>&1 || \
yum install -y curl expect socat ca-certificates >/dev/null 2>&1 || \
dnf install -y curl expect socat ca-certificates >/dev/null 2>&1 || true

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 开放 80-83 端口（ACME 必须）
ufw allow 80:83/tcp 2>/dev/null || true
firewall-cmd --add-port=80-83/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT 2>/dev/null || true

# 执行官方脚本 + expect 自动化
echo -e "\n\033[33m执行官方安装脚本（全自动处理 SSL + IP证书）...\033[0m"

expect <<'EOF'
set timeout 600
log_user 1

spawn bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

# 端口自定义
expect {
    -re {Would you like to customize the Panel Port settings\?.*\[y/n\]:} { send "y\r" }
    timeout { send_user "\n超时: 未匹配端口提示\n"; exit 1 }
}

expect {
    -re {Please set up the panel port:.*} { send "$env(PORT)\r" }
    timeout { send_user "\n超时: 未匹配端口输入\n"; exit 1 }
}

# SSL 选择 (新版提示)
expect {
    -re {Choose SSL certificate setup method:.*2.*IP Address} { send "2\r" }
    -re {Choose an option.*default.*} { send "2\r" }
    timeout { send_user "\n超时: 未匹配 SSL 选择\n"; exit 1 }
}

# IPv6 跳过
expect {
    -re {Do you have an IPv6 address.*leave empty to skip} { send "\r" }
    timeout { send_user "\n无 IPv6 提示，继续\n" }
}

# ACME 端口 (默认80，如果占用了循环问新端口)
set ports {80 81 82 83}
foreach p $ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "$p\r" }
        -re {Port .* is in use.*Enter another port} { send "$p\r" }
        -re {Port .* is in use.*} { continue }
        timeout { send_user "\n无端口提示，继续\n"; break }
    }
}

# 其他可能的 y/n 或确认（统一 n 或 y 根据需要）
expect {
    -re {\[y/n\]:} { send "y\r" }  ;# 证书设置到面板 y
    -re {Would you like to modify.*} { send "n\r" }
    -re {.*finish.*} { }
    eof { }
    timeout { send_user "\n最终超时，假设完成\n" }
}

expect eof
EOF

# 等待服务就绪 + 强制设置用户名密码（官方可能随机生成）
echo -e "\n\033[33m等待服务启动并设置账号...\033[0m"
sleep 10
for i in {1..20}; do
    if /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1
        echo -e "\033[32m账号已强制设置为 $USERNAME / $PASSWORD\033[0m"
        break
    fi
    echo "等待 x-ui 命令可用... ($i/20)"
    sleep 5
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1

# 输出
IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装完成！（IP证书有效期约6天，自动续期）\033[0m"
echo -e "访问: \033[36mhttps://$IP:$PORT\033[0m （使用 HTTPS，忽略短期证书警告）"
echo -e "用户名: \033[32m$USERNAME\033[0m   密码: \033[32m$PASSWORD\033[0m"
echo ""
echo "提示："
echo "  • 登录后立即改面板路径（设置 → 面板设置 → 面板路径）防扫描"
echo "  • 如果证书申请失败（80端口被占/网络问题），手动运行 'x-ui' → 选择2 → 尝试其他端口"
echo "  • 检查: systemctl status x-ui"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
echo ""
