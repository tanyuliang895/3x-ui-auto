#!/bin/bash
PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m安装 3X-UI（自动申请证书）...\033[0m"

# BBR
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
modprobe tcp_bbr 2>/dev/null

# 依赖
apt update -y && apt install -y curl expect >/dev/null 2>&1 || true

# 开放 80 端口
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# 下载
TEMP_SCRIPT="/tmp/3x.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 自动申请证书（加强匹配）
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    expect -re "customize.*\[y/n\]" { send "y\r" }
    expect -re "panel port:" { send "$PORT\r" }

    # 证书菜单 - 回车默认 2 (IP证书)
    expect -re "Choose an option" { send "\r" }

    # 80 端口确认 - 回车默认 80
    expect -re "Port to use for ACME HTTP-01 listener" { send "\r" }

    # 所有其他证书提示 - 回车或 n
    expect -re "(?i)(IPv6|domain|域名|enter|SSL|acme)" { send "\r" }
    expect -re "\\[y/n\\]" { send "n\r" }
    expect -re ".*" { send "\r" }  # 终极兜底

    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT"

# 设置根路径 + 账号
/usr/local/x-ui/x-ui setting -webBasePath "/" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n完成！访问 https://你的IP:$PORT (或 http 如果证书失败)"
echo "用户: $USERNAME   密码: $PASSWORD"
