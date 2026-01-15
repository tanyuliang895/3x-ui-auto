#!/bin/bash
PORT=2026
USER=liang
PASS=liang

echo "安装 3X-UI（无证书版）..."

# BBR
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1
modprobe tcp_bbr 2>/dev/null

# 依赖
apt update -y && apt install -y curl expect >/dev/null 2>&1 || true

# 下载官方
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o /tmp/3x.sh
chmod +x /tmp/3x.sh

# expect - 任何证书提示都跳过
expect <<END
    set timeout -1
    spawn /tmp/3x.sh
    expect -re "customize.*\[y/n\]" { send "y\r" }
    expect -re "panel port:" { send "$PORT\r" }
    expect -re "SSL|certificate|Choose an option|RECOMMENDED|MANDATORY" { send "n\r" }  # 跳过证书
    expect -re ".*" { send "\r" }  # 所有剩余提示回车
    expect eof
END

rm -f /tmp/3x.sh

# 强制 HTTP + 根路径 + 账号
/usr/local/x-ui/x-ui setting -https false >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -webBasePath "/" >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui setting -username $USER -password $PASS >/dev/null 2>&1 || true
/usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true

echo "完成！访问 http://你的IP:$PORT"
echo "用户: $USER   密码: $PASS"
echo "登录后手动申请证书（面板设置 → SSL 证书）"
