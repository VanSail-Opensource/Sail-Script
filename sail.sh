#!/bin/bash
#===========================================
# Sail Script - 服务器管理脚本
# 由 SailData.Cloud 设计
#===========================================

# 彩色输出函数
green() {
    echo -e "\033[32m$1\033[0m"
}

red() {
    echo -e "\033[31m$1\033[0m"
}

yellow() {
    echo -e "\033[33m$1\033[0m"
}

# 退出时统一打印署名（支持正常退出和 Ctrl+C 等）
trap 'echo -e "\nDesigned by SailData.Cloud\n"; exit' EXIT

#===========================
# 基础信息
#===========================
basic_info() {
    clear
    echo "===== 基础信息 ====="
    echo ""
    echo "主机名: $(hostname)"
    echo "操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -s)"
    echo "内核版本: $(uname -r)"
    echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
    echo ""
    echo "CPU型号: $(grep 'model name' /proc/cpuinfo 2>/dev/null | head -n1 | cut -d: -f2 | sed -e 's/^ *//' || echo '无法获取')"
    echo "CPU核心数: $(nproc 2>/dev/null || echo '无法获取')"
    echo ""

    if command -v free &>/dev/null; then
        free -h
    fi

    echo ""

    if command -v df &>/dev/null; then
        df -h
    fi

    echo ""
    read -p "按回车键返回服务器信息菜单..." dummy
}

#===========================
# 流媒体检测
#===========================
streaming_check() {
    clear
    echo "===== 流媒体解锁 & IP质量检测 ====="
    echo ""

    bash <(curl -L ip.check.place) -y

    echo ""
    read -p "按回车键返回服务器信息菜单..." dummy
}

#===========================
# 服务器信息菜单
#===========================
server_info() {
    while true; do
        clear
        echo "===== 1. 服务器信息 ====="
        echo "==================================="
        echo " 1. 基础信息"
        echo " 2. 流媒体解锁"
        echo " 0. 返回主菜单"
        echo "==================================="

        read -p "请输入选项 [0-2]: " info_choice

        case $info_choice in
            1)
                basic_info
                ;;
            2)
                streaming_check
                ;;
            0)
                break
                ;;
            *)
                echo "无效选项，请重试"
                sleep 1
                ;;
        esac
    done
}

#===========================
# 宝塔安装
#===========================
install_bt_panel() {
    clear
    echo "===== 宝塔面板安装 ====="
    echo ""

    green "即将安装宝塔面板..."
    echo ""

    if [ -f /usr/bin/curl ]; then
        curl -sSO https://download.bt.cn/install/install_panel.sh
    else
        wget -O install_panel.sh https://download.bt.cn/install/install_panel.sh
    fi

    bash install_panel.sh ed8484bec
    rm -f install_panel.sh

    echo ""
    read -p "按回车键返回面板安装菜单..." dummy
}

#===========================
# 1Panel 安装
#===========================
install_1panel() {
    clear
    echo "===== 1Panel 安装 ====="
    echo ""

    green "即将安装 1Panel..."
    echo ""

    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"

    echo ""
    read -p "按回车键返回面板安装菜单..." dummy
}

#===========================
# 面板安装菜单
#===========================
panel_install() {
    while true; do
        clear
        echo "===== 2. 面板安装 ====="
        echo "==================================="
        echo " 1. 宝塔面板"
        echo " 2. 1Panel"
        echo " 0. 返回主菜单"
        echo "==================================="

        read -p "请输入选项 [0-2]: " panel_choice

        case $panel_choice in
            1)
                install_bt_panel
                ;;
            2)
                install_1panel
                ;;
            0)
                break
                ;;
            *)
                echo "无效选项，请重试"
                sleep 1
                ;;
        esac
    done
}

#===========================
# OpenClaw 安装
#===========================
install_openclaw() {
    clear
    echo "===== OpenClaw 安装 ====="
    echo ""

    green "即将安装 OpenClaw..."
    echo ""

    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --beta

    echo ""
    read -p "按回车键返回实用工具菜单..." dummy
}

#===========================
# Docker 安装状态检测
#===========================
check_docker_status() {
    echo "==================================="
    echo " Docker 安装状态"
    echo "==================================="

    docker_version=$(docker -v 2>/dev/null)
    compose_version=$(docker-compose -v 2>/dev/null)

    if [ -n "$docker_version" ]; then
        green "Docker: $docker_version"
    else
        red "Docker: 未安装"
    fi

    if [ -n "$compose_version" ]; then
        green "Docker Compose: $compose_version"
    else
        red "Docker Compose: 未安装"
    fi

    echo "==================================="
    echo ""
}

#===========================
# Docker 一键部署
#===========================
install_docker() {
    clear
    echo "===== Docker 一键部署 ====="
    echo ""

    green "即将安装 Docker..."
    echo ""

    bash <(curl -sL https://cdn.jsdelivr.net/gh/abokecn/docker@main/DockerInstallation.sh)

    echo ""
    read -p "按回车键返回 Docker 菜单..." dummy
}

#===========================
# Docker Compose 一键部署
#===========================
install_docker_compose() {
    clear
    echo "===== Docker Compose 一键部署 ====="
    echo ""

    green "即将安装 Docker Compose..."
    echo ""

    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose

    echo ""
    read -p "按回车键返回 Docker 菜单..." dummy
}

#===========================
# Docker 菜单
#===========================
docker_install_menu() {
    while true; do
        clear
        echo "===== 4. Docker 一键部署 ====="
        echo ""

        check_docker_status

        echo " 1. Docker 一键部署"
        echo " 2. Docker Compose 一键部署"
        echo " 0. 返回主菜单"
        echo "==================================="

        read -p "请输入选项 [0-2]: " docker_choice

        case $docker_choice in
            1)
                install_docker
                ;;
            2)
                install_docker_compose
                ;;
            0)
                break
                ;;
            *)
                echo "无效选项，请重试"
                sleep 1
                ;;
        esac
    done
}

#===========================
# 实用工具菜单
#===========================
tools() {
    while true; do
        clear
        echo "===== 3. 实用工具 ====="
        echo "==================================="
        echo " 1. OpenClaw"
        echo " 0. 返回主菜单"
        echo "==================================="

        read -p "请输入选项 [0-1]: " tools_choice

        case $tools_choice in
            1)
                install_openclaw
                ;;
            0)
                break
                ;;
            *)
                echo "无效选项，请重试"
                sleep 1
                ;;
        esac
    done
}

#===========================
# 主菜单
#===========================
while true; do
    clear

    echo "==================================="
    echo " Sail Script"
    echo " Designed by SailData.Cloud"
    echo "==================================="
    echo " 1. 服务器信息"
    echo " 2. 面板安装"
    echo " 3. 实用工具"
    echo " 4. Docker 一键部署"
    echo " 0. 退出"
    echo "==================================="

    read -p "请输入选项 [0-4]: " choice

    case $choice in
        1)
            server_info
            ;;
        2)
            panel_install
            ;;
        3)
            tools
            ;;
        4)
            docker_install_menu
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选项，请重试"
            sleep 1
            ;;
    esac
done
