#!/bin/bash
# 3X-UI 全自动安装脚本（2026-01-15 终极匹配版：精确捕捉多行 SSL 提示）
# 端口: 2026 | 用户: liang | 密码: liang | BBR

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装 (端口: \033[32m$PORT\033[0m | 用户/密码: $USERNAME/$PASSWORD)"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖 curl expect socat ca-certificates..."
apt update -y && apt install -y curl expect socat ca-certificates >/dev/null 2>&1 || true

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 开放端口（证书验证必须）
echo "开放 80-83 端口..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
echo "下载官方脚本到 $TEMP_SCRIPT..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载失败\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

# expect 精确匹配你的日志（多行、Note、括号、default 2 for IP）
echo -e "\n\033[33m开始自动化安装...\033[0m"

expect <<EOF
set timeout 900
log_user 1

spawn bash "$TEMP_SCRIPT"

expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n"; exit 1 }
}

expect {
    -re {Please set up the panel port:.*} { send "$PORT\r" }
    timeout { send_user "未匹配端口输入\n"; exit 1 }
}

# 精确匹配多行 SSL 提示（你的日志完整文本）
expect {
    -re {Choose SSL certificate setup method:.*1\. Let's Encrypt for Domain.*2\. Let's Encrypt for IP Address.*Note:.*Choose an option.*\(default 2 for IP\):} { send "2\r" }
    -re {Choose an option.*default 2 for IP.*:} { send "2\r" }
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项（提示文本变化）\n"; exit 1 }
}

expect {
    -re {Do you have an IPv6 address to include.*leave empty to skip.*:} { send "\r" }
    timeout { send_user "无IPv6，继续\n" }
}

set ports {80 81 82 83}
foreach p \$ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "\$p\r" }
        -re {Port.*is in use.*Enter another port.*:} { send "\$p\r" }
        -re {Port.*is in use.*} { continue }
        timeout { send_user "无端口提示，继续\n"; break }
    }
}

expect {
    -re {Would you like to set this certificate.*\[y/n\]:} { send "y\r" }
    -re {Would you like to modify --reloadcmd.*\[y/n\]:} { send "n\r" }
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "最终超时，假设完成\n" }
}

expect eof
EOF

rm -f "$TEMP_SCRIPT" 2>/dev/null

# 补齐服务文件
echo "补齐并启动服务..."
cat > /etc/systemd/system/x-ui.service <<EOF
[Unit]
Description=x-ui Service
After=network.target

[Service]
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui || true

# 强制设置账号
echo -e "\n\033[33m设置账号...\033[0m"
sleep 15
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" || true
/usr/local/x-ui/x-ui restart || true

IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问: https://$IP:$PORT （如果证书失败，用 http://$IP:$PORT）"
echo -e "用户名: $USERNAME"
echo -e "密码: $PASSWORD"
echo ""
echo "提示："
echo "  • 确保服务器公网 80 端口开放"
echo "  • 登录后改面板路径防扫描"
echo "  • 检查状态: systemctl status x-ui"
