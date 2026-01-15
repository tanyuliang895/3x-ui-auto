#!/usr/bin/env bash
# 文件名建议：install-3x-ui-auto.sh
# 功能：一键安装/更新 3x-ui，并设置用户名 liang / 密码 liang / 端口 2026 + 开启 BBR

set -e

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'

echo -e "${green}开始安装/更新 3x-ui (用户名: liang | 密码: liang | 端口: 2026)${plain}"

# ==================== 自动开启 BBR ====================
enable_bbr() {
    echo -e "${green}正在启用 BBR 加速...${plain}"
    
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    fi
    
    sysctl -p >/dev/null 2>&1
    
    # 检查当前是否已启用 BBR
    current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "${green}BBR 已启用 (当前拥塞控制: bbr)${plain}"
    else
        modprobe tcp_bbr
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        echo -e "${green}BBR 临时启用成功，再次重启服务器后永久生效${plain}"
    fi
    
    lsmod | grep -q bbr && echo -e "${green}tcp_bbr 模块已加载${plain}" || echo -e "${red}警告：tcp_bbr 模块未加载（可能内核不支持）${plain}"
}

enable_bbr

# ==================== 下载并安装最新 3x-ui ====================
TMP_DIR="/tmp/3x-ui-install"
INSTALL_DIR="/usr/local/x-ui"
mkdir -p "$TMP_DIR" "$INSTALL_DIR"

ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64)  ARCH_SUFFIX="amd64" ;;
    aarch64|arm64) ARCH_SUFFIX="arm64" ;;
    *) echo -e "${red}不支持的架构: $ARCH${plain}"; exit 1 ;;
esac

echo -e "${green}正在获取最新版本...${plain}"
LATEST_TAG=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST_TAG" ]]; then
    echo -e "${red}无法获取最新版本，使用官方一键安装作为备用${plain}"
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
else
    echo -e "${green}最新版本: ${LATEST_TAG}${plain}"
    
    cd "$TMP_DIR"
    FILE_NAME="x-ui-linux-${ARCH_SUFFIX}.tar.gz"
    wget -N --no-check-certificate "https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_TAG}/${FILE_NAME}"
    
    tar zxvf "${FILE_NAME}"
    chmod +x x-ui/x-ui x-ui/bin/xray*
    
    # 停止旧服务（如果存在）
    systemctl stop x-ui 2>/dev/null || true
    
    # 替换核心文件
    cp -f x-ui/x-ui /usr/bin/x-ui
    cp -f x-ui/x-ui.sh /usr/bin/x-ui
    cp -f x-ui/x-ui.service /etc/systemd/system/x-ui.service 2>/dev/null || true
    cp -rf x-ui/* "$INSTALL_DIR"/
    
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl restart x-ui
fi

# 等待服务启动
sleep 5

# ==================== 设置用户名、密码、端口 ====================
echo -e "${green}正在设置面板账号: liang / liang  | 端口: 2026${plain}"

/usr/local/x-ui/x-ui setting -username liang -password liang -port 2026 >/dev/null 2>&1

# 重启面板使设置生效
systemctl restart x-ui

# 清理临时文件
cd / && rm -rf "$TMP_DIR"

# ==================== 最终提示 ====================
panel_ip=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "你的服务器IP")

echo -e "\n${green}3x-ui 安装/更新完成！${plain}"
echo -e "面板地址: http://${panel_ip}:2026  （建议尽快配置 SSL 证书后使用 https）"
echo -e "用户名: ${green}liang${plain}"
echo -e "密码:   ${green}liang${plain}"
echo -e "端口:   ${green}2026${plain}"
echo -e "\n${yellow}强烈建议登录后立即修改密码，并开启面板中的 Fail2Ban 防爆破功能！${plain}"
echo -e "BBR 加速已尝试开启（重启服务器后完全生效）"
echo -e "查看 BBR 状态: ${green}sysctl net.ipv4.tcp_congestion_control${plain}"
echo -e "查看服务状态: ${green}systemctl status x-ui${plain}"
