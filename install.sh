#!/bin/bash
# 3X-UI 终极零交互一键脚本（自动上真 HTTPS 绿锁 + BBR + 最新版）
# 作者：宇亮 @tanyuliang895
# 仓库：https://github.com/tanyuliang895/3x-ui-auto

set -e

USERNAME="liang"
PASSWORD="liang"
PORT="2026"
WEB_PATH="/liang"
EMAIL="admin@$(curl -s4 icanhazip.com).xui.one"   # 自动生成假邮箱，反正 ZeroSSL 也不验证

IP=$(curl -s4 icanhazip.com)

echo -e "\n零交互安装 3X-UI + 自动申请 ZeroSSL 真实 HTTPS 证书（绿锁）\n"

# 1. 启用 BBR
echo "→ 启用 BBR 加速..."
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
echo "BBR 已启用"

# 2. 调用官方脚本（固定参数）
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
y
$PORT
$USERNAME
$PASSWORD
$WEB_PATH
EOF

# 3. 强制使用 ZeroSSL 申请真实 IP 证书（关键核心！）
echo "→ 正在申请 ZeroSSL 真实 HTTPS 证书（90天有效，自动续期）..."
sleep 5

# 切换到 ZeroSSL（最稳定）
sudo x-ui settings <<EOF
11
2
EOF

# 申请证书（使用 ZeroSSL + 假邮箱）
sudo x-ui ssl <<EOF
2
$IP
$EMAIL
y
EOF

sleep 8

# 重启使证书生效
x-ui restart

echo -e "\n全部完成！现在可以直接用 HTTPS 绿锁访问了！\n"
echo "面板地址: https://$IP:$PORT$WEB_PATH/"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "证书类型: ZeroSSL 真实证书（90天有效，已自动续期）"
echo "强烈建议：立即登录改密码 + 开启 Fail2Ban"
echo -e "\n脚本作者：宇亮 @tanyuliang895   玩得开心！\n"
