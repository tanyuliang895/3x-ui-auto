#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 修复日期: 2026-01-10，解决 expect heredoc 变量不展开 + 匹配官方最新提示

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，全自动）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m"
echo -e "\033[33m申请 IP SSL（80端口必须开放）\033[0m\n"

# 安装依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动 apt/yum install curl expect"
fi

# 开放 80 端口
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 块 - 使用双引号 heredoc 让 $TEMP_SCRIPT 展开
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    # 1. 端口自定义 y
    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }

    # 2. 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # 3. SSL 选择 - 宽松匹配关键词，回车选默认 IP
    expect -re "(?i)Choose an option" { send "\\r" }

    # 4. IPv6 跳过
    expect -re "(?i)Do you have an IPv6.*skip" { send "\\r" }

    # 5. 域名/其他输入跳过
    expect -re "(?i)(domain|域名|enter)" { send "\\r" }

    # 6. y/n 默认 n
    expect -re "\\[y/n\\]" { send "n\\r" }

    # 兜底任何剩余提示回车
    expect -re ".*" { send "\\r" }
    expect eof
END_EXPECT

# 清理
rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 设置固定账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[31mIP证书6天有效，生产用域名证书\033[0m"
