#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互、无证书、固定端口 2026 + BBR 加速）
# 加强版 - 覆盖 80 端口确认 + 所有 SSL 提示

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m安装 3X-UI（无证书版）...\033[0m"

# BBR
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
modprobe tcp_bbr 2>/dev/null

# 依赖
apt update -y && apt install -y curl expect 2>/dev/null || yum install -y curl expect 2>/dev/null

# 下载
TEMP_SCRIPT="/tmp/3x-ui.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 加强覆盖 80 端口 + 所有 SSL 相关提示
expect <<END_EXPECT
    set timeout -1
    spawn $TEMP_SCRIPT

    # 端口自定义
    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 菜单 - 故意 n 跳过
    expect -re "(?i)Choose an option" { send "n\\r" }

    # 80 端口确认 - 回车默认 80
    expect -re "(?i)Port to use for ACME HTTP-01 listener" { send "\\r" }

    # IPv6 / 域名 / 其他提示 - 跳过
    expect -re "(?i)(IPv6|domain|域名|enter|Do you have)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re ".*" { send "\\r" }  # 兜底所有剩余

    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT"

# 关闭 HTTPS + 根路径
echo "强制关闭 HTTPS + 设置根路径..."
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -webBasePath "/" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 设置账号
echo "设置账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

echo -e "\033[32m完成！访问 http://你的IP:$PORT\033[0m"
echo "用户: $USERNAME  密码: $PASSWORD"
