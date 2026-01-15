#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang + BBR 加速）
# 最终优化版 - 基于官方 install.sh 最新提示（2026-01-15），精确 expect 匹配

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR 加速）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m\n"

# ======================== 启用 BBR 加速 ========================
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

# ======================== 安装依赖 ========================
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    { echo -e "\033[31m依赖安装失败，请手动安装 curl expect\033[0m"; exit 1; }
fi

# ======================== 开放 80 端口 ========================
echo "开放 80 端口（用于 IP SSL）..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# ======================== 下载官方 install.sh ========================
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载官方安装脚本失败，请检查网络/GitHub连通性\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

# ======================== expect 自动化交互（精确匹配官方最新提示） ========================
echo "开始自动化安装（expect 部分）... 请耐心等待，日志会显示交互细节"

expect <<'END_EXPECT'
    set timeout 120
    log_user 1   ;# 开启详细日志输出，便于调试（成功后可改成 0）

    spawn bash "$TEMP_SCRIPT"

    # 1. 精确匹配官方端口自定义 [y/n] 提示
    expect {
        "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " { send "y\r" }
        timeout { send_user "\n=== TIMEOUT: 未等到 [y/n] 端口自定义提示 ===\n"; exit 1 }
        eof     { send_user "\n=== EOF: install.sh 意外结束 ===\n"; exit 1 }
    }

    # 2. 精确匹配端口输入提示
    expect {
        "Please set up the panel port: " { send "$env(PORT)\r" }
        timeout { send_user "\n=== TIMEOUT: 未等到 'Please set up the panel port:' ===\n"; exit 1 }
    }

    # 3. SSL 证书选择：默认回车选 2 (IP证书)
    expect {
        "Choose SSL certificate setup method:" { send "2\r" }   ;# 如果没有默认，直接选2
        "Choose an option (default 2 for IP): " { send "\r" }   ;# 有默认2，回车
        timeout { send_user "\n=== TIMEOUT: 未等到 SSL 选项提示 ===\n"; exit 1 }
    }

    # 4. IPv6 提示（如果出现，空回车跳过）
    expect {
        "Do you have an IPv6 address to include? (leave empty to skip): " { send "\r" }
        timeout { send_user "\nNo IPv6 prompt detected, continuing...\n" }
    }

    # 5. ACME 监听端口（默认80，如果占用则尝试备用端口）
    set tried 0
    set alt_ports {81 82 83 84 8080 8000}
    while {$tried < 6} {
        expect {
            "Port to use for ACME HTTP-01 listener (default 80): " { send "80\r" }
            -re "Port \\d+ is in use." {
                incr tried
                set alt [lindex $alt_ports $tried]
                send_user "\nPort in use, trying alternative: $alt\n"
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

    # 6. 其他可能的提示（默认 n 或回车跳过）
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

# 清理临时文件
rm -f "$TEMP_SCRIPT" 2>/dev/null

# ======================== 设置用户名密码（等待服务就绪） ========================
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

# 重启面板
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装/更新完成！\033[0m"
echo -e "面板地址: \033[36mhttps://你的服务器IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m   密码: \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m (start/stop/restart/status 等)"
echo -e "\033[31m注意: IP证书有效期仅约6天！生产环境强烈建议换域名+真实证书\033[0m"
echo -e "\033[32mBBR 已永久启用，可运行 'sysctl net.ipv4.tcp_congestion_control' 验证（显示 bbr 即成功）\033[0m"
echo -e "\033[33m证书续期建议: crontab -e 加一行 '0 3 * * * /root/.acme.sh/acme.sh --renew -d 你的IP --force --home /root/.acme.sh'\033[0m"
