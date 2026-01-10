#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 最终修复: 2026-01-10，修正 expect 变量展开 + 宽松匹配官方提示

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m"
echo -e "\033[33m申请 IP SSL（80端口必须开放）\033[0m\n"

# 依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖..."
    apt update -y && apt install -y curl expect || yum install -y curl expect || dnf install -y curl expect || echo "依赖失败，请手动安装"
fi

# 开放80端口
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 使用双引号 heredoc 让 bash 展开 $TEMP_SCRIPT
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    # 端口 y
    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }

    # 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 选择 - 宽松匹配
    expect -re "(?i)Choose an option" { send "\\r" }

    # IPv6 跳过
    expect -re "(?i)Do you have an IPv6.*skip" { send "\\r" }

    # 域名跳过
    expect -re "(?i)(domain|域名)" { send "\\r" }

    # y/n 默认 n
    expect -re "\\[y/n\\]" { send "n\\r" }

    # 兜底
    expect -re ".*" { send "\\r" }
    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 设置账号
echo "设置账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m完成！\033[0m"
echo "面板: https://你的IP:$PORT"
echo "用户: $USERNAME  密码: $PASSWORD"
echo "\033[31mIP证书6天有效，生产用域名\033[0m"
