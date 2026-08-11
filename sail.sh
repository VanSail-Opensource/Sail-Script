#!/usr/bin/env bash
# ============================================================
# Sail Script - Linux 服务器管理工具箱
# Designed by SailData.Cloud
# Repository: https://github.com/VanSail-Opensource/Sail-Script
# ============================================================

SAIL_VERSION="2.1.0"
REPO_SLUG="VanSail-Opensource/Sail-Script"
REPO_URL="https://github.com/${REPO_SLUG}"
RAW_URL="https://raw.githubusercontent.com/${REPO_SLUG}/main/sail.sh"
NQCN_CDN_URL="https://cdn.jsdelivr.net/gh/${REPO_SLUG}@main/scripts/nodequality-cn.sh"
INSTALL_DIR="/usr/local/lib/sail-script"
INSTALL_PATH="${INSTALL_DIR}/sail.sh"
SHORTCUT_PATH="/usr/local/bin/sail"

set -o pipefail

# ---------- UI ----------
if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m'
else
    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_BOLD=""
fi

info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
success() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error()   { printf '%s[ERR ]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

clear_screen() {
    if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

pause() {
    [[ -t 0 ]] || return 0
    printf '\n'
    read -r -p "按回车键继续..." _
}

confirm() {
    local prompt="${1:-确认继续？}"
    local answer
    [[ -t 0 ]] || return 1
    read -r -p "${prompt} [y/N]: " answer
    case "${answer,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

header() {
    printf '%s\n' "${C_CYAN}============================================================${C_RESET}"
    printf '%s%s Sail Script%s  v%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$SAIL_VERSION"
    printf ' Designed by SailData.Cloud\n'
    printf ' %s\n' "$REPO_URL"
    printf '%s\n' "${C_CYAN}============================================================${C_RESET}"
}

section() {
    printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
    printf '%s\n' "------------------------------------------------------------"
}

# ---------- Common helpers ----------
is_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]]
}

require_root() {
    if is_root; then
        return 0
    fi
    error "此操作需要 root 权限。请使用 root 用户运行，或执行：sudo -i"
    return 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local output="$2"

    if has_cmd curl; then
        curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$url" -o "$output"
    elif has_cmd wget; then
        wget -q --timeout=15 --tries=3 -O "$output" "$url"
    else
        error "未找到 curl 或 wget，无法下载文件。"
        return 1
    fi
}

run_remote_bash() {
    local url="$1"
    shift || true

    local temp
    temp="$(mktemp)" || return 1

    info "下载脚本：$url"
    if ! download_file "$url" "$temp"; then
        rm -f "$temp"
        error "下载失败。"
        return 1
    fi

    if ! bash -n "$temp" >/dev/null 2>&1; then
        rm -f "$temp"
        error "远程脚本未通过 Bash 语法检查，已停止执行。"
        return 1
    fi

    bash "$temp" "$@"
    local rc=$?
    rm -f "$temp"
    return "$rc"
}

os_pretty_name() {
    if [[ -r /etc/os-release ]]; then
        (
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
        )
    else
        uname -s
    fi
}

detect_pkg_manager() {
    local pm
    for pm in apt-get dnf yum apk pacman; do
        if has_cmd "$pm"; then
            printf '%s' "$pm"
            return 0
        fi
    done
    return 1
}

human_uptime() {
    if has_cmd uptime; then
        uptime -p 2>/dev/null || uptime
    else
        printf '未知'
    fi
}

cpu_model() {
    if has_cmd lscpu; then
        lscpu 2>/dev/null | awk -F: '/Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}'
    elif [[ -r /proc/cpuinfo ]]; then
        awk -F: '/model name|Hardware|Processor/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo
    else
        printf '未知'
    fi
}

virtualization_type() {
    if has_cmd systemd-detect-virt; then
        systemd-detect-virt 2>/dev/null || printf 'none'
    elif has_cmd virt-what; then
        virt-what 2>/dev/null | head -n1
    else
        printf '未知'
    fi
}

local_ips() {
    if has_cmd ip; then
        local v4 v6
        v4="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | paste -sd ', ' -)"
        v6="$(ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | paste -sd ', ' -)"
        printf 'IPv4: %s\n' "${v4:-无}"
        printf 'IPv6: %s\n' "${v6:-无}"
    else
        printf 'IP: 无法获取（缺少 ip 命令）\n'
    fi
}

# ---------- Server information ----------
basic_info() {
    clear_screen
    header
    section "服务器概览"

    printf '主机名      : %s\n' "$(hostname 2>/dev/null || printf '未知')"
    printf '操作系统    : %s\n' "$(os_pretty_name)"
    printf '内核        : %s\n' "$(uname -r)"
    printf '架构        : %s\n' "$(uname -m)"
    printf '虚拟化      : %s\n' "$(virtualization_type)"
    printf '运行时间    : %s\n' "$(human_uptime)"
    printf 'CPU         : %s\n' "$(cpu_model)"
    printf 'CPU 核心    : %s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf '未知')"
    printf '负载        : %s\n' "$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || printf '未知')"

    section "内存"
    if has_cmd free; then
        free -h
    else
        warn "缺少 free 命令。"
    fi

    section "磁盘"
    if has_cmd df; then
        df -hT -x tmpfs -x devtmpfs 2>/dev/null || df -h
    else
        warn "缺少 df 命令。"
    fi

    section "网络地址"
    local_ips

    section "TCP"
    if has_cmd sysctl; then
        printf '拥塞控制    : %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '未知')"
        printf '队列算法    : %s\n' "$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '未知')"
    else
        printf '无法获取（缺少 sysctl）\n'
    fi
}

public_ip_info() {
    clear_screen
    header
    section "公网 IP 信息"

    if ! has_cmd curl && ! has_cmd wget; then
        error "需要 curl 或 wget。"
        pause
        return 1
    fi

    local body temp
    temp="$(mktemp)" || return 1
    if download_file "https://ipinfo.io/json" "$temp"; then
        body="$(cat "$temp")"
        printf '%s\n' "$body"
    else
        error "获取公网 IP 信息失败。"
    fi
    rm -f "$temp"
    pause
}

run_nq() {
    clear_screen
    header
    section "NodeQuality (NQ) 官方一键运行"

    if ! has_cmd curl; then
        error "运行 NodeQuality 需要 curl。"
        return 1
    fi

    info "官方入口：https://run.NodeQuality.com"
    info "执行：bash <(curl -sL https://run.NodeQuality.com)"
    bash <(curl -sL https://run.NodeQuality.com)
}

run_nq_cn() {
    clear_screen
    header
    section "NodeQuality (NQ) 国内网络受阻运行"

    if ! has_cmd curl; then
        error "运行 NodeQuality 需要 curl。"
        return 1
    fi

    local temp rc
    temp="$(mktemp)" || return 1

    info "通过 Sail Script CDN 镜像启动器加载 NodeQuality。"
    info "CDN：$NQCN_CDN_URL"
    if ! curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$NQCN_CDN_URL" -o "$temp"; then
        rm -f "$temp"
        error "NQCN CDN 启动器下载失败。"
        return 1
    fi

    if ! bash -n "$temp" >/dev/null 2>&1; then
        rm -f "$temp"
        error "NQCN 启动器未通过 Bash 语法检查，已停止执行。"
        return 1
    fi

    bash "$temp"
    rc=$?
    rm -f "$temp"
    return "$rc"
}

streaming_check() {
    clear_screen
    header
    section "流媒体解锁 / IP 质量检测"
    warn "该功能会下载并执行第三方脚本：https://ip.check.place"
    if ! confirm "确认执行 IP 检测脚本？"; then
        return 0
    fi
    run_remote_bash "https://ip.check.place" -y
    pause
}

ping_test() {
    clear_screen
    header
    section "基础延迟 / 丢包测试"

    if ! has_cmd ping; then
        error "系统没有 ping 命令。"
        pause
        return 1
    fi

    local target
    for target in 1.1.1.1 8.8.8.8 9.9.9.9; do
        printf '\n%s>>> %s%s\n' "$C_CYAN" "$target" "$C_RESET"
        ping -c 4 -W 2 "$target" 2>/dev/null || warn "$target 不可达或 ICMP 被限制。"
    done
    pause
}

http_latency_test() {
    clear_screen
    header
    section "HTTP 连接耗时"

    if ! has_cmd curl; then
        error "此功能需要 curl。"
        pause
        return 1
    fi

    local url
    for url in \
        "https://www.cloudflare.com/cdn-cgi/trace" \
        "https://github.com" \
        "https://www.google.com/generate_204"; do
        printf '%-43s ' "$url"
        curl -o /dev/null -sS -L --max-time 10 \
            -w 'DNS:%{time_namelookup}s Connect:%{time_connect}s TLS:%{time_appconnect}s Total:%{time_total}s\n' \
            "$url" || printf '失败\n'
    done
    pause
}

show_listening_ports() {
    clear_screen
    header
    section "监听端口"

    if has_cmd ss; then
        ss -lntup
    elif has_cmd netstat; then
        netstat -lntup
    else
        error "未找到 ss 或 netstat。"
    fi
    pause
}

network_menu() {
    while true; do
        clear_screen
        header
        section "网络与 IP 工具"
        cat <<'EOF'
 1. 公网 IP / ASN 信息
 2. NodeQuality 一键运行（NQ / 官方直连）
 3. NodeQuality 国内网络受阻运行（NQCN / CDN）
 4. 流媒体解锁 & IP 质量检测
 5. Ping 延迟 / 丢包测试
 6. HTTP 连接耗时测试
 7. 查看监听端口
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-7]: " choice
        case "$choice" in
            1) public_ip_info ;;
            2) run_nq; pause ;;
            3) run_nq_cn; pause ;;
            4) streaming_check ;;
            5) ping_test ;;
            6) http_latency_test ;;
            7) show_listening_ports ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- System maintenance ----------
system_update() {
    require_root || return 1
    local pm
    pm="$(detect_pkg_manager)" || {
        error "未识别到受支持的软件包管理器。"
        return 1
    }

    info "检测到软件包管理器：$pm"
    case "$pm" in
        apt-get)
            apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
            ;;
        dnf)
            dnf upgrade -y
            ;;
        yum)
            yum update -y
            ;;
        apk)
            apk update && apk upgrade
            ;;
        pacman)
            pacman -Syu --noconfirm
            ;;
    esac
}

system_cleanup() {
    require_root || return 1
    local pm
    pm="$(detect_pkg_manager)" || {
        error "未识别到受支持的软件包管理器。"
        return 1
    }

    case "$pm" in
        apt-get)
            apt-get autoremove -y
            apt-get autoclean -y
            apt-get clean
            ;;
        dnf)
            dnf autoremove -y || true
            dnf clean all
            ;;
        yum)
            yum autoremove -y || true
            yum clean all
            ;;
        apk)
            rm -rf /var/cache/apk/*
            ;;
        pacman)
            pacman -Sc --noconfirm
            ;;
    esac
    success "软件包缓存清理完成。"
}

journal_cleanup() {
    require_root || return 1
    if ! has_cmd journalctl; then
        error "当前系统没有 journalctl。"
        return 1
    fi

    warn "将仅保留最近 7 天的 systemd journal 日志。"
    confirm "确认清理旧日志？" || return 0
    journalctl --vacuum-time=7d
}

largest_paths() {
    clear_screen
    header
    section "根目录一级路径占用（Top 20）"
    warn "统计可能需要一些时间，且会跳过无权限读取的目录。"
    if has_cmd du; then
        du -xhd1 / 2>/dev/null | sort -h | tail -n 20
    else
        error "缺少 du 命令。"
    fi
    pause
}

system_maintenance_menu() {
    while true; do
        clear_screen
        header
        section "系统维护"
        cat <<'EOF'
 1. 更新系统软件包
 2. 清理软件包缓存 / 无用依赖
 3. 清理 7 天以前的 systemd 日志
 4. 查看根目录一级磁盘占用
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-4]: " choice
        case "$choice" in
            1)
                warn "系统更新可能升级内核或关键软件包。"
                if confirm "确认开始系统更新？"; then
                    system_update
                fi
                pause
                ;;
            2)
                if confirm "确认执行安全的软件包缓存清理？"; then
                    system_cleanup
                fi
                pause
                ;;
            3) journal_cleanup; pause ;;
            4) largest_paths ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- Panels ----------
install_bt_panel() {
    require_root || return 1
    clear_screen
    header
    section "宝塔面板安装"
    warn "将执行宝塔官方远程安装脚本。"
    confirm "确认安装宝塔面板？" || return 0
    run_remote_bash "https://download.bt.cn/install/install_panel.sh" "ed8484bec"
    pause
}

install_1panel() {
    require_root || return 1
    clear_screen
    header
    section "1Panel 安装"
    warn "将执行 1Panel 官方远程安装脚本。"
    confirm "确认安装 1Panel？" || return 0
    run_remote_bash "https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh"
    pause
}

panel_menu() {
    while true; do
        clear_screen
        header
        section "面板安装"
        cat <<'EOF'
 1. 宝塔面板
 2. 1Panel
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-2]: " choice
        case "$choice" in
            1) install_bt_panel ;;
            2) install_1panel ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- Docker ----------
docker_status() {
    section "Docker 状态"

    if has_cmd docker; then
        success "$(docker --version 2>/dev/null)"
        if docker info >/dev/null 2>&1; then
            success "Docker daemon 正常运行"
        else
            warn "Docker CLI 已安装，但 daemon 当前不可用或无访问权限"
        fi
    else
        warn "Docker 未安装"
    fi

    if has_cmd docker && docker compose version >/dev/null 2>&1; then
        success "$(docker compose version 2>/dev/null)"
    elif has_cmd docker-compose; then
        success "$(docker-compose --version 2>/dev/null)"
    else
        warn "Docker Compose 未安装"
    fi
}

install_docker() {
    require_root || return 1
    clear_screen
    header
    section "Docker 安装"
    warn "将从 https://get.docker.com 下载 Docker 官方安装脚本。"
    confirm "确认安装 / 更新 Docker？" || return 0

    run_remote_bash "https://get.docker.com"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        if has_cmd systemctl; then
            systemctl enable --now docker >/dev/null 2>&1 || true
        fi
        success "Docker 安装流程完成。"
    fi
    pause
    return "$rc"
}

compose_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf 'x86_64' ;;
        aarch64|arm64) printf 'aarch64' ;;
        armv7l|armv7) printf 'armv7' ;;
        ppc64le) printf 'ppc64le' ;;
        s390x) printf 's390x' ;;
        riscv64) printf 'riscv64' ;;
        *) return 1 ;;
    esac
}

install_docker_compose() {
    require_root || return 1
    local arch
    arch="$(compose_arch)" || {
        error "当前架构 $(uname -m) 暂未配置 Compose 二进制下载映射。"
        pause
        return 1
    }

    local plugin_dir="/usr/local/lib/docker/cli-plugins"
    local plugin_path="${plugin_dir}/docker-compose"
    local url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
    local temp
    temp="$(mktemp)" || return 1

    clear_screen
    header
    section "Docker Compose 安装"
    info "目标：Docker Compose v2 CLI Plugin"
    info "架构：linux-${arch}"
    confirm "确认安装 / 更新 Docker Compose？" || {
        rm -f "$temp"
        return 0
    }

    if ! download_file "$url" "$temp"; then
        rm -f "$temp"
        error "Docker Compose 下载失败。"
        pause
        return 1
    fi

    mkdir -p "$plugin_dir"
    install -m 0755 "$temp" "$plugin_path"
    ln -sf "$plugin_path" /usr/local/bin/docker-compose
    rm -f "$temp"

    if "$plugin_path" version >/dev/null 2>&1; then
        success "$("$plugin_path" version)"
    else
        warn "文件已安装，但版本检查失败。"
    fi
    pause
}

docker_ps() {
    clear_screen
    header
    if ! has_cmd docker; then
        error "Docker 未安装。"
    else
        docker ps -a
    fi
    pause
}

docker_disk_usage() {
    clear_screen
    header
    if ! has_cmd docker; then
        error "Docker 未安装。"
    else
        docker system df
    fi
    pause
}

docker_prune() {
    require_root || return 1
    if ! has_cmd docker; then
        error "Docker 未安装。"
        pause
        return 1
    fi

    clear_screen
    header
    section "Docker 清理"
    warn "将删除未使用的容器、网络、悬空镜像和构建缓存。"
    warn "不会主动删除正在使用的数据卷；本操作仍可能影响后续回滚。"
    confirm "确认执行 docker system prune -f？" || return 0
    docker system prune -f
    pause
}

docker_menu() {
    while true; do
        clear_screen
        header
        docker_status
        section "Docker 管理"
        cat <<'EOF'
 1. 安装 / 更新 Docker
 2. 安装 / 更新 Docker Compose v2
 3. 查看所有容器
 4. 查看 Docker 磁盘占用
 5. 清理未使用的 Docker 数据
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-5]: " choice
        case "$choice" in
            1) install_docker ;;
            2) install_docker_compose ;;
            3) docker_ps ;;
            4) docker_disk_usage ;;
            5) docker_prune ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- Tools ----------
install_openclaw() {
    clear_screen
    header
    section "OpenClaw 安装"
    warn "将下载并执行 https://openclaw.ai/install.sh，并使用 --beta 参数。"
    confirm "确认安装 OpenClaw？" || return 0
    run_remote_bash "https://openclaw.ai/install.sh" "--beta"
    pause
}

tools_menu() {
    while true; do
        clear_screen
        header
        section "实用工具"
        cat <<'EOF'
 1. OpenClaw 安装
 2. 查看监听端口
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-2]: " choice
        case "$choice" in
            1) install_openclaw ;;
            2) show_listening_ports ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- Self install / update ----------
extract_remote_version() {
    local file="$1"
    sed -n 's/^SAIL_VERSION="\([^"]*\)".*/\1/p' "$file" | head -n1
}

version_gt() {
    # Returns success if $1 > $2. sort -V is common on GNU/Linux.
    if has_cmd sort && sort -V </dev/null >/dev/null 2>&1; then
        [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" && "$1" != "$2" ]]
    else
        [[ "$1" != "$2" ]]
    fi
}

check_update() {
    local temp latest
    temp="$(mktemp)" || return 1

    info "检查最新版本..."
    if ! download_file "$RAW_URL" "$temp"; then
        rm -f "$temp"
        error "无法获取最新脚本。"
        return 1
    fi

    latest="$(extract_remote_version "$temp")"
    rm -f "$temp"

    if [[ -z "$latest" ]]; then
        error "无法解析远程版本号。"
        return 1
    fi

    printf '当前版本：%s\n' "$SAIL_VERSION"
    printf '远程版本：%s\n' "$latest"
    if [[ "$latest" == "$SAIL_VERSION" ]]; then
        success "当前已经是最新版本。"
    elif version_gt "$latest" "$SAIL_VERSION"; then
        warn "发现新版本：$latest"
    else
        warn "本地版本与远程版本不同，请按需更新。"
    fi
}

self_update() {
    local temp latest target
    temp="$(mktemp)" || return 1

    info "下载最新 Sail Script..."
    if ! download_file "$RAW_URL" "$temp"; then
        rm -f "$temp"
        error "下载失败。"
        return 1
    fi

    if ! bash -n "$temp"; then
        rm -f "$temp"
        error "新版本未通过 Bash 语法检查，拒绝覆盖。"
        return 1
    fi

    latest="$(extract_remote_version "$temp")"
    target=""
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* && "${BASH_SOURCE[0]}" != /proc/* ]]; then
        target="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    elif [[ -f "$INSTALL_PATH" ]]; then
        target="$INSTALL_PATH"
    fi

    if [[ -z "$target" ]]; then
        rm -f "$temp"
        warn "当前通过管道 / 进程替换运行，无法安全覆盖自身。"
        info "请先执行：sudo bash <(curl -fsSL $RAW_URL) install-shortcut"
        return 1
    fi

    if [[ ! -w "$target" ]]; then
        require_root || {
            rm -f "$temp"
            return 1
        }
    fi

    warn "即将更新：$target"
    confirm "确认用版本 ${latest:-未知} 覆盖当前脚本？" || {
        rm -f "$temp"
        return 0
    }

    cp -p "$target" "${target}.bak" 2>/dev/null || true
    install -m 0755 "$temp" "$target"
    rm -f "$temp"
    success "更新完成：${SAIL_VERSION} -> ${latest:-未知}"
    info "备份（如可创建）：${target}.bak"
}

install_shortcut() {
    require_root || return 1
    local temp
    temp="$(mktemp)" || return 1

    info "安装 Sail Script 到：$INSTALL_PATH"
    if ! download_file "$RAW_URL" "$temp"; then
        rm -f "$temp"
        error "下载失败。"
        return 1
    fi

    if ! bash -n "$temp"; then
        rm -f "$temp"
        error "下载内容未通过 Bash 语法检查。"
        return 1
    fi

    mkdir -p "$INSTALL_DIR"
    install -m 0755 "$temp" "$INSTALL_PATH"
    ln -sfn "$INSTALL_PATH" "$SHORTCUT_PATH"
    rm -f "$temp"

    success "安装完成。以后可直接输入：sail"
}

uninstall_shortcut() {
    require_root || return 1
    warn "只会删除 Sail Script 自身的快捷命令与安装副本。"
    confirm "确认卸载 /usr/local/bin/sail？" || return 0
    rm -f "$SHORTCUT_PATH"
    rm -f "$INSTALL_PATH"
    rmdir "$INSTALL_DIR" 2>/dev/null || true
    success "Sail Script 快捷安装已移除。"
}

script_management_menu() {
    while true; do
        clear_screen
        header
        section "Sail Script 管理"
        cat <<'EOF'
 1. 检查更新
 2. 更新当前脚本
 3. 安装 sail 快捷命令
 4. 卸载 sail 快捷命令
 0. 返回主菜单
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-4]: " choice
        case "$choice" in
            1) check_update; pause ;;
            2) self_update; pause ;;
            3) install_shortcut; pause ;;
            4) uninstall_shortcut; pause ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

# ---------- CLI ----------
print_help() {
    cat <<EOF
Sail Script v${SAIL_VERSION}

用法：
  sail.sh [command] [subcommand]

命令：
  menu                     打开交互式主菜单（默认）
  info                     显示服务器概览
  NQ                       NodeQuality 官方一键运行
  NQCN                     NodeQuality 国内网络受阻运行（CDN 镜像）
  ipcheck                  流媒体解锁 / IP 质量检测
  ports                    查看监听端口
  update                   更新系统软件包
  cleanup                  清理软件包缓存 / 无用依赖
  docker status            查看 Docker 状态
  docker install           安装 / 更新 Docker
  docker compose           安装 / 更新 Docker Compose v2
  panel bt                 安装宝塔面板
  panel 1panel             安装 1Panel
  openclaw                 安装 OpenClaw
  check-update             检查 Sail Script 更新
  self-update              更新 Sail Script
  install-shortcut         安装 /usr/local/bin/sail 快捷命令
  uninstall-shortcut       删除 sail 快捷命令
  version                  显示版本
  help                     显示帮助

示例：
  bash <(curl -fsSL ${RAW_URL})
  ./sail.sh NQ
  ./sail.sh NQCN
  ./sail.sh info
  ./sail.sh docker install
EOF
}

main_menu() {
    while true; do
        clear_screen
        header
        cat <<'EOF'

 1. 服务器概览
 2. 网络与 IP 工具
 3. 系统维护
 4. Docker 管理
 5. 面板安装
 6. 实用工具
 7. Sail Script 管理
 0. 退出

EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-7]: " choice
        case "$choice" in
            1) basic_info; pause ;;
            2) network_menu ;;
            3) system_maintenance_menu ;;
            4) docker_menu ;;
            5) panel_menu ;;
            6) tools_menu ;;
            7) script_management_menu ;;
            0) printf '\nDesigned by SailData.Cloud\n'; return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

dispatch() {
    local cmd="${1:-menu}"
    local sub="${2:-}"

    case "$cmd" in
        ""|menu)
            main_menu
            ;;
        info)
            basic_info
            ;;
        NQ)
            run_nq
            ;;
        NQCN)
            run_nq_cn
            ;;
        ipcheck)
            streaming_check
            ;;
        ports)
            show_listening_ports
            ;;
        update)
            system_update
            ;;
        cleanup)
            system_cleanup
            ;;
        docker)
            case "$sub" in
                ""|menu) docker_menu ;;
                status) docker_status ;;
                install) install_docker ;;
                compose) install_docker_compose ;;
                *) error "未知 Docker 子命令：$sub"; print_help; return 2 ;;
            esac
            ;;
        panel)
            case "$sub" in
                bt) install_bt_panel ;;
                1panel) install_1panel ;;
                ""|menu) panel_menu ;;
                *) error "未知 panel 子命令：$sub"; print_help; return 2 ;;
            esac
            ;;
        openclaw)
            install_openclaw
            ;;
        check-update)
            check_update
            ;;
        self-update)
            self_update
            ;;
        install-shortcut)
            install_shortcut
            ;;
        uninstall-shortcut)
            uninstall_shortcut
            ;;
        version|--version|-v)
            printf 'Sail Script %s\n' "$SAIL_VERSION"
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            error "未知命令：$cmd"
            print_help
            return 2
            ;;
    esac
}

dispatch "$@"
