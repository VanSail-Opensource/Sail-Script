#!/usr/bin/env bash
# Sail Script - VPS initialization / hardening assistant
set -uo pipefail

VERSION="1.0.0"
STATE_DIR="/var/lib/sail-script/init"
SSH_MAIN="/etc/ssh/sshd_config"
SSH_SNIPPET="/etc/ssh/sshd_config.d/99-sail-init.conf"
F2B_JAIL="/etc/fail2ban/jail.d/99-sail-sshd.local"

if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
 R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; C=$'\033[36m'; N=$'\033[0m'; BD=$'\033[1m'
else R=""; G=""; Y=""; B=""; C=""; N=""; BD=""; fi

info(){ printf '%s[INFO]%s %s\n' "$B" "$N" "$*"; }
ok(){ printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$N" "$*"; }
err(){ printf '%s[ERR ]%s %s\n' "$R" "$N" "$*" >&2; }
has(){ command -v "$1" >/dev/null 2>&1; }
pause(){ [[ -t 0 ]] || return 0; printf '\n'; read -r -p "按回车键继续..." _; }
confirm(){ local a; [[ -t 0 ]] || return 1; read -r -p "${1:-确认继续？} [y/N]: " a; [[ "${a,,}" == y || "${a,,}" == yes ]]; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] && return 0; err "需要 root 权限。"; return 1; }

header(){
 printf '%s============================================================%s\n' "$C" "$N"
 printf '%s Sail VPS Init%s  v%s\n' "$BD" "$N" "$VERSION"
 printf ' 常用工具 / Fail2ban / SSH 端口 / 密钥登录 / 安全检查\n'
 printf '%s============================================================%s\n' "$C" "$N"
}

pkg_manager(){ local p; for p in apt-get dnf yum apk pacman; do has "$p" && { printf '%s' "$p"; return 0; }; done; return 1; }

install_common_tools(){
 need_root || return 1
 local pm; pm="$(pkg_manager)" || { err "无法识别包管理器。"; return 1; }
 info "安装常用命令；不会执行整机发行版升级。"
 case "$pm" in
  apt-get)
   apt-get update || return 1
   DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget git vim nano jq unzip zip tar rsync tmux htop lsof ca-certificates gnupg \
    sudo cron iproute2 iputils-ping dnsutils net-tools socat openssh-client openssh-server fail2ban
   ;;
  dnf)
   dnf install -y curl wget git vim nano jq unzip zip tar rsync tmux htop lsof ca-certificates gnupg2 \
    sudo cronie iproute iputils bind-utils net-tools socat openssh-clients openssh-server fail2ban
   ;;
  yum)
   yum install -y curl wget git vim nano jq unzip zip tar rsync tmux htop lsof ca-certificates gnupg2 \
    sudo cronie iproute iputils bind-utils net-tools socat openssh-clients openssh-server fail2ban
   ;;
  apk)
   apk update
   apk add curl wget git vim nano jq unzip zip tar rsync tmux htop lsof ca-certificates gnupg \
    sudo dcron iproute2 iputils bind-tools net-tools socat openssh-client openssh-server fail2ban
   ;;
  pacman)
   pacman -Sy --noconfirm
   pacman -S --needed --noconfirm curl wget git vim nano jq unzip zip tar rsync tmux htop lsof \
    ca-certificates gnupg sudo cronie iproute2 iputils bind net-tools socat openssh fail2ban
   ;;
 esac
 ok "常用工具安装完成。"
}

current_ssh_port(){
 if has sshd; then sshd -T 2>/dev/null | awk '/^port /{print $2; exit}'; else printf '22'; fi
}

ssh_service(){
 has systemctl || return 1
 systemctl list-unit-files ssh.service >/dev/null 2>&1 && { printf 'ssh.service'; return 0; }
 systemctl list-unit-files sshd.service >/dev/null 2>&1 && { printf 'sshd.service'; return 0; }
 return 1
}

restart_ssh(){
 if has systemctl; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  local svc; svc="$(ssh_service 2>/dev/null || true)"
  [[ -n "$svc" ]] && systemctl restart "$svc" && return 0
 fi
 has service && { service ssh restart 2>/dev/null || service sshd restart 2>/dev/null; return $?; }
 return 1
}

sshd_test(){ has sshd || { err "未找到 sshd。"; return 1; }; sshd -t; }
ensure_state(){ mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true; }

supports_snippet(){
 [[ -d /etc/ssh/sshd_config.d ]] &&
 grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSH_MAIN" 2>/dev/null
}

backup_ssh_once(){
 ensure_state
 [[ -f "${STATE_DIR}/sshd_config.original" ]] || cp -p "$SSH_MAIN" "${STATE_DIR}/sshd_config.original" 2>/dev/null || true
 if [[ -f "$SSH_SNIPPET" && ! -f "${STATE_DIR}/99-sail-init.conf.previous" ]]; then
  cp -p "$SSH_SNIPPET" "${STATE_DIR}/99-sail-init.conf.previous"
 fi
}

write_ssh_setting(){
 local key="$1" value="$2"
 backup_ssh_once
 if supports_snippet; then
  touch "$SSH_SNIPPET"; chmod 600 "$SSH_SNIPPET"
  sed -i -E "/^[[:space:]]*${key}[[:space:]]+/Id" "$SSH_SNIPPET"
  printf '%s %s\n' "$key" "$value" >> "$SSH_SNIPPET"
 else
  sed -i -E "/^[[:space:]#]*${key}[[:space:]]+/Id" "$SSH_MAIN"
  printf '\n%s %s\n' "$key" "$value" >> "$SSH_MAIN"
 fi
}

restore_ssh(){
 if supports_snippet; then
  if [[ -f "${STATE_DIR}/99-sail-init.conf.previous" ]]; then cp -p "${STATE_DIR}/99-sail-init.conf.previous" "$SSH_SNIPPET"; else rm -f "$SSH_SNIPPET"; fi
 elif [[ -f "${STATE_DIR}/sshd_config.original" ]]; then
  cp -p "${STATE_DIR}/sshd_config.original" "$SSH_MAIN"
 fi
}

allow_tcp(){
 local port="$1"
 if has ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "${port}/tcp" || return 1; ok "UFW 已放行 TCP/${port}"
 elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${port}/tcp" || return 1
  firewall-cmd --reload || return 1; ok "firewalld 已放行 TCP/${port}"
 elif has nft && nft list ruleset 2>/dev/null | grep -q .; then
  warn "检测到 nftables 自定义规则，请人工确认 TCP/${port} 已放行。"
 elif has iptables && iptables -S 2>/dev/null | grep -q -- '-P INPUT DROP'; then
  warn "iptables INPUT 默认 DROP，请人工确认 TCP/${port} 已放行。"
 fi
}

configure_fail2ban(){
 need_root || return 1
 has fail2ban-client || { err "Fail2ban 未安装，请先执行基础初始化。"; return 1; }
 mkdir -p /etc/fail2ban/jail.d
 local port backend="auto"; port="$(current_ssh_port)"; port="${port:-22}"
 has journalctl && [[ -d /run/systemd/system ]] && backend="systemd"
 cat > "$F2B_JAIL" <<EOF
[sshd]
enabled = true
port = ${port}
backend = ${backend}
maxretry = 5
findtime = 10m
bantime = 1h
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 24h
EOF
 if has systemctl; then
  systemctl enable --now fail2ban
  systemctl restart fail2ban
 else
  service fail2ban restart 2>/dev/null || true
 fi
 fail2ban-client status sshd 2>/dev/null || warn "Fail2ban 已配置，但暂时无法读取 sshd jail 状态。"
 ok "Fail2ban SSH 防护已启用，保护端口：${port}。"
}

change_ssh_port(){
 need_root || return 1
 has sshd || { err "OpenSSH Server 未安装。"; return 1; }
 local old new; old="$(current_ssh_port)"; old="${old:-22}"
 printf '当前 SSH 端口：%s\n' "$old"
 read -r -p "请输入新 SSH 端口 [1024-65535]: " new
 [[ "$new" =~ ^[0-9]+$ ]] || { err "端口格式错误。"; return 1; }
 (( new >= 1024 && new <= 65535 )) || { err "端口必须在 1024-65535。"; return 1; }
 [[ "$new" != "$old" ]] || { warn "新旧端口相同。"; return 0; }
 if has ss && ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${new}$"; then err "TCP/${new} 已被占用。"; return 1; fi
 warn "会先放行新端口、备份 SSH 配置、执行 sshd -t，再重启 SSH。"
 confirm "确认把 SSH 端口改为 ${new}？" || return 0
 allow_tcp "$new" || { err "防火墙放行失败，终止修改。"; return 1; }
 write_ssh_setting Port "$new"
 if ! sshd_test; then err "sshd 配置校验失败，正在恢复。"; restore_ssh; sshd_test || true; return 1; fi
 if ! restart_ssh; then err "SSH 重启失败，正在恢复。"; restore_ssh; restart_ssh || true; return 1; fi
 sleep 1
 if has ss && ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${new}$"; then ok "SSH 已监听 TCP/${new}。"; else warn "未能确认新端口监听，请保持当前会话并另开终端测试。"; fi
 [[ -f "$F2B_JAIL" ]] && configure_fail2ban || true
 warn "请立即另开会话测试：ssh -p ${new} 用户@服务器；确认成功前不要关闭当前会话。"
}

valid_key(){ case "$1" in ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) return 0;; *) return 1;; esac; }

add_public_key(){
 need_root || return 1
 local def user key home group; def="${SUDO_USER:-root}"
 read -r -p "写入密钥的用户名 [${def}]: " user; user="${user:-$def}"
 getent passwd "$user" >/dev/null 2>&1 || { err "用户不存在：$user"; return 1; }
 home="$(getent passwd "$user" | cut -d: -f6)"; group="$(id -gn "$user")"
 printf '请粘贴一整行 SSH 公钥（推荐 ssh-ed25519）：\n'; IFS= read -r key
 valid_key "$key" || { err "不是支持的 OpenSSH 公钥格式。"; return 1; }
 install -d -m 700 -o "$user" -g "$group" "$home/.ssh"
 touch "$home/.ssh/authorized_keys"; chown "$user:$group" "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
 grep -Fqx "$key" "$home/.ssh/authorized_keys" && warn "该公钥已经存在。" || { printf '%s\n' "$key" >> "$home/.ssh/authorized_keys"; ok "公钥已加入 ${user}。"; }
 write_ssh_setting PubkeyAuthentication yes
 sshd_test || { err "sshd 校验失败，未重启。"; return 1; }
 restart_ssh || warn "SSH 服务重启失败，请手工检查。"
 warn "请先另开终端确认密钥登录成功，再关闭密码登录。"
}

has_key(){
 local user="$1" home; home="$(getent passwd "$user" | cut -d: -f6)"
 [[ -s "$home/.ssh/authorized_keys" ]] && grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-)' "$home/.ssh/authorized_keys"
}

key_only(){
 need_root || return 1
 local def user; def="${SUDO_USER:-root}"
 read -r -p "确认已验证密钥登录的用户名 [${def}]: " user; user="${user:-$def}"
 getent passwd "$user" >/dev/null 2>&1 || { err "用户不存在。"; return 1; }
 has_key "$user" || { err "未发现 authorized_keys，为防止锁死，拒绝关闭密码登录。"; return 1; }
 warn "将关闭 PasswordAuthentication 与 KbdInteractiveAuthentication。"
 confirm "你已经在另一个 SSH 会话验证过密钥登录成功了吗？" || return 0
 write_ssh_setting PubkeyAuthentication yes
 write_ssh_setting PasswordAuthentication no
 write_ssh_setting KbdInteractiveAuthentication no
 [[ "$user" == root ]] && write_ssh_setting PermitRootLogin prohibit-password
 if ! sshd_test; then err "sshd 校验失败，正在恢复。"; restore_ssh; return 1; fi
 restart_ssh || { err "SSH 重启失败，正在恢复。"; restore_ssh; restart_ssh || true; return 1; }
 ok "已关闭 SSH 密码/键盘交互认证。"
}

status(){
 header
 printf 'SSH 端口        : %s\n' "$(current_ssh_port)"
 if has sshd; then
  printf '公钥登录        : %s\n' "$(sshd -T 2>/dev/null | awk '/^pubkeyauthentication /{print $2;exit}')"
  printf '密码登录        : %s\n' "$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2;exit}')"
  printf '交互认证        : %s\n' "$(sshd -T 2>/dev/null | awk '/^kbdinteractiveauthentication /{print $2;exit}')"
  printf 'Root SSH        : %s\n' "$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2;exit}')"
 fi
 if has fail2ban-client; then fail2ban-client ping >/dev/null 2>&1 && printf 'Fail2ban        : running\n' || printf 'Fail2ban        : installed / stopped\n'; else printf 'Fail2ban        : 未安装\n'; fi
 has ufw && printf 'UFW             : %s\n' "$(ufw status 2>/dev/null | head -n1)"
 has firewall-cmd && printf 'firewalld       : %s\n' "$(firewall-cmd --state 2>/dev/null || printf stopped)"
}

basic(){
 need_root || return 1
 header
 warn "基础初始化：安装常用命令 + OpenSSH Server + Fail2ban；不会修改 SSH 端口或关闭密码登录。"
 confirm "确认开始？" || return 0
 install_common_tools || return 1
 configure_fail2ban || warn "Fail2ban 配置未完全成功。"
 if has systemctl; then
  systemctl enable --now cron 2>/dev/null || systemctl enable --now crond 2>/dev/null || true
  systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
 fi
 ok "基础 VPS 初始化完成。"
}

guided(){
 basic || return 1
 confirm "是否修改 SSH 为高位端口？" && change_ssh_port
 confirm "是否添加 SSH 公钥？" && add_public_key
 confirm "是否在验证密钥可用后关闭 SSH 密码登录？" && key_only
 status
}

menu(){
 while true; do
  clear 2>/dev/null || true; header
  cat <<'EOF'
 1. 一键基础初始化（常用工具 + Fail2ban，推荐）
 2. 完整初始化向导
 3. 安装 / 补齐常用命令
 4. 配置 / 重载 Fail2ban SSH 防护
 5. 修改 SSH 高位端口
 6. 添加 SSH 公钥
 7. 关闭密码登录，仅保留密钥登录
 8. 查看初始化 / SSH 安全状态
 0. 返回
EOF
  read -r -p "请输入选项 [0-8]: " c
  case "$c" in
   1) basic; pause;; 2) guided; pause;; 3) install_common_tools; pause;; 4) configure_fail2ban; pause;;
   5) change_ssh_port; pause;; 6) add_public_key; pause;; 7) key_only; pause;; 8) status; pause;; 0) return 0;;
   *) warn "无效选项。"; sleep 1;;
  esac
 done
}

help_text(){
 cat <<EOF
Sail VPS Init v${VERSION}
  menu       初始化菜单
  basic      常用工具 + Fail2ban
  guided     完整交互式初始化
  packages   安装常用工具
  fail2ban   配置 Fail2ban
  ssh-port   修改 SSH 高位端口
  add-key    添加 SSH 公钥
  key-only   关闭 SSH 密码登录
  status     查看状态
EOF
}

case "${1:-menu}" in
 menu) menu;; basic|auto) basic;; guided|wizard) guided;; packages|tools) install_common_tools;;
 fail2ban) configure_fail2ban;; ssh-port|port) change_ssh_port;; add-key|key) add_public_key;;
 key-only|harden-ssh) key_only;; status) status;; help|-h|--help) help_text;;
 *) err "未知命令：$1"; help_text; exit 2;;
esac
