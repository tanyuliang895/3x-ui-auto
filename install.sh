#!/bin/bash
# 3X-UI 一键安装 + HTTP（端口 2026） + BBR
# 作者：优化版 by 宇亮
# 特点：HTTP访问，无HTTPS，无503

set -e

### ===== 基础参数 =====
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
WEB_PATH="/liang"

IP=$(curl -s4 icanhazip.com)

echo -e "\n[+] 开始零交互安装 3X-UI + HTTP访问\n"

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

### ===== 3. 禁用 HTTPS，启用 HTTP =====
echo "[+] 禁用 3X-UI HTTPS 模式，确保使用 HTTP..."
x-ui setting -s https false
x-ui restart

### ===== 4. 确认面板已监听端口 =====
echo "[+] 检查 3X-UI 面板是否在端口 $PORT 监听..."
sleep 2
LISTEN=$(ss -tunlp | grep $PORT || true)
if [[ -z "$LISTEN" ]]; then
    echo "[!] 面板未监听端口 $PORT，尝试再次启动..."
    x-ui restart
    sleep 2
    LISTEN=$(ss -tunlp | grep $PORT || true)
    if [[ -z "$LISTEN" ]]; then
        echo "[✖] 面板仍未启动，请检查日志：journalctl -u x-ui -n 50"
        exit 1
    fi
fi
echo "[+] 面板正常启动，端口 $PORT 已就绪"

### ===== 5. 完成信息 =====
echo -e "\n================ 安装完成 ================\n"
echo "面板地址: http://$IP:$PORT$WEB_PATH/"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "协议: HTTP（无加密，端口 $PORT）"
echo
echo "安全建议："
echo " - 登录后立即修改密码"
echo " - 修改默认端口 / 路径"
echo " - 启用防火墙保护面板"
echo
echo "脚本作者：优化版 by 宇亮"
echo "=========================================\n"
