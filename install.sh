#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互、无证书、固定端口 2026 + 账号 liang/liang + BBR 加速）
# 无证书版 - 彻底跳过 SSL 全部提示 + 根路径

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（全自动 + BBR + 无证书）...\033[0m"
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

# 下载官方 install.sh
TEMP_SCRIPT="/tmp/3x-ui.sh"
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# expect - 彻底跳过证书（故意 n + 兜底所有提示）
expect <<END_EXPECT
    set timeout -1

    spawn $TEMP_SCRIPT

    expect -re "(?i)Would you like to customize.*\\[y/n\\]" { send "y\\r" }
    expect -re "(?i)Please set up the panel port:" { send "$PORT\\r" }

    # SSL 菜单 - 故意 n 跳过证书申请
    expect -re "(?i)Choose an option" { send "n\\r" }

    # 后续所有证书相关提示 - 全部回车或 n 跳过
    expect -re "(?i)(Port to use|IPv6|domain|域名|enter)" { send "\\r" }
    expect -re "\\[y/n\\]" { send "n\\r" }
    expect -re ".*" { send "\\r" }  # 超级兜底

    expect eof
END_EXPECT

rm -f "$TEMP_SCRIPT" >/dev/null 2>&1

# 强制关闭 HTTPS + 设置根路径
echo "强制关闭 HTTPS + 设置根路径为 / ..."
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -webBasePath "/" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

# 设置账号
echo "设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1 || true

# 重启
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！BBR 已开启\033[0m"
echo -e "面板地址: \033[36mhttp://你的IP:$PORT\033[0m （纯 HTTP，无证书）"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui\033[0m"
echo -e "\033[32mBBR 已永久开启！\033[0m"
echo -e "\033[31mHTTP 不加密，仅内网/测试用，外网暴露有风险！\033[0m"
