#!/bin/bash
# 生产级 3X-UI 自动部署脚本
# 功能：系统升级 + 最新内核 + BBR + 最新面板 + 自动账号密码端口
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/x-ui-auto/main/install.sh)

set -e

# ================== 配置参数 ==================
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
# =============================================

echo "========== 1. 升级 Ubuntu 到最新 =========="
apt update -y
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
apt autoremove -y

echo "========== 2. 安装最新 HWE 内核 =========="
apt install -y --install-recommends linux-generic-hwe-$(lsb_release -rs)

echo "========== 3. 启用 BBR (必须在装面板前) =========="
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_ecn=1
net.ipv4.tcp_fastopen=3
EOF
sysctl --system

echo "========== 4. 安装依赖 =========="
apt install -y curl wget sudo

echo "========== 5. 安装最新官方 3X-UI =========="
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "等待面板初始化..."
sleep 6

echo "========== 6. 无交互写入面板配置 =========="
x-ui setting -username ${USERNAME}
x-ui setting -password ${PASSWORD}
x-ui setting -port ${PORT}
x-ui setting -webBasePath /

echo "========== 7. 重启面板 =========="
systemctl restart x-ui

IP=$(curl -4s icanhazip.com || echo "服务器IP")

echo
echo "============== 安装完成 =============="
echo "访问地址: http://${IP}:${PORT}"
echo "用户名: ${USERNAME}"
echo "密码: ${PASSWORD}"
echo
echo "⚠️ 必须执行 reboot 进入新内核，BBR 才真正生效！"
echo "======================================"
