#!/bin/bash

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
# 说明: 记录操作信息到日志文件,并在屏幕上显示。
log() {
    echo -e "$(date "+%Y-%m-%d %H:%M:%S") - $1" | tee -a $LOG_FILE
}

# --- 函数: 检查Root权限 ---
# 说明: 确保脚本由root用户执行,否则退出。
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须以 root 用户权限运行！${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo bash $0'${NC}"
        exit 1
    fi
}

# --- 函数: 显示系统信息 ---
# 说明: 展示服务器的硬件和软件配置概览。
show_system_info() {
    log "执行: 显示系统信息"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                      系统信息概览                           ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    
    # 操作系统信息
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "${GREEN}操作系统    :${NC} $PRETTY_NAME"
    elif [ -f /etc/redhat-release ]; then
        echo -e "${GREEN}操作系统    :${NC} $(cat /etc/redhat-release)"
    fi
    
    echo -e "${GREEN}内核版本    :${NC} $(uname -r)"
    echo -e "${GREEN}系统架构    :${NC} $(uname -m)"
    echo -e "${GREEN}主机名      :${NC} $(hostname)"
    
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    
    # CPU 信息
    echo -e "${GREEN}CPU 型号     :${NC} $(lscpu | grep 'Model name' | awk -F: '{print $2}' | sed 's/^[ \t]*//')"
    echo -e "${GREEN}CPU 核心数   :${NC} $(lscpu | grep '^CPU(s):' | awk '{print $2}')"
    echo -e "${GREEN}系统负载    :${NC} $(uptime | awk -F'load average:' '{print $2}')"

    echo -e "${CYAN}--------------------------------------------------------------${NC}"

    # 内存信息
    free -h | grep 'Mem:' | awk '{print "\033[0;32m内存        :\033[0m 总计 " $2 ", 已用 " $3 ", 可用 " $7}'
    free -h | grep 'Swap:' | awk '{print "\033[0;32m交换空间    :\033[0m 总计 " $2 ", 已用 " $3}'
    
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
    
    # 磁盘信息
    echo -e "${GREEN}磁盘使用情况:${NC}"
    df -hT | grep -E '^/dev/' | sed 's/Mounted on/挂载点/' | sed 's/Use%/使用率/' | sed 's/Filesystem/文件系统/' | sed 's/Size/大小/' | sed 's/Used/已用/' | sed 's/Avail/可用/' | sed 's/Type/类型/'
    
    echo -e "${CYAN}==============================================================${NC}"
    log "完成: 显示系统信息"
    echo -e "\n按 [Enter] 键返回主菜单..."
    read -r
}

# --- 函数: 清理系统垃圾 ---
# 说明: 清理软件包缓存、旧日志和临时文件。
clean_system() {
    log "执行: 清理系统垃圾"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                        开始系统清理                           ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    
    echo -e "${YELLOW}正在清理包管理器缓存...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get clean -y
        log "APT缓存已清理"
    elif command -v yum &> /dev/null; then
        yum clean all
        log "YUM缓存已清理"
    elif command -v dnf &> /dev/null; then
        dnf clean all
        log "DNF缓存已清理"
    else
        echo -e "${RED}未知的包管理器,跳过缓存清理。${NC}"
        log "警告: 未知的包管理器,跳过缓存清理"
    fi
    echo -e "${GREEN}包管理器缓存清理完成！${NC}\n"
    sleep 1

    echo -e "${YELLOW}正在清理旧的日志文件... (仅清空内容,不删除文件)${NC}"
    find /var/log -type f -name "*.log" -exec truncate --size 0 {} \;
    log "旧日志文件已清空"
    echo -e "${GREEN}旧日志文件清理完成！${NC}\n"
    sleep 1

    echo -e "${YELLOW}正在清理 /tmp 目录下的临时文件...${NC}"
    rm -rf /tmp/*
    log "/tmp目录已清理"
    echo -e "${GREEN}/tmp 目录清理完成！${NC}\n"

    echo -e "${CYAN}==============================================================${NC}"
    log "完成: 清理系统垃圾"
    echo -e "\n按 [Enter] 键返回主菜单..."
    read -r
}

# --- 函数: 优化内核参数 ---
# 说明: 修改sysctl配置,优化网络、内存等性能。
optimize_kernel() {
    log "执行: 优化内核参数"
    SYSCTL_CONF="/etc/sysctl.conf"
    SYSCTL_BAK="/etc/sysctl.conf.bak.$(date +%F_%T)"

    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                       开始内核参数优化                         ${NC}"
    echo -e "${CYAN}==============================================================${NC}"

    echo -e "${YELLOW}警告：此操作将修改系统内核参数。${NC}"
    echo -e "${YELLOW}为安全起见,已将原始配置备份至: $SYSCTL_BAK${NC}"
    cp "$SYSCTL_CONF" "$SYSCTL_BAK"
    log "备份 sysctl.conf 至 $SYSCTL_BAK"
    sleep 2

    # 创建一个新的配置文件,避免直接修改主文件,方便管理
    cat > /etc/sysctl.d/99-custom-optimizer.conf << EOF
# 由系统优化脚本于 $(date) 自动添加
#
# 网络性能优化 (开启BBR)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0

# 内存管理优化
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# 文件句柄数限制
fs.file-max = 655350
fs.nr_open = 655350
EOF
    
    log "写入新的sysctl配置到 /etc/sysctl.d/99-custom-optimizer.conf"
    echo -e "${GREEN}新的内核配置已写入 /etc/sysctl.d/99-custom-optimizer.conf 文件。${NC}"
    
    echo -e "\n${YELLOW}正在应用新的内核参数...${NC}"
    sysctl --system
    log "已使用 'sysctl --system' 应用新配置"
    
    echo -e "\n${GREEN}内核参数优化完成！${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    log "完成: 优化内核参数"
    echo -e "\n按 [Enter] 键返回主菜单..."
    read -r
}


# --- 函数: 检测服务器超售 ---
# 说明: 通过CPU窃取时间和磁盘I/O两大关键指标,判断云服务器是否存在资源超售。
check_oversold() {
    log "执行: 检测服务器超售"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                    云服务器超售情况检测                       ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${YELLOW}免责声明：此检测基于常用性能指标,结果仅供参考。${NC}\n"
    sleep 2

    # 1. CPU窃取时间检测
    echo -e "${BLUE}--- 1. 正在检测 CPU 窃取时间 (Steal Time) ---${NC}"
    echo -e "CPU窃取时间(st)是宿主机分配给其他虚拟机而从本机“偷走”的CPU时间。"
    echo -e "一个持续高于 5% 的值通常表明宿主机资源紧张,有超售嫌疑。\n"
    
    if ! command -v vmstat &> /dev/null; then
        echo -e "${RED}vmstat 命令未找到,无法检测CPU窃取时间。请安装 procps 包。${NC}"
        log "错误: vmstat命令未找到"
    else
        CPU_STEAL=$(vmstat 1 2 | tail -1 | awk '{print $NF}')
        echo -e "${YELLOW}正在采样CPU状态...${NC}"
        sleep 1
        echo -e "当前 CPU 窃取时间: ${PURPLE}${CPU_STEAL}%${NC}"
        if (( $(echo "$CPU_STEAL > 5" | bc -l) )); then
            echo -e "${RED}警告：CPU 窃取时间较高 (${CPU_STEAL}%),这可能是服务器超售的一个强烈信号！${NC}"
            log "检测到高CPU窃取时间: ${CPU_STEAL}%"
        else
            echo -e "${GREEN}CPU 窃取时间正常 (${CPU_STEAL}%),宿主机CPU资源目前看起来充足。${NC}"
            log "CPU窃取时间正常: ${CPU_STEAL}%"
        fi
    fi
    
    echo -e "\n${CYAN}--------------------------------------------------------------${NC}\n"
    sleep 2

    # 2. 磁盘I/O性能检测
    echo -e "${BLUE}--- 2. 正在检测磁盘 I/O 性能 ---${NC}"
    echo -e "磁盘性能差是超售的另一个常见迹象,因为多个虚拟机共享物理磁盘。"
    echo -e "将使用dd命令向当前目录写入一个 256MB 的测试文件...\n"
    
    IO_TEST_FILE="test_io_optimizer.tmp"
    IO_RESULT=$(dd if=/dev/zero of=$IO_TEST_FILE bs=64k count=4k oflag=dsync 2>&1)
    IO_SPEED=$(echo $IO_RESULT | awk -F', ' '{print $3}')
    
    # 清理测试文件
    rm -f $IO_TEST_FILE
    
    echo -e "磁盘写入速度: ${PURPLE}${IO_SPEED}${NC}"
    
    # 从速度中提取数值和单位
    IO_SPEED_VALUE=$(echo $IO_SPEED | sed 's/ .*//')
    IO_SPEED_UNIT=$(echo $IO_SPEED | sed 's/.* //')

    # 统一转换为 MB/s 以便比较
    if [[ "$IO_SPEED_UNIT" == "GB/s" ]]; then
        IO_SPEED_MBPS=$(echo "$IO_SPEED_VALUE * 1024" | bc)
    elif [[ "$IO_SPEED_UNIT" == "kB/s" ]]; then
        IO_SPEED_MBPS=$(echo "$IO_SPEED_VALUE / 1024" | bc)
    else
        IO_SPEED_MBPS=$IO_SPEED_VALUE
    fi

    if (( $(echo "$IO_SPEED_MBPS < 50" | bc -l) )); then
        echo -e "${RED}警告：磁盘 I/O 性能较差 (${IO_SPEED})。这可能是由于存储资源共享过度导致的。${NC}"
        log "检测到低磁盘I/O性能: ${IO_SPEED}"
    elif (( $(echo "$IO_SPEED_MBPS < 150" | bc -l) )); then
        echo -e "${YELLOW}注意：磁盘 I/O 性能一般 (${IO_SPEED})。对于某些应用可能成为瓶颈。${NC}"
        log "检测到一般磁盘I/O性能: ${IO_SPEED}"
    else
        echo -e "${GREEN}磁盘 I/O 性能良好 (${IO_SPEED})。${NC}"
        log "磁盘I/O性能良好: ${IO_SPEED}"
    fi

    echo -e "\n${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}                        检测结论                           ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    if (( $(echo "$CPU_STEAL > 5" | bc -l) )) || (( $(echo "$IO_SPEED_MBPS < 50" | bc -l) )); then
        echo -e "${RED}综合来看,您的服务器很可能存在超售情况。建议进行更全面的基准测试或联系服务商。${NC}"
        log "结论: 可能存在超售"
    else
        echo -e "${GREEN}综合来看,您的服务器性能指标表现正常,未见明显的超售迹象。${NC}"
        log "结论: 未见明显超售迹象"
    fi
    echo -e "${CYAN}==============================================================${NC}"
    
    log "完成: 检测服务器超售"
    echo -e "\n按 [Enter] 键返回主菜单..."
    read -r
}

# --- 函数: 一键全自动模式 ---
# 说明: 自动按顺序执行清理、优化和检测任务。
full_auto_mode() {
    log "执行: 一键全自动优化"
    echo -e "${YELLOW}即将开始全自动优化... 将依次执行：系统清理 -> 内核优化 -> 超售检测${NC}"
    sleep 3
    clean_system
    optimize_kernel
    check_oversold
    echo -e "${GREEN}所有自动任务已执行完毕！${NC}"
    log "完成: 一键全自动优化"
    echo -e "\n按 [Enter] 键返回主菜单..."
    read -r
}


# --- 函数: 显示主菜单 ---
# 说明: 脚本的主交互界面。
show_menu() {
    clear
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "${PURPLE}              Linux 系统综合优化工具                       ${NC}"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e " ${GREEN}1.${NC} 显示系统信息概览"
    echo -e " ${GREEN}2.${NC} 清理系统垃圾"
    echo -e " ${GREEN}3.${NC} 优化系统内核参数 (网络/内存)"
    echo -e " ${GREEN}4.${NC} ${YELLOW}检测云服务器是否超售${NC}"
    echo -e " ${GREEN}5.${NC} ${RED}一键全自动优化 (执行2,3,4)${NC}"
    echo -e " ${GREEN}6.${NC} 退出脚本"
    echo -e "${CYAN}==============================================================${NC}"
    echo -e "操作日志保存在: ${BLUE}${LOG_FILE}${NC}"
}

# --- 主程序逻辑 ---
# 说明: 脚本的入口和主循环。
check_root
touch $LOG_FILE
log "脚本启动"

while true; do
    show_menu
    read -rp "请输入您的选择 [1-6]: " choice
    case $choice in
        1)
            show_system_info
            ;;
        2)
            clean_system
            ;;
        3)
            optimize_kernel
            ;;
        4)
            check_oversold
            ;;
        5)
            full_auto_mode
            ;;
        6)
            log "脚本退出"
            echo -e "${GREEN}感谢使用！再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入,请输入 1 到 6 之间的数字。${NC}"
            sleep 2
            ;;
    esac
done
