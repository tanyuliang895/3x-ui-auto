#!/bin/bash
set -e
# 确保脚本以root执行
if [ $EUID -ne 0 ]; then
    echo "Error: 此脚本必须以root权限运行！"
    echo "请执行: sudo -i 切换root后再运行本脚本"
    exit 1
fi

# ====================== 自定义配置（你的参数） ======================
USERNAME="liang"       # 面板用户名
PASSWORD="liang"       # 面板密码
PANEL_PORT="2026"      # 面板端口
# ======================================================================

# ====================== 第一步：开启 BBR 网络加速 ======================
echo -e "\033[32m[1/7] 配置 BBR 网络加速...\033[0m"
# 检查内核版本（BBR需要内核≥4.9）
KERNEL_VERSION=$(uname -r | cut -d '.' -f 1-2)
if [[ $(echo "$KERNEL_VERSION < 4.9" | bc -l) -eq 1 ]]; then
    echo -e "\033[33m当前内核版本过低（$KERNEL_VERSION），BBR需要内核≥4.9！\033[0m"
    read -p "是否自动升级内核？升级后会自动重启，重启后需重新运行本脚本 (y/n)：" upgrade_kernel
    upgrade_kernel=${upgrade_kernel:-n}
    if [ "$upgrade_kernel" = "y" ]; then
        # 仅支持Debian/Ubuntu内核自动升级
        if [ -f /etc/debian_version ]; then
            apt update -y && apt install -y linux-image-generic-hwe-20.04 -y
            echo -e "\033[31m内核升级完成！系统将在5秒后重启，重启后重新执行本脚本即可\033[0m"
            sleep 5 && reboot
        else
            echo -e "\033[31mCentOS系统请手动升级内核：yum install -y kernel-ml && reboot\033[0m"
            exit 1
        fi
    else
        echo -e "\033[33m跳过BBR配置（内核版本不足，后续可手动升级内核后再开启）\033[0m"
    fi
else
    # 写入BBR配置并生效
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    # 验证BBR状态
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr" && lsmod | grep -q "tcp_bbr"; then
        echo -e "\033[32mBBR加速已成功开启 ✔\033[0m"
    else
        echo -e "\033[33mBBR配置已写入，重启系统后生效！\033[0m"
    fi
fi

# ====================== 第二步：补全系统依赖 ======================
echo -e "\033[32m[2/7] 安装/更新基础依赖...\033[0m"
if [ -f /etc/debian_version ]; then
    apt update -y && apt install -y curl wget sudo tar openssl nginx certbot python3-certbot-nginx jq bc || {
        echo -e "\033[31m依赖安装失败！\033[0m"
        exit 1
    }
elif [ -f /etc/redhat-release ]; then
    yum install -y curl wget sudo tar openssl nginx certbot python3-certbot-nginx jq bc || {
        echo -e "\033[31m依赖安装失败！\033[0m"
        exit 1
    }
else
    echo -e "\033[33m警告：未识别的系统发行版，仅支持Debian/Ubuntu/CentOS\033[0m"
fi

# ====================== 第三步：自动获取3x-ui最新版本+修复解压路径 ======================
echo -e "\033[32m[3/7] 获取3x-ui最新版本...\033[0m"
# 从GitHub API获取最新版本号
LATEST_VERSION=$(curl -s https://api.github.com/repos/vaxilu/x-ui/releases/latest | jq -r '.tag_name')
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo -e "\033[33mGitHub API访问失败，使用稳定版v1.8.2\033[0m"
    LATEST_VERSION="v1.8.2"
fi
echo -e "\033[32m当前3x-ui最新版本：$LATEST_VERSION\033[0m"

# 下载最新版本压缩包
DOWNLOAD_URL="https://github.com/vaxilu/x-ui/releases/download/${LATEST_VERSION}/x-ui-linux-amd64.tar.gz"
echo -e "\033[32m正在下载：$DOWNLOAD_URL\033[0m"
wget -q -O /tmp/x-ui.tar.gz $DOWNLOAD_URL || {
    echo -e "\033[31m3x-ui下载失败！请检查网络或手动下载\033[0m"
    exit 1
}

# 修复解压路径（关键：--strip-components 1 去掉顶层目录）
rm -rf /usr/local/x-ui
mkdir -p /usr/local/x-ui
tar -xzf /tmp/x-ui.tar.gz -C /usr/local/x-ui --strip-components 1 || {
    echo -e "\033[31m3x-ui解压失败！压缩包可能损坏\033[0m"
    exit 1
}
chmod +x /usr/local/x-ui/x-ui
rm -f /tmp/x-ui.tar.gz

# 验证可执行文件是否存在
if [ ! -f /usr/local/x-ui/x-ui ]; then
    echo -e "\033[31m3x-ui可执行文件缺失！解压失败\033[0m"
    exit 1
fi

# ====================== 第四步：配置x-ui系统服务 ======================
echo -e "\033[32m[4/7] 配置x-ui系统服务...\033[0m"
cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=x-ui
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/x-ui/x-ui run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl stop x-ui  # 停止旧服务（若存在）

# ====================== 第五步：定制用户名/密码/端口 ======================
echo -e "\033[32m[5/7] 配置面板参数...\033[0m"
CONFIG_FILE="/usr/local/x-ui/config.json"

# 初始化配置文件
if [ ! -f $CONFIG_FILE ]; then
    /usr/local/x-ui/x-ui setting -username $USERNAME -password $PASSWORD
fi

# 修改面板端口（保证JSON格式正确）
jq --arg port "$PANEL_PORT" '.web.port = ($port | tonumber)' $CONFIG_FILE > temp.json && mv temp.json $CONFIG_FILE

# 覆盖用户名/密码
/usr/local/x-ui/x-ui setting -username $USERNAME -password $PASSWORD

# 释放占用端口
if netstat -tulpn | grep -q ":$PANEL_PORT "; then
    echo -e "\033[33m端口$PANEL_PORT已被占用，自动释放...\033[0m"
    lsof -ti:$PANEL_PORT | xargs -r kill -9
fi

# ====================== 第六步：SSL证书配置 ======================
echo -e "\033[32m[6/7] 配置SSL证书...\033[0m"
echo -e "\033[33mLet's Encrypt支持域名/IP证书！\033[0m"
echo "1. 域名证书（90天自动续期）"
echo "2. IP证书（60天自动续期）"
echo "3. 跳过（自签名证书，测试用）"
read -p "选择配置方式（默认2）：" ssl_option
ssl_option=${ssl_option:-2}

case $ssl_option in
    1)
        read -p "输入你的域名：" domain
        # 开放80端口（证书验证必需）
        if [ -f /etc/debian_version ]; then
            ufw allow 80/tcp > /dev/null 2>&1 || iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        else
            firewall-cmd --add-port=80/tcp --permanent && firewall-cmd --reload
        fi
        certbot certonly --standalone -d $domain --agree-tos --register-unsafely-without-email || {
            echo -e "\033[31m域名证书申请失败！\033[0m"
            exit 1
        }
        ;;
    2)
        ip=$(curl -s https://api.ipify.org)
        echo -e "\033[33m当前公网IP：$ip\033[0m"
        certbot certonly --standalone -d $ip --agree-tos --register-unsafely-without-email || {
            echo -e "\033[31mIP证书申请失败！\033[0m"
            exit 1
        }
        ;;
    3)
        # 生成自签名证书
        mkdir -p /usr/local/x-ui/cert
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /usr/local/x-ui/cert/server.key \
            -out /usr/local/x-ui/cert/server.crt \
            -subj "/CN=localhost" > /dev/null 2>&1
        echo -e "\033[32m自签名证书已生成\033[0m"
        ;;
    *)
        echo -e "\033[31m无效选项！\033[0m"
        exit 1
        ;;
esac

# ====================== 第七步：启动服务并输出信息 ======================
echo -e "\033[32m[7/7] 启动x-ui服务...\033[0m"
systemctl enable x-ui --now
systemctl restart x-ui

# 验证服务状态
if ! systemctl is-active --quiet x-ui; then
    echo -e "\033[31mx-ui启动失败！查看日志：journalctl -u x-ui\033[0m"
    exit 1
fi

# 最终信息输出
ip=$(curl -s https://api.ipify.org)
echo -e "\033[32m==================== 配置完成 ====================\033[0m"
echo -e "✅ 面板地址：http://$ip:$PANEL_PORT"
echo -e "✅ 用户名：$USERNAME"
echo -e "✅ 密码：$PASSWORD"
echo -e "✅ 3x-ui版本：$LATEST_VERSION（最新版）"
echo -e "✅ BBR加速：已配置（内核≥4.9则已生效）"
echo -e "🔧 常用命令："
echo -e "  查看状态：systemctl status x-ui"
echo -e "  重启面板：systemctl restart x-ui"
echo -e "  升级面板：重新运行本脚本即可自动更新到最新版"
