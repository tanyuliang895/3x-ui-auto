#!/bin/bash

# 配置（你的需求）
PANEL_PORT=2026
USERNAME="liang"
PASSWORD="liang"

# 自动装 expect（如果没有）
if ! command -v expect &> /dev/null; then
    echo "Installing expect..."
    apt update -qq && apt install -y expect || yum install -y expect || dnf install -y expect
fi

# 清理旧的
systemctl stop x-ui 2>/dev/null || true
systemctl disable x-ui 2>/dev/null || true
rm -f /etc/systemd/system/x-ui.service
systemctl daemon-reload 2>/dev/null

echo "Downloading official 3x-ui install script..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o /tmp/install-3x-ui.sh
chmod +x /tmp/install-3x-ui.sh

echo "Starting fully automatic (zero-interaction) installation..."

expect <<'END'
set timeout 180

spawn /tmp/install-3x-ui.sh

# 端口自定义：回答 y
expect {
    "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " { send "y\r" }
    -re {Would you like to customize.*\[y/n\]:}     { send "y\r" }  ;# 模糊匹配防文字微变
    timeout { send_user "\nTimeout on port customize prompt\n" }
}

# 输入端口号
expect {
    "Please set up the panel port: " { send "2026\r" }
    timeout { send_user "\nTimeout on port input\n" }
}

# SSL 选项：选 2 (IP cert)
expect {
    "Choose an option" { send "2\r" }
    -re {Choose an option.*default.*IP} { send "2\r" }
    timeout { send_user "\nTimeout on SSL choose\n" }
}

# IPv6：跳过
expect {
    "Do you have an IPv6 address to include? (leave empty to skip): " { send "\r" }
    timeout { }
}

# ACME 端口：默认 80
expect {
    "Port to use for ACME HTTP-01 listener (default 80): " { send "\r" }
    timeout { }
}

# 如果 80 占用：试 81
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort): " { send "81\r" }
    timeout { }
}
# 如果还占用：试 82
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort): " { send "82\r" }
    timeout { }
}
# 最终放弃（如果还不行）
expect {
    "Enter another port for acme.sh standalone listener (leave empty to abort): " { send "\r" }
    timeout { }
}

# reloadcmd：不改
expect {
    "Would you like to modify --reloadcmd for ACME? (y/n): " { send "n\r" }
    timeout { }
}

# 设置证书到面板：是
expect {
    "Would you like to set this certificate for the panel? (y/n): " { send "y\r" }
    timeout { }
}

expect eof
END

rm -f /tmp/install-3x-ui.sh

sleep 10  # 等服务起来

if systemctl is-active x-ui &>/dev/null; then
    echo "Installation successful!"

    # 改用户名密码
    echo "Setting username/password to liang/liang..."
    x-ui setting -username liang -password liang

    echo ""
    echo "========================================"
    echo "Done! Access panel at:"
    echo "http://你的IP:2026"
    echo "Username: liang"
    echo "Password: liang"
    echo "(https if cert worked)"
    echo "Check status: x-ui"
    echo "Logs: journalctl -u x-ui -e"
    echo "========================================"
else
    echo "Failed. Possible reasons:"
    echo "- Port 80/81/82 blocked/occupied (for cert validation)"
    echo "- Network/firewall blocking Let's Encrypt"
    echo "- Run manual install to debug: bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)"
    echo "Try: ufw allow 80,81,82,2026 ; ufw reload"
fi
