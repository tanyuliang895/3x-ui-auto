#!/bin/bash
# 3X-UI 全自动安装脚本（2026最终稳定版：修复 spawn <(curl) 问题 + 强制 IP SSL）
# 端口: 2026 | 用户: liang | 密码: liang | 自动 BBR + 证书
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装脚本 (端口: \033[32m$PORT\033[0m)"
echo -e "   用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root
[ "$(id -u)" != "0" ] && { echo -e "\033[31m请用 root 执行！\033[0m"; exit 1; }

# 安装依赖
echo "安装依赖 curl expect socat ca-certificates..."
apt update -y && apt install -y curl expect socat ca-certificates >/dev/null 2>&1 || \
yum install -y curl expect socat ca-certificates >/dev/null 2>&1 || \
dnf install -y curl expect socat ca-certificates >/dev/null 2>&1 || true

# 启用 BBR
echo -e "\n\033[33m启用 BBR 加速...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 开放证书所需端口
echo "开放 80-83 端口..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh 到临时文件（关键修复）
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
echo "下载官方安装脚本..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载官方脚本失败，请检查网络\033[0m"
    exit 1
fi

# 使用 expect 自动化交互
echo -e "\n\033[33m开始全自动安装（处理强制 SSL IP证书）...\033[0m"

expect <<'END_EXPECT'
set timeout 900
log_user 1

spawn bash "$TEMP_SCRIPT"

# 端口自定义
expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义提示\n"; exit 1 }
}

expect {
    -re {Please set up the panel port:.*} { send "$env(PORT)\r" }
    timeout { send_user "未匹配端口输入提示\n"; exit 1 }
}

# SSL 选择 IP证书 (2)
expect {
    -re {Choose.*option.*default.*2.*IP.*:} { send "2\r" }
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项\n"; exit 1 }
}

# IPv6 跳过
expect {
    -re {Do you have an IPv6 address.*leave empty to skip.*:} { send "\r" }
    timeout { send_user "无IPv6提示，继续\n" }
}

# ACME 监听端口（尝试80->81->82->83）
set ports {80 81 82 83}
foreach p $ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "$p\r" }
        -re {Port.*is in use.*Enter another port.*:} { send "$p\r" }
        -re {Port.*is in use.*} { continue }
        timeout { send_user "无端口提示，继续\n"; break }
    }
}

# 后续确认（如果有）
expect {
    -re {Would you like to set this certificate for the panel.*\[y/n\]:} { send "y\r" }
    -re {Would you like to modify --reloadcmd.*\[y/n\]:} { send "n\r" }
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "最终超时，假设完成\n" }
}

expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" 2>/dev/null

# 强制设置用户名密码端口
echo -e "\n\033[33m等待服务启动并设置账号...\033[0m"
sleep 15
for i in {1..30}; do
    if [ -x /usr/local/x-ui/x-ui ] && /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1
        echo -e "\033[32m账号设置完成！\033[0m"
        break
    fi
    echo "等待... ($i/30)"
    sleep 5
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 输出信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问地址: \033[36mhttps://$IP:$PORT\033[0m (使用 HTTPS，短期证书可能有警告)"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "重要提示："
echo "  • 确保服务器**公网 80 端口开放**（Let's Encrypt 需要验证）"
echo "  • 如果证书申请失败，手动运行 'x-ui' → SSL证书 → 选2 → 尝试其他端口"
echo "  • 登录后立即修改面板路径（webBasePath）"
echo "  • 检查状态: systemctl status x-ui"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
echo ""
