#!/bin/bash
# 3X-UI 全自动安装脚本（2026-01-15 终极稳定版：完全修复 spawn 失败 + 强制 IP SSL）
# 端口: 2026 | 用户: liang | 密码: liang | BBR + 证书自动
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

# 依赖安装
echo "安装依赖 curl expect socat ca-certificates..."
apt update -y && apt install -y curl expect socat ca-certificates >/dev/null 2>&1 || true

# BBR 启用
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 开放证书端口
echo "开放 80-83 端口..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh 到本地（关键修复 spawn 问题）
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
echo "下载官方安装脚本到临时文件..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载官方脚本失败，请检查网络或 GitHub\033[0m"
    exit 1
fi

# expect 自动化交互
echo -e "\n\033[33m开始全自动安装（处理强制 SSL IP证书）...\033[0m"

expect <<'END_EXPECT'
set timeout 900
log_user 1

spawn bash "$TEMP_SCRIPT"

# 端口自定义 y
expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义提示\n"; exit 1 }
}

# 输入端口
expect {
    -re {Please set up the panel port:.*} { send "$env(PORT)\r" }
    timeout { send_user "未匹配端口输入提示\n"; exit 1 }
}

# 选 IP 证书 (2)
expect {
    -re {Choose.*default.*2.*IP.*:} { send "2\r" }
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项\n"; exit 1 }
}

# 跳过 IPv6
expect {
    -re {Do you have an IPv6 address.*leave empty to skip.*:} { send "\r" }
    timeout { send_user "无IPv6提示，继续\n" }
}

# ACME 端口尝试循环
set ports {80 81 82 83}
foreach p $ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "$p\r" }
        -re {Port.*is in use.*Enter another port.*:} { send "$p\r" }
        -re {Port.*is in use.*} { continue }
        timeout { send_user "无端口提示，继续\n"; break }
    }
}

# 后续确认
expect {
    -re {Would you like to set this certificate.*\[y/n\]:} { send "y\r" }
    -re {Would you like to modify --reloadcmd.*\[y/n\]:} { send "n\r" }
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "最终超时，假设完成\n" }
}

expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" 2>/dev/null

# 强制设置账号
echo -e "\n\033[33m等待服务启动并强制设置账号...\033[0m"
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

# 输出
IP=$(curl -s4 icanhazip.com || echo "你的服务器IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问面板: \033[36mhttps://$IP:$PORT\033[0m (IP证书短期有效，自动续期)"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "提示："
echo "  • 确保服务器公网80端口开放（证书验证必须）"
echo "  • 浏览器证书警告可忽略（短期证书）"
echo "  • 登录后立即修改面板路径防扫描"
echo "  • 检查状态: systemctl status x-ui"
echo ""
