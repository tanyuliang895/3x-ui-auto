#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 更新: 2026-01-10，精确匹配 SSL 选择菜单 + 修复所有已知 bug

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
    echo "依赖安装失败，请手动安装"
fi

# 开放 80 端口（必须）
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本到临时文件
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 精确匹配官方当前提示（2026-01-10）
expect <<'END_EXPECT'
    set timeout -1

    spawn "$TEMP_SCRIPT"

    # 端口自定义
    expect -re "(?i)Would you like to customize the Panel Port settings\?.*\[y/n\]" { send "y\r" }

    # 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\r" }

    # SSL 选择菜单 - 精确匹配当前文字（含 default 2 for IP）
    expect -re "(?i)Choose an option.*\(default 2 for IP\):" { send "\r" }

    # IPv6（IP 方式下）
    expect -re "(?i)Do you have an IPv6 address to include\?.*leave empty to skip" { send "\r" }

    # 后续可能的域名/端口/确认 y/n → 全部 n 或回车（IP 方式通常跳过域名）
    expect -re "(?i)(Please enter your domain|domain name)" { send "\r" }  ;# 跳过域名
    expect -re "\[y/n\]" { send "n\r" }
    expect -re "(?i)(set this certificate|modify|reloadcmd|Would you like to set)" { send "n\r" }

    # 兜底
    expect -re ".*" { send "\r" }
    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT"

# 设置固定账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理: x-ui 命令\033[0m"
echo -e "\033[31m注意: IP证书仅6天有效，生产建议用域名\033[0m"
