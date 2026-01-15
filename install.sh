#!/bin/bash

# ============================================
# 3X-UI 全自动安装脚本（含BBR加速）
# 用户名: liang / 密码: liang / 端口: 2026
# 完全自动化，包含BBR加速优化
# ============================================

set -e  # 任何命令失败则立即退出

# 用户指定的配置（按你的要求）
PANEL_USERNAME="liang"
PANEL_PASSWORD="liang"
PANEL_PORT="2026"

# 其他配置
DOWNLOAD_TIMEOUT=30
BACKUP_DIR="/tmp/3x-ui-backup-$(date +%s)"
INSTALL_DIR="/usr/local/3x-ui"
CONFIG_DIR="/etc/3x-ui"
SERVICE_FILE="/etc/systemd/system/3x-ui.service"
LOG_FILE="/var/log/3x-ui-install-$(date +%Y%m%d-%H%M%S).log"
ARCH=""
VERSION="latest"

# ============================================
# 工具函数
# ============================================

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_status() {
    echo "[✓] $1"
    log_message "[STATUS] $1"
}

print_warning() {
    echo "[!] $1"
    log_message "[WARNING] $1"
}

print_error() {
    echo "[✗] $1"
    log_message "[ERROR] $1"
    exit 1
}

check_cmd() {
    if [ $? -ne 0 ]; then
        print_error "$1 失败"
    fi
}

# 静默安装依赖
install_dependency() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_message "安装依赖: $cmd"
            if [ -f /etc/debian_version ]; then
                DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
                DEBIAN_FRONTEND=noninteractive apt-get install -y "$cmd" > /dev/null 2>&1
            elif [ -f /etc/redhat-release ]; then
                yum install -y "$cmd" > /dev/null 2>&1
            elif [ -f /etc/centos-release ]; then
                yum install -y "$cmd" > /dev/null 2>&1
            elif [ -f /etc/alpine-release ]; then
                apk add --no-cache "$cmd" > /dev/null 2>&1
            fi
            check_cmd "安装 $cmd"
        fi
    done
}

# ============================================
# BBR加速功能
# ============================================

enable_bbr() {
    print_status "启用 BBR 加速..."
    
    # 检查是否已启用BBR
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        print_status "BBR 已启用"
        return 0
    fi
    
    # 检查内核版本是否支持BBR（4.9+）
    KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
    if [ "$(echo "$KERNEL_VERSION >= 4.9" | bc -l 2>/dev/null)" -eq 1 ] || [ "$KERNEL_VERSION" = "4.9" ]; then
        print_status "内核版本 $KERNEL_VERSION 支持 BBR"
    else
        print_warning "内核版本 $KERNEL_VERSION 可能不支持BBR，尝试启用..."
    fi
    
    # 启用BBR
    cat >> /etc/sysctl.conf << EOF
# BBR Congestion Control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Network optimization
net.ipv4.tcp_fastopen=3
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.netdev_max_backlog=10000
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30
EOF
    
    # 应用配置
    sysctl -p > /dev/null 2>&1
    
    # 检查是否启用成功
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        print_status "BBR 加速已成功启用"
    else
        print_warning "BBR 启用失败，但将继续安装"
    fi
}

# 优化系统参数
optimize_system() {
    print_status "优化系统参数..."
    
    # 增加文件描述符限制
    cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
    
    # 优化TCP参数
    cat >> /etc/sysctl.conf << EOF
# TCP optimization
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 10000 65000
EOF
    
    # 应用配置
    sysctl -p > /dev/null 2>&1
    print_status "系统参数优化完成"
}

# ============================================
# 安装过程开始
# ============================================

# 记录开始时间
START_TIME=$(date +%s)
log_message "=== 3X-UI 全自动安装开始 ==="
log_message "用户名: $PANEL_USERNAME, 密码: $PANEL_PASSWORD, 端口: $PANEL_PORT"

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    print_error "请使用 root 用户运行此脚本"
fi

# 系统优化
enable_bbr
optimize_system

# 检测系统架构
detect_arch() {
    case "$(uname -m)" in
        'x86_64' | 'x64') ARCH="amd64" ;;
        'aarch64' | 'arm64') ARCH="arm64" ;;
        'armv7l' | 'arm') ARCH="armv7" ;;
        'i386' | 'i686') ARCH="386" ;;
        *)
            ARCH="amd64"  # 默认使用amd64
            print_warning "未知架构 $(uname -m)，使用默认架构: amd64"
            ;;
    esac
    print_status "系统架构: $ARCH"
}

# 安装依赖
install_dependencies() {
    print_status "安装系统依赖..."
    install_dependency curl wget unzip openssl
}

# 停止旧服务
stop_old_service() {
    print_status "停止旧服务..."
    
    # 停止 3x-ui
    if systemctl list-unit-files | grep -q 3x-ui.service; then
        systemctl stop 3x-ui > /dev/null 2>&1 || true
        systemctl disable 3x-ui > /dev/null 2>&1 || true
    fi
    
    # 停止 x-ui
    if systemctl list-unit-files | grep -q x-ui.service; then
        systemctl stop x-ui > /dev/null 2>&1 || true
        systemctl disable x-ui > /dev/null 2>&1 || true
    fi
}

# 备份旧数据
backup_old_data() {
    print_status "备份旧数据..."
    
    mkdir -p "$BACKUP_DIR" > /dev/null 2>&1
    
    # 备份数据库
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        cp -f "/etc/x-ui/x-ui.db" "$BACKUP_DIR/x-ui.db.bak" > /dev/null 2>&1
    fi
    
    if [ -f "/etc/3x-ui/3x-ui.db" ]; then
        cp -f "/etc/3x-ui/3x-ui.db" "$BACKUP_DIR/3x-ui.db.bak" > /dev/null 2>&1
    fi
    
    # 备份配置文件
    if [ -d "/etc/x-ui" ]; then
        cp -rf "/etc/x-ui" "$BACKUP_DIR/x-ui-config" > /dev/null 2>&1
    fi
}

# 下载主程序
download_3xui() {
    print_status "下载 3X-UI 主程序..."
    
    # 多个下载源
    local urls=(
        "https://github.com/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
        "https://cdn.jsdelivr.net/gh/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
        "https://ghproxy.com/https://github.com/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
    )
    
    for url in "${urls[@]}"; do
        print_status "尝试从: $(echo $url | cut -d'/' -f3)"
        if timeout $DOWNLOAD_TIMEOUT wget --no-check-certificate -q -O /tmp/3x-ui-linux-${ARCH}.zip "$url"; then
            print_status "下载成功"
            return 0
        fi
        print_warning "下载失败，尝试下一个源..."
    done
    
    print_error "所有下载源都失败，请检查网络"
}

# 解压和安装
install_files() {
    print_status "解压安装文件..."
    
    rm -rf /tmp/3x-ui-linux-${ARCH} > /dev/null 2>&1
    
    if ! unzip -q -o /tmp/3x-ui-linux-${ARCH}.zip -d /tmp/3x-ui-linux-${ARCH} 2>/dev/null; then
        print_error "解压失败"
    fi
    
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR/tls" > /dev/null 2>&1
    
    # 复制文件
    cp -f /tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui "$INSTALL_DIR/" > /dev/null 2>&1
    if [ -d "/tmp/3x-ui-linux-${ARCH}/3x-ui/bin" ]; then
        cp -f /tmp/3x-ui-linux-${ARCH}/3x-ui/bin/* "$INSTALL_DIR/" > /dev/null 2>&1
    fi
    
    # 设置权限
    chmod +x "$INSTALL_DIR/x-ui" > /dev/null 2>&1
    chown -R root:root "$INSTALL_DIR" > /dev/null 2>&1
    
    print_status "文件安装完成"
}

# 生成证书
generate_certificate() {
    print_status "生成 SSL 证书..."
    
    local cert_file="$CONFIG_DIR/tls/cert.pem"
    local key_file="$CONFIG_DIR/tls/key.pem"
    
    # 生成自签名证书 (完全静默)
    openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes \
        -out "$cert_file" \
        -keyout "$key_file" \
        -subj "/C=US/ST=California/L=San Francisco/O=3X-UI/CN=localhost" \
        2>/dev/null
    
    # 设置权限
    chmod 600 "$cert_file" "$key_file" > /dev/null 2>&1
    chown root:root "$cert_file" "$key_file" > /dev/null 2>&1
    
    print_status "SSL 证书已生成"
}

# 迁移旧数据
migrate_data() {
    print_status "迁移旧数据..."
    
    # 优先使用 x-ui 的数据
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        cp -f "/etc/x-ui/x-ui.db" "$CONFIG_DIR/3x-ui.db" > /dev/null 2>&1
        print_status "已迁移 x-ui 数据库"
    # 其次使用 3x-ui 的数据
    elif [ -f "/etc/3x-ui/3x-ui.db" ]; then
        cp -f "/etc/3x-ui/3x-ui.db" "$CONFIG_DIR/3x-ui.db" > /dev/null 2>&1
        print_status "已迁移 3x-ui 数据库"
    else
        # 创建新数据库
        touch "$CONFIG_DIR/3x-ui.db" > /dev/null 2>&1
    fi
    
    # 设置数据库权限
    chmod 644 "$CONFIG_DIR/3x-ui.db" > /dev/null 2>&1
    chown root:root "$CONFIG_DIR/3x-ui.db" > /dev/null 2>&1
    
    print_status "数据迁移完成"
}

# 创建系统服务
create_service() {
    print_status "创建系统服务..."
    
    # 移除旧服务文件
    rm -f /etc/systemd/system/x-ui.service > /dev/null 2>&1
    rm -f /etc/systemd/system/3x-ui.service > /dev/null 2>&1
    
    # 创建新服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=3X-UI Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/x-ui
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload > /dev/null 2>&1
    
    # 启用服务
    systemctl enable 3x-ui > /dev/null 2>&1
    
    print_status "系统服务创建完成"
}

# 配置防火墙
configure_firewall() {
    print_status "配置防火墙..."
    
    # 检测防火墙类型并配置
    if command -v ufw > /dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
        ufw allow "$PANEL_PORT/tcp" > /dev/null 2>&1
        ufw reload > /dev/null 2>&1
        print_status "UFW 防火墙已配置"
    elif command -v firewall-cmd > /dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="$PANEL_PORT/tcp" > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        print_status "FirewallD 已配置"
    elif command -v iptables > /dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$PANEL_PORT" -j ACCEPT > /dev/null 2>&1
        # 尝试保存规则
        if command -v iptables-save > /dev/null 2>&1; then
            mkdir -p /etc/iptables > /dev/null 2>&1
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        print_status "iptables 已配置"
    else
        print_warning "未检测到防火墙，端口 $PANEL_PORT 可能需要手动开放"
    fi
}

# 配置面板参数
configure_panel() {
    print_status "配置面板参数..."
    
    # 先停止可能正在运行的服务
    systemctl stop 3x-ui 2>/dev/null || true
    sleep 2
    
    # 创建配置文件
    cat > "$CONFIG_DIR/config.json" << EOF
{
    "panel_port": $PANEL_PORT,
    "panel_settings": {
        "username": "$PANEL_USERNAME",
        "password": "$PANEL_PASSWORD"
    },
    "ssl": {
        "enabled": true,
        "cert_file": "$CONFIG_DIR/tls/cert.pem",
        "key_file": "$CONFIG_DIR/tls/key.pem"
    }
}
EOF
    
    # 设置配置文件权限
    chmod 600 "$CONFIG_DIR/config.json" > /dev/null 2>&1
    chown root:root "$CONFIG_DIR/config.json" > /dev/null 2>&1
    
    print_status "面板参数配置完成"
}

# 启动服务
start_service() {
    print_status "启动 3X-UI 服务..."
    
    # 启动服务
    systemctl start 3x-ui > /dev/null 2>&1
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet 3x-ui; then
        print_status "3X-UI 服务启动成功"
    else
        print_warning "服务启动可能有问题，尝试查看日志: journalctl -u 3x-ui"
        # 尝试重启一次
        systemctl restart 3x-ui > /dev/null 2>&1
        sleep 3
    fi
}

# 清理临时文件
cleanup() {
    print_status "清理临时文件..."
    
    rm -f /tmp/3x-ui-linux-${ARCH}.zip > /dev/null 2>&1
    rm -rf /tmp/3x-ui-linux-${ARCH} > /dev/null 2>&1
    
    # 保留备份目录，但记录位置
    if [ -d "$BACKUP_DIR" ]; then
        echo "备份目录: $BACKUP_DIR" >> "$LOG_FILE"
    fi
    
    print_status "清理完成"
}

# 显示安装结果
show_result() {
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # 获取本机IP
    LOCAL_IP="127.0.0.1"
    if command -v curl > /dev/null 2>&1; then
        LOCAL_IP=$(curl -s -4 ip.sb 2>/dev/null || echo "127.0.0.1")
    elif command -v wget > /dev/null 2>&1; then
        LOCAL_IP=$(wget -qO- ipinfo.io/ip 2>/dev/null || echo "127.0.0.1")
    else
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    fi
    
    # 检查BBR状态
    BBR_STATUS="未启用"
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        BBR_STATUS="已启用"
    fi
    
    # 创建凭据文件
    cat > /root/3x-ui-install-result.txt << EOF
================================
3X-UI 自动安装完成
================================
安装时间: $(date)
安装耗时: ${DURATION}秒
日志文件: $LOG_FILE
BBR状态: ${BBR_STATUS}

访问地址:
  http://${LOCAL_IP}:${PANEL_PORT}
  https://${LOCAL_IP}:${PANEL_PORT}

登录凭据:
  用户名: ${PANEL_USERNAME}
  密码: ${PANEL_PASSWORD}
  端口: ${PANEL_PORT}

管理命令:
  状态检查: systemctl status 3x-ui
  启动服务: systemctl start 3x-ui
  停止服务: systemctl stop 3x-ui
  重启服务: systemctl restart 3x-ui
  查看日志: journalctl -u 3x-ui -f

证书位置:
  $CONFIG_DIR/tls/cert.pem
  $CONFIG_DIR/tls/key.pem

网络优化:
  BBR加速: ${BBR_STATUS}
  文件描述符: 65535

安全警告:
  当前使用弱密码，建议立即修改！
================================
EOF
    
    # 显示简洁结果
    echo ""
    echo "========================================"
    echo "  3X-UI 安装完成！"
    echo "========================================"
    echo "  面板地址: http://${LOCAL_IP}:${PANEL_PORT}"
    echo "  用户名: ${PANEL_USERNAME}"
    echo "  密码: ${PANEL_PASSWORD}"
    echo "  端口: ${PANEL_PORT}"
    echo "  BBR加速: ${BBR_STATUS}"
    echo "----------------------------------------"
    echo "  安装耗时: ${DURATION}秒"
    echo "  日志文件: $LOG_FILE"
    echo "  详细结果: /root/3x-ui-install-result.txt"
    echo "========================================"
    
    # 验证服务状态
    echo ""
    echo "服务状态检查:"
    if systemctl is-active --quiet 3x-ui; then
        echo "  [✓] 3X-UI 服务运行正常"
    else
        echo "  [!] 服务未运行，请检查日志"
    fi
    
    # 检查端口
    if ss -tlnp | grep -q ":${PANEL_PORT} "; then
        echo "  [✓] 端口 ${PANEL_PORT} 监听正常"
    else
        echo "  [!] 端口未监听，服务可能未启动"
    fi
    
    # 检查BBR状态
    echo ""
    echo "网络优化状态:"
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "  [✓] BBR 加速已启用"
    else
        echo "  [!] BBR 加速未启用"
    fi
}

# ============================================
# 主安装流程
# ============================================

main() {
    echo "开始 3X-UI 全自动安装（含BBR加速）..."
    echo "配置: 用户=liang, 密码=liang, 端口=2026"
    echo "安装日志: $LOG_FILE"
    echo ""
    
    # 执行安装步骤
    detect_arch
    install_dependencies
    stop_old_service
    backup_old_data
    download_3xui
    install_files
    generate_certificate
    migrate_data
    configure_panel
    create_service
    start_service
    configure_firewall
    cleanup
    show_result
    
    log_message "=== 3X-UI 安装完成 ==="
}

# 执行主函数
main
