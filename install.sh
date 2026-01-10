#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，默认用户名: liang, 密码: liang, 端口: 2024）
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)
# 优势：自动迁移旧数据、固定端口、IP SSL 证书（需 80 端口开放）

USERNAME="liang"
PASSWORD="liang"
PORT="2024"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，全自动）...\033[0m"
echo -e "\033[33m默认: 用户名 $USERNAME / 密码 $PASSWORD / 端口 $PORT\033[0m"
echo -e "\033[33m自动迁移旧数据 + 申请 IP SSL（需 80 端口开放）\033[0m"
echo ""

# 安装依赖
if ! command -v curl &> /dev/null || ! command -v expect &> /dev/null; then
    echo "安装依赖 curl expect..."
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update -y && apt-get install -y curl expect
    elif [ -x "$(command -v yum)" ]; then
        yum install -y curl expect
    elif [ -x "$(command -v dnf)" ]; then
        dnf install -y curl expect
    else
        echo "不支持的系统！请手动安装 curl/expect。"
        exit 1
    fi
fi

# 开放 80 端口
echo "开放 80 端口..."
if command -v ufw &> /dev/null; then
    ufw allow 80 &> /dev/null || true
    ufw reload &> /dev/null || true
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --add-port=80/tcp --permanent &> /dev/null || true
    firewall-cmd --reload &> /dev/null || true
fi

# 优化 expect：先强制自定义端口 (y)，再输入固定值 + 处理所有常见提示
expect <<EOF
    set timeout -1
    spawn bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    # 先处理“是否自定义端口”提示（强制 y 固定端口）
    expect "customize the Panel Port settings?* [y/n]*" { send "y\r" }
    expect "Please set up the panel port*" { send "$PORT\r" }

    # 用户名/密码
    expect "username*" { send "$USERNAME\r" }
    expect "password*" { send "$PASSWORD\r" }
    expect "password*" { send "$PASSWORD\r" }

    # SSL 默认 IP 证书（回车选 2）
    expect "Choose an option*" { send "\r" }

    # 其他可能提示（回车默认或跳过）
    expect {
        "y/n*" { send "n\r" }
        "domain*" { send "\r" }
        "IPv6*" { send "\r" }
        eof
    }

    expect eof
EOF

echo -e "\n\033[32m安装完成！\033[0m"
echo "面板地址: https://你的IP:$PORT"
echo "用户名: $USERNAME  密码: $PASSWORD"
echo -e "\033[33m管理: x-ui（可更新/SSL/备份）\033[0m"
echo -e "\033[33mSSL 失败？用 x-ui 菜单重申请（检查 80 端口）\033[0m"
