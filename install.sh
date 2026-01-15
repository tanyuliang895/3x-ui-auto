#!/bin/bash
# 3X-UI 一键全自动安装/更新脚本（零交互 + 最新 Xray + BBR）
# GitHub: https://github.com/tanyuliang895/3x-ui-auto
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

USERNAME="liang"
PASSWORD="liang"
PORT="2026"
WEB_PATH="/liang"  # 自定义路径，防扫描，访问: http://IP:PORT/liang/
BBR=true

echo -e "\n🚀 零交互安装/更新 3X-UI 开始..."
echo "用户名: $USERNAME | 密码: $PASSWORD | 端口: $PORT | 路径: $WEB_PATH | Xray: 自动最新版"

# 启用 BBR
if [ "$BBR" = true ]; then
    echo "→ 启用 BBR 加速..."
    if ! grep -q "bbr" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl -p
    fi
    echo "BBR 已启用（当前: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')）"
fi

# 安装必要工具（安静模式）
echo "→ 安装 curl wget tar unzip..."
apt update -yqq && apt install -yqq curl wget tar unzip >/dev/null 2>&1 || yum install -y curl wget tar unzip >/dev/null 2>&1

# 获取服务器 IP
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的IP")

echo "→ 执行官方脚本（自动安装最新 3X-UI + 最新 Xray，无版本选择）..."

# 核心：喂入官方交互（顺序：继续 y → 自定义端口 y → 端口 → 用户 → 密码 → 路径）
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
y
$PORT
$USERNAME
$PASSWORD
$WEB_PATH
EOF

sleep 6  # 等待服务启动

# 可选：强制更新到最新 Xray（如果捆绑不是最新，可加这行）
# x-ui update xray

echo -e "\n✅ 安装/更新完成！（Xray 核心已自动使用最新版）"
echo "面板地址: http://$IP:$PORT$WEB_PATH/"
echo "用户名: $USERNAME   密码: $PASSWORD"
echo "端口: $PORT   Web路径: $WEB_PATH （登录记得加路径）"
echo "管理命令: x-ui （restart / update / update xray 等）"
echo "安全提醒：立即登录面板改密码 + 设置 SSL + 装 Fail2Ban"
echo "安全上网，玩得开心！🚀"

exit 0
