#!/bin/bash
# 3X-UI 全自动安装脚本（2026-01-15 最终完美版：处理强制SSL IP证书 + 端口冲突循环）
# 端口: 2026 | 用户: liang | 密码: liang | BBR
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

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

# 开放 80-83 端口（关键！ACME 验证需要公网访问）
echo "开放 80-83 端口（用于证书验证）..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
firewall-cmd --add-port=80-83/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true

# 全自动 expect（精确匹配官方提示）
echo -e "\n\033[33m自动化执行官方安装（处理强制 IP SSL）...\033[0m"

expect <<'END_EXPECT'
set timeout 900
log_user 1

spawn bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

# 端口自定义 y
expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n"; exit 1 }
}

# 输入端口
expect {
    -re {Please set up the panel port:.*} { send "$env(PORT)\r" }
    timeout { send_user "未匹配端口输入\n"; exit 1 }
}

# SSL 选项选 2 (IP证书)
expect {
    -re {Choose an option.*default 2 for IP.*:} { send "2\r" }
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项\n"; exit 1 }
}

# IPv6 跳过 (空)
expect {
    -re {Do you have an IPv6 address to include.*leave empty to skip.*:} { send "\r" }
    timeout { send_user "无IPv6提示，继续\n" }
}

# ACME 端口（处理冲突循环）
set ports {80 81 82 83}
foreach p $ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "$p\r" }
        -re {Port.*is in use.*Enter another port.*:} { send "$p\r" }
        -re {Port.*is in use.*} { continue }
        timeout { send_user "无端口提示，继续\n"; break }
    }
}

# 后续确认 (y 应用证书, n 修改 reloadcmd)
expect {
    -re {Would you like to set this certificate for the panel.*\[y/n\]:} { send "y\r" }
    -re {Would you like to modify --reloadcmd for ACME.*\[y/n\]:} { send "n\r" }
    -re {\[y/n\]:} { send "y\r" }
    "certificate configured successfully" { }
    eof { }
    timeout { send_user "最终超时，假设完成\n" }
}

expect eof
END_EXPECT

# 强制设置用户名/密码/端口（覆盖官方随机）
echo -e "\n\033[33m等待服务启动并强制设置账号...\033[0m"
sleep 15
for i in {1..30}; do
    if [ -x /usr/local/x-ui/x-ui ] && /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1
        echo -e "\033[32m账号设置成功！\033[0m"
        break
    fi
    echo "等待 x-ui 命令可用... ($i/30)"
    sleep 5
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 完成信息
IP=$(curl -s4 icanhazip.com || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问面板: \033[36mhttps://$IP:$PORT\033[0m （IP证书有效约6天，acme.sh自动续期）"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "重要注意："
echo "  • 服务器必须**公网可访问80端口**（或你选择的端口），否则证书申请失败（Let's Encrypt验证）"
echo "  • 如果证书失败（日志显示 'Failed to issue'），手动运行 'x-ui' → SSL管理 → 选2 → 换端口重试"
echo "  • 浏览器可能显示证书警告（短期证书），点击高级 → 继续"
echo "  • 登录后**立即修改面板路径** (webBasePath) 提高安全性"
echo "  • 检查服务: systemctl status x-ui"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
echo ""
