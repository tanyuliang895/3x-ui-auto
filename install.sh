#!/bin/bash
# 3X-UI 一键全自动安装脚本（零交互，固定端口 2026 + 账号 liang/liang）
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)
# 优势：自动迁移旧数据、固定一切、默认 IP SSL（需 80 端口开放）

PORT="2026"
USERNAME="liang"
PASSWORD="liang"

set -e

echo -e "\033[32m正在安装 3X-UI（最新官方版，完全全自动）...\033[0m"
echo -e "\033[33m固定端口: $PORT  用户名: $USERNAME  密码: $PASSWORD\033[0m"
echo -e "\033[33m自动迁移旧数据 + 申请 IP SSL（需 80 端口开放）\033[0m"
echo ""

# 安装依赖（curl + expect）
if ! command -v curl &> /dev/null || ! command -v expect &> /dev/null; then
    echo "安装依赖 curl expect..."
    apt-get update -y && apt-get install -y curl expect 2>/dev/null || \
    yum install -y curl expect 2>/dev/null || \
    dnf install -y curl expect 2>/dev/null || \
    echo "依赖安装失败，请手动安装 curl 和 expect"
fi

# 开放 80 端口（用于 IP SSL 申请）
echo "开放 80 端口..."
ufw allow 80 >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
firewall-cmd --add-port=80/tcp --permanent >/dev/null 2>&1 || true
firewall-cmd --reload >/dev/null 2>&1 || true
iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

# 全自动运行官方安装脚本（最宽松匹配版）
expect <<'END_EXPECT'
    set timeout -1

    spawn bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    # 1. 是否自定义端口 → 匹配任何带 customize / Panel Port / [y/n] 的提示
    expect -re "(?i)(customize|panel.*port|port settings).*\[y/n\]" { send "y\r" }

    # 2. 输入端口（匹配更松，兼容 "Please set up the panel port:" 等）
    expect -re "(?i)(please set up|set up|enter|panel port|port:).*" { send "$PORT\r" }

    # 3. 证书选择 → 默认回车（选 2：IP证书）
    expect -re "(?i)(choose an option|select|option|证书).*" { send "\r" }

    # 4. IPv6 提示 → 留空跳过
    expect -re "(?i)(ipv6|Do you have an IPv6|IPv6 address).*" { send "\r" }

    # 5. 域名相关提示 → 全部跳过（留空）
    expect -re "(?i)(domain|域名|enter your domain).*" { send "\r" }

    # 6. 其他可能的 y/n 提示（证书确认、reloadcmd 等） → 默认 n 或回车
    expect -re "\[y/n\]" { send "n\r" }
    expect -re "(?i)(continue|yes/no|modify|reloadcmd)" { send "n\r" }

    # 最终兜底：任何剩余提示都回车（防止卡住）
    expect -re ".*" { send "\r" }
    expect eof
END_EXPECT

# 安装完成后强制设置固定账号（覆盖官方随机生成的）
echo "强制设置固定账号 $USERNAME / $PASSWORD ..."
/usr/local/x-ui/x-ui setting -username "$USERNAME" -password "$PASSWORD" >/dev/null 2>&1

# 重启服务
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo -e "\n\033[32m安装完成！一切全自动固定\033[0m"
echo -e "面板地址: \033[36mhttps://你的IP:$PORT\033[0m"
echo -e "用户名: \033[36m$USERNAME\033[0m"
echo -e "密码:   \033[36m$PASSWORD\033[0m"
echo -e "\033[33m管理命令: x-ui （可更新/重启/查看日志/修改SSL等）\033[0m"
echo -e "\033[31m注意：当前为固定弱密码，仅测试推荐！生产环境请立即修改为强密码\033[0m"
