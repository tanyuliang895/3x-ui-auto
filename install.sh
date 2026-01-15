#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互 + 固定端口 2026 + 固定账号 liang/liang + BBR 加速）
# 已修复 expect 兼容性问题（支持官方新交互）

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

# ======================== 放行 80 端口 ========================
echo "开放 80 端口（用于 IP SSL）..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# ======================== 下载官方 install.sh ========================
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# ======================== expect 自动化交互 ========================
expect <<'END_EXPECT'
    set timeout -1

    spawn "$::env(TEMP_SCRIPT)"

    # 通用 eat 输出
    expect {
        -re ".*" {}
        timeout {}
    }

    # 自动化所有交互
    expect {
        -re "(?i)Would you like to customize" { send "y\r"; exp_continue }
        -re "(?i)Please set up the panel port" { send "$::env(PORT)\r"; exp_continue }
        -re "(?i)Choose.*option" { send "\r"; exp_continue }
        -re "(?i)Do you have an IPv6" { send "\r"; exp_continue }
        -re "(?i)(domain|域名|enter your domain)" { send "\r"; exp_continue }
        -re "\\[y/n\\]" { send "n\r"; exp_continue }
        -re ".*" { send "\r"; exp_continue }
        eof
    }
END_EXPECT

# 清理临时
rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# ======================== 设置固定账号 ========================
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# ======================== 重启服务 ========================
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！BBR 已开启\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[31mIP证书仅6天有效，生产环境建议改域名证书\033[0m"
echo -e "\033[32mBBR 加速已永久启用！可运行 sysctl net.ipv4.tcp_congestion_con]()
