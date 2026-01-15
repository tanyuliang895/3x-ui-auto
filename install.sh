#!/bin/bash

# ============================================
# 3X-UI 全自动安装脚本（含BBR加速）- 修复版
# 修复下载和解压问题，增加文件验证
# ============================================

set -e

# 用户指定的配置
PANEL_USERNAME="liang"
PANEL_PASSWORD="liang"
PANEL_PORT="2026"

# 其他配置
DOWNLOAD_TIMEOUT=45  # 增加超时时间
BACKUP_DIR="/tmp/3x-ui-backup-$(date +%s)"
INSTALL_DIR="/usr/local/3x-ui"
CONFIG_DIR="/etc/3x-ui"
SERVICE_FILE="/etc/systemd/system/3x-ui.service"
LOG_FILE="/var/log/3x-ui-install-$(date +%Y%m%d-%H%M%S).log"
ARCH=""

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
    
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        print_status "BBR 已启用"
        return 0
    fi
    
    # 启用BBR
    cat >> /etc/sysctl.conf << EOF
# BBR Congestion Control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Network optimization
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.netdev_max_backlog=10000
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_slow_start_after_idle=0
EOF
    
    sysctl -p > /dev/null 2>&1
    
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        print_status "BBR 加速已成功启用"
    else
        print_warning "BBR 启用失败，但将继续安装"
    fi
}

# ============================================
# 修复的下载和解压功能
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

# 检查文件是否是有效的zip文件
check_zip_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # 检查文件大小（至少1KB）
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    if [ "$size" -lt 1024 ]; then
        print_warning "文件太小 ($size 字节)，可能下载不完整"
        return 1
    fi
    
    # 检查文件类型
    if command -v file > /dev/null 2>&1; then
        if file "$file" | grep -q "Zip archive data"; then
            return 0
        fi
    fi
    
    # 检查文件头
    if head -c 4 "$file" | grep -q "^PK"; then
        return 0
    fi
    
    return 1
}

# 下载主程序 - 修复版
download_3xui() {
    print_status "下载 3X-UI 主程序..."
    
    # 多个下载源，包括直接二进制文件
    local urls=(
        "https://cdn.jsdelivr.net/gh/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
        "https://github.com/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
        "https://ghproxy.com/https://github.com/MHSanaei/3x-ui/releases/latest/download/3x-ui-linux-${ARCH}.zip"
    )
    
    local download_success=0
    local attempt=1
    local max_attempts=3
    
    while [ $attempt -le $max_attempts ] && [ $download_success -eq 0 ]; do
        print_status "下载尝试 $attempt/$max_attempts"
        
        for url in "${urls[@]}"; do
            print_status "尝试从: $(echo $url | cut -d'/' -f3)"
            
            # 清理旧文件
            rm -f /tmp/3x-ui-linux-${ARCH}.zip
            
            # 使用curl或wget下载
            if command -v curl > /dev/null 2>&1; then
                if timeout $DOWNLOAD_TIMEOUT curl -sSL -o /tmp/3x-ui-linux-${ARCH}.zip "$url"; then
                    print_status "下载完成，检查文件..."
                    if check_zip_file "/tmp/3x-ui-linux-${ARCH}.zip"; then
                        print_status "文件验证成功"
                        download_success=1
                        break 2
                    else
                        print_warning "文件验证失败，尝试下一个源..."
                        rm -f /tmp/3x-ui-linux-${ARCH}.zip
                    fi
                else
                    print_warning "下载失败，尝试下一个源..."
                fi
            elif command -v wget > /dev/null 2>&1; then
                if timeout $DOWNLOAD_TIMEOUT wget -q -O /tmp/3x-ui-linux-${ARCH}.zip "$url"; then
                    print_status "下载完成，检查文件..."
                    if check_zip_file "/tmp/3x-ui-linux-${ARCH}.zip"; then
                        print_status "文件验证成功"
                        download_success=1
                        break 2
                    else
                        print_warning "文件验证失败，尝试下一个源..."
                        rm -f /tmp/3x-ui-linux-${ARCH}.zip
                    fi
                else
                    print_warning "下载失败，尝试下一个源..."
                fi
            fi
        done
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            print_status "等待 5 秒后重试..."
            sleep 5
        fi
    done
    
    if [ $download_success -eq 0 ]; then
        print_error "所有下载源都失败，请检查网络"
    fi
}

# 解压和安装 - 修复版
install_files() {
    print_status "解压安装文件..."
    
    # 清理旧目录
    rm -rf /tmp/3x-ui-linux-${ARCH}
    
    # 创建临时目录
    mkdir -p /tmp/3x-ui-linux-${ARCH}
    
    # 尝试解压
    if unzip -q -o /tmp/3x-ui-linux-${ARCH}.zip -d /tmp/3x-ui-linux-${ARCH} 2>/dev/null; then
        print_status "解压成功"
    else
        # 如果解压失败，尝试其他方法
        print_warning "标准解压失败，尝试其他方法..."
        
        # 方法1: 使用python解压
        if command -v python3 > /dev/null 2>&1; then
            print_status "尝试使用 Python 解压..."
            if python3 -c "import zipfile; zipfile.ZipFile('/tmp/3x-ui-linux-${ARCH}.zip').extractall('/tmp/3x-ui-linux-${ARCH}')" 2>/dev/null; then
                print_status "Python 解压成功"
            else
                # 方法2: 使用7z解压
                if command -v 7z > /dev/null 2>&1; then
                    print_status "尝试使用 7z 解压..."
                    if 7z x -o/tmp/3x-ui-linux-${ARCH} /tmp/3x-ui-linux-${ARCH}.zip > /dev/null 2>&1; then
                        print_status "7z 解压成功"
                    else
                        print_error "所有解压方法都失败"
                    fi
                else
                    print_error "无法解压文件，请手动检查下载的文件"
                fi
            fi
        fi
    fi
    
    # 检查解压后的文件
    if [ ! -f "/tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui" ]; then
        print_warning "未找到标准路径，尝试查找文件..."
        find /tmp/3x-ui-linux-${ARCH} -name "x-ui" -type f | head -1
    fi
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR/tls"
    
    # 复制文件
    if [ -f "/tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui" ]; then
        cp -f "/tmp/3x-ui-linux-${ARCH}/3x-ui/x-ui" "$INSTALL_DIR/"
        if [ -d "/tmp/3x-ui-linux-${ARCH}/3x-ui/bin" ]; then
            cp -f /tmp/3x-ui-linux-${ARCH}/3x-ui/bin/* "$INSTALL_DIR/" 2>/dev/null || true
        fi
    else
        # 尝试查找x-ui二进制文件
        local xui_bin=$(find /tmp/3x-ui-linux-${ARCH} -name "x-ui" -type f | head -1)
        if [ -n "$xui_bin" ]; then
            cp -f "$xui_bin" "$INSTALL_DIR/"
            print_status "找到并复制 x-ui 二进制文件"
        else
            print_error "未找到 x-ui 可执行文件"
        fi
    fi
    
    # 设置权限
    chmod +x "$INSTALL_DIR/x-ui" 2>/dev/null || true
    chown -R root:root "$INSTALL_DIR"
    
    print_status "文件安装完成"
}

# ============================================
# 简化的安装流程
# ============================================

install_dependencies() {
    print_status "安装系统依赖..."
    
    if [ -f /etc/debian_version ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget unzip > /dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl wget unzip > /dev/null 2>&1
    fi
    
    # 确保unzip可用
    if ! command -v unzip > /dev/null 2>&1; then
        print_error "无法安装 unzip，请手动安装"
    fi
}

generate_certificate() {
    print_status "生成 SSL 证书..."
    
    mkdir -p "$CONFIG_DIR/tls"
    
    openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes \
        -out "$CONFIG_DIR/tls/cert.pem" \
        -keyout "$CONFIG_DIR/tls/key.pem" \
        -subj "/C=US/ST=California/L=San Francisco/O=3X-UI/CN=localhost" \
        2>/dev/null
    
    chmod 600 "$CONFIG_DIR/tls/cert.pem" "$CONFIG_DIR/tls/key.pem"
    print_status "SSL 证书已生成"
}

create_service() {
    print_status "创建系统服务..."
    
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
    
    systemctl daemon-reload > /dev/null 2>&1
    systemctl enable 3x-ui > /dev/null 2>&1
    
    print_status "系统服务创建完成"
}

configure_panel() {
    print_status "配置面板参数..."
    
    # 创建简单的配置文件
    cat > "$CONFIG_DIR/config.json" << EOF
{
    "panel_port": $PANEL_PORT,
    "panel_settings": {
        "username": "$PANEL_USERNAME",
        "password": "$PANEL_PASSWORD"
    }
}
EOF
    
    chmod 600 "$CONFIG_DIR/config.json"
    print_status "面板参数配置完成"
}

start_service() {
    print_status "启动 3X-UI 服务..."
    
    systemctl start 3x-ui > /dev/null 2>&1
    sleep 3
    
    if systemctl is-active --quiet 3x-ui; then
        print_status "3X-UI 服务启动成功"
    else
        print_warning "服务启动可能有问题，尝试重启..."
        systemctl restart 3x-ui > /dev/null 2>&1
        sleep 2
    fi
}

show_result() {
    echo ""
    echo "========================================"
    echo "  3X-UI 安装完成！"
    echo "========================================"
    
    # 获取本机IP
    LOCAL_IP="127.0.0.1"
    if command -v curl > /dev/null 2>&1; then
        LOCAL_IP=$(curl -s -4 ip.sb 2>/dev/null || echo "127.0.0.1")
    fi
    
    echo "  面板地址: http://${LOCAL_IP}:${PANEL_PORT}"
    echo "  用户名: ${PANEL_USERNAME}"
    echo "  密码: ${PANEL_PASSWORD}"
    echo "  端口: ${PANEL_PORT}"
    echo "----------------------------------------"
    echo "  日志文件: $LOG_FILE"
    echo "========================================"
    
    # 验证服务
    echo ""
    echo "服务状态:"
    if systemctl is-active --quiet 3x-ui; then
        echo "  [✓] 3X-UI 服务运行正常"
    else
        echo "  [!] 服务未运行，请检查: journalctl -u 3x-ui"
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
    
    # 检查root
    if [ "$(id -u)" != "0" ]; then
        print_error "请使用 root 用户运行"
    fi
    
    # 启用BBR
    enable_bbr
    
    # 安装步骤
    detect_arch
    install_dependencies
    download_3xui
    install_files
    generate_certificate
    create_service
    configure_panel
    start_service
    
    show_result
    log_message "=== 安装完成 ==="
}

# 执行
main
