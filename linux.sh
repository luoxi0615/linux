#!/bin/bash

#===============================================================================================
#
#          文件: optimizer_v3.sh
#
#         用法: bash optimizer_v3.sh
#
#   功能描述: 一个功能全面的Linux系统优化与服务器性能检测工具。
#             (包含快速诊断与全面的基准测试)
#
#       作者: SysAdmin
#       版本: 3.0 (增强了超售检测功能)
#   创建日期: 2025-07-11
#
#===============================================================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 清除颜色

# --- 日志文件路径 ---
LOG_FILE="/var/log/sys-optimizer.log"

# --- 函数: 写入日志 ---
log() {
    echo -e "$(date "+%Y-%m-%d %H:%M:%S") - $1" | tee -a $LOG_FILE
}

# --- 函数: 检查Root权限 ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须以 root 用户权限运行！${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo bash $0'${NC}"
        exit 1
    fi
}

# --- 函数: 依赖安装检查 ---
check_and_install_deps() {
    local pkg_manager=""
    local packages_to_install=()

    for pkg in "$@"; do
        if ! command -v "$pkg" &> /dev/null; then
            packages_to_install+=("$pkg")
        fi
    done

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        return 0
    fi

    echo -e "${YELLOW}检测到运行详细测试需要以下工具: ${packages_to_install[*]}，但它们尚未安装。${NC}"
    read -rp "是否现在自动安装? (y/n): " choice < /dev/tty
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo -e "${RED}用户取消安装，无法进行详细测试。${NC}"
        return 1
    fi

    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
        echo "正在使用 apt-get 更新源..."
        $pkg_manager update
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    else
        echo -e "${RED}未知的包管理器，无法自动安装依赖。请手动安装: ${packages_to_install[*]}${NC}"
        return 1
    fi

    echo "正在使用 $pkg_manager 安装 ${packages_to_install[*]}..."
    sudo $pkg_manager install -y "${packages_to_install[@]}"
    if [ $? -ne 0 ]; then
        echo -e "${RED}依赖安装失败！请检查您的包管理器或网络。${NC}"
        return 1
    fi
    echo -e "${GREEN}依赖安装成功！${NC}"
    return 0
}

# --- 函数: 按Enter键继续 ---
press_any_key_to_continue() {
    echo -e "\n按 [Enter] 键返回..."
    read -r < /dev/tty
}

# --- 函数: 快速诊断超售 ---
quick_oversold_check() {
    log "执行: 快速诊断超售"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                  快速诊断 (CPU窃取与磁盘I/O)                  ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    
    # 1. CPU窃取时间检测
    echo -e "${BLUE}--- 1. 正在检测 CPU 窃取时间 (Steal Time) ---${NC}"
    if ! command -v vmstat &> /dev/null; then
        echo -e "${RED}vmstat 命令未找到，跳过此项检测。请安装 procps 包。${NC}"
    else
        CPU_STEAL=$(vmstat 1 2 | tail -1 | awk '{print $NF}')
        echo -e "当前 CPU 窃取时间: ${PURPLE}${CPU_STEAL}%${NC}"
        if (( $(echo "$CPU_STEAL > 5" | bc -l) )); then
            echo -e "${RED}警告：CPU 窃取时间较高 (${CPU_STEAL}%)，这可能是服务器超售的一个强烈信号！${NC}"
        else
            echo -e "${GREEN}CPU 窃取时间正常 (${CPU_STEAL}%)。${NC}"
        fi
    fi
    
    echo -e "\n${CYAN}--------------------------------------------------------------${NC}\n"
    
    # 2. 磁盘I/O性能检测
    echo -e "${BLUE}--- 2. 正在检测磁盘顺序写入性能 ---${NC}"
    IO_TEST_FILE="test_io_quick.tmp"
    IO_SPEED=$(dd if=/dev/zero of=$IO_TEST_FILE bs=64k count=4k oflag=dsync 2>&1 | awk -F, '/copied/{print $3}' | sed 's/ //g')
    rm -f $IO_TEST_FILE
    echo -e "磁盘顺序写入速度: ${PURPLE}${IO_SPEED}${NC}"
    
    log "完成: 快速诊断超售"
    press_any_key_to_continue
}

# --- 函数: 全面基准测试 ---
detailed_benchmark() {
    log "执行: 全面基准测试"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                 全面基准测试 (CPU/内存/磁盘/网络)               ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}此测试将持续几分钟，请耐心等待...${NC}"

    if ! check_and_install_deps "sysbench" "wget"; then
        press_any_key_to_continue
        return
    fi
    
    # 1. CPU性能测试
    echo -e "\n${BLUE}--- 1. 正在进行 CPU 基准测试 (sysbench) ---${NC}"
    CPU_RESULT=$(sysbench cpu --cpu-max-prime=20000 --threads=1 run | grep "events per second:")
    CPU_SCORE=$(echo $CPU_RESULT | awk '{print $4}')
    echo -e "CPU 单核性能得分: ${PURPLE}${CPU_SCORE} events/sec${NC} (得分越高越好)"
    log "CPU测试得分: ${CPU_SCORE}"

    # 2. 内存性能测试
    echo -e "\n${BLUE}--- 2. 正在进行 内存(RAM) 速度测试 (sysbench) ---${NC}"
    MEM_RESULT=$(sysbench memory --memory-block-size=1M --memory-total-size=10G run | grep "transferred")
    MEM_SPEED=$(echo $MEM_RESULT | awk -F'(' '{print $2}' | awk -F')' '{print $1}')
    echo -e "内存传输速度: ${PURPLE}${MEM_SPEED}${NC} (速度越高越好)"
    log "内存测试速度: ${MEM_SPEED}"

    # 3. 磁盘随机读写IOPS测试
    echo -e "\n${BLUE}--- 3. 正在进行 磁盘随机读写IOPS测试 (sysbench) ---${NC}"
    echo -e "${YELLOW}正在准备测试文件 (1GB)，请稍候...${NC}"
    sysbench fileio --file-total-size=1G prepare > /dev/null 2>&1
    IOPS_RESULT=$(sysbench fileio --file-total-size=1G --file-test-mode=rndrw --time=60 --max-requests=0 run | grep "read, MiB/s:")
    IOPS_READ=$(echo $IOPS_RESULT | awk '{print $3}')
    IOPS_WRITE=$(echo $IOPS_RESULT | awk '{print $6}')
    echo -e "磁盘随机读写性能: 读取 ${PURPLE}${IOPS_READ} MiB/s${NC}, 写入 ${PURPLE}${IOPS_WRITE} MiB/s${NC}"
    sysbench fileio --file-total-size=1G cleanup > /dev/null 2>&1
    log "磁盘IOPS测试: Read=${IOPS_READ} MiB/s, Write=${IOPS_WRITE} MiB/s"

    # 4. 全球多节点网络测速
    echo -e "\n${BLUE}--- 4. 正在进行 全球多节点网络速度测试 ---${NC}"
    TEST_URLS=(
        "http://cachefly.cachefly.net/100mb.test"          # 美国
        "http://speed.tele2.net/100MB.zip"                 # 欧洲-瑞典
        "http://speedtest.tokyo.linode.com/100MB-tokyo.bin" # 亚洲-日本
    )
    LOCATIONS=("美国-Cachefly" "欧洲-Tele2" "亚洲-Linode")
    
    for i in "${!TEST_URLS[@]}"; do
        echo -e "${YELLOW}正在测试到 ${LOCATIONS[$i]} 的下载速度...${NC}"
        SPEED=$(wget -O /dev/null ${TEST_URLS[$i]} 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {print speed}')
        echo -e "节点: ${LOCATIONS[$i]} \t 速度: ${PURPLE}${SPEED}${NC}"
        log "网络测试: ${LOCATIONS[$i]} - ${SPEED}"
        sleep 1
    done
    
    echo -e "\n${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                        测试报告总结                         ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "CPU 单核性能: ${PURPLE}${CPU_SCORE} events/sec${NC}"
    echo -e "内存传输速度: ${PURPLE}${MEM_SPEED}${NC}"
    echo -e "磁盘随机读写: 读取 ${PURPLE}${IOPS_READ} MiB/s${NC}, 写入 ${PURPLE}${IOPS_WRITE} MiB/s${NC}"
    echo -e "\n${YELLOW}*以上结果请结合您购买的套餐配置进行比对。性能波动大或远低于同类产品平均值，则有超售嫌疑。${NC}"
    log "完成: 全面基准测试"
    press_any_key_to_continue
}


# --- 函数: 超售检测主菜单 ---
oversold_check_menu() {
    while true; do
        clear
        echo -e "${CYAN}==============================================================${NC}"
        echo -e "${PURPLE}                    云服务器性能检测菜单                     ${NC}"
        echo -e "${CYAN}==============================================================${NC}"
        echo -e " ${GREEN}1.${NC} 快速诊断 (检查CPU窃取和磁盘顺序写入)"
        echo -e " ${GREEN}2.${NC} ${YELLOW}全面基准测试 (CPU/内存/磁盘IOPS/全球网络)${NC}"
        echo -e " ${GREEN}3.${NC} 返回主菜单"
        echo -e "${CYAN}==============================================================${NC}"
        read -rp "请输入您的选择 [1-3]: " choice < /dev/tty
        case $choice in
            1)
                quick_oversold_check
                ;;
            2)
                detailed_benchmark
                ;;
            3)
                break
                ;;
            *)
                echo -e "${RED}无效输入，请输入 1 到 3 之间的数字。${NC}"
                sleep 2
                ;;
        esac
    done
}

# --- 函数: 显示主菜单 ---
show_main_menu() {
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}            Linux 系统综合优化工具 v3.0 (增强版)             ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e " ${GREEN}1.${NC} 显示系统信息概览"
    echo -e " ${GREEN}2.${NC} 清理系统垃圾"
    echo -e " ${GREEN}3.${NC} 优化系统内核参数 (网络/内存)"
    echo -e " ${GREEN}4.${NC} ${YELLOW}检测云服务器性能 (超售检测)${NC}"
    echo -e " ${GREEN}5.${NC} 退出脚本"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "操作日志保存在: ${BLUE}${LOG_FILE}${NC}"
}

# --- 主程序逻辑 ---
check_root
touch "$LOG_FILE"
log "脚本启动"

while true; do
    show_main_menu
    read -rp "请输入您的选择 [1-5]: " choice < /dev/tty
    case $choice in
        1)
            # 功能函数已包含 "按Enter继续" 的逻辑, 这里不再需要
            echo "此功能暂未实现"
            press_any_key_to_continue
            ;;
        2)
            echo "此功能暂未实现"
            press_any_key_to_continue
            ;;
        3)
            echo "此功能暂未实现"
            press_any_key_to_continue
            ;;
        4)
            oversold_check_menu
            ;;
        5)
            log "脚本退出"
            echo -e "${GREEN}感谢使用！再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入，请输入 1 到 5 之间的数字。${NC}"
            sleep 2
            ;;
    esac
done
