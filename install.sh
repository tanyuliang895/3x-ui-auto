#!/bin/bash
set -e
# 确保以root权限执行
if [ $EUID -ne 0 ]; then
    echo "Error: 请执行 sudo -i 切换root后再运行"
    exit 1
fi

# ====================== 自定义配置（仅保留固定参数） ======================
USERNAME="liang"       # 面板用户名
PASSWORD="liang"       # 面板密码
PANEL_PORT="2026"      # 面板端口
# ======================================================================

# ====================== 1. 清理旧残留 ======================
echo -e "\033[32m[1/8] 清理旧3x-ui残留...\033[0m"
rm -rf /usr/local/3x-ui
rm -f /etc/systemd/system/3x-ui.service

# ====================== 2. 安装依赖 ======================
echo -e "\033[32m[2/8] 安装基础依赖...\033[0m"
apt update -y && apt install -y curl wget sudo tar openssl nginx certbot python3-certbot-nginx jq bc

# ====================== 3. 开启BBR加速 ======================
echo -e "\033[32m[3/8] 配置BBR加速...\033[0m"
KERNEL_VERSION=$(uname -r | cut -d '.' -f 1-2)
if [[ $(echo "$KERNEL_VERSION < 4.9" | bc -l) -eq 1 ]]; then
    echo -e "\033[33m内核版本过低，自动升级内核以支持BBR...\033[0m"
    apt install -y linux-image-generic-hwe-20.04 -y
    echo -e "\033[31m内核升级完成！5秒后重启，重启后重新运行本脚本\033[0m"
    sleep 5 && reboot
else
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "\033[32mBBR加速已开启 ✔\033[0m"
    fi
fi

# ====================== 4. 自动获取3x-ui最新版本（核心新增） ======================
echo -e "\033[32m[4/8] 从GitHub API获取3x-ui最新版本...\033[0m"
# 调用GitHub API获取3x-ui最新Release版本号
LATEST_VERSION=$(curl -s --connect-timeout 10 https://api.github.com/repos/MHSanaei/3x-ui/releases/latest | jq -r '.tag_name')

# 降级处理：API访问失败时，默认使用v2.8.7
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo -e "\033[33mGitHub API访问失败，使用默认最新版v2.8.7\033[0m"
    LATEST_VERSION="v2.8.7"
else
    echo -e "\033[32m检测到3x-ui最新版本：$LATEST_VERSION\033[0m"
fi

# ====================== 5. 下载3x-ui最新版本 ======================
echo -e "\033[32m[5/8] 下载3x-ui $LATEST_VERSION...\033[0m"
DOWNLOAD_URL="https://github.com/MHSanaei/3x-ui/releases/download/${LATEST_VERSION}/3x-ui-linux-amd64.tar.gz"
wget -q --connect-timeout 15 -O /tmp/3x-ui.tar.gz $DOWNLOAD_URL || {
    echo -e "\033[31m下载失败！请检查网络是否能访问GitHub\033[0m"
    exit 1
}

# ====================== 6. 解压并安装 ======================
echo -e "\033[32m[6/8] 安装3x-ui...\033[0m"
mkdir -p /usr/local/3x-ui
tar -xzf /tmp/3x-ui.tar.gz -C /usr/local/3x-ui --strip-components 1
chmod +x /usr/local/3x-ui/3x-ui
rm -f /tmp/3x-ui.tar.gz

# 验证可执行文件
if [ ! -f /usr/local/3x-ui/3x-ui ]; then
    echo -e "\033[31m解压失败！压缩包损坏\033[0m"
    exit 1
fi

# ====================== 7. 配置系统服务 ======================
echo -e "\033[32m[7/8] 配置3x-ui服务...\033[0m"
cat > /etc/systemd/system/3x-ui.service << EOF
[Unit]
Description=3x-ui
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/3x-ui/3x-ui run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# ====================== 8. 配置用户名/密码/端口 ======================
echo -e "\033[32m[8/8] 配置面板参数...\033[0m"
CONFIG_FILE="/usr/local/3x-ui/db/config.json"
# 初始化配置
/usr/local/3x-ui/3x-ui setting -username $USERNAME -password $PASSWORD
# 修改面板端口
jq --arg port "$PANEL_PORT" '.web.port = ($port | tonumber)' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE

# 释放端口
if netstat -tulpn | grep -q ":$PANEL_PORT "; then
    lsof -ti:$PANEL_PORT | xargs -r kill -9
fi

# ====================== 启动并输出信息 ======================
systemctl enable 3x-ui --now
systemctl restart 3x-ui

# 验证服务状态
if ! systemctl is-active --quiet 3x-ui; then
    echo -e "\033[31m3x-ui启动失败！查看日志：journalctl -u 3x-ui\033[0m"
    exit 1
fi

# 最终信息
ip=$(curl -s https://api.ipify.org)
echo -e "\033[32m==================== 安装成功 ====================\033[0m"
echo -e "✅ 3x-ui版本：$LATEST_VERSION（自动获取的最新版）"
echo -e "✅ 面板地址：http://$ip:$PANEL_PORT"
echo -e "✅ 用户名：$USERNAME | 密码：$PASSWORD"
echo -e "✅ BBR加速：已开启（内核≥4.9）"
echo -e "🔧 常用命令："
echo -e "  查看状态：systemctl status 3x-ui"
echo -e "  重启面板：systemctl restart 3x-ui"
echo -e "  升级面板：重新运行本脚本即可自动更新到最新版"
