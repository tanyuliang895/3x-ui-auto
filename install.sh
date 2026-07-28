#!/usr/bin/env bash
set -Eeuo pipefail

PANEL_USER="liang"
PANEL_PASS="liang123456"
PANEL_PORT="2026"
PANEL_PATH="/"

XUI_PIN_VERSION="v3.4.2"
XRAY_PIN_VERSION="v26.6.27"

INSTALL_URL="https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"

green="\033[32m"
yellow="\033[33m"
red="\033[31m"
plain="\033[0m"

log() {
  echo -e "${green}[OK]${plain} $*"
}

warn() {
  echo -e "${yellow}[WARN]${plain} $*"
}

fail() {
  echo -e "${red}[ERROR]${plain} $*" >&2
  exit 1
}

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "请使用 root 用户运行此脚本"
  fi
}

install_deps() {
  log "安装基础依赖"

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget tar gzip unzip ca-certificates procps iproute2 iptables

  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget tar gzip unzip ca-certificates procps-ng iproute iptables

  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget tar gzip unzip ca-certificates procps-ng iproute iptables

  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl wget tar gzip unzip ca-certificates procps-ng iproute2 iptables

  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive refresh
    zypper --non-interactive install curl wget tar gzip unzip ca-certificates procps iproute2 iptables

  elif command -v apk >/dev/null 2>&1; then
    apk update
    apk add curl wget tar gzip unzip ca-certificates procps iproute2 iptables

  else
    fail "未识别包管理器，建议使用 Ubuntu / Debian / CentOS / AlmaLinux / RockyLinux / Fedora / Arch / Alpine"
  fi
}

service_stop() {
  systemctl stop x-ui >/dev/null 2>&1 || rc-service x-ui stop >/dev/null 2>&1 || true
}

service_start() {
  systemctl start x-ui >/dev/null 2>&1 || rc-service x-ui start >/dev/null 2>&1 || true
}

service_restart() {
  systemctl restart x-ui >/dev/null 2>&1 || rc-service x-ui restart >/dev/null 2>&1 || true
}

service_enable() {
  systemctl enable x-ui >/dev/null 2>&1 || rc-update add x-ui >/dev/null 2>&1 || true
}

service_is_active() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet x-ui && return 0
  fi

  if command -v rc-service >/dev/null 2>&1; then
    rc-service x-ui status >/dev/null 2>&1 && return 0
  fi

  return 1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|x64|amd64)
      echo "amd64"
      ;;
    i386|i686|x86)
      echo "386"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7*|armv7|arm)
      echo "armv7"
      ;;
    armv6*|armv6)
      echo "armv6"
      ;;
    armv5*|armv5)
      echo "armv5"
      ;;
    s390x)
      echo "s390x"
      ;;
    *)
      fail "当前架构不支持：$(uname -m)"
      ;;
  esac
}

get_xray_asset() {
  local arch
  arch="$(detect_arch)"

  case "${arch}" in
    amd64)
      echo "Xray-linux-64.zip"
      ;;
    386)
      echo "Xray-linux-32.zip"
      ;;
    arm64)
      echo "Xray-linux-arm64-v8a.zip"
      ;;
    armv7)
      echo "Xray-linux-arm32-v7a.zip"
      ;;
    armv6)
      echo "Xray-linux-arm32-v6.zip"
      ;;
    armv5)
      echo "Xray-linux-arm32-v5.zip"
      ;;
    s390x)
      echo "Xray-linux-s390x.zip"
      ;;
    *)
      echo ""
      ;;
  esac
}

find_xray_target() {
  local arch
  local target

  arch="$(detect_arch)"
  target="/usr/local/x-ui/bin/xray-linux-${arch}"

  if [ -f "${target}" ]; then
    echo "${target}"
    return 0
  fi

  target="$(find /usr/local/x-ui/bin -maxdepth 1 -type f -name 'xray-linux-*' 2>/dev/null | head -n 1 || true)"

  if [ -n "${target}" ] && [ -f "${target}" ]; then
    echo "${target}"
    return 0
  fi

  echo ""
}

enable_bbr() {
  log "启用 BBR 加速"

  modprobe tcp_bbr 2>/dev/null || true

  cat > /etc/sysctl.d/99-3xui-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system >/dev/null 2>&1 || true

  local current_bbr
  current_bbr="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

  if [ "${current_bbr}" = "bbr" ]; then
    log "BBR 已启用：${current_bbr}"
  else
    warn "BBR 未成功启用，可能是当前系统内核不支持"
  fi
}

install_3xui() {
  local tmp_script
  tmp_script="$(mktemp)"

  log "下载 3x-ui 官方安装脚本"
  curl -fsSL --connect-timeout 20 -o "${tmp_script}" "${INSTALL_URL}"
  chmod +x "${tmp_script}"

  log "开始 0 交互安装 3x-ui ${XUI_PIN_VERSION}"

  env \
    XUI_NONINTERACTIVE=1 \
    XUI_USERNAME="${PANEL_USER}" \
    XUI_PASSWORD="${PANEL_PASS}" \
    XUI_PANEL_PORT="${PANEL_PORT}" \
    XUI_WEB_BASE_PATH="${PANEL_PATH}" \
    XUI_INIT_WEB_BASE_PATH="${PANEL_PATH}" \
    XUI_SSL_MODE="none" \
    XUI_DB_TYPE="sqlite" \
    bash "${tmp_script}" "${XUI_PIN_VERSION}"

  rm -f "${tmp_script}"

  service_enable
  log "3x-ui ${XUI_PIN_VERSION} 安装完成"
}

force_panel_settings() {
  log "强制设置面板账号、密码、端口、根路径"

  if [ -x /usr/local/x-ui/x-ui ]; then
    /usr/local/x-ui/x-ui setting \
      -username "${PANEL_USER}" \
      -password "${PANEL_PASS}" \
      -port "${PANEL_PORT}" \
      -webBasePath "${PANEL_PATH}" >/dev/null 2>&1 || true
  else
    warn "未找到 /usr/local/x-ui/x-ui，跳过强制设置"
  fi

  service_enable
  service_restart
  sleep 2

  if service_is_active; then
    log "3x-ui 服务运行正常"
  else
    systemctl status x-ui --no-pager 2>/dev/null || rc-service x-ui status 2>/dev/null || true
    fail "3x-ui 启动失败，请查看上面的错误日志"
  fi
}

pin_xray_core_for_shadowrocket() {
  log "固定 Xray Core 到 ${XRAY_PIN_VERSION}"

  local asset
  local target
  local tmp_dir

  asset="$(get_xray_asset)"

  if [ -z "${asset}" ]; then
    warn "当前架构不支持自动固定 Xray Core：$(uname -m)"
    return 0
  fi

  if [ ! -d /usr/local/x-ui/bin ]; then
    warn "未找到 /usr/local/x-ui/bin，跳过 Xray Core 固定"
    return 0
  fi

  target="$(find_xray_target)"

  if [ -z "${target}" ]; then
    warn "未找到 xray-linux-* 文件，跳过 Xray Core 固定"
    return 0
  fi

  service_stop

  cp -f "${target}" "${target}.bak.$(date +%Y%m%d-%H%M%S)" || true

  tmp_dir="$(mktemp -d)"

  log "下载 Xray Core ${XRAY_PIN_VERSION}"
  curl -fL --retry 3 --connect-timeout 20 \
    -o "${tmp_dir}/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/${XRAY_PIN_VERSION}/${asset}"

  unzip -o "${tmp_dir}/xray.zip" -d "${tmp_dir}/xray" >/dev/null

  if [ ! -f "${tmp_dir}/xray/xray" ]; then
    rm -rf "${tmp_dir}"
    service_start
    fail "Xray Core 解压失败，未找到 xray 文件"
  fi

  chmod +x "${tmp_dir}/xray/xray"
  cp -f "${tmp_dir}/xray/xray" "${target}"
  chmod +x "${target}"

  rm -rf "${tmp_dir}"

  service_restart
  sleep 2

  log "Xray Core 已固定"
  "${target}" version | head -n 1 || true
}

open_all_ports() {
  log "放行系统内 TCP / UDP 全端口"

  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -qi active; then
      ufw allow 1:65535/tcp || true
      ufw allow 1:65535/udp || true
      ufw reload || true
      log "UFW 已放行所有端口"
    else
      log "UFW 未启用，跳过"
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port=1-65535/tcp || true
      firewall-cmd --permanent --add-port=1-65535/udp || true
      firewall-cmd --reload || true
      log "firewalld 已放行所有端口"
    else
      log "firewalld 未运行，跳过"
    fi
  fi

  if command -v iptables >/dev/null 2>&1; then
    iptables -P INPUT ACCEPT || true
    iptables -P FORWARD ACCEPT || true
    iptables -P OUTPUT ACCEPT || true

    iptables -C INPUT -p tcp --dport 1:65535 -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p tcp --dport 1:65535 -j ACCEPT || true

    iptables -C INPUT -p udp --dport 1:65535 -j ACCEPT >/dev/null 2>&1 || \
      iptables -I INPUT -p udp --dport 1:65535 -j ACCEPT || true

    log "iptables 已放行所有 IPv4 端口"
  fi

  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -P INPUT ACCEPT || true
    ip6tables -P FORWARD ACCEPT || true
    ip6tables -P OUTPUT ACCEPT || true

    ip6tables -C INPUT -p tcp --dport 1:65535 -j ACCEPT >/dev/null 2>&1 || \
      ip6tables -I INPUT -p tcp --dport 1:65535 -j ACCEPT || true

    ip6tables -C INPUT -p udp --dport 1:65535 -j ACCEPT >/dev/null 2>&1 || \
      ip6tables -I INPUT -p udp --dport 1:65535 -j ACCEPT || true

    log "ip6tables 已放行所有 IPv6 端口"
  fi

  log "系统防火墙处理完成"
}

get_public_ip() {
  local ip

  ip="$(curl -4 -fsSL --connect-timeout 8 https://api.ipify.org 2>/dev/null || true)"

  if [ -z "${ip}" ]; then
    ip="$(curl -4 -fsSL --connect-timeout 8 https://ifconfig.me 2>/dev/null || true)"
  fi

  if [ -z "${ip}" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  echo "${ip}"
}

show_result() {
  local ip
  local target

  ip="$(get_public_ip)"
  target="$(find_xray_target || true)"

  echo
  echo "========================================"
  echo "3x-ui 安装完成"
  echo "3x-ui 版本：${XUI_PIN_VERSION}"
  echo "面板地址：http://${ip}:${PANEL_PORT}/"
  echo "用户名：${PANEL_USER}"
  echo "密码：${PANEL_PASS}"
  echo "面板端口：${PANEL_PORT}"
  echo "访问路径：/"
  echo "Xray Core：固定 ${XRAY_PIN_VERSION}"
  echo "系统防火墙：已尝试放行 TCP/UDP 全端口"
  echo "========================================"
  echo

  if [ -n "${target}" ] && [ -f "${target}" ]; then
    echo "当前 Xray 版本："
    "${target}" version | head -n 1 || true
    echo
  fi

  echo "常用命令："
  echo "x-ui"
  echo "x-ui status"
  echo "x-ui restart"
  echo "x-ui log"
  echo "systemctl status x-ui --no-pager"
  echo
  echo "提醒：不要在面板里升级 3x-ui 或 Xray Core，否则可能再次出现 Shadowrocket 有延迟但没网络。"
  echo
}

main() {
  check_root
  install_deps
  enable_bbr
  install_3xui
  force_panel_settings
  pin_xray_core_for_shadowrocket
  open_all_ports
  show_result
}

main "$@"
