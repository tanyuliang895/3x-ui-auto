#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互、无证书、固定端口 2026 + BBR）
# 最终破坏版 - 强制跳过 SSL 菜单，使用纯 HTTP

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m安装 3X-UI（全自动 + BBR + 无证书）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m"
echo -e "\033[33m访问: http://你的IP:$PORT\033[0m\n"

# BBR 加速
echo -e "\033[36m启用 BBR...\033[0m"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
modprobe tcp_bbr 2>/dev/null || true
echo -e "\033[32mBBR 已开启！\033[0m\n"

# 依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖..."
    apt update -y && apt install -y curl expect 2>/dev/null || yum install -y curl expect 2>/dev/null || dnf install -y curl expect 2>/dev/null
fi

# 下载官方脚本
TEMP_SCRIPT="/tmp/3x-ui.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect：端口正常，SSL 菜单强制发送无效输入跳过
expect <<END_EXPECT
    set timeout -1
    spawn $TEMP_SCRIPT

    # 端口 y
    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }

    # 输入端口
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 菜单出现 → 发送无效字符（如 "n"），让它报错跳过申请
    expect -re "(?i)Choose an option" { send "n\\r" }  # 故意 n 或无效，强制跳过

    # 后续所有提示回车或 n
    expect -re "(?i)(IPv6|domain|域名)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re ".*" { send "\\r" }

    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 强制关闭 HTTPS
echo "强制关闭 HTTPS..."
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 设置账号
echo "设置账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板: \033[36mhttp://你的IP:$PORT\033[0m"
echo -e "用户: \033[36m$USERNAME\033[0m  密码: \033[36m$PASSWORD\033[0m"
echo -e "\033[31mHTTP 无加密，仅内网/测试用！\033[0m"
echo -e "\033[32mBBR 已永久开启\033[0m"
