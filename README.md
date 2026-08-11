# Sail Script

> 面向 Linux VPS / 服务器的轻量级交互式管理工具箱，由 **SailData.Cloud** 设计。

Sail Script 保持单文件、开箱即用的特点，同时补齐服务器概览、网络诊断、系统维护、Docker 管理、面板安装、自更新和快捷命令等常用能力。

## ✨ 功能

### 服务器概览

- 操作系统、内核、架构、虚拟化环境
- CPU 型号、核心数、系统负载
- 内存、Swap、磁盘占用
- 本机 IPv4 / IPv6
- TCP 拥塞控制算法与默认队列算法

### 网络与 IP 工具

- 公网 IP / ASN 信息
- 流媒体解锁与 IP 质量检测
- Ping 延迟 / 丢包测试
- HTTP DNS / TCP / TLS / Total 耗时测试
- 监听端口查看

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
- 自更新（覆盖前执行 `bash -n` 检查，并尽量保留 `.bak`）
- 安装 `/usr/local/bin/sail` 快捷命令
- 卸载快捷命令
- 支持交互菜单与 CLI 子命令

## 🚀 快速使用

直接打开菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VanSail-Opensource/Sail-Script/main/sail.sh)
```

也可以下载后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/VanSail-Opensource/Sail-Script/main/sail.sh -o sail.sh
chmod +x sail.sh
./sail.sh
```

> 当前重构版本正在开发分支 `agent/modernize-sail-script` 中，可先将 URL 中的 `main` 替换为该分支进行测试。

## ⌨️ CLI 用法

```bash
./sail.sh info
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

以后直接运行：

```bash
sail
sail info
sail docker status
```

## 🔐 安全设计

Sail Script 中涉及系统变更的操作会尽量遵循以下规则：

- 修改系统前检查 root 权限
- 危险或外部脚本操作要求用户确认
- 远程 Shell 脚本先下载到临时文件，再执行 `bash -n` 语法检查
- 不使用 `curl ... | bash` 直接管道执行
- Docker 使用官方 `get.docker.com`
- Docker Compose 使用官方 GitHub Release 二进制
- 自更新前先校验 Bash 语法
- Docker 清理默认不主动删除 volume

请注意：宝塔、1Panel、OpenClaw、IP 检测等功能仍会执行对应项目提供的第三方脚本。运行前请自行确认来源与风险。

## 📦 支持范围

主要面向常见 Linux 服务器发行版：

- Debian / Ubuntu
- Fedora / RHEL / Rocky Linux / AlmaLinux
- Alpine Linux
- Arch Linux

部分功能依赖 `systemd`、`curl`、`iproute2` 等组件；脚本会在多数情况下进行检测并给出提示。

## 🧭 设计方向

Sail Script 的目标不是复制其他大型一键脚本，而是保持 **轻量、清晰、可维护**：

1. 核心功能保持在单个 `sail.sh` 中，便于审计与一键执行。
2. 功能按服务器信息、网络、系统维护、Docker、面板、工具、自管理分类。
3. 同时支持交互式菜单与 CLI，方便人工使用和自动化调用。
4. 对高风险操作增加确认、权限检查和基本错误处理。

## 项目地址

GitHub: https://github.com/VanSail-Opensource/Sail-Script

## License

请以仓库中的 LICENSE 文件为准。

---

Designed by **SailData.Cloud**
