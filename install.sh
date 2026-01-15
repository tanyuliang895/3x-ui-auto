#!/bin/bash

# ------------------- 你的配置 -------------------
PANEL_PORT=2026
DESIRED_USERNAME="liang"
DESIRED_PASSWORD="liang"
SSL_OPTION=2  # 2 为 IP 证书（默认选这个，零交互）
# ------------------- 配置结束 -------------------

# 确保 expect 已安装（零交互方式）
if ! command -v expect &> /dev/null; then
    if command -v apt &> /dev/null; then
        apt update -qq && apt install -y expect >/dev/null 2>&1
    elif command -v yum &> /dev/null; then
        yum install -y expect >/dev/null 2>&1
    elif command -v dnf &> /dev/null; then
        dnf install -y expect >/dev/null 2>&1
    else
        echo "无法自动安装 expect，请手动安装后重试。"
        exit 1
    fi
fi

# 清理旧安装（防止干扰）
systemctl stop x-ui >/dev/null 2>&1 || true
systemctl disable x-ui >/dev/null 2>&1 || true
rm -f /etc/systemd/system/x-ui.service
systemctl daemon-reload >/dev/null 2>&1

# 下载官方最新脚本
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o /tmp/3x-ui-install.sh
chmod +x /tmp/3x-ui-install.sh

echo "开始完全零交互安装 3x-ui（端口: $PANEL_PORT，SSL: IP证书）..."

# 用 expect 自动化所有可能交互（基于官方脚本提示顺序）
expect <<EOF
spawn /tmp/3x-ui-install.sh

# 端口自定义部分
expect {
    "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]:" { send "y\r" }
    timeout { send_user "超时未出现端口自定义提示\n"; exit 1 }
}
expect {
    "Please set up the panel port:" { send "$PANEL_PORT\r" }
    timeout { send_user "超时未出现端口输入提示\n"; exit 1 }
}

# SSL 主选择（选 2: IP证书）
expect {
    "Choose an option:" { send "$SSL_OPTION\r" }
    timeout { send_user "超时未出现SSL选项\n"; exit 1 }
}

# IP证书特定：ACME端口（默认80，回车）
expect {
    "Port to use for ACME HTTP-01 listener (default 80):" { send "\r" }
    timeout {}
}

# 如果端口占用：输入另一个端口（假设不占用，这里设一个备用如81；如果经常占用，可改）
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort):" { send "81\r" }
    timeout {}
}

# IPv6（留空跳过）
expect {
    "Do you have an IPv6 address to include? (leave empty to skip):" { send "\r" }
    timeout {}
}

# reloadcmd 修改？（选 n 跳过）
expect {
    "Would you like to modify --reloadcmd for ACME? (y/n):" { send "n\r" }
    timeout {}
}

# 设置证书到面板？（选 y）
expect {
    "Would you like to set this certificate for the panel? (y/n):" { send "y\r" }
    timeout {}
}

# 捕获其他可能提示或结束
expect eof
EOF

# 清理临时文件
rm -f /tmp/3x-ui-install.sh

# 检查安装是否成功
if systemctl is-active --quiet x-ui; then
    echo "3x-ui 安装成功！端口: $PANEL_PORT"

    # 等待面板启动
    sleep 5

    # 零交互修改用户名/密码
    echo "正在零交互修改用户名/密码为 $DESIRED_USERNAME / $DESIRED_PASSWORD ..."
    x-ui setting -username "$DESIRED_USERNAME" -password "$DESIRED_PASSWORD" >/dev/null 2>&1

    # 显示信息
    echo ""
    echo "====================================="
    echo "安装完成！访问面板："
    echo "http://你的服务器IP:$PANEL_PORT (或 https 如果证书成功)"
    echo "用户名: $DESIRED_USERNAME"
    echo "密码: $DESIRED_PASSWORD"
    echo "====================================="
else
    echo "安装失败！请检查日志：journalctl -u x-ui -xe"
    echo "或手动运行官方脚本调试。"
fi
