#!/bin/bash
# 3X-UI 零交互一键安装脚本（自动 HTTPS 加密 + BBR）
# 作者：宇亮 @tanyuliang895
# 仓库：https://github.com/tanyuliang895/3x-ui-auto

set -e

### ===== 基础参数 =====
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
WEB_PATH="/liang"

# 如需真正浏览器信任 HTTPS，请填写域名并确保已解析到本机 IP
DOMAIN=""   # 例如：panel.example.com

EMAIL="admin@xui.local"
IP=$(curl -s4 icanhazip.com)

echo -e "\n[+] 零交互安装 3X-UI + HTTPS 加密访问\n"

### ===== 1. 启用 BBR =====
echo "[+] 启用 BBR 加速..."
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo "[+] BBR 已启用"

### ===== 2. 安装 3X-UI（官方脚本）=====
echo "[+] 安装 3X-UI 面板..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
y
$PORT
$USERNAME
$PASSWORD
$WEB_PATH
EOF

### ===== 3. HTTPS 证书配置 =====
echo "[+] 配置 HTTPS 访问..."

if [[ -n "$DOMAIN" ]]; then
    echo "[+] 检测到域名：$DOMAIN"
    echo "[+] 使用 ZeroSSL 申请公网受信任证书"

    x-ui settings <<EOF
11
2
EOF

    x-ui ssl <<EOF
2
$DOMAIN
$EMAIL
y
EOF

    HTTPS_NOTE="浏览器受信任 HTTPS（ZeroSSL 域名证书）"
    ACCESS_HOST="$DOMAIN"

else
    echo "[!] 未配置域名，使用本地自签 HTTPS 证书"
    echo "[!] 浏览器访问 IP 时会提示“不安全”，属于正常现象"

    x-ui settings <<EOF
11
1
EOF

    HTTPS_NOTE="HTTPS 加密连接（自签证书，非浏览器信任）"
    ACCESS_HOST="$IP"
fi

sleep 5
x-ui restart

### ===== 4. 完成信息 =====
echo -e "\n================ 安装完成 ================\n"
echo "面板地址: https://$ACCESS_HOST:$PORT$WEB_PATH/"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "HTTPS 状态: $HTTPS_NOTE"
echo
echo "安全建议："
echo " - 登录后立即修改密码"
echo " - 修改默认端口 / 路径"
echo " - 启用 Fail2Ban 或防火墙"
echo
echo "脚本作者：宇亮 @tanyuliang895"
echo "=========================================\n"
