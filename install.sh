#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 更新日期: 2026-01-10，完美匹配官方当前提示

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m固定端口: $PORT  用户名: $USERNAME  密码: $PASSWORD\033[0m"
echo -e "\033[33m自动迁移旧数据 + 申请 IP SSL（需 80 端口开放）\033[0m\n"

# 安装依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动安装 curl expect"
fi

# 开放80端口（IP SSL 必须）
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 超级匹配版 expect（精确针对官方当前提示）
expect <<'END_EXPECT'
    set timeout -1

    spawn bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    # 1. 端口自定义提示 - 精确匹配官方文字（含括号）
    expect -re "(?i)Would you like to customize the Panel Port settings\?.*\[y/n\]" { send "y\r" }

    # 2. 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\r" }

    # 3. SSL 选项选择 - 默认回车（选2 IP）
    expect -re "(?i)Choose an option.*\(default 2 for IP\):" { send "\r" }

    # 4. IPv6 提示 - 留空跳过
    expect -re "(?i)Do you have an IPv6 address to include\?.*leave empty to skip" { send "\r" }

    # 5. 可能的证书确认 y/n 或其他 - 默认 n
    expect -re "\[y/n\]" { send "n\r" }
    expect -re "(?i)(set this certificate|modify|reloadcmd|continue)" { send "n\r" }

    # 兜底：任何剩余输入都回车（防意外）
    expect -re ".*" { send "\r" }
    expect eof
END_EXPECT

# 强制设置固定账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1

# 重启服务
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui （可更新/重启/改SSL等）\033[0m"
echo -e "\033[31m注意：弱密码仅测试用，生产环境立即改强密码！\033[0m"
