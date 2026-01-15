#!/bin/bash

# ------------------- 你的专属配置 -------------------
PANEL_PORT=2026
USERNAME="liang"
PASSWORD="liang"
SSL_OPTION=2  # 固定选2：IP证书（官方默认且最匹配你的需求）
# ------------------- 配置结束 -------------------

# 自动安装 expect（如果没有）
if ! command -v expect >/dev/null 2>&1; then
    echo "安装 expect 中..."
    if command -v apt >/dev/null 2>&1; then
        apt update -qq && apt install -y expect >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y expect >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y expect >/dev/null 2>&1
    else
        echo "无法自动安装 expect，请手动安装（apt/yum/dnf install expect）后重试。"
        exit 1
    fi
fi

# 清理旧残留（防止干扰）
systemctl stop x-ui >/dev/null 2>&1 || true
systemctl disable x-ui >/dev/null 2>&1 || true
rm -f /etc/systemd/system/x-ui.service
systemctl daemon-reload >/dev/null 2>&1

echo "开始完全零交互安装 3x-ui（端口=$PANEL_PORT，用户名/密码=liang/liang，SSL=IP证书）..."

# 下载官方最新 install.sh
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o /tmp/3x-ui-install.sh
chmod +x /tmp/3x-ui-install.sh

# expect 自动化所有交互（基于官方最新提示精确匹配）
expect <<'EOF'
set timeout 120

spawn /tmp/3x-ui-install.sh

# 1. 端口自定义提示（只在有默认凭证时出现，但我们强制处理）
expect {
    "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]:" { send "y\r" }
    timeout { }
}

expect {
    "Please set up the panel port:" { send "$env(PANEL_PORT)\r" }
    timeout { }
}

# 2. SSL 证书选择（核心：选2 IP证书）
expect {
    "Choose an option (default 2 for IP):" { send "$env(SSL_OPTION)\r" }
    timeout { send_user "未出现SSL选择提示，可能脚本已变或跳过\n" }
}

# 3. IPv6 输入（留空跳过）
expect {
    "Do you have an IPv6 address to include? (leave empty to skip):" { send "\r" }
    timeout { }
}

# 4. ACME 端口（默认80）
expect {
    "Port to use for ACME HTTP-01 listener (default 80):" { send "\r" }
    timeout { }
}

# 5. 如果80占用，输入备用端口（多层尝试：81 → 82 → abort）
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort):" { send "81\r" }
    timeout { }
}
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort):" { send "82\r" }
    timeout { }
}
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort):" { send "\r" }  ;# 最终abort，避免卡死
    timeout { }
}

# 6. reloadcmd 修改（选n，不改）
expect {
    "Would you like to modify --reloadcmd for ACME? (y/n):" { send "n\r" }
    timeout { }
}

# 7. 设置证书到面板（选y）
expect {
    "Would you like to set this certificate for the panel? (y/n):" { send "y\r" }
    timeout { }
}

# 等待脚本结束
expect eof
EOF

# 清理临时脚本
rm -f /tmp/3x-ui-install.sh

# 检查服务是否运行
sleep 8  # 给点时间让服务启动
if systemctl is-active --quiet x-ui; then
    echo "3x-ui 核心安装成功！"

    # 立即修改用户名/密码（官方支持此命令）
    echo "修改用户名/密码为 liang / liang ..."
    x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1

    echo ""
    echo "======================================"
    echo "安装 & 配置完成！"
    echo "访问地址： http://你的服务器IP:$PANEL_PORT"
    echo "          （如果IP证书成功，则 https 也可用）"
    echo "用户名: $USERNAME"
    echo "密码  : $PASSWORD"
    echo ""
    echo "注意：IP证书只有6天有效，建议尽快登录面板后改更强密码 + 伪装路径（webBasePath）"
    echo "防火墙：确保 $PANEL_PORT 已开放（ufw allow $PANEL_PORT 或 firewall-cmd）"
    echo "日志查看： journalctl -u x-ui -f"
    echo "======================================"
else
    echo "安装失败！可能原因："
    echo "- 80/81/82端口全被占用（证书验证失败）"
    echo "- 网络问题（无法访问GitHub或Let's Encrypt）"
    echo "- 系统兼容性（检查是否支持 acme.sh）"
    echo ""
    echo "调试建议："
    echo "1. 手动运行官方脚本看卡在哪里： bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)"
    echo "2. 查看日志： journalctl -u x-ui -xe"
    echo "3. 临时关闭防火墙测试： ufw disable 或 systemctl stop firewalld"
fi
