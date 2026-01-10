#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 最终优化版 - 2026/01/10，针对 SSL 菜单 "Choose an option" 宽松匹配

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m固定端口: $PORT | 用户: $USERNAME | 密: $PASSWORD\033[0m"
echo -e "\033[33m自动申请 IP SSL（需 80 端口开放）\033[0m\n"

# 安装依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动安装 curl expect"
fi

# 开放 80 端口
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本到临时文件
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 自动化（SSL 菜单用最宽松匹配）
expect <<'END_EXPECT'
    set timeout -1

    spawn "$TEMP_SCRIPT"

    # 端口自定义 y
    expect -re "(?i)Would you like to customize.*\[y/n\]" { send "y\r" }

    # 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\r" }

    # SSL 选择菜单 - 宽松匹配：只要有 "Choose an option" 就回车选默认 IP
    expect -re "(?i)Choose an option" { send "\r" }

    # IPv6 留空
    expect -re "(?i)Do you have an IPv6.*skip" { send "\r" }

    # 域名跳过
    expect -re "(?i)(domain|域名)" { send "\r" }

    # 所有 y/n → n
    expect -re "\[y/n\]" { send "n\r" }

    # 兜底任何提示都回车
    expect -re ".*" { send "\r" }
    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 设置账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户: \033[36m$USERNAME\033[0m"
echo -e "密码: \033[36m$PASSWORD\033[0m"
echo -e "\033[33mx-ui 命令管理面板\033[0m"
echo -e "\033[31mIP证书6天有效，生产建议用域名\033[0m"
