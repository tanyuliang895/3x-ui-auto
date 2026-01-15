#!/bin/bash
# 3X-UI 全自动安装脚本（完全跳过 SSL 强制版 + BBR + 端口 2026 + liang/liang）
# 访问: http://你的IP:2026

set -e

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "   3X-UI 全自动安装（跳过 SSL）"
echo -e "   端口: \033[32m$PORT\033[0m | 用户名: \033[32m$USERNAME\033[0m | 密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# root 检查
[ "$(id -u)" != "0" ] && { echo -e "\033[31m必须 root 执行！\033[0m"; exit 1; }

# 依赖
echo "安装依赖..."
apt update -y && apt install -y curl wget tar expect socat ca-certificates >/dev/null 2>&1 || true

# BBR 永久启用
echo -e "\n\033[33m启用 BBR...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 开放面板端口
echo "开放端口 $PORT..."
ufw allow "$PORT"/tcp >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT >/dev/null 2>&1 || true

# 下载官方 install.sh
TEMP_SCRIPT="/tmp/3x-ui-install.sh"
echo "下载官方脚本..."
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载失败\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

# patch 跳过 SSL（注释掉所有证书相关代码）
echo "跳过 SSL 强制设置..."
sed -i '/SSL Certificate Setup/d' "$TEMP_SCRIPT"
sed -i '/Choose SSL certificate setup method/d' "$TEMP_SCRIPT"
sed -i '/Let'\''s Encrypt/d' "$TEMP_SCRIPT"
sed -i '/acme.sh/d' "$TEMP_SCRIPT"
sed -i '/read -r -p "Choose an option/d' "$TEMP_SCRIPT"
sed -i '/read -r -p "Port to use for ACME/d' "$TEMP_SCRIPT"
sed -i '/read -r -p "Do you have an IPv6/d' "$TEMP_SCRIPT"
sed -i '/read -r -p "Would you like to set this certificate/d' "$TEMP_SCRIPT"
sed -i 's/echo "SSL Certificate Setup (MANDATORY)"/echo "SSL 已跳过（手动添加）"/g' "$TEMP_SCRIPT"

# 运行 patch 后的脚本（expect 只处理端口）
echo -e "\n\033[33m运行 patch 版脚本...\033[0m"

expect <<EOF
set timeout 600
log_user 1

spawn bash "$TEMP_SCRIPT"

expect {
    -re {Would you like to customize the Panel Port settings.*\[y/n\]:} { send "y\r" }
    timeout { send_user "未匹配端口自定义\n" }
}

expect {
    -re {Please set up the panel port:.*} { send "$PORT\r" }
    timeout { send_user "未匹配端口输入\n" }
}

# 其他所有提示默认 y 或跳过
expect {
    -re {\[y/n\]:} { send "y\r" }
    eof { }
    timeout { send_user "超时，假设完成\n" }
}

expect eof
EOF

rm -f "$TEMP_SCRIPT" 2>/dev/null

# 手动补齐服务文件（防止未创建）
echo "补齐服务文件..."
cat > /etc/systemd/system/x-ui.service <<EOF
[Unit]
Description=x-ui Service
After=network.target

[Service]
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui

# 强制设置账号（覆盖官方随机）
echo -e "\n\033[33m设置账号...\033[0m"
sleep 10
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$PORT" || true
/usr/local/x-ui/x-ui restart

IP=$(curl -s4 icanhazip.com || echo "你的IP")
echo -e "\n\033[32m安装完成！\033[0m"
echo -e "访问面板: \033[36mhttp://$IP:$PORT\033[0m （HTTP 方式）"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo ""
echo "重要提示："
echo "  • 登录后**立即修改面板路径** (webBasePath) 防扫描"
echo "  • 检查服务: systemctl status x-ui"
echo "  • 后续加 SSL: 面板内 SSL证书 → 选2 (IP证书) → 试端口 80"
echo "  • 卸载: /usr/local/x-ui/x-ui uninstall"
echo ""
