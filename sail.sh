#!/usr/bin/env bash
# ============================================================
# Sail Script - Linux 服务器管理工具箱
# Designed by SailData.Cloud
# Repository: https://github.com/VanSail-Opensource/Sail-Script
# ============================================================

SAIL_VERSION="2.3.0"
REPO_SLUG="VanSail-Opensource/Sail-Script"
REPO_URL="https://github.com/${REPO_SLUG}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/main"
CDN_BASE="https://cdn.jsdelivr.net/gh/${REPO_SLUG}@main"
RAW_URL="${RAW_BASE}/sail.sh"
NQCN_CDN_URL="${CDN_BASE}/scripts/nodequality-cn.sh"
BBR_CDN_URL="${CDN_BASE}/scripts/bbr-optimize.sh"
INIT_CDN_URL="${CDN_BASE}/scripts/vps-init.sh"
INSTALL_DIR="/usr/local/lib/sail-script"
INSTALL_PATH="${INSTALL_DIR}/sail.sh"
SHORTCUT_PATH="/usr/local/bin/sail"

set -o pipefail

if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_BOLD=""
fi

info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
success() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error()   { printf '%s[ERR ]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

clear_screen() { [[ -t 1 ]] && command -v clear >/dev/null 2>&1 && clear || true; }
pause() { [[ -t 0 ]] || return 0; printf '\n'; read -r -p "按回车键继续..." _; }
confirm() { local answer; [[ -t 0 ]] || return 1; read -r -p "${1:-确认继续？} [y/N]: " answer; [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; }

header() {
    printf '%s============================================================%s\n' "$C_CYAN" "$C_RESET"
    printf '%s%s Sail Script%s  v%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$SAIL_VERSION"
    printf ' Designed by SailData.Cloud\n %s\n' "$REPO_URL"
    printf '%s============================================================%s\n' "$C_CYAN" "$C_RESET"
}
section() { printf '\n%s%s%s\n------------------------------------------------------------\n' "$C_BOLD" "$1" "$C_RESET"; }

is_root() { [[ ${EUID:-$(id -u)} -eq 0 ]]; }
require_root() { is_root && return 0; error "此操作需要 root 权限。请使用 root 用户运行，或执行：sudo -i"; return 1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

download_file() {
    local url="$1" output="$2"
    if has_cmd curl; then
        curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$url" -o "$output"
    elif has_cmd wget; then
        wget -q --timeout=15 --tries=3 -O "$output" "$url"
    else
        error "未找到 curl 或 wget。"; return 1
    fi
}

run_remote_bash() {
    local url="$1"; shift || true
    local temp; temp="$(mktemp)" || return 1
    info "下载脚本：$url"
    if ! download_file "$url" "$temp"; then rm -f "$temp"; error "下载失败。"; return 1; fi
    if ! bash -n "$temp" >/dev/null 2>&1; then rm -f "$temp"; error "远程脚本未通过 Bash 语法检查。"; return 1; fi
    bash "$temp" "$@"; local rc=$?; rm -f "$temp"; return "$rc"
}

run_cdn_module() {
    local url="$1" name="$2"; shift 2 || true
    local temp; temp="$(mktemp)" || return 1
    info "加载模块：$name"
    info "CDN：$url"
    if ! download_file "$url" "$temp"; then rm -f "$temp"; error "$name 下载失败。"; return 1; fi
    if ! bash -n "$temp" >/dev/null 2>&1; then rm -f "$temp"; error "$name 未通过 Bash 语法检查。"; return 1; fi
    bash "$temp" "$@"; local rc=$?; rm -f "$temp"; return "$rc"
}

os_pretty_name() { if [[ -r /etc/os-release ]]; then (. /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"); else uname -s; fi; }
detect_pkg_manager() { local pm; for pm in apt-get dnf yum apk pacman; do has_cmd "$pm" && { printf '%s' "$pm"; return 0; }; done; return 1; }
cpu_model() { if has_cmd lscpu; then lscpu 2>/dev/null | awk -F: '/Model name/ {sub(/^[ \t]+/,"",$2);print $2;exit}'; else awk -F: '/model name|Hardware|Processor/ {sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null; fi; }
virtualization_type() { if has_cmd systemd-detect-virt; then systemd-detect-virt 2>/dev/null || printf 'none'; elif has_cmd virt-what; then virt-what 2>/dev/null | head -n1; else printf '未知'; fi; }

basic_info() {
    clear_screen; header; section "服务器概览"
    printf '主机名      : %s\n' "$(hostname 2>/dev/null || printf '未知')"
    printf '操作系统    : %s\n' "$(os_pretty_name)"
    printf '内核        : %s\n架构        : %s\n虚拟化      : %s\n' "$(uname -r)" "$(uname -m)" "$(virtualization_type)"
    printf '运行时间    : %s\n' "$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf '未知')"
    printf 'CPU         : %s\nCPU 核心    : %s\n' "$(cpu_model)" "$(nproc 2>/dev/null || printf '未知')"
    printf '负载        : %s\n' "$(awk '{print $1,$2,$3}' /proc/loadavg 2>/dev/null || printf '未知')"
    section "内存"; has_cmd free && free -h || warn "缺少 free 命令。"
    section "磁盘"; has_cmd df && (df -hT -x tmpfs -x devtmpfs 2>/dev/null || df -h) || warn "缺少 df 命令。"
    section "网络地址"
    if has_cmd ip; then ip -br addr 2>/dev/null; else warn "缺少 ip 命令。"; fi
    section "TCP"
    if has_cmd sysctl; then
        printf '拥塞控制    : %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
        printf '队列算法    : %s\n' "$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '未知')"
    fi
}

public_ip_info() { clear_screen; header; section "公网 IP 信息"; local t; t="$(mktemp)" || return 1; download_file "https://ipinfo.io/json" "$t" && cat "$t" || error "获取失败。"; rm -f "$t"; pause; }
run_nq() { clear_screen; header; section "NodeQuality (NQ) 官方一键运行"; has_cmd curl || { error "需要 curl。"; return 1; }; info "执行：bash <(curl -sL https://run.NodeQuality.com)"; bash <(curl -sL https://run.NodeQuality.com); }
run_nq_cn() { clear_screen; header; section "NodeQuality (NQ) 国内网络受阻运行"; run_cdn_module "$NQCN_CDN_URL" "NodeQuality CN"; }

run_bbr() {
    local action="${1:-auto}"
    clear_screen; header; section "一键 BBR / TCP 优化"
    run_cdn_module "$BBR_CDN_URL" "Sail BBR Optimizer" "$action"
}

run_init() {
    local action="${1:-menu}"
    clear_screen; header; section "VPS 一键初始化"
    run_cdn_module "$INIT_CDN_URL" "Sail VPS Init" "$action"
}

streaming_check() { clear_screen; header; section "流媒体解锁 / IP 质量检测"; warn "将执行第三方脚本：https://ip.check.place"; confirm "确认执行？" || return 0; run_remote_bash "https://ip.check.place" -y; pause; }
ping_test() { clear_screen; header; section "基础延迟 / 丢包测试"; has_cmd ping || { error "没有 ping 命令。"; pause; return 1; }; local x; for x in 1.1.1.1 8.8.8.8 9.9.9.9; do printf '\n>>> %s\n' "$x"; ping -c 4 -W 2 "$x" 2>/dev/null || warn "$x 不可达。"; done; pause; }
http_latency_test() { clear_screen; header; section "HTTP 连接耗时"; has_cmd curl || { error "需要 curl。"; pause; return 1; }; local u; for u in https://www.cloudflare.com/cdn-cgi/trace https://github.com https://www.google.com/generate_204; do printf '%-43s ' "$u"; curl -o /dev/null -sS -L --max-time 10 -w 'DNS:%{time_namelookup}s Connect:%{time_connect}s TLS:%{time_appconnect}s Total:%{time_total}s\n' "$u" || printf '失败\n'; done; pause; }
show_listening_ports() { clear_screen; header; section "监听端口"; if has_cmd ss; then ss -lntup; elif has_cmd netstat; then netstat -lntup; else error "未找到 ss 或 netstat。"; fi; pause; }

bbr_menu() {
    while true; do
        clear_screen; header; section "BBR / TCP 优化"
        cat <<'EOF'
 1. 一键智能优化（推荐 / BBR + fq）
 2. 查看 BBR / qdisc 状态
 3. 均衡模式
 4. 高吞吐模式
 5. 低延迟模式
 6. 高并发模式
 7. 安装 XanMod LTS BBRv3 内核
 8. 回滚 Sail BBR 优化
 0. 返回网络菜单
EOF
        read -r -p "请输入选项 [0-8]: " c
        case "$c" in
            1) run_bbr auto; pause;; 2) run_bbr status; pause;; 3) run_bbr balanced; pause;; 4) run_bbr throughput; pause;; 5) run_bbr latency; pause;; 6) run_bbr concurrent; pause;; 7) run_bbr xanmod; pause;; 8) run_bbr rollback; pause;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac
    done
}

network_menu() {
    while true; do
        clear_screen; header; section "网络与 IP 工具"
        cat <<'EOF'
 1. 公网 IP / ASN 信息
 2. NodeQuality 一键运行（NQ / 官方直连）
 3. NodeQuality 国内网络受阻运行（NQCN / CDN）
 4. 一键 BBR / TCP 优化
 5. 流媒体解锁 & IP 质量检测
 6. Ping 延迟 / 丢包测试
 7. HTTP 连接耗时测试
 8. 查看监听端口
 0. 返回主菜单
EOF
        read -r -p "请输入选项 [0-8]: " c
        case "$c" in 1) public_ip_info;; 2) run_nq; pause;; 3) run_nq_cn; pause;; 4) bbr_menu;; 5) streaming_check;; 6) ping_test;; 7) http_latency_test;; 8) show_listening_ports;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac
    done
}

system_update() {
    require_root || return 1; local pm; pm="$(detect_pkg_manager)" || { error "未识别包管理器。"; return 1; }
    case "$pm" in apt-get) apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y;; dnf) dnf upgrade -y;; yum) yum update -y;; apk) apk update && apk upgrade;; pacman) pacman -Syu --noconfirm;; esac
}
system_cleanup() {
    require_root || return 1; local pm; pm="$(detect_pkg_manager)" || return 1
    case "$pm" in apt-get) apt-get autoremove -y; apt-get autoclean -y; apt-get clean;; dnf) dnf autoremove -y || true; dnf clean all;; yum) yum autoremove -y || true; yum clean all;; apk) rm -rf /var/cache/apk/*;; pacman) pacman -Sc --noconfirm;; esac
    success "清理完成。"
}
journal_cleanup() { require_root || return 1; has_cmd journalctl || { error "没有 journalctl。"; return 1; }; warn "仅保留最近 7 天 journal。"; confirm "确认清理？" && journalctl --vacuum-time=7d; }
largest_paths() { clear_screen; header; section "根目录一级路径占用（Top 20）"; du -xhd1 / 2>/dev/null | sort -h | tail -n20; pause; }

system_maintenance_menu() {
    while true; do
        clear_screen; header; section "系统维护"
        printf ' 1. 更新系统软件包\n 2. 清理软件包缓存 / 无用依赖\n 3. 清理 7 天以前的 systemd 日志\n 4. 查看根目录一级磁盘占用\n 0. 返回主菜单\n'
        read -r -p "请输入选项 [0-4]: " c
        case "$c" in 1) warn "可能升级内核或关键软件包。"; confirm "确认更新？" && system_update; pause;; 2) confirm "确认清理？" && system_cleanup; pause;; 3) journal_cleanup; pause;; 4) largest_paths;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac
    done
}

install_bt_panel() { require_root || return 1; clear_screen; header; section "宝塔面板安装"; warn "将执行宝塔官方安装脚本。"; confirm "确认安装？" || return 0; run_remote_bash "https://download.bt.cn/install/install_panel.sh" ed8484bec; pause; }
install_1panel() { require_root || return 1; clear_screen; header; section "1Panel 安装"; warn "将执行 1Panel 官方安装脚本。"; confirm "确认安装？" || return 0; run_remote_bash "https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh"; pause; }
panel_menu() { while true; do clear_screen; header; section "面板安装"; printf ' 1. 宝塔面板\n 2. 1Panel\n 0. 返回主菜单\n'; read -r -p "请输入选项 [0-2]: " c; case "$c" in 1) install_bt_panel;; 2) install_1panel;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac; done; }

docker_status() { section "Docker 状态"; has_cmd docker && success "$(docker --version 2>/dev/null)" || warn "Docker 未安装"; if has_cmd docker && docker compose version >/dev/null 2>&1; then success "$(docker compose version)"; elif has_cmd docker-compose; then success "$(docker-compose --version)"; else warn "Docker Compose 未安装"; fi; }
install_docker() { require_root || return 1; clear_screen; header; section "Docker 安装"; warn "使用 Docker 官方 get.docker.com。"; confirm "确认安装 / 更新？" || return 0; run_remote_bash "https://get.docker.com"; has_cmd systemctl && systemctl enable --now docker >/dev/null 2>&1 || true; pause; }
compose_arch() { case "$(uname -m)" in x86_64|amd64) printf x86_64;; aarch64|arm64) printf aarch64;; armv7l|armv7) printf armv7;; ppc64le) printf ppc64le;; s390x) printf s390x;; riscv64) printf riscv64;; *) return 1;; esac; }
install_docker_compose() { require_root || return 1; local a p t; a="$(compose_arch)" || { error "不支持此架构。"; pause; return 1; }; p=/usr/local/lib/docker/cli-plugins/docker-compose; t="$(mktemp)" || return 1; confirm "确认安装 / 更新 Compose v2？" || { rm -f "$t"; return 0; }; download_file "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${a}" "$t" || { rm -f "$t"; return 1; }; mkdir -p "$(dirname "$p")"; install -m0755 "$t" "$p"; ln -sfn "$p" /usr/local/bin/docker-compose; rm -f "$t"; "$p" version; pause; }
docker_ps() { clear_screen; header; has_cmd docker && docker ps -a || error "Docker 未安装。"; pause; }
docker_disk_usage() { clear_screen; header; has_cmd docker && docker system df || error "Docker 未安装。"; pause; }
docker_prune() { require_root || return 1; clear_screen; header; warn "删除未使用容器、网络、悬空镜像、构建缓存；默认不删除 volume。"; confirm "确认执行 docker system prune -f？" && docker system prune -f; pause; }
docker_menu() { while true; do clear_screen; header; docker_status; section "Docker 管理"; printf ' 1. 安装 / 更新 Docker\n 2. 安装 / 更新 Docker Compose v2\n 3. 查看所有容器\n 4. 查看 Docker 磁盘占用\n 5. 清理未使用 Docker 数据\n 0. 返回主菜单\n'; read -r -p "请输入选项 [0-5]: " c; case "$c" in 1) install_docker;; 2) install_docker_compose;; 3) docker_ps;; 4) docker_disk_usage;; 5) docker_prune;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac; done; }

install_openclaw() { clear_screen; header; section "OpenClaw 安装"; warn "将执行 openclaw.ai/install.sh --beta。"; confirm "确认安装？" || return 0; run_remote_bash "https://openclaw.ai/install.sh" --beta; pause; }
tools_menu() { while true; do clear_screen; header; section "实用工具"; printf ' 1. OpenClaw 安装\n 2. 查看监听端口\n 0. 返回主菜单\n'; read -r -p "请输入选项 [0-2]: " c; case "$c" in 1) install_openclaw;; 2) show_listening_ports;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac; done; }

extract_remote_version() { sed -n 's/^SAIL_VERSION="\([^"]*\)".*/\1/p' "$1" | head -n1; }
check_update() { local t latest; t="$(mktemp)" || return 1; download_file "$RAW_URL" "$t" || { rm -f "$t"; return 1; }; latest="$(extract_remote_version "$t")"; rm -f "$t"; printf '当前版本：%s\n远程版本：%s\n' "$SAIL_VERSION" "${latest:-未知}"; }
self_update() { local t latest target; t="$(mktemp)" || return 1; download_file "$RAW_URL" "$t" || { rm -f "$t"; return 1; }; bash -n "$t" || { rm -f "$t"; error "新版本语法检查失败。"; return 1; }; latest="$(extract_remote_version "$t")"; target="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"; [[ -f "$target" ]] || { rm -f "$t"; warn "管道运行无法安全覆盖自身。"; return 1; }; [[ -w "$target" ]] || require_root || { rm -f "$t"; return 1; }; confirm "确认更新 ${SAIL_VERSION} -> ${latest:-未知}？" || { rm -f "$t"; return 0; }; cp -p "$target" "${target}.bak" 2>/dev/null || true; install -m0755 "$t" "$target"; rm -f "$t"; success "更新完成。"; }
install_shortcut() { require_root || return 1; local t; t="$(mktemp)" || return 1; download_file "$RAW_URL" "$t" || { rm -f "$t"; return 1; }; bash -n "$t" || { rm -f "$t"; return 1; }; mkdir -p "$INSTALL_DIR"; install -m0755 "$t" "$INSTALL_PATH"; ln -sfn "$INSTALL_PATH" "$SHORTCUT_PATH"; rm -f "$t"; success "以后可直接输入：sail"; }
uninstall_shortcut() { require_root || return 1; confirm "确认卸载 sail 快捷命令？" || return 0; rm -f "$SHORTCUT_PATH" "$INSTALL_PATH"; rmdir "$INSTALL_DIR" 2>/dev/null || true; success "已移除。"; }
script_management_menu() { while true; do clear_screen; header; section "Sail Script 管理"; printf ' 1. 检查更新\n 2. 更新当前脚本\n 3. 安装 sail 快捷命令\n 4. 卸载 sail 快捷命令\n 0. 返回主菜单\n'; read -r -p "请输入选项 [0-4]: " c; case "$c" in 1) check_update; pause;; 2) self_update; pause;; 3) install_shortcut; pause;; 4) uninstall_shortcut; pause;; 0) return 0;; *) warn "无效选项。"; sleep 1;; esac; done; }

print_help() {
    cat <<EOF
Sail Script v${SAIL_VERSION}

用法：./sail.sh [command] [subcommand]

  menu                     打开交互式主菜单
  info                     显示服务器概览
  INIT                     打开 VPS 初始化菜单
  INIT basic               常用工具 + Fail2ban 基础初始化
  INIT guided              完整 VPS 初始化向导
  INIT packages            安装常用命令
  INIT fail2ban            配置 Fail2ban SSH 防护
  INIT ssh-port            修改 SSH 高位端口
  INIT add-key             添加 SSH 公钥
  INIT key-only            关闭 SSH 密码登录
  INIT status              查看 SSH / Fail2ban 状态
  NQ                       NodeQuality 官方一键运行
  NQCN                     NodeQuality 国内网络受阻运行
  BBR                      一键智能 BBR + fq 优化
  BBR status               查看 BBR / qdisc 状态
  BBR balanced             均衡模式
  BBR throughput           高吞吐模式
  BBR latency              低延迟模式
  BBR concurrent           高并发模式
  BBR xanmod               安装 XanMod LTS BBRv3 内核
  BBR rollback             回滚 Sail BBR 优化
  ipcheck                  流媒体 / IP 质量检测
  ports                    查看监听端口
  update                   更新系统软件包
  cleanup                  清理软件包缓存 / 无用依赖
  docker status|install|compose
  panel bt|1panel
  openclaw
  check-update | self-update
  install-shortcut | uninstall-shortcut
  version | help
EOF
}

main_menu() {
    while true; do
        clear_screen; header
        printf '\n 1. 服务器概览\n 2. 网络与 IP 工具\n 3. VPS 一键初始化\n 4. 系统维护\n 5. Docker 管理\n 6. 面板安装\n 7. 实用工具\n 8. Sail Script 管理\n 0. 退出\n\n'
        read -r -p "请输入选项 [0-8]: " c
        case "$c" in 1) basic_info; pause;; 2) network_menu;; 3) run_init menu;; 4) system_maintenance_menu;; 5) docker_menu;; 6) panel_menu;; 7) tools_menu;; 8) script_management_menu;; 0) printf '\nDesigned by SailData.Cloud\n'; return 0;; *) warn "无效选项。"; sleep 1;; esac
    done
}

dispatch() {
    local cmd="${1:-menu}" sub="${2:-}"
    case "$cmd" in
        ""|menu) main_menu;;
        info) basic_info;;
        INIT) run_init "${sub:-menu}";;
        NQ) run_nq;;
        NQCN) run_nq_cn;;
        BBR) run_bbr "${sub:-auto}";;
        ipcheck) streaming_check;;
        ports) show_listening_ports;;
        update) system_update;;
        cleanup) system_cleanup;;
        docker) case "$sub" in ""|menu) docker_menu;; status) docker_status;; install) install_docker;; compose) install_docker_compose;; *) error "未知 Docker 子命令：$sub"; return 2;; esac;;
        panel) case "$sub" in bt) install_bt_panel;; 1panel) install_1panel;; ""|menu) panel_menu;; *) error "未知 panel 子命令：$sub"; return 2;; esac;;
        openclaw) install_openclaw;;
        check-update) check_update;;
        self-update) self_update;;
        install-shortcut) install_shortcut;;
        uninstall-shortcut) uninstall_shortcut;;
        version|--version|-v) printf 'Sail Script %s\n' "$SAIL_VERSION";;
        help|--help|-h) print_help;;
        *) error "未知命令：$cmd"; print_help; return 2;;
    esac
}

dispatch "$@"
