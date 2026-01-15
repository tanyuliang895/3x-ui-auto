#!/bin/bash
# 3X-UI 一键全自动安装脚本（2026最新兼容版）
# 默认端口: 2026    用户名: liang    密码: liang
# 自动启用 BBR 加速 + 获取最新版本
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 配置参数（可自行修改）
DEFAULT_PORT="2026"
USERNAME="liang"
PASSWORD="liang"

echo -e "\033[36m========================================\033[0m"
echo -e "     3X-UI 全自动安装脚本 (端口默认: \033[32m$DEFAULT_PORT\033[0m)"
echo -e "     用户名: \033[32m$USERNAME\033[0m    密码: \033[32m$PASSWORD\033[0m"
echo -e "\033[36m========================================\033[0m\n"

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：请使用 root 权限运行此脚本！\033[0m"
    exit 1
fi

# 安装必要依赖
if ! command -v curl &> /dev/null || ! command -v socat &> /dev/null; then
    echo "安装必要依赖 (curl socat ca-certificates)..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y curl socat ca-certificates
    elif command -v yum &> /dev/null; then
        yum install -y curl socat ca-certificates
    elif command -v dnf &> /dev/null; then
        dnf install -y curl socat ca-certificates
    else
        echo -e "\033[31m不支持的系统，请手动安装 curl socat 后重试。\033[0m"
        exit 1
    fi
fi

# 启用 BBR
echo -e "\n\033[33m正在启用 BBR 加速...\033[0m"
modprobe tcp_bbr 2>/dev/null || true
cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p >/dev/null 2>&1
echo -e "\033[32mBBR 已启用！\033[0m"

# 执行官方最新安装脚本（master 分支自动获取最新版）
echo -e "\n\033[33m开始执行 3X-UI 官方安装（自动选择自定义端口并设置为 $DEFAULT_PORT）...\033[0m"

# 使用 expect 实现自动化交互（需先安装 expect）
if ! command -v expect &> /dev/null; then
    echo "安装 expect 以实现自动交互..."
    if command -v apt-get &> /dev/null; then
        apt-get install -y expect
    elif command -v yum &> /dev/null; then
        yum install -y expect
    elif command -v dnf &> /dev/null; then
        dnf install -y expect
    else
        echo -e "\033[31m无法自动安装 expect，请手动安装后重试。\033[0m"
        exit 1
    fi
fi

# 使用 expect 自动化回答 y + 输入端口（后续用户名密码官方会随机生成，我们安装后再改）
expect <<EOF
spawn bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
expect {
    "Would you like to customize the Panel Port settings?*" {
        send "y\r"
        exp_continue
    }
    "Please set up the panel port:*" {
        send "$DEFAULT_PORT\r"
        exp_continue
    }
    eof
}
EOF

# 等待安装完成（官方脚本会自动生成随机用户名密码）
sleep 5

# 安装完成后立即修改为我们想要的用户名和密码 + 端口（万一官方随机了端口也强制改回）
echo -e "\n\033[33m安装完成，正在设置用户名/密码/端口...\033[0m"
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" -port "$DEFAULT_PORT" >/dev/null 2>&1

# 重启服务确保生效
/usr/local/x-ui/x-ui restart

# 输出最终信息
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me)
echo -e "\n\033[32m安装完成！3X-UI 已就绪\033[0m"
echo -e "访问地址: \033[36mhttp://$IP:$DEFAULT_PORT\033[0m"
echo -e "用户名: \033[32m$USERNAME\033[0m"
echo -e "密码:   \033[32m$PASSWORD\033[0m"
echo -e "\n提示："
echo "  • 建议安装后立即登录面板修改路径（webBasePath）提高安全性"
echo "  • 可在面板内或运行 'x-ui' 命令手动申请 SSL 证书"
echo "  • BBR 加速已开启，如需检查：sysctl net.ipv4.tcp_congestion_control"
echo ""
