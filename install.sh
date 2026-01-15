#!/bin/bash
# 3X-UI 全自动安装脚本（2026-01-15 最终稳定版：不 patch，只 expect 自动化 + 补服务 + BBR）
# 端口: 2026 | 用户: liang | 密码: liang | 自动处理 SSL 选择 IP 证书

set -e

export PORT="2026"
export USERNAME="liang"
export PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装 (端口: \033[32m$PORT\033[0m | 用户/密码: $USERNAME/$PASSWORD)"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
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

# 开放端口
echo "开放 80-83 端口（证书验证） + $PORT..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
ufw allow "$PORT"/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 自动化（宽松匹配所有提示）
echo -e "\n\033[33m自动化执行官方安装...\033[0m"

expect <<EOF
set timeout 900
log_user 1

spawn bash "$TEMP_SCRIPT"

expect {
    -re {Would you like to customize.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n" }
}

expect {
    -re {Please set up the panel port:.*} { send "$PORT\r" }
    timeout { send_user "未匹配端口输入\n" }
}

expect {
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    -re {Choose an option.*default 2.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项，继续尝试\n" }
}

expect {
    -re {Do you have an IPv6.*leave empty.*:} { send "\r" }
    timeout { send_user "无IPv6，继续\n" }
}

set ports {80 81 82 83}
foreach p \$ports {
    expect {
        -re {Port to use for ACME.*default 80.*:} { send "\$p\r" }
        -re {Port.*is in use.*} { send "\$p\r" }
        timeout { send_user "无端口提示，继续\n"; break }
    }
}

expect {
    -re {Would you like to set this certificate.*\[y/n\]:} { send "y\r" }
    -re {Would you like to modify --reloadcmd.*\[y/n\]:} { send "n\r" }
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "超时，假设完成\n" }
}

expect eof
EOF

# 补齐服务文件（防止缺失）
echo "补齐服务文件..."
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
echo -e "访问: http://$IP:$PORT （如果证书失败，用 HTTP 方式）"
echo -e "用户名: $USERNAME"
echo -e "密码: $PASSWORD"
echo ""
echo "提示："
echo "  • 如果出现证书失败，面板仍可用 HTTP 访问"
echo "  • 登录后改面板路径（webBasePath）"
echo "  • 检查: systemctl status x-ui"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
