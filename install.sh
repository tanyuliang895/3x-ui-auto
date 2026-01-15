#!/usr/bin/env bash
# 文件名建议: install-3x-ui-zero-interaction.sh
# 目标: 完全零交互、一键安装/更新 3x-ui v2.8.7+，用户名 liang / 密码 liang / 端口 2026 + BBR
# 兼容 Ubuntu/Debian/CentOS 等主流系统（需 root 执行）

set -e

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'

echo -e "${green}零交互安装 3x-ui 开始 (用户名: liang | 密码: liang | 端口: 2026 + BBR)${plain}\n"

# ==================== 第一步：开启 BBR（已验证零交互） ====================
echo -e "${green}开启 TCP BBR + FQ...${plain}"
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-bbr.conf
modprobe tcp_bbr 2>/dev/null || true
echo -e "${green}BBR 配置完成（当前: $(sysctl -n net.ipv4.tcp_congestion_control)）${plain}"

# ==================== 第二步：下载并安装最新 release ====================
TMP_DIR="/tmp/x-ui-install-$(date +%s)"
mkdir -p "$TMP_DIR" && cd "$TMP_DIR"

echo -e "${green}获取最新版本...${plain}"
LATEST_TAG=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/' || echo "v2.8.7")

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH_SUFFIX="amd64" ;;
    aarch64|arm64) ARCH_SUFFIX="arm64" ;;
    *) echo -e "${red}不支持的架构: $ARCH${plain}" && exit 1 ;;
esac

FILE="x-ui-linux-${ARCH_SUFFIX}.tar.gz"
URL="https://github.com/MHSanaei/3x-ui/releases/download/v${LATEST_TAG#v}/${FILE}"

echo -e "${green}下载 ${LATEST_TAG} (${ARCH_SUFFIX}) ...${plain}"
curl -L -o "$FILE" "$URL" || { echo -e "${red}下载失败！检查网络或版本${plain}"; exit 1; }

tar zxf "$FILE"
chmod +x x-ui/x-ui x-ui/bin/xray* x-ui/x-ui.sh 2>/dev/null || true

# 安装目录
XUI_DIR="/usr/local/x-ui"
mkdir -p "$XUI_DIR" /usr/bin /etc/systemd/system

# 复制核心文件
cp -f x-ui/x-ui /usr/bin/x-ui
cp -f x-ui/x-ui.sh /usr/bin/x-ui.sh
cp -rf x-ui/bin/* "$XUI_DIR/bin/"
cp -rf x-ui/* "$XUI_DIR/"  # 包含 geoip 等

# ==================== 第三步：强制创建/覆盖 service 文件（零交互关键） ====================
echo -e "${green}创建 systemd 服务文件...${plain}"

# 优先用包里的（debian 版最常见）
if [ -f "x-ui/x-ui.service.debian" ]; then
    cp -f x-ui/x-ui.service.debian /etc/systemd/system/x-ui.service
elif [ -f "x-ui/x-ui.service" ]; then
    cp -f x-ui/x-ui.service /etc/systemd/system/x-ui.service
else
    # 手动写一个通用版（最保险）
    cat > /etc/systemd/system/x-ui.service <<'EOF'
[Unit]
Description=X-UI Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/x-ui
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
fi

chmod 644 /etc/systemd/system/x-ui.service

# ==================== 第四步：设置账号端口（x-ui CLI 支持非交互） ====================
echo -e "${green}设置用户名/密码/端口...${plain}"
/usr/bin/x-ui setting -port 2026 >/dev/null 2>&1 || true
/usr/bin/x-ui setting -username liang >/dev/null 2>&1 || true
/usr/bin/x-ui setting -password liang >/dev/null 2>&
