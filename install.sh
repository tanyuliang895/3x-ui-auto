#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互、无证书、固定端口 2026 + 账号 liang/liang + BBR 加速）
# 最终版 - 2026-01-10，强制跳过 SSL 申请，使用纯 HTTP

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR + 无证书）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m"
echo -e "\033[33m访问: http://你的IP:$PORT（纯 HTTP，无证书）\033[0m\n"

# ======================== 启用 BBR 加速 ========================
echo -e "\033[36m启用 BBR v2 + fq...\033[0m"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
modprobe tcp_bbr 2>/dev/null || true
echo "拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "\033[32mBBR 已启用！\033[0m\n"

# ======================== 安装依赖 ========================
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖 curl expect..."
    apt update -y && apt install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动安装"
fi

# ======================== 下载官方 install.sh ========================
TEMP_SCRIPT="/tmp/3x-ui-install-temp.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# ======================== expect 自动化（强制跳过 SSL） ========================
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    # 1. 自定义端口 → y
    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }

    # 2. 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # 3. SSL 菜单 → 强制不选（回车默认，但我们后面关闭 HTTPS）
    expect -re "(?i)Choose an option" { send "\\r" }  # 回车选默认

    # 4. IPv6 / 域名 / 其他 → 全部回车跳过
    expect -re "(?i)(IPv6|domain|域名|enter)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }

    # 兜底所有剩余提示回车
    expect -re ".*" { send "\\r" }

    expect eof
END_EXPECT

# 清理
rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# ======================== 强制关闭 HTTPS ========================
echo "强制关闭 HTTPS，使用纯 HTTP..."
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# ======================== 设置固定账号 ========================
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# ======================== 重启服务 ========================
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttp://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[32mBBR 加速已永久开启\033[0m"
echo -e "\033[31mHTTP 不加密，仅适合内网/测试，外网暴露有风险！\033[0m"
