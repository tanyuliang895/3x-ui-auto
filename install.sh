#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)
# 优势：自动迁移旧数据、固定一切、默认 IP SSL（需 80 端口开放）

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m固定端口: $PORT  用户名: $USERNAME  密码: $PASSWORD\033[0m"
echo -e "\033[33m自动迁移旧数据 + 申请 IP SSL（需 80 端口开放）\033[0m"
echo ""

# 安装依赖
if ! command -v curl &> /dev/null || ! command -v expect &> /dev/null; then
    echo "安装依赖 curl expect..."
    apt-get update -y && apt-get install -y curl expect || yum install -y curl expect || dnf install -y curl expect || echo "依赖失败，请手动安装"
fi

# 开放 80 端口
echo "开放 80 端口..."
ufw allow 80 &> /dev/null || true
ufw reload &> /dev/null || true
firewall-cmd --add-port=80/tcp --permanent &> /dev/null || true
firewall-cmd --reload &> /dev/null || true

# 全自动安装官方脚本（固定端口 + 默认 IP SSL）
expect <<EOF
    set timeout -1
    spawn bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    # 强制自定义端口 (y)
    expect "customize the Panel Port settings?* [y/n]*" { send "y\r" }

    # 输入固定端口
    expect "Please set up the panel port*" { send "$PORT\r" }

    # SSL 默认 IP 证书 (回车选 2)
    expect "Choose an option*" { send "\r" }

    # IPv6 等其他提示（回车跳过）
    expect "IPv6 address*" { send "\r" }
    expect {
        "y/n*" { send "n\r" }
        "domain*" { send "\r" }
        eof
    }

    expect eof
EOF

# 安装完成后，强制改成固定账号（覆盖随机生成的）
echo "强制设置固定账号 liang/liang..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD"
/usr/local/x-ui/x-ui restart

echo -e "\n\033[32m安装完成！一切全自动固定\033[0m"
echo "面板地址: https://你的IP:$PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo -e "\033[33m管理命令: x-ui（可更新/重启/SSL 等）\033[0m"
echo -e "\033[33m注意：固定弱密码有风险，建议生产环境改强密码\033[0m"
