#!/usr/bin/env bash
# 文件名建议：install-3x-ui-zero.sh
# 功能：真正零交互一键安装/更新 3x-ui (v2.8.7+)
# 用户: liang / 密码: liang / 端口: 2026 + 开启 BBR
# 兼容：Debian/Ubuntu/CentOS/Alma/Rocky 等（需 root 执行）
# 修复点：创建缺失的 /usr/local/x-ui/bin/ 等目录，避免 cp 失败

set -e

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'
yellow='\033[1;33m'

echo -e "${green}零交互安装/更新 3x-ui 开始 (用户名: liang | 密码: liang | 端口: 2026 + BBR)${plain}\n"

# ==================== 第一步：开启 BBR ====================
echo -e "${green}→ 启用 BBR ...${plain}"
cat > /etc/sysctl.d/99-tcp-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl -p /etc/sysctl.d/99-tcp-bbr.conf >/dev/null 2>&1 || true
modprobe tcp_bbr >/dev/null 2>&1 || true

current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
echo -e "${green}BBR 配置完成（当前拥塞控制: ${current_cc:-未知})${plain}\n"

# ==================== 第二步：安装依赖 ====================
echo -e "${green}→ 安装必要工具 (curl wget tar unzip)...${plain}"
if command -v apt &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq >/dev/null
    apt install -y -qq curl wget tar unzip >/dev/null
elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
    if command -v dnf &>/dev/null; then
        dnf install -y -q curl wget tar unzip
    else
        yum install -y -q curl wget tar unzip
    fi
fi

# ==================== 第三步：下载最新 release ====================
TMP_DIR=$(mktemp -d)
INSTALL_DIR="/usr/local/x-ui"
mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/bin" /etc/x-ui

echo -e "${green}→ 获取最新版本...${plain}"
LATEST_TAG=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_TAG" ]]; then
    echo -e "${red}获取版本失败，退出${plain}"
    exit 1
fi

echo -e "最新版本: ${green}${LATEST_TAG}${plain}"

cd "$TMP_DIR"

ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64)  ARCH_SUFFIX="amd64" ;;
    aarch64|arm64) ARCH_SUFFIX="arm64" ;;
    *) echo -e "${red}不支持的架构: $ARCH${plain}"; exit 1 ;;
esac

FILE_NAME="x-ui-linux-${ARCH_SUFFIX}.tar.gz"
DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_TAG}/${FILE_NAME}"

wget -q --show-progress --no-check-certificate "$DOWNLOAD_URL" -O "$FILE_NAME"

tar -xzf "$FILE_NAME"
cd x-ui || { echo -e "${red}解压后未找到 x-ui 目录${plain}"; exit 1; }

# 赋予执行权限
chmod +x x-ui bin/xray* 2>/dev/null || true

# ==================== 第四步：复制文件（关键修复：先创建目录） ====================
echo -e "${green}→ 安装文件到 ${INSTALL_DIR} ...${plain}"

# 确保所有目标子目录存在（防止 cp 报错）
mkdir -p "$INSTALL_DIR/bin"

# 复制主程序、bin 目录等
cp -f x-ui          "$INSTALL_DIR/x-ui"      2>/dev/null || true
cp -f bin/xray*     "$INSTALL_DIR/bin/"      2>/dev/null || true
cp -f x-ui.db       /etc/x-ui/x-ui.db        2>/dev/null || true   # db 放 /etc/x-ui/ 更标准

# 如果有其他文件（如 geoip.dat 等），也复制
cp -rf ./* "$INSTALL_DIR/" 2>/dev/null || true

# ==================== 第五步：创建/更新 systemd 服务 ====================
echo -e "${green}→ 创建 systemd 服务文件 ...${plain}"
cat > /etc/systemd/system/x-ui.service <<'EOF'
[Unit]
Description=3x-ui Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/x-ui
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# ==================== 第六步：设置面板参数（零交互） ====================
echo -e "${green}→ 设置用户名/密码/端口 ...${plain}"

if [[ -x "$INSTALL_DIR/x-ui" ]]; then
    "$INSTALL_DIR/x-ui" setting -username liang -password liang -port 2026 >/dev/null 2>&1
else
    echo -e "${red}未找到 x-ui 可执行文件，设置跳过${plain}"
fi

# ==================== 第七步：启动服务 ====================
echo -e "${green}→ 启动并设置开机自启 ...${plain}"
systemctl enable x-ui --now >/dev/null 2>&1

sleep 3

if systemctl is-active --quiet x-ui; then
    echo -e "${green}安装/更新成功！${plain}"
    IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "你的服务器IP")
    echo -e "面板地址: ${green}http://${IP}:2026/${plain}"
    echo -e "用户名: ${green}liang${plain}    密码: ${green}liang${plain}"
    echo -e "端口:   ${green}2026${plain}"
    echo -e "\n${yellow}建议：登录后立即改密码 + 开启 Fail2Ban 防暴力破解${plain}"
else
    echo -e "${red}服务启动失败，查看日志：${plain}"
    echo "journalctl -u x-ui -xe --no-pager"
fi

# 清理
cd /tmp
rm -rf "$TMP_DIR"

echo -e "\n${green}脚本执行完毕。${plain}"
