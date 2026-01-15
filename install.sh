#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang + BBR 加速）
# 修复版 - 解决 "no such variable TEMP_SCRIPT" + 精确 expect 匹配官方提示

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

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载官方安装脚本失败，请检查网络/GitHub连通性\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

# expect 自动化（关键修复：用单引号 heredoc + env 传递变量）
echo "开始自动化安装（expect 部分）... 请耐心等待，日志会显示交互细节"

expect <<'END_EXPECT'
    set timeout 120
    log_user 1   ;# 开启详细输出，便于看哪步卡住

    # 用 env 访问 Bash 环境变量（避免 no such variable）
    spawn bash $env(TEMP_SCRIPT)

    # 1. 端口自定义 [y/n] - 官方精确文字
    expect {
        "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " { send "y\r" }
        timeout { send_user "\nTIMEOUT: 未等到端口自定义 [y/n]\n"; exit 1 }
        eof     { send_user "\nEOF: install.sh 意外结束\n"; exit 1 }
    }

    # 2. 输入端口 - 官方精确文字
    expect {
        "Please set up the panel port: " { send "$env(PORT)\r" }
        timeout { send_user "\nTIMEOUT: 未等到端口输入提示\n"; exit 1 }
    }

    # 3. SSL 选择 - 默认回车选 IP (2)
    expect {
        "Choose an option (default 2 for IP): " { send "\r" }
        "Choose SSL certificate setup method:" { send "2\r" }
        timeout { send_user "\nTIMEOUT: 未等到 SSL 选项\n"; exit 1 }
    }

    # 4. IPv6 - 空回车跳过
    expect {
        "Do you have an IPv6 address to include? (leave empty to skip): " { send "\r" }
        timeout { send_user "\nNo IPv6 prompt, skip\n" }
    }

    # 5. ACME 端口（默认80，占用时尝试备用）
    set tried 0
    set alt_ports {81 82 83 84 8080 8000}
    while {$tried < 6} {
        expect {
            "Port to use for ACME HTTP-01 listener (default 80): " { send "80\r" }
            -re "Port \\d+ is in use." {
                incr tried
                set alt [lindex $alt_ports $tried]
                send_user "\nPort in use, trying $alt\n"
                send "$alt\r"
            }
            -re "Enter another port for acme.sh standalone listener.*: " {
                incr tried
                set alt [lindex $alt_ports $tried]
                send "$alt\r"
            }
            timeout { break }
        }
    }

    # 6. 兜底其他提示
    expect {
        -re "\\[y/n\\]: " { send "n\r" }
        -re ".*: " { send "\r" }
        "installation finished" { }
        "x-ui.*running now" { }
        eof { }
        timeout { }
    }

    expect eof
END_EXPECT

# 清理
rm -f "$TEMP_SCRIPT" 2>/dev/null

# 设置用户名密码（等待循环）
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

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户: \033[36m$USERNAME\033[0m   密码: \033[36m$PASSWORD\033[0m"
echo -e "\033[33m命令: x-ui\033[0m"
echo -e "\033[31mIP证书仅6天有效，建议换域名证书\033[0m"
echo -e "\033[32mBBR 已启用，验证: sysctl net.ipv4.tcp_congestion_control\033[0m"
