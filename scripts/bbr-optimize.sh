#!/usr/bin/env bash
# ============================================================
# Sail Script - BBR / TCP network optimizer
# Inspired by ideas from EasyBBR3, vps-tcp-tune and Kejilion.sh.
# This implementation is maintained independently by Sail Script.
# ============================================================

set -uo pipefail

VERSION="1.0.0"
CONFIG_FILE="/etc/sysctl.d/99-sail-bbr.conf"
STATE_DIR="/var/lib/sail-script/bbr"
ORIGINAL_STATE="${STATE_DIR}/original-values.conf"
PREVIOUS_CONFIG="${STATE_DIR}/previous-sail-bbr.conf"
XANMOD_KEYRING="/etc/apt/keyrings/xanmod-archive-keyring.gpg"
XANMOD_SOURCE="/etc/apt/sources.list.d/xanmod-release.list"

if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; C=$'\033[36m'; N=$'\033[0m'; BD=$'\033[1m'
else
    R=""; G=""; Y=""; B=""; C=""; N=""; BD=""
fi

info() { printf '%s[INFO]%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$Y" "$N" "$*"; }
err()  { printf '%s[ERR ]%s %s\n' "$R" "$N" "$*" >&2; }

header() {
    printf '%s============================================================%s\n' "$C" "$N"
    printf '%s Sail BBR Optimizer%s  v%s\n' "$BD" "$N" "$VERSION"
    printf ' BBR + FQ / 自适应 TCP 参数 / 状态检测 / 回滚 / XanMod BBRv3\n'
    printf '%s============================================================%s\n' "$C" "$N"
}

pause() {
    [[ -t 0 ]] || return 0
    printf '\n'
    read -r -p "按回车键继续..." _
}

confirm() {
    local prompt="${1:-确认继续？}" answer
    [[ -t 0 ]] || return 1
    read -r -p "${prompt} [y/N]: " answer
    case "${answer,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

need_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        err "此操作需要 root 权限。"
        return 1
    fi
}

has() { command -v "$1" >/dev/null 2>&1; }

sysctl_exists() {
    [[ -e "/proc/sys/${1//./\/}" ]]
}

sysctl_get() {
    sysctl -n "$1" 2>/dev/null || true
}

virt_type() {
    if has systemd-detect-virt; then
        systemd-detect-virt 2>/dev/null || printf 'none'
    elif has virt-what; then
        virt-what 2>/dev/null | head -n1
    else
        printf 'unknown'
    fi
}

bbr_module_version() {
    if has modinfo; then
        modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2; exit}'
    fi
}

bbr_label() {
    local v kernel
    v="$(bbr_module_version)"
    kernel="$(uname -r)"
    if [[ "$v" =~ ^3([.]|$) ]] || [[ "$v" == "3" ]]; then
        printf 'BBRv3'
    elif [[ "$kernel" == *xanmod* && -n "$v" ]]; then
        printf 'BBR (%s module v%s)' "$kernel" "$v"
    else
        printf 'BBR'
    fi
}

available_cc() {
    sysctl_get net.ipv4.tcp_available_congestion_control
}

ensure_bbr_available() {
    if has modprobe; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi
    if ! available_cc | grep -qw bbr; then
        err "当前内核没有可用的 BBR 拥塞控制模块。"
        warn "如果是 Debian/Ubuntu x86_64，可运行：$0 xanmod"
        warn "容器型 VPS（LXC/OpenVZ/Docker 等）通常无法自行更换宿主机内核。"
        return 1
    fi
}

memory_mb() {
    awk '/MemTotal:/ {printf "%d", $2/1024; exit}' /proc/meminfo 2>/dev/null
}

auto_buffer_bytes() {
    local mem
    mem="$(memory_mb)"
    mem="${mem:-1024}"
    if (( mem <= 384 )); then
        printf '4194304'       # 4 MiB
    elif (( mem <= 768 )); then
        printf '8388608'       # 8 MiB
    elif (( mem <= 1536 )); then
        printf '16777216'      # 16 MiB
    elif (( mem <= 4096 )); then
        printf '33554432'      # 32 MiB
    else
        printf '67108864'      # 64 MiB
    fi
}

save_original_state_once() {
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR" 2>/dev/null || true

    if [[ ! -f "$ORIGINAL_STATE" ]]; then
        : > "$ORIGINAL_STATE"
        chmod 600 "$ORIGINAL_STATE"
        local key value
        for key in \
            net.core.default_qdisc \
            net.ipv4.tcp_congestion_control \
            net.core.rmem_max \
            net.core.wmem_max \
            net.ipv4.tcp_rmem \
            net.ipv4.tcp_wmem \
            net.core.netdev_max_backlog \
            net.core.somaxconn \
            net.ipv4.tcp_max_syn_backlog \
            net.ipv4.tcp_mtu_probing \
            net.ipv4.tcp_fastopen \
            net.ipv4.tcp_slow_start_after_idle \
            net.ipv4.tcp_notsent_lowat \
            net.ipv4.ip_local_port_range \
            net.ipv4.tcp_fin_timeout; do
            if sysctl_exists "$key"; then
                value="$(sysctl_get "$key")"
                printf '%s=%s\n' "$key" "$value" >> "$ORIGINAL_STATE"
            fi
        done
        ok "已保存优化前运行参数：$ORIGINAL_STATE"
    fi

    if [[ -f "$CONFIG_FILE" && ! -f "$PREVIOUS_CONFIG" ]]; then
        cp -p "$CONFIG_FILE" "$PREVIOUS_CONFIG"
        ok "已备份原 Sail BBR 配置：$PREVIOUS_CONFIG"
    fi
}

add_setting() {
    local file="$1" key="$2" value="$3"
    if sysctl_exists "$key"; then
        printf '%s = %s\n' "$key" "$value" >> "$file"
    fi
}

default_ifaces() {
    if has ip; then
        ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u
    fi
}

apply_fq_live() {
    has tc || return 0
    local dev qline
    while read -r dev; do
        [[ -n "$dev" ]] || continue
        qline="$(tc qdisc show dev "$dev" 2>/dev/null | head -n1)"
        case "$qline" in
            *" qdisc mq "*|*" qdisc noqueue "*|*" htb "*|*" tbf "*|*|*" cake "*|*" netem "*)
                warn "$dev 当前存在多队列/整形 qdisc，跳过实时替换，仅设置系统默认 fq。"
                ;;
            *)
                if tc qdisc replace dev "$dev" root fq >/dev/null 2>&1; then
                    ok "$dev 已实时切换为 fq"
                else
                    warn "$dev 无法实时切换 fq；重连/重启后仍会使用新的默认 qdisc。"
                fi
                ;;
        esac
    done < <(default_ifaces)
}

write_profile() {
    local profile="$1"
    local base_buf buf backlog somax synbacklog fin lowat
    base_buf="$(auto_buffer_bytes)"
    buf="$base_buf"
    backlog=16384
    somax=8192
    synbacklog=8192
    fin=30
    lowat=16384

    case "$profile" in
        balanced)
            ;;
        throughput)
            buf=$(( base_buf * 2 ))
            (( buf > 134217728 )) && buf=134217728
            backlog=32768
            somax=16384
            synbacklog=16384
            ;;
        latency)
            (( buf > 33554432 )) && buf=33554432
            backlog=8192
            somax=4096
            synbacklog=8192
            fin=20
            lowat=8192
            ;;
        concurrent)
            backlog=65536
            somax=32768
            synbacklog=32768
            fin=20
            ;;
        *)
            err "未知优化模式：$profile"
            return 2
            ;;
    esac

    local tmp
    tmp="$(mktemp)" || return 1
    cat > "$tmp" <<EOF
# Sail Script BBR optimization
# Version: ${VERSION}
# Profile: ${profile}
# Generated: $(date -Is 2>/dev/null || date)
# Remove with: sail BBR rollback

EOF

    add_setting "$tmp" net.core.default_qdisc fq
    add_setting "$tmp" net.ipv4.tcp_congestion_control bbr
    add_setting "$tmp" net.core.rmem_max "$buf"
    add_setting "$tmp" net.core.wmem_max "$buf"
    add_setting "$tmp" net.ipv4.tcp_rmem "4096 131072 $buf"
    add_setting "$tmp" net.ipv4.tcp_wmem "4096 16384 $buf"
    add_setting "$tmp" net.core.netdev_max_backlog "$backlog"
    add_setting "$tmp" net.core.somaxconn "$somax"
    add_setting "$tmp" net.ipv4.tcp_max_syn_backlog "$synbacklog"
    add_setting "$tmp" net.ipv4.tcp_mtu_probing 1
    add_setting "$tmp" net.ipv4.tcp_fastopen 3
    add_setting "$tmp" net.ipv4.tcp_slow_start_after_idle 0
    add_setting "$tmp" net.ipv4.tcp_notsent_lowat "$lowat"
    add_setting "$tmp" net.ipv4.ip_local_port_range "10240 65535"
    add_setting "$tmp" net.ipv4.tcp_fin_timeout "$fin"

    install -m 0644 "$tmp" "$CONFIG_FILE"
    rm -f "$tmp"

    printf '%s' "$profile" > "${STATE_DIR}/profile"
    printf '%s' "$buf" > "${STATE_DIR}/buffer-bytes"
}

show_conflicts() {
    local found=0 file
    for file in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
        [[ -f "$file" ]] || continue
        [[ "$file" == "$CONFIG_FILE" ]] && continue
        if grep -Eq '^[[:space:]]*(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control|net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem))[[:space:]]*=' "$file" 2>/dev/null; then
            if (( found == 0 )); then
                warn "检测到可能覆盖 Sail BBR 参数的其他配置："
            fi
            printf '  - %s\n' "$file"
            found=1
        fi
    done
    return 0
}

verify() {
    local cc qdisc
    cc="$(sysctl_get net.ipv4.tcp_congestion_control)"
    qdisc="$(sysctl_get net.core.default_qdisc)"
    printf '\n'
    if [[ "$cc" == "bbr" ]]; then
        ok "拥塞控制：$(bbr_label)（sysctl: bbr）"
    else
        warn "当前拥塞控制仍为：${cc:-未知}"
    fi
    if [[ "$qdisc" == "fq" ]]; then
        ok "默认队列算法：fq"
    else
        warn "默认队列算法：${qdisc:-未知}"
    fi
}

apply_profile() {
    local profile="${1:-balanced}"
    need_root || return 1
    has sysctl || { err "缺少 sysctl。"; return 1; }
    ensure_bbr_available || return 1

    header
    info "模式：$profile"
    info "内存：$(memory_mb) MiB；自适应 TCP Buffer：$(( $(auto_buffer_bytes) / 1024 / 1024 )) MiB（基础档）"
    warn "会写入 $CONFIG_FILE，并调整 TCP/队列参数。"
    confirm "确认应用 Sail BBR 优化？" || return 0

    save_original_state_once
    write_profile "$profile" || return 1

    if sysctl -p "$CONFIG_FILE"; then
        ok "sysctl 参数已应用。"
    else
        warn "部分 sysctl 参数应用失败，请查看上方输出。"
    fi

    apply_fq_live
    show_conflicts
    verify
    ok "配置已持久化：$CONFIG_FILE"
}

status() {
    header
    printf '内核版本        : %s\n' "$(uname -r)"
    printf '架构            : %s\n' "$(uname -m)"
    printf '虚拟化          : %s\n' "$(virt_type)"
    printf '内存            : %s MiB\n' "$(memory_mb)"
    printf '可用拥塞算法    : %s\n' "$(available_cc)"
    printf '当前拥塞算法    : %s\n' "$(sysctl_get net.ipv4.tcp_congestion_control)"
    printf '默认 qdisc      : %s\n' "$(sysctl_get net.core.default_qdisc)"
    local modv
    modv="$(bbr_module_version)"
    printf 'tcp_bbr version : %s\n' "${modv:-未提供（通常表示普通主线 BBR）}"
    if [[ "$modv" =~ ^3([.]|$) ]] || [[ "$modv" == "3" ]]; then
        ok "检测到 BBRv3 模块。"
    elif available_cc | grep -qw bbr; then
        ok "当前内核支持 BBR。"
    else
        warn "当前内核未发现 BBR。"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        printf 'Sail 配置       : %s\n' "$CONFIG_FILE"
        printf 'Sail 模式       : %s\n' "$(cat "${STATE_DIR}/profile" 2>/dev/null || printf '未知')"
    else
        printf 'Sail 配置       : 未安装\n'
    fi

    if has tc; then
        local dev
        while read -r dev; do
            [[ -n "$dev" ]] || continue
            printf '\n[%s] ' "$dev"
            tc qdisc show dev "$dev" 2>/dev/null | head -n1
        done < <(default_ifaces)
    fi
    show_conflicts
}

rollback() {
    need_root || return 1
    header
    warn "将移除 Sail BBR sysctl 配置并恢复首次优化前记录的运行参数。"
    warn "不会自动卸载 XanMod 内核。"
    confirm "确认回滚？" || return 0

    rm -f "$CONFIG_FILE"
    if [[ -f "$PREVIOUS_CONFIG" ]]; then
        cp -p "$PREVIOUS_CONFIG" "$CONFIG_FILE"
        ok "已恢复此前存在的 Sail BBR 配置文件。"
    fi

    if has sysctl; then
        sysctl --system >/dev/null 2>&1 || true
    fi

    if [[ -f "$ORIGINAL_STATE" ]]; then
        local key value
        while IFS='=' read -r key value; do
            [[ -n "$key" ]] || continue
            sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
        done < "$ORIGINAL_STATE"
        ok "已恢复优化前记录的运行参数。"
    else
        warn "没有找到优化前状态记录，仅移除了 Sail 配置。"
    fi

    rm -f "${STATE_DIR}/profile" "${STATE_DIR}/buffer-bytes"
    verify
}

install_xanmod() {
    need_root || return 1
    header

    local arch virt id like codename
    arch="$(uname -m)"
    virt="$(virt_type)"
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        err "XanMod 官方仓库的 BBRv3 路径仅面向 x86_64；当前架构：$arch"
        return 1
    fi
    case "$virt" in
        lxc|openvz|docker|podman|systemd-nspawn|wsl|wsl2)
            err "当前环境为容器型虚拟化（$virt），无法自行更换宿主机内核。"
            return 1
            ;;
    esac

    id=""; like=""; codename=""
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        id="${ID:-}"
        like="${ID_LIKE:-}"
        codename="${VERSION_CODENAME:-}"
    fi
    if [[ "$id $like" != *debian* && "$id $like" != *ubuntu* ]]; then
        err "当前仅为 Debian/Ubuntu 系实现 XanMod BBRv3 自动安装。"
        return 1
    fi
    if [[ -z "$codename" ]] && has lsb_release; then
        codename="$(lsb_release -sc 2>/dev/null || true)"
    fi
    if [[ -z "$codename" ]]; then
        err "无法识别发行版 codename。"
        return 1
    fi

    warn "将添加 XanMod 官方 APT 仓库并安装 linux-xanmod-lts-x64v1。"
    warn "安装新内核可能与 DKMS / OpenZFS / VirtualBox / VMware 等模块存在兼容性问题。"
    warn "安装完成后需要重启，脚本不会自动重启服务器。"
    confirm "确认安装 XanMod LTS（BBRv3）内核？" || return 0

    export DEBIAN_FRONTEND=noninteractive
    apt-get update || return 1
    apt-get install -y ca-certificates wget gnupg || return 1
    mkdir -p /etc/apt/keyrings

    local keytmp
    keytmp="$(mktemp)" || return 1
    if ! wget -qO "$keytmp" https://dl.xanmod.org/archive.key; then
        rm -f "$keytmp"
        err "XanMod PGP key 下载失败。"
        return 1
    fi
    if ! gpg --dearmor --yes -o "$XANMOD_KEYRING" "$keytmp"; then
        rm -f "$keytmp"
        err "XanMod PGP key 导入失败。"
        return 1
    fi
    rm -f "$keytmp"

    printf 'deb [signed-by=%s] http://deb.xanmod.org %s main\n' "$XANMOD_KEYRING" "$codename" > "$XANMOD_SOURCE"
    apt-get update || return 1
    apt-get install -y linux-xanmod-lts-x64v1 || return 1

    if has update-grub; then
        update-grub || true
    fi

    ok "XanMod LTS 内核安装完成。"
    info "重启后执行：$0 status"
    info "若 tcp_bbr 模块 version 显示 3，再执行：$0 auto"
}

menu() {
    while true; do
        clear 2>/dev/null || true
        header
        cat <<'EOF'
 1. 一键智能优化（推荐 / balanced）
 2. 查看 BBR / qdisc 状态
 3. 均衡模式
 4. 高吞吐模式
 5. 低延迟模式
 6. 高并发模式
 7. 安装 XanMod LTS BBRv3 内核（Debian/Ubuntu x86_64）
 8. 回滚 Sail BBR 优化
 0. 返回
EOF
        printf '%s\n' "------------------------------------------------------------"
        read -r -p "请输入选项 [0-8]: " choice
        case "$choice" in
            1|3) apply_profile balanced; pause ;;
            2) status; pause ;;
            4) apply_profile throughput; pause ;;
            5) apply_profile latency; pause ;;
            6) apply_profile concurrent; pause ;;
            7) install_xanmod; pause ;;
            8) rollback; pause ;;
            0) return 0 ;;
            *) warn "无效选项。"; sleep 1 ;;
        esac
    done
}

help_text() {
    cat <<EOF
Sail BBR Optimizer v${VERSION}

用法：
  $0 auto                    一键智能均衡优化
  $0 status                  查看状态
  $0 balanced                均衡模式
  $0 throughput              高吞吐模式
  $0 latency                 低延迟模式
  $0 concurrent              高并发模式
  $0 xanmod                  安装 XanMod LTS BBRv3 内核
  $0 rollback                回滚 Sail BBR 参数
  $0 menu                    交互菜单
EOF
}

case "${1:-menu}" in
    auto|balanced) apply_profile balanced ;;
    throughput) apply_profile throughput ;;
    latency) apply_profile latency ;;
    concurrent) apply_profile concurrent ;;
    status) status ;;
    xanmod|bbr3) install_xanmod ;;
    rollback|restore) rollback ;;
    menu) menu ;;
    help|-h|--help) help_text ;;
    *) err "未知命令：$1"; help_text; exit 2 ;;
esac
