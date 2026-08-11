# Sail Script

> 面向 Linux VPS / 服务器的轻量级交互式管理工具箱，由 **SailData.Cloud** 设计。

Sail Script 保持单文件入口、开箱即用，并将 NodeQuality 国内版、BBR/TCP 优化、VPS 初始化等复杂功能拆为独立模块。

## ✨ 功能

### VPS 一键初始化

打开初始化菜单：

```bash
./sail.sh INIT
```

基础初始化：

```bash
./sail.sh INIT basic
```

基础初始化默认会：

- 安装常用命令：`curl`、`wget`、`git`、`vim`、`nano`、`jq`、`unzip`、`zip`、`rsync`、`tmux`、`htop`、`lsof`、`socat` 等
- 安装 / 补齐 OpenSSH Server
- 安装并启用 Fail2ban
- 创建独立的 SSH Fail2ban jail
- 启用 cron / SSH 服务（存在 systemd 时）
- **不会自动修改 SSH 端口**
- **不会自动关闭密码登录**

完整交互式初始化：

```bash
./sail.sh INIT guided
```

还可以单独执行：

```bash
./sail.sh INIT packages
./sail.sh INIT fail2ban
./sail.sh INIT ssh-port
./sail.sh INIT add-key
./sail.sh INIT key-only
./sail.sh INIT status
```

SSH 安全设计：

- 修改端口前自动备份 SSH 配置
- 新端口限制为 `1024-65535`
- 检查端口是否已经监听
- UFW / firewalld 已启用时，先放行新端口再修改 SSH
- 检测到自定义 nftables / iptables 时不擅自改规则，只给出警告
- 修改 SSH 后先运行 `sshd -t`
- Ubuntu systemd socket activation 场景会执行 `systemctl daemon-reload`
- SSH 重启失败时尝试恢复配置
- 修改端口后同步更新 Sail Fail2ban jail
- 添加公钥时校验 OpenSSH 公钥格式和 `authorized_keys` 权限
- 只有检测到目标用户存在 `authorized_keys`，并再次确认已实际测试密钥登录后，才允许关闭密码登录
- Root 采用密钥登录时设置 `PermitRootLogin prohibit-password`，而不是直接禁止 root

初始化模块位于：

```text
scripts/vps-init.sh
```

### 服务器概览

- 操作系统、内核、架构、虚拟化环境
- CPU 型号、核心数、系统负载
- 内存、Swap、磁盘占用
- 本机 IPv4 / IPv6
- TCP 拥塞控制算法与默认队列算法

### 网络与 IP 工具

- 公网 IP / ASN 信息
- NodeQuality 官方一键运行
- NodeQuality 国内网络受阻运行
- 一键 BBR / TCP 优化
- 流媒体解锁与 IP 质量检测
- Ping 延迟 / 丢包测试
- HTTP DNS / TCP / TLS / Total 耗时测试
- 监听端口查看

#### NodeQuality

```bash
./sail.sh NQ
./sail.sh NQCN
```

`NQ` 等价于：

```bash
bash <(curl -sL https://run.NodeQuality.com)
```

`NQCN` 通过 Sail Script CDN 启动器获取最新版 NodeQuality，并对 GitHub Raw / Release 下载入口进行加速处理。

### 一键 BBR / TCP 优化

```bash
./sail.sh BBR
./sail.sh BBR status
./sail.sh BBR balanced
./sail.sh BBR throughput
./sail.sh BBR latency
./sail.sh BBR concurrent
./sail.sh BBR xanmod
./sail.sh BBR rollback
```

主要设计：

- 优先使用当前内核已有的 `bbr`
- 推荐组合 `BBR + fq`
- 根据服务器内存自动缩放 TCP socket buffer
- 均衡 / 高吞吐 / 低延迟 / 高并发四档
- 写入 `/etc/sysctl.d/99-sail-bbr.conf`
- 首次优化前保存原始 sysctl 状态
- 检测潜在冲突配置
- 不强制覆盖已有 CAKE / TBF / HTB / netem / 多队列 qdisc
- 支持回滚
- Debian / Ubuntu x86_64 可选安装 XanMod LTS BBRv3

> BBRv3 与普通主线 BBR 不混淆；只有明确检测到 v3 模块时才显示 BBRv3。

### 系统维护

- Debian / Ubuntu：`apt`
- Fedora / RHEL / Rocky / AlmaLinux：`dnf` / `yum`
- Alpine：`apk`
- Arch Linux：`pacman`
- 系统更新
- 软件包缓存和无用依赖清理
- systemd journal 清理
- 磁盘占用分析

### Docker 管理

- Docker 官方脚本安装 / 更新
- Docker Compose v2
- Docker / Compose 状态检测
- 容器列表
- Docker 磁盘占用
- 安全清理未使用数据

### 面板与工具

- 宝塔面板
- 1Panel
- OpenClaw

### Sail Script 自管理

- 版本检查
- 自更新
- `/usr/local/bin/sail` 快捷命令
- CLI + 交互菜单

## 🚀 快速使用

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VanSail-Opensource/Sail-Script/main/sail.sh)
```

或者：

```bash
curl -fsSL https://raw.githubusercontent.com/VanSail-Opensource/Sail-Script/main/sail.sh -o sail.sh
chmod +x sail.sh
./sail.sh
```

## ⌨️ CLI 示例

```bash
./sail.sh info
./sail.sh INIT
./sail.sh INIT basic
./sail.sh INIT guided
./sail.sh NQ
./sail.sh NQCN
./sail.sh BBR
./sail.sh BBR status
./sail.sh ports
./sail.sh docker status
./sail.sh check-update
```

完整帮助：

```bash
./sail.sh help
```

安装快捷命令：

```bash
sudo ./sail.sh install-shortcut
sail INIT
```

## 🔐 安全设计

- 修改系统前检查 root 权限
- 高风险操作要求确认
- CDN 模块先下载到临时文件，再执行 `bash -n`
- SSH 改动使用备份、`sshd -t` 校验与失败恢复
- 不在未验证密钥可登录时自动关闭 SSH 密码认证
- Docker 使用官方 `get.docker.com`
- BBR 使用独立 sysctl.d 配置并保留回滚状态
- Docker 清理默认不主动删除 volume

需要注意：`NQ` 按设计直接执行 NodeQuality 官方命令，因此不经过 Sail Script 自己的下载校验流程。宝塔、1Panel、OpenClaw、IP 检测等功能也会执行对应项目提供的第三方脚本。

## 📦 支持范围

主要面向：

- Debian / Ubuntu
- Fedora / RHEL / Rocky Linux / AlmaLinux
- Alpine Linux
- Arch Linux

部分包在某些发行版的软件源中可能不存在；初始化模块会保留包管理器的原始错误输出方便排查。

## 🧭 设计方向

1. `sail.sh` 保持统一入口。
2. NQCN、BBR、VPS 初始化等复杂功能拆为独立模块。
3. 同时支持交互式菜单与 CLI。
4. 对高风险操作增加确认、权限检查、备份、校验和回滚。
5. 借鉴成熟脚本的思路，但保持独立实现。

## 项目地址

GitHub: https://github.com/VanSail-Opensource/Sail-Script

## License

请以仓库中的 LICENSE 文件为准。

---

Designed by **SailData.Cloud**
