#!/bin/bash
# 3X-UI 全自动安装脚本（跳过 SSL 强制版 + BBR + 端口 2026 + liang/liang）
# 完全自动，无需手动交互，面板用 HTTP

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装 (端口: \033[32m$PORT\033[0m | 用户/密码: $USERNAME/$PASSWORD)"
echo -e "   跳过 SSL 强制设置（后续可手动加）"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
apt update -y && apt install -y curl expect socat ca-certificates wget tar >/dev/null 2>&1 || true

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 下载并修改官方 install.sh（跳过 SSL 部分）
echo "下载并 patch 官方脚本（跳过 SSL）..."
TMP_INSTALL="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TMP_INSTALL"

# 强制跳过 SSL 部分（注释掉或替换为 n）
sed -i 's/read -r -p "Choose SSL certificate setup method:/# &/' "$TMP_INSTALL"
sed -i 's/read -r -p "Choose an option (default 2 for IP):/# &/' "$TMP_INSTALL"
sed -i 's/read -r -p "Port to use for ACME HTTP-01 listener/# &/' "$TMP_INSTALL"
sed -i 's/read -r -p "Do you have an IPv6 address/# &/' "$TMP_INSTALL"
sed -i 's/read -r -p "Would you like to set this certificate/# &/' "$TMP_INSTALL"
sed -i 's/acme.sh --issue/# &/' "$TMP_INSTALL"
sed -i 's/acme.sh --install-cert/# &/' "$TMP_INSTALL"
sed -i 's/echo "SSL Certificate Setup (MANDATORY)"/echo "SSL 强制设置已跳过（手动添加）"/' "$TMP_INSTALL"

chmod +x "$TMP_INSTALL"

# 运行修改后的脚本（expect 只处理端口）
echo -e "\n\033[33m运行修改版官方脚本...\033[0m"

expect <<EOF
set timeout 600
log_user 1

spawn bash "$TMP_INSTALL"

expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n" }
}

expect {
    -re {Please set up the panel port:.*} { send "$PORT\r" }
    timeout { send_user "未匹配端口输入\n" }
}

# 其他提示默认或 y
expect {
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "超时，假设完成\n" }
}

expect eof
EOF

rm -f "$TMP_INSTALL" 2>/dev/null

# 强制设置账号
echo -e "\n\033[33m设置账号...\033[0m"
sleep 10
for i in {1..20}; do
    if [ -x /usr/local/x-ui/x-ui ] && /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1
        echo -e "\033[32m账号设置完成！\033[0m"
        break
    fi
    sleep 5
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装完成！（SSL 已跳过）\033[0m"
echo -e "访问: http://$IP:$PORT （HTTP 方式，建议后续手动加证书）"
echo -e "用户名: $USERNAME"
echo -e "密码: $PASSWORD"
echo ""
echo "提示："
echo "  • 登录后立即修改面板路径（webBasePath）"
echo "  • 手动加证书：运行 'x-ui' → SSL证书 → 选2 → 试端口"
echo "  • 检查状态: systemctl status x-ui"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
