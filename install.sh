#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang + BBR 加速）
# 修复版 - 覆盖 80 端口确认 + 根路径 + 证书申请

PORT="2026"
USERNAME="liang"
PASSWORD="liang"
WEB_BASE_PATH="/"  # 强制根路径

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR + 证书申请）...\033[0m"
echo -e "\033[33m端口: $PORT | 用户: $USERNAME | 密码: $PASSWORD\033[0m\n"

# BBR 加速
echo -e "\033[36m启用 BBR...\033[0m"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi
modprobe tcp_bbr 2>/dev/null || true
echo "当前拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "\033[32mBBR 已开启！\033[0m\n"

# 依赖
if ! command -v curl >/dev/null || ! command -v expect >/dev/null; then
    echo "安装依赖..."
    apt update -y && apt install -y curl expect 2>/dev/null || yum install -y curl expect 2>/dev/null || dnf install -y curl expect 2>/dev/null
fi

# 开放 80 端口
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true

# 下载
TEMP_SCRIPT="/tmp/3x-ui.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 覆盖 80 端口 + 所有 SSL 提示
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 菜单 - 回车选默认 2 (IP证书)
    expect -re "(?i)Choose an option" { send "\\r" }

    # 80 端口确认 - 回车默认 80
    expect -re "(?i)Port to use for ACME HTTP-01 listener" { send "\\r" }

    # IPv6 / 域名 / 其他 - 回车或 n
    expect -re "(?i)(IPv6|domain|域名|enter)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re ".*" { send "\\r" }  # 加强兜底

    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 设置根路径 + 关闭 HTTPS（备用）
echo "设置根路径 + 关闭 HTTPS（备用）..."
/usr/local/x-ui/x-ui setting -webBasePath "$WEB_BASE_PATH" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 设置账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！\033[0m"
echo -e "面板地址: \033[36mhttp://你的IP:$PORT\033[0m （根路径）"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[32mBBR 已永久开启\033[0m"
echo -e "\033[31m证书申请可能失败（限额），用 http 访问面板（忽略警告）\033[0m"
