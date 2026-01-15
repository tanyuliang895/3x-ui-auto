#!/bin/bash
# 3X-UI 全自动安装脚本（修复 spawn <(curl) 失败 - 使用本地临时文件）
# 端口: 2026 | 用户: liang | 密码: liang | BBR + 强制 IP SSL

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装 (端口: \033[32m$PORT\033[0m | 用户/密码: $USERNAME/$PASSWORD)"
echo -e "\033[36m========================================\033[0m\n"

# root
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
apt update -y && apt install -y curl expect socat ca-certificates >/dev/null 2>&1 || true

# BBR
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 端口开放
echo "开放 80-83 端口..."
ufw allow 80:83/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80:83 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本到本地文件（解决 spawn 问题）
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
echo "下载官方脚本到 $TEMP_SCRIPT..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载失败\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

# expect 自动化
echo -e "\n\033[33m开始自动化安装...\033[0m"

expect <<'END_EXPECT'
set timeout 900
log_user 1

spawn bash "$TEMP_SCRIPT"

expect {
    -re {Would you like to customize.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n"; exit 1 }
}

expect {
    -re {Please set up the panel port:.*} { send "$env(PORT)\r" }
    timeout { send_user "未匹配端口输入\n"; exit 1 }
}

expect {
    -re {Choose.*option.*default.*2.*} { send "2\r" }
    -re {Choose SSL certificate setup method:.*} { send "2\r" }
    timeout { send_user "未匹配 SSL 选项\n"; exit 1 }
}

expect {
    -re {Do you have an IPv6 address.*leave empty.*:} { send "\r" }
    timeout { send_user "无IPv6，继续\n" }
}

# 端口冲突循环
set ports {80 81 82 83}
foreach p $ports {
    expect {
        -re {Port to use for ACME HTTP-01 listener.*default 80.*:} { send "$p\r" }
        -re {Port.*is in use.*Enter another.*:} { send "$p\r" }
        -re {Port.*is in use.*} { continue }
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
END_EXPECT

rm -f "$TEMP_SCRIPT"

# 设置账号
echo -e "\n\033[33m等待设置账号...\033[0m"
sleep 20
for i in {1..40}; do
    if /usr/local/x-ui/x-ui setting --help >/dev/null 2>&1; then
        /usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" >/dev/null 2>&1
        echo -e "\033[32m账号设置完成！\033[0m"
        break
    fi
    sleep 5
done

/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问: https://$IP:$PORT"
echo -e "用户名: $USERNAME"
echo -e "密码: $PASSWORD"
echo ""
echo "提示：公网80端口必须开放。登录后改路径。"
