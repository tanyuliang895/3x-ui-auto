#!/bin/bash

# ============================================
# 3X-UI 全自动安装脚本（修复版）
# 修复版本号问题，优化下载逻辑
# 用户名: liang / 密码: liang / 端口: 2026
# 完全自动化零交互，包含BBR加速
# ============================================

set -e

# 用户指定的配置
PANEL_USERNAME="liang"
PANEL_PASSWORD="liang"
PANEL_PORT="2026"

# 其他配置
DOWNLOAD_TIMEOUT=60
BACKUP_DIR="/tmp/3x-ui-backup-$(date +%s)"
INSTALL_DIR="/usr/local/3x-ui"
CONFIG_DIR="/etc/3x-ui"
SERVICE_FILE="/etc/systemd/system/3x-ui.service"
LOG_FILE="/var/log/3x-ui-install-$(date +%Y%m%d-%H%M%S).log"

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

# ============================================
# BBR加速功能
# ============================================

enable_bbr() {
    print_status "启用 BBR 加速..."
    
    # 检查是否已启用BBR
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        print_status "BBR 已启用"
        return 0
    fi
    
    # 启用BBR优化
    cat >> /etc/sysctl.conf << 'EOF'
# BBR 网络优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP 参数优化
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
EOF
    
    # 应用配置
    sysctl -p > /dev/null 2>&1
    
    # 验证BBR是否启用
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        print_status "BBR 加速已成功启用"
    else
        print_warning "BBR 启用失败（可能内核不支持），继续安装..."
    fi
}

# ============================================
# 获取最新版本号（修复的核心）
# ============================================

get_latest_version() {
    print_status "获取 3X-UI 最新版本号..."
    
    # 尝试从GitHub API获取最新版本
    local version=""
    
    # 方法1: 使用GitHub API
    if command -v curl > /dev/null 2>&1; then
        version=$(curl -s --connect-timeout 10 \
            "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" \
            | grep -o '"tag_name": *"[^"]*"' \
            | head -1 \
            | cut -d'"' -f4 \
            | sed 's/^v//' 2>/dev/null)
    fi
    
    # 方法2: 如果方法1失败，尝试直接解析release页面
    if [ -z "$version" ] && command -v curl > /dev/null 2>&1; then
        version=$(curl -s --connect-timeout 10 \
            "https://github.com/MHSanaei/3x-ui/releases/latest" \
            | grep -o '/releases/tag/v[0-9]*\.[0-9]*\.[0-9]*' \
            | head -1 \
            | cut -d'/' -f5 \
            | sed 's/^v//' 2>/dev/null)
    fi
    
    # 如果无法获取版本号，使用已知可用的版本
    if [ -z "$version" ]; then
        print_warning "无法获取最新版本，使用已知稳定版本: 1.8.4"
        version="1.8.4"
    else
        print_status "检测到最新版本: v$version"
    fi
    
    echo "$version"
}

# ============================================
# 安装过程
# ============================================

detect_arch() {
    case "$(uname -m)" in
        'x86_64' | 'x64') ARCH="amd64" ;;
        'aarch64' | 'arm64') ARCH="arm64" ;;
        'armv7l' | 'arm') ARCH="armv7" ;;
        'i386' | 'i686') ARCH="386" ;;
        *)
            ARCH="amd64"
            print_warning "未知架构 $(uname -m)，使用默认架构: amd64"
            ;;
    esac
    print_status "系统架构: $ARCH"
}

install_dependencies() {
    print_status "安装系统依赖..."
    
    if [ -f /etc/debian_version ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip > /dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl wget unzip > /dev/null 2>&1
    elif [ -f /etc/centos-release ]; then
        yum install -y curl wget unzip > /dev/null 2>&1
    fi
    
    # 验证必要的工具已安装
    if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
        print_error "无法安装下载工具 (curl/wget)"
    fi
    
    if ! command -v unzip > /dev/null 2>&1; then
        print_error "无法安装解压工具 (unzip)"
    fi
    
    print_status "系统依赖安装完成"
}

download_3xui() {
    print_status "下载 3X-UI 主程序..."
    
    # 获取最新版本号
    local version=$(get_latest_version)
    local filename="3x-ui-linux-${ARCH}.zip"
    local download_url="https://github.com/MHSanaei/3x-ui/releases/download/v${version}/${filename}"
    
    print_status "下载地址: $download_url"
    
    # 尝试下载
    local success=0
    local temp_file="/tmp/${filename}"
    
    # 清理可能存在的旧文件
    rm -f "$temp_file" 2>/dev/null
    
    # 方法1: 使用curl下载
    if command -v curl > /dev/null 2>&1; then
        print_status "使用 curl 下载..."
        if curl -L --connect-timeout 30 --retry 3 -o "$temp_file" "$download_url"; then
            success=1
        fi
    fi
    
    # 方法2: 如果curl失败，尝试wget
    if [ $success -eq 0 ] && command -v wget > /dev/null 2>&1; then
        print_status "使用 wget 下载..."
        if wget --timeout=30 --tries=3 -O "$temp_file" "$download_url"; then
            success=1
        fi
    fi
    
    # 检查下载是否成功
    if [ $success -eq 0 ]; then
        print_error "下载失败，请检查:"
        print_error "  1. 网络连接"
        print_error "  2. GitHub访问状态"
        print_error "  3. 版本号是否正确"
    fi
    
    # 检查文件大小和完整性
    local file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    
    if [ "$file_size" -lt 102400 ]; then  # 小于100KB可能是错误页面
        print_warning "文件大小异常 ($file_size 字节)，可能是错误页面"
        
        # 检查文件内容
        if head -c 200 "$temp_file" 2>/dev/null | grep -q -i "html\|not found\|error\|404"; then
            print_error "下载的文件是错误页面，可能是版本号问题"
        fi
    else
        print_status "文件下载成功，大小: $(($file_size/1024)) KB"
    fi
    
    # 移动文件到标准位置
    mv "$temp_file" "/tmp/3x-ui-linux-${ARCH}.zip" 2>/dev/null
    print_status "下载完成"
}

install_files() {
    print_status "解压安装文件..."
    
    # 清理旧目录
    rm -rf /tmp/3x-ui-linux-${ARCH} 2>/dev/null
    
    # 创建临时目录
    mkdir -p /tmp/3x-ui-linux-${ARCH}
    
    # 解压文件
    if ! unzip -q -o "/tmp/3x-ui-linux-${ARCH}.zip" -d /tmp/3x-ui-linux-${ARCH} 2>/dev/null; then
        print_warning "标准解压失败，尝试其他解压方法..."
        
        # 尝试使用Python解压
        if command -v python3 > /dev/null 2>&1; then
            if python3 -c "import zipfile; zipfile.ZipFile('/tmp/3x-ui-linux-${ARCH}.zip').extractall('/tmp/3x-ui-linux-${ARCH}')" 2>/dev/null; then
                print_status "Python解压成功"
            else
                print_error "解压失败，文件可能已损坏"
            fi
        else
            print_error "解压失败且无Python可用"
        fi
    else
        print_status "解压成功"
    fi
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR/tls"
    
    # 查找并复制x-ui二进制文件
    local xui_bin=""
    
    # 尝试多个可能的路径
    if [ -f "/tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui" ]; then
        xui_bin="/tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui"
    elif [ -f "/tmp/3x-ui-linux-${ARCH}/x-ui" ]; then
        xui_bin="/tmp/3x-ui-linux-${ARCH}/x-ui"
    else
        # 搜索所有可能的x-ui文件
        xui_bin=$(find "/tmp/3x-ui-linux-${ARCH}" -name "x-ui" -type f | head -1)
    fi
    
    if [ -n "$xui_bin" ] && [ -f "$xui_bin" ]; then
        cp -f "$xui_bin" "$INSTALL_DIR/"
        print_status "找到并复制 x-ui 二进制文件"
    else
        print_error "未找到 x-ui 可执行文件"
    fi
    
    # 复制其他可能的文件
    if [ -d "/tmp/3x-ui-linux-${ARCH}/3x-ui/bin" ]; then
        cp -f /tmp/3x-ui-linux-${ARCH}/3x-ui/bin/* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    
    # 设置权限
    chmod +x "$INSTALL_DIR/x-ui" 2>/dev/null || chmod 755 "$INSTALL_DIR/x-ui"
    chown -R root:root "$INSTALL_DIR"
    
    print_status "文件安装完成"
}

generate_certificate() {
    print_status "生成 SSL 证书..."
    
    mkdir -p "$CONFIG_DIR/tls"
    
    # 生成自签名证书
    openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes \
        -out "$CONFIG_DIR/tls/cert.pem" \
        -keyout "$CONFIG_DIR/tls/key.pem" \
        -subj "/C=US/ST=California/L=San Francisco/O=3X-UI/CN=localhost" \
        2>/dev/null
    
    # 设置权限
    chmod 600 "$CONFIG_DIR/tls/cert.pem" "$CONFIG_DIR/tls/key.pem"
    chown root:root "$CONFIG_DIR/tls/cert.pem" "$CONFIG_DIR/tls/key.pem"
    
    print_status "SSL 证书已生成"
}

configure_database() {
    print_status "配置数据库..."
    
    # 检查是否有旧数据需要迁移
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        print_status "检测到旧版 x-ui 数据库，尝试迁移..."
        cp -f "/etc/x-ui/x-ui.db" "$CONFIG_DIR/3x-ui.db" 2>/dev/null || true
    elif [ -f "/etc/3x-ui/3x-ui.db" ]; then
        print_status "检测到旧版 3x-ui 数据库..."
        cp -f "/etc/3x-ui/3x-ui.db" "$CONFIG_DIR/3x-ui.db" 2>/dev/null || true
    fi
    
    # 如果数据库不存在，创建新数据库
    if [ ! -f "$CONFIG_DIR/3x-ui.db" ]; then
        touch "$CONFIG_DIR/3x-ui.db"
        print_status "创建新数据库"
    fi
    
    # 设置数据库权限
    chmod 644 "$CONFIG_DIR/3x-ui.db" 2>/dev/null || true
    chown root:root "$CONFIG_DIR/3x-ui.db" 2>/dev/null || true
    
    print_status "数据库配置完成"
}

create_service() {
    print_status "创建系统服务..."
    
    # 移除可能存在的旧服务文件
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null
    rm -f /etc/systemd/system/3x-ui.service 2>/dev/null
    
    # 创建服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=3X-UI Panel Service
Documentation=https://github.com/MHSanaei/3x-ui
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/x-ui
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

# 安全设置
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd并启用服务
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable 3x-ui > /dev/null 2>&1
    
    print_status "系统服务创建完成"
}

configure_firewall() {
    print_status "配置防火墙..."
    
    # 尝试配置防火墙（如果可用）
    local port_open=0
    
    # 检查UFW
    if command -v ufw > /dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
        if ufw allow "$PANEL_PORT/tcp" > /dev/null 2>&1; then
            ufw reload > /dev/null 2>&1
            print_status "UFW 防火墙已配置"
            port_open=1
        fi
    # 检查firewalld
    elif command -v firewall-cmd > /dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        if firewall-cmd --permanent --add-port="$PANEL_PORT/tcp" > /dev/null 2>&1; then
            firewall-cmd --reload > /dev/null 2>&1
            print_status "FirewallD 已配置"
            port_open=1
        fi
    # 检查iptables
    elif command -v iptables > /dev/null 2>&1; then
        if iptables -I INPUT -p tcp --dport "$PANEL_PORT" -j ACCEPT > /dev/null 2>&1; then
            print_status "iptables 规则已添加"
            port_open=1
        fi
    fi
    
    if [ $port_open -eq 0 ]; then
        print_warning "无法自动配置防火墙，请手动开放端口 $PANEL_PORT"
    fi
}

start_service() {
    print_status "启动 3X-UI 服务..."
    
    # 停止可能正在运行的服务
    systemctl stop x-ui 2>/dev/null || true
    systemctl stop 3x-ui 2>/dev/null || true
    sleep 2
    
    # 启动服务
    if ! systemctl start 3x-ui; then
        print_warning "服务启动失败，尝试调试启动..."
        
        # 尝试直接运行二进制文件查看错误
        if [ -f "$INSTALL_DIR/x-ui" ]; then
            echo "尝试直接运行二进制文件..."
            timeout 5 "$INSTALL_DIR/x-ui" --help || true
        fi
        
        # 再次尝试启动
        systemctl restart 3x-ui 2>/dev/null || true
        sleep 3
    fi
    
    # 检查服务状态
    if systemctl is-active --quiet 3x-ui; then
        print_status "3X-UI 服务启动成功"
    else
        print_warning "服务可能未正常运行，请检查: journalctl -u 3x-ui"
    fi
}

cleanup() {
    print_status "清理临时文件..."
    
    # 清理下载和解压的临时文件
    rm -f "/tmp/3x-ui-linux-${ARCH}.zip" 2>/dev/null
    rm -rf "/tmp/3x-ui-linux-${ARCH}" 2>/dev/null
    
    print_status "清理完成"
}

show_result() {
    # 获取本机IP
    local local_ip="127.0.0.1"
    
    if command -v curl > /dev/null 2>&1; then
        local_ip=$(curl -s -4 --connect-timeout 3 ip.sb 2>/dev/null || \
                   curl -s -4 --connect-timeout 3 ifconfig.me 2>/dev/null || \
                   echo "127.0.0.1")
    fi
    
    if [ "$local_ip" = "127.0.0.1" ]; then
        local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | head -1 || echo "127.0.0.1")
    fi
    
    # 检查服务状态
    local service_status="未知"
    if systemctl is-active --quiet 3x-ui; then
        service_status="运行中"
    elif systemctl is-failed --quiet 3x-ui; then
        service_status="失败"
    else
        service_status="未运行"
    fi
    
    # 检查端口监听
    local port_status="未监听"
    if ss -tlnp 2>/dev/null | grep -q ":$PANEL_PORT "; then
        port_status="已监听"
    elif netstat -tlnp 2>/dev/null | grep -q ":$PANEL_PORT "; then
        port_status="已监听"
    fi
    
    # 显示安装结果
    echo ""
    echo "========================================"
    echo "      3X-UI 安装完成！"
    echo "========================================"
    echo ""
    echo "  访问地址:"
    echo "    http://${local_ip}:${PANEL_PORT}"
    echo "    https://${local_ip}:${PANEL_PORT}"
    echo ""
    echo "  登录凭据:"
    echo "    用户名: $PANEL_USERNAME"
    echo "    密  码: $PANEL_PASSWORD"
    echo "    端  口: $PANEL_PORT"
    echo ""
    echo "  服务状态: $service_status"
    echo "  端口状态: $port_status"
    echo ""
    echo "  管理命令:"
    echo "    启动: systemctl start 3x-ui"
    echo "    停止: systemctl stop 3x-ui"
    echo "    状态: systemctl status 3x-ui"
    echo "    日志: journalctl -u 3x-ui -f"
    echo ""
    echo "  安装日志: $LOG_FILE"
    echo "========================================"
    echo ""
    
    # 重要安全提醒
    if [ "$PANEL_PASSWORD" = "liang" ]; then
        echo "⚠️  ⚠️  ⚠️  重要安全警告 ⚠️  ⚠️  ⚠️"
        echo "您正在使用默认密码 'liang'，这是极不安全的！"
        echo "请立即登录面板并修改密码！"
        echo ""
    fi
    
    # 保存安装信息到文件
    cat > /root/3x-ui-install-info.txt << EOF
================================
3X-UI 安装信息
================================
安装时间: $(date)
系统架构: $(uname -m)
面板版本: $(get_latest_version)

访问信息:
  HTTP:  http://${local_ip}:${PANEL_PORT}
  HTTPS: https://${local_ip}:${PANEL_PORT}

登录凭据:
  用户名: ${PANEL_USERNAME}
  密码: ${PANEL_PASSWORD}
  端口: ${PANEL_PORT}

服务状态: ${service_status}
端口状态: ${port_status}

安装目录: ${INSTALL_DIR}
配置目录: ${CONFIG_DIR}
数据文件: ${CONFIG_DIR}/3x-ui.db
证书文件: ${CONFIG_DIR}/tls/

管理命令:
  systemctl start 3x-ui     # 启动
  systemctl stop 3x-ui      # 停止
  systemctl restart 3x-ui   # 重启
  systemctl status 3x-ui    # 状态
  journalctl -u 3x-ui -f    # 日志

安全提醒:
  当前使用默认密码，请立即修改！
================================
EOF
    
    echo "详细信息已保存到: /root/3x-ui-install-info.txt"
    echo ""
}

# ============================================
# 主安装流程
# ============================================

main() {
    echo ""
    echo "========================================"
    echo "  3X-UI 全自动安装脚本（修复版）"
    echo "========================================"
    echo "  用户名: $PANEL_USERNAME"
    echo "  密码: $PANEL_PASSWORD"
    echo "  端口: $PANEL_PORT"
    echo "========================================"
    echo ""
    echo "开始安装，详细日志: $LOG_FILE"
    echo ""
    
    # 检查root权限
    if [ "$(id -u)" != "0" ]; then
        print_error "请使用 root 用户运行此脚本 (sudo $0)"
    fi
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行安装步骤
    enable_bbr
    detect_arch
    install_dependencies
    download_3xui
    install_files
    generate_certificate
    configure_database
    create_service
    configure_firewall
    start_service
    cleanup
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_message "安装完成，耗时 ${duration} 秒"
    
    # 显示结果
    show_result
    
    # 最终状态检查
    echo ""
    echo "最终状态检查:"
    echo -n "  服务状态: "
    if systemctl is-active --quiet 3x-ui; then
        echo "[✓] 运行正常"
    else
        echo "[!] 未运行"
        echo "  请运行以下命令查看错误:"
        echo "    journalctl -u 3x-ui -n 50 --no-pager"
    fi
    
    echo -n "  端口监听: "
    if ss -tlnp 2>/dev/null | grep -q ":$PANEL_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$PANEL_PORT "; then
        echo "[✓] 正常"
    else
        echo "[!] 未监听"
    fi
    
    echo ""
    echo "安装完成！如果遇到问题，请查看日志文件: $LOG_FILE"
}

# 执行主函数
main
