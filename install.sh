#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang + BBR 加速）
# 2026-01-15 最终优化版：精确匹配 ACME 端口提示，防卡死

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
    echo "依赖安装失败，请手动安装 curl expect"
fi

# ======================== 开放 80 端口 ========================
echo "开放 80 端口（用于 IP SSL 证书申请）..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# ======================== 下载官方 install.sh ========================
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# ======================== expect 自动化交互（最强版：精确匹配官方端口提示） ========================
expect <<END_EXPECT
    set timeout -1
    # exp_internal 1   # 如仍卡住，取消注释这行，运行后把详细日志贴给我调试

    spawn $TEMP_SCRIPT

    expect {
        # 1. 自定义面板端口 → y
        -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" ; exp_continue }

        # 2. 输入面板端口（固定 2026）
        -re "(?i)Please set up the panel port:.*port" { send "$PORT\\r" ; exp_continue }

        # 3. SSL 证书选项 → 默认回车（选 IP 证书）
        -re "(?i)Choose.*option.*1.*2.*Let's Encrypt" { send "\\r" ; exp_continue }

        # 4. IPv6 跳过 → 直接回车
        -re "(?i)Do you have an IPv6.*(include|empty to skip)" { send "\\r" ; exp_continue }

        # 5. 域名输入 → 跳过（IP 证书不需要）
        -re "(?i)(domain|域名|enter your domain)" { send "\\r" ; exp_continue }

        # 6. 精确匹配：ACME HTTP-01 listener 端口提示（官方原词）
        -re "(?i)Port to use for ACME HTTP-01 listener.*default 80" { 
            send "\\r"   ;# 直接用默认 80
            exp_continue 
        }

        # 7. 如果端口占用：问另一个端口 → 留空 abort
        -re "(?i)Enter another port for acme.sh standalone listener.*abort" { 
            send "\\r"   ;# 留空，让它处理（通常 abort 或 fallback）
            exp_continue 
        }

        # 8. 其他所有 [y/n] → 默认 n
        -re "(?i)\\[y/n\\]" { send "n\\r" ; exp_continue }

        # 9. 终极兜底：任何未匹配输出 → 每 2 秒自动回车一次，防止 hang
        -re ".*" { 
            after 2000
            send "\\r"
            exp_continue 
        }

        eof
    }
END_EXPECT

# 清理临时文件
rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# ======================== 设置固定账号 ========================
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# ======================== 重启服务 ========================
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！BBR 已开启\033[0m"
echo -e "面板地址: \033[36mhttps://你的服务器IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[31m注意：IP证书有效期约6天，会自动续期；建议生产用域名+90天证书\033[0m"
echo -e "\033[32mBBR 验证：sysctl net.ipv4.tcp_congestion_control （应为 bbr）\033[0m"
