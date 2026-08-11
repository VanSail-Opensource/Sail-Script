# Sail Script

> 面向 Linux VPS / 服务器的轻量级交互式管理工具箱，由 **SailData.Cloud** 设计。

Sail Script 保持单文件入口、开箱即用的特点，同时补齐服务器概览、网络诊断、NodeQuality、BBR/TCP 优化、系统维护、Docker 管理、面板安装、自更新和快捷命令等常用能力。

## ✨ 功能

### 服务器概览

- 操作系统、内核、架构、虚拟化环境
- CPU 型号、核心数、系统负载
- 内存、Swap、磁盘占用
- 本机 IPv4 / IPv6
- TCP 拥塞控制算法与默认队列算法

### 网络与 IP 工具

- 公网 IP / ASN 信息
- NodeQuality 官方一键运行
- NodeQuality 国内网络受阻运行（CDN 镜像启动器）
- 一键 BBR / TCP 优化
- 流媒体解锁与 IP 质量检测
- Ping 延迟 / 丢包测试
- HTTP DNS / TCP / TLS / Total 耗时测试
- 监听端口查看

#### NodeQuality 快捷命令

```bash
./sail.sh NQ
./sail.sh NQCN
```

`NQ` 等价于：

```bash
bash <(curl -sL https://run.NodeQuality.com)
```

`NQCN` 会通过 Sail Script 的 CDN 启动器获取最新版 NodeQuality，并将相关 GitHub Raw / Release 下载入口切换到 CDN 或加速线路。

### 一键 BBR / TCP 优化

默认智能均衡优化：

```bash
./sail.sh BBR
```

状态查看与不同场景：

```bash
./sail.sh BBR status
./sail.sh BBR balanced
./sail.sh BBR throughput
./sail.sh BBR latency
./sail.sh BBR concurrent
./sail.sh BBR xanmod
./sail.sh BBR rollback
```

BBR 模块位于：

```text
scripts/bbr-optimize.sh
```

主要设计：

- 优先使用当前内核已有的 `bbr`，不为了“优化”而强制换内核
- 推荐组合为 `BBR + fq`
- 根据服务器内存自动缩放 TCP socket buffer
- 提供均衡、高吞吐、低延迟、高并发四种参数档位
- 写入独立配置 `/etc/sysctl.d/99-sail-bbr.conf`
- 第一次优化前保存原始 sysctl 状态
- 检测其他可能冲突的 sysctl 配置
- 已有 CAKE / TBF / HTB / netem / 多队列 qdisc 时不强制实时覆盖
- 支持 `rollback` 回滚 Sail Script 写入的网络参数
- Debian / Ubuntu x86_64 可选安装 XanMod LTS 内核以获得 BBRv3

> BBRv3 与普通主线 BBR 不混淆。脚本会查看 `tcp_bbr` 模块 version；只有明确检测到 v3 时才显示 BBRv3。

### 系统维护

- Debian / Ubuntu：`apt`
- Fedora / RHEL / Rocky / AlmaLinux：`dnf` / `yum`
- Alpine：`apk`
- Arch Linux：`pacman`
- 一键系统更新
- 软件包缓存和无用依赖清理
- systemd journal 日志清理
- 根目录一级磁盘占用分析

### Docker 管理

- Docker 官方脚本安装 / 更新
- Docker Compose v2 CLI Plugin 安装 / 更新
- Docker / Compose 状态检测
- 容器列表
- Docker 磁盘占用
- 安全清理未使用的 Docker 数据

### 面板与工具

- 宝塔面板
- 1Panel
- OpenClaw

### Sail Script 自管理

- 版本检查
- 自更新
- 安装 `/usr/local/bin/sail` 快捷命令
- 卸载快捷命令
- 支持交互菜单与 CLI 子命令

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

> 当前新增功能位于开发分支 `agent/modernize-sail-script`。生产 CDN 地址固定指向 `main`，因此相关模块需合并进 `main` 后才能通过正式 CDN 入口运行。

## ⌨️ CLI 用法

```bash
./sail.sh info
./sail.sh NQ
./sail.sh NQCN
./sail.sh BBR
./sail.sh BBR status
./sail.sh BBR throughput
./sail.sh ports
./sail.sh docker status
./sail.sh docker install
./sail.sh docker compose
./sail.sh check-update
```

完整帮助：

```bash
./sail.sh help
```

### 安装 `sail` 快捷命令

```bash
sudo ./sail.sh install-shortcut
```

以后可直接运行：

```bash
sail
sail info
sail NQ
sail NQCN
sail BBR
sail BBR status
```

## 🔐 安全设计

- 修改系统前检查 root 权限
- 危险或外部脚本操作要求用户确认
- 模块先下载到临时文件，再执行 `bash -n` 语法检查
- Docker 使用官方 `get.docker.com`
- Docker Compose 使用官方 GitHub Release 二进制
- Docker 清理默认不主动删除 volume
- BBR 参数写入独立 sysctl.d 文件，不批量注释或重写系统已有配置
- BBR 首次优化保存可回滚状态
- 安装 XanMod 前检查架构、虚拟化类型和发行版

需要注意：`NQ` 按设计要求直接执行 NodeQuality 官方命令，因此该入口不经过 Sail Script 自己的下载校验流程。宝塔、1Panel、OpenClaw、IP 检测等功能同样会执行对应项目提供的第三方脚本。

## 📦 支持范围

主要面向：

- Debian / Ubuntu
- Fedora / RHEL / Rocky Linux / AlmaLinux
- Alpine Linux
- Arch Linux

XanMod BBRv3 自动安装当前仅支持 **Debian / Ubuntu x86_64**，且不适用于无法自行更换内核的 LXC / OpenVZ / Docker 等容器型环境。

## 🧭 设计方向

Sail Script 的目标不是复制大型一键脚本，而是保持 **轻量、清晰、可维护**：

1. `sail.sh` 保持为统一入口。
2. NodeQuality 国内版、BBR 等复杂功能拆为独立模块。
3. 同时支持交互式菜单与 CLI。
4. 对高风险操作增加确认、权限检查、备份与回滚。
5. 借鉴成熟脚本的优化思路，但保留独立实现，避免整份复制第三方项目。

## 项目地址

GitHub: https://github.com/VanSail-Opensource/Sail-Script

## License

请以仓库中的 LICENSE 文件为准。

---

Designed by **SailData.Cloud**
