#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 更新日期: 2026-01-10，完美匹配官方当前提示 + 修复 spawn bug

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m固定端口: $PORT  用户名: $USERNAME  密码: $PASSWORD\033[0m"
echo -e "\033[33m自动迁移旧数据 + 申请 IP SSL（需 80 端口开放）\033[0m\n"

# 安装依赖（curl + expect）
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动 apt/yum install curl expect"
fi

# 开放 80 端口（IP SSL 必须）
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 先下载官方 install.sh 到临时文件（最稳方式，避免 process substitution bug）
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect 自动化交互（超级宽松 + 精确匹配官方 2026-01-10 提示）
expect <<END_EXPECT
    set timeout -1

    spawn "$TEMP_SCRIPT"

    # 1. 是否自定义端口（官方完整提示，含括号）
    expect -re "(?i)Would you like to customize the Panel Port settings\\?.*\\[y/n\\]" { send "y\\r" }

    # 2. 输入端口（官方文字）
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # 3. SSL 证书选择（默认 2 - IP证书，回车即可）
    expect -re "(?i)Choose an option.*\\(default 2 for IP\\):" { send "\\r" }

    # 4. IPv6 提示（IP方式下出现，留空跳过）
    expect -re "(?i)Do you have an IPv6 address to include\\?.*leave empty to skip" { send "\\r" }

    # 5. 其他可能的 y/n 提示（证书确认、reloadcmd、set for panel 等）→ 默认 n 或跳过
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re "(?i)(set this certificate|modify|reloadcmd|continue|Would you like to set)" { send "n\\r" }

    # 最终兜底：任何剩余提示都回车（防止意外卡住）
    expect -re ".*" { send "\\r" }
    expect eof
END_EXPECT

# 清理临时文件
rm -f "$TEMP_SCRIPT"

# 强制设置固定账号（覆盖官方随机生成的）
echo "强制设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1

# 重启服务
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！一切全自动固定\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui （可更新/重启/查看日志/修改SSL等）\033[0m"
echo -e "\033[31m注意：当前为固定弱密码，仅测试推荐！生产环境请立即修改为强密码\033[0m"
