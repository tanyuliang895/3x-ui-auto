#!/bin/bash

# =====================================================
# liang 3x-ui Auto Installer v1.0
# MHSanaei/3x-ui
# Zero Interaction Install
# =====================================================

set -e

export LANG=zh_CN.UTF-8


# ================= 配置 =================

USERNAME="liang"
PASSWORD="liang123456"
PORT="2026"

SERVICE="x-ui"

BACKUP_PATH="/root/x-ui-backup"


# ================= LOGO =================

clear

echo "
=====================================================
             liang 3x-ui Auto Installer

          MHSanaei 3x-ui Zero Interaction

=====================================================
"



# ================= 系统检测 =================


detect_system(){

echo "========== 检测系统 =========="


if [ ! -f /etc/os-release ]; then

echo "无法检测系统"

exit 1

fi


source /etc/os-release


case "$ID" in


ubuntu|debian)

PM="apt"

;;


centos|rhel|rocky|almalinux)

PM="yum"

;;


fedora)

PM="dnf"

;;


alpine)

PM="apk"

;;


*)

echo "不支持系统: $ID"

exit 1

;;

esac


echo "系统: $PRETTY_NAME"

echo "包管理: $PM"

}



# ================= 安装依赖 =================


install_dependencies(){

echo

echo "========== 安装依赖 =========="


case "$PM" in


apt)

apt update -y

apt install -y \
curl \
wget \
tar \
openssl \
jq \
socat \
cron \
ethtool \
iproute2 \
net-tools


;;


yum)

yum install -y epel-release || true

yum install -y \
curl \
wget \
tar \
openssl \
jq \
socat \
cronie \
ethtool \
iproute \
net-tools


;;


dnf)

dnf install -y \
curl \
wget \
tar \
openssl \
jq \
socat \
cronie \
ethtool \
iproute \
net-tools


;;


apk)

apk update

apk add \
curl \
wget \
tar \
openssl \
jq \
socat \
dcron \
ethtool \
iproute2


;;

esac

}



# ================= 安装3x-ui =================


install_3xui(){

echo

echo "========== 安装 MHSanaei 3x-ui =========="


export XUI_NONINTERACTIVE=1


bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)


unset XUI_NONINTERACTIVE


sleep 5



echo

echo "========== 设置面板参数 =========="



/usr/local/x-ui/x-ui setting \
-username "$USERNAME" || true



/usr/local/x-ui/x-ui setting \
-password "$PASSWORD" || true



/usr/local/x-ui/x-ui setting \
-port "$PORT" || true



/usr/local/x-ui/x-ui setting \
-webBasePath "/" || true



systemctl restart x-ui

systemctl enable x-ui


}



# ================= BBR =================


enable_bbr(){


echo

echo "========== 开启 BBR =========="


cat >/etc/sysctl.d/99-liang-bbr.conf <<EOF

net.core.default_qdisc=fq

net.ipv4.tcp_congestion_control=bbr

EOF


sysctl --system >/dev/null 2>&1 || true


}



# ================= 网络优化 =================


network_opt(){


echo

echo "========== 网络优化 =========="


cat >/etc/sysctl.d/99-liang-network.conf <<EOF


net.ipv4.tcp_fastopen=3

net.ipv4.tcp_mtu_probing=1

net.ipv4.tcp_tw_reuse=1

net.ipv4.tcp_fin_timeout=15

net.ipv4.tcp_keepalive_time=300


net.core.rmem_max=16777216

net.core.wmem_max=16777216

net.core.netdev_max_backlog=250000

net.core.somaxconn=65535


fs.file-max=2097152


EOF


sysctl --system >/dev/null 2>&1 || true



NIC=$(ip route | grep default | awk '{print $5}' | head -1)



if [ -n "$NIC" ]

then


echo "优化网卡: $NIC"


ip link set dev "$NIC" mtu 1500 || true


ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || true


fi



ulimit -n 1048576 || true


}



# ================= 防火墙 =================


firewall(){


echo

echo "========== 防火墙设置 =========="


if command -v ufw >/dev/null 2>&1

then


ufw allow "$PORT"/tcp || true

ufw allow 443/tcp || true


elif command -v firewall-cmd >/dev/null 2>&1

then


firewall-cmd --permanent --add-port="$PORT"/tcp || true

firewall-cmd --permanent --add-port=443/tcp || true

firewall-cmd --reload || true


else


iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT || true

iptables -I INPUT -p tcp --dport 443 -j ACCEPT || true


fi


}



# ================= 备份 =================


backup(){


echo

echo "========== 备份配置 =========="


mkdir -p "$BACKUP_PATH"


if [ -d /etc/x-ui ]

then

tar czf \
"$BACKUP_PATH/x-ui-$(date +%F).tar.gz" \
/etc/x-ui


echo "备份完成"


fi


}



# ================= 检测 =================


check_status(){


echo

echo "========== 状态检测 =========="



systemctl is-active --quiet x-ui && \
echo "✅ x-ui运行正常" || \
echo "❌ x-ui异常"



if command -v xray >/dev/null 2>&1

then

echo "✅ Xray版本:"

xray version | head -2

fi



echo

echo "监听端口:"

ss -tlnp | grep LISTEN || true



echo

echo "BBR:"

sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true


}



# ================= 输出 =================


show_info(){


IP=$(curl -4 -s icanhazip.com || echo "服务器IP")


echo "

=====================================================

          liang 3x-ui 安装完成


面板地址:

http://$IP:$PORT


用户名:

$USERNAME


密码:

$PASSWORD


=====================================================


节点配置:

进入后台

入站列表

创建:

VLESS
+
Reality
+
Vision


=====================================================

"



}



# ================= 主流程 =================


main(){


detect_system


install_dependencies


install_3xui


enable_bbr


network_opt


firewall


backup


check_status


show_info


}



main
