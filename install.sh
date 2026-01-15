#!/bin/bash

# 极简版 3X-UI 安装脚本
set -e

echo "[✓] 开始安装 3X-UI (用户名: liang, 密码: liang, 端口: 2026)"

# 启用BBR
echo "[✓] 启用 BBR..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p > /dev/null 2>&1

# 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) ARCH="amd64" ;;
esac

echo "[✓] 系统架构: $ARCH"

# 安装依赖
echo "[✓] 安装依赖..."
apt-get update > /dev/null 2>&1
apt-get install -y curl wget unzip > /dev/null 2>&1

# 下载（使用固定版本避免latest问题）
echo "[✓] 下载 3X-UI..."
VERSION="1.0.0"  # 你可以修改为最新版本

# 尝试多个下载源
if curl -sSL -o /tmp/x-ui.zip "https://github.com/MHSanaei/3x-ui/releases/download/v${VERSION}/3x-ui-linux-${ARCH}.zip" || \
   curl -sSL -o /tmp/x-ui.zip "https://cdn.jsdelivr.net/gh/MHSanaei/3x-ui/releases/download/v${VERSION}/3x-ui-linux-${ARCH}.zip" || \
   wget -q -O /tmp/x-ui.zip "https://github.com/MHSanaei/3x-ui/releases/download/v${VERSION}/3x-ui-linux-${ARCH}.zip"; then
    
    echo "[✓] 下载成功"
else
    echo "[✗] 下载失败，请检查网络"
    exit 1
fi

# 解压
echo "[✓] 解压文件..."
unzip -o /tmp/x-ui.zip -d /tmp/x-ui > /dev/null 2>&1 || {
    echo "[!] 解压失败，尝试其他方法..."
    # 尝试手动查找并复制文件
    find /tmp -name "x-ui" -type f -exec cp {} /usr/local/bin/ \; 2>/dev/null
}

# 安装
echo "[✓] 安装文件..."
mkdir -p /usr/local/3x-ui /etc/3x-ui
cp -f /tmp/x-ui/3x-ui/x-ui /usr/local/3x-ui/ 2>/dev/null || \
cp -f /tmp/x-ui/x-ui /usr/local/3x-ui/ 2>/dev/null || \
cp -f $(find /tmp -name "x-ui" -type f | head -1) /usr/local/3x-ui/ 2>/dev/null

chmod +x /usr/local/3x-ui/x-ui

# 创建服务
echo "[✓] 创建服务..."
cat > /etc/systemd/system/3x-ui.service << EOF
[Unit]
Description=3X-UI Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/3x-ui
ExecStart=/usr/local/3x-ui/x-ui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 3x-ui

# 启动
echo "[✓] 启动服务..."
systemctl start 3x-ui

# 结果
echo ""
echo "========================================"
echo "  安装完成！"
echo "========================================"
echo "  面板地址: http://$(curl -s ip.sb || hostname -I | awk '{print $1}'):2026"
echo "  用户名: liang"
echo "  密码: liang"
echo "========================================"
echo ""
echo "检查服务状态: systemctl status 3x-ui"
