#!/bin/bash
# 3X-UI 一键全自动安装/更新（支持自动域名证书 + BBR + 最新 Xray）
# GitHub: https://github.com/tanyuliang895/3x-ui-auto
# 用法：bash <(curl -Ls https://raw.githubusercontent.com/tanyuliang895/3x-ui-auto/main/install.sh)

set -e

# 可自定义参数
USERNAME="liang"
PASSWORD="liang"
PORT="2026"
WEB_PATH="/liang"          # 防扫描路径，访问时要加这个
BBR=true
DOMAIN=""                  # ← 如果想自动上证书，请在这里填域名（例如 panel.yourdomain.com），留空则跳过

echo -e "\n🚀 零交互安装/更新 3X-UI 开始..."
echo "用户名: $USERNAME | 密码: $PASSWORD | 端口: $PORT | 路径: $WEB_PATH | Xray: 最新版"

# 启用 BBR
if [ "$BBR" = true ]; then
    echo "→ 启用 BBR 加速..."
    if ! grep -q "bbr" /etc/sysctl.conf; then
        cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl -p
    fi
    echo "BBR 已启用（当前: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')）"
fi

# 安装必要工具
apt update -yqq && apt install -yqq curl wget tar unzip >/dev/null 2>&1 || yum install -y curl wget tar unzip >/dev/null 2>&1

# 获取服务器 IP
IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me || echo "你的IP")

# 如果用户填了域名，自动申请证书
if [ -n "$DOMAIN" ]; then
    echo "→ 检测到域名 $DOMAIN，正在检查解析..."
    DOMAIN_IP=$(dig +short $DOMAIN | grep -v '^$' | head -1)
    if [ "$DOMAIN_IP" = "$IP" ]; then
        echo "域名解析正确！开始自动申请 Let's Encrypt 域名证书（需要外部 80/443 端口开放）..."
        CERT_SUCCESS=false
        # 3X-UI 官方脚本在安装后会自动提供证书申请功能，但我们这里提前调用
        # 直接用 acme.sh 申请（更稳定）
        if command -v acme.sh >/dev/null 2>&1; then
            ~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --httpport 80 --force || true
            if [ -f "/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer" ]; then
                CERT_SUCCESS=true
            fi
        fi
        if [ "$CERT_SUCCESS" = true ]; then
            echo "证书申请成功！后续可登录面板自动配置"
        else
            echo "证书申请失败（请确保 80 端口对外开放），稍后手动在面板申请"
        fi
    else
        echo "警告：域名 $DOMAIN 未正确解析到服务器 IP $IP，跳过自动证书"
    fi
fi

echo "→ 执行官方 3X-UI 安装脚本..."

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
y
$PORT
$USERNAME
$PASSWORD
$WEB_PATH
EOF

sleep 6

# 如果证书申请成功，自动把证书填入 3X-UI（可选）
if [ "$CERT_SUCCESS" = true ]; then
    echo "→ 自动配置 SSL 到 3X-UI..."
    x-ui setting -webCertFile "/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer"
    x-ui setting -webKeyFile "/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key"
    x-ui restart
fi

echo -e "\n✅ 安装完成！"
if [ -n "$DOMAIN" ] && [ "$CERT_SUCCESS" = true ]; then
    echo "面板地址（已启用 HTTPS）：https://$DOMAIN:$PORT$WEB_PATH/"
else
    echo "面板地址（暂无证书）：http://$IP:$PORT$WEB_PATH/"
fi

echo "用户名: $USERNAME   密码: $PASSWORD"
echo "端口: $PORT   Web路径: $WEB_PATH"
echo "管理命令: x-ui"
echo "安全提醒：立即登录改密码 + 装 Fail2Ban"
echo "安全上网，玩得开心！🚀"
