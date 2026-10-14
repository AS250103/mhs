#!/bin/bash

# ---------------- 交互菜单 ----------------

menu_snapshot() {
    MENU_CORE_VER=$(core_version)
    MENU_SERVICE_STATE=$(service_state)
    MENU_SERVICE_TEXT=$(service_state_text "$MENU_SERVICE_STATE")

    case $MENU_SERVICE_STATE in
    active) MENU_SERVICE_COLOR=$green ;;
    failed | not-installed) MENU_SERVICE_COLOR=$red ;;
    *) MENU_SERVICE_COLOR=$gray ;;
    esac

    if [[ ! -f $is_conf ]]; then
        MENU_CONFIG_TEXT="$is_conf (未创建)"
    elif config_is_blank; then
        MENU_CONFIG_TEXT="$is_conf (待填写)"
    else
        MENU_CONFIG_TEXT="$is_conf"
    fi

    if [[ -f $is_proxy_file ]]; then
        MENU_PROXY_ACTION="关闭系统代理"
        if [[ $MENU_SERVICE_STATE == active ]]; then
            MENU_PROXY_TEXT="已开启"
        else
            MENU_PROXY_TEXT="已开启 (不可用)"
        fi
    else
        MENU_PROXY_ACTION="开启系统代理"
        MENU_PROXY_TEXT="未开启"
    fi

    local port
    if port=$(get_mixed_port); then
        if [[ $MENU_SERVICE_STATE == active ]]; then
            if port_listened_by_core "$port"; then
                MENU_PORT_TEXT="$port (监听中)"
            else
                MENU_PORT_TEXT="$port (未监听)"
            fi
        else
            MENU_PORT_TEXT="$port"
        fi
    else
        MENU_PORT_TEXT="未配置"
    fi
}

menu_term_width() {
    local w=${COLUMNS:-}
    [[ $w =~ ^[0-9]+$ ]] || w=
    if [[ ! $w ]] && command -v tput >/dev/null 2>&1; then
        w=$(tput cols 2>/dev/null)
    fi
    [[ $w =~ ^[0-9]+$ ]] || w=80
    printf '%s\n' "$w"
}

# 按显示宽度补空格 (中文占 2 列)
menu_pad() {
    local s=$1 target=$2 w
    w=$(printf '%s' "$s" | wc -L 2>/dev/null)
    [[ $w =~ ^[0-9]+$ ]] || w=${#s}
    if ((w < target)); then
        printf '%s%*s' "$s" "$((target - w))" ''
    else
        printf '%s' "$s"
    fi
}

show_banner() {
    menu_snapshot

    local w line
    w=$(menu_term_width)
    if [[ $w -ge 64 ]]; then
        line=$(printf '─%.0s' {1..60})
    else
        line=$(printf '─%.0s' {1..40})
    fi

    echo
    _cyan "mihomo-ms  管理脚本 ${is_sh_ver}"
    echo "$line"

    if [[ $w -ge 64 ]]; then
        local v1 v2 v3 v4
        v1=$(menu_pad "$MENU_CORE_VER" 14)
        v2=$(menu_pad "$MENU_SERVICE_TEXT" 12)
        v3=$(menu_pad "$MENU_PROXY_TEXT" 14)
        v4=$(menu_pad "$MENU_PORT_TEXT" 12)
        echo -e " 核心版本  ${green}${v1}${none} 服务状态  ${MENU_SERVICE_COLOR}${v2}${none}"
        echo -e " 系统代理  ${v3} 代理端口  ${v4}"
    else
        echo " 核心版本  $MENU_CORE_VER"
        echo -e " 服务状态  ${MENU_SERVICE_COLOR}${MENU_SERVICE_TEXT}${none}"
        echo " 系统代理  $MENU_PROXY_TEXT"
        echo " 代理端口  $MENU_PORT_TEXT"
    fi
    echo " 配置文件  $MENU_CONFIG_TEXT"
    echo "$line"
}

menu_items() {
    echo " 服务"
    echo "   1  启动                 2  停止"
    echo "   3  重启                 4  详细状态"
    echo
    echo " 配置与代理"
    echo "   5  编辑配置             6  $MENU_PROXY_ACTION"
    echo
    echo " 诊断"
    echo "   7  连通性测试           8  查看日志"
    echo
    echo " 维护"
    echo "   9  安装 / 修复         10  更新核心"
    echo "  11  卸载"
    echo
    echo "   0  退出                 R / 回车  刷新"
}

# 在子 shell 中执行操作, 避免出错时退出整个菜单
menu_action() {
    local act=$1
    shift
    (
        trap 'exit 130' INT
        dispatch "$act" "$@"
    )
    local rc=$?
    if ((rc >= 128)); then
        echo
        _yellow "已取消"
        return 1
    fi
    if ((rc != 0)); then
        echo
        _yellow "操作未完成 (退出码 $rc)"
        return 1
    fi
    return 0
}

show_menu() {
    local interactive=
    [[ -t 0 && -t 1 ]] && interactive=1

    local choice rc
    trap 'echo; _yellow "已取消当前操作"' INT
    while :; do
        if [[ $interactive ]]; then
            clear
        fi
        show_banner
        echo
        menu_items
        echo

        read -r -p "请选择: " choice
        rc=$?
        if ((rc > 128)); then
            continue
        elif ((rc != 0)); then
            echo
            return 0
        fi

        case $choice in
        1) menu_action start ;;
        2) menu_action stop ;;
        3) menu_action restart ;;
        4) menu_action status ;;
        5) menu_action config ;;
        6)
            if [[ -f $is_proxy_file ]]; then
                menu_action proxy off
            else
                menu_action proxy on
            fi
            ;;
        7) menu_action test ;;
        8) menu_action log ;;
        9) menu_action install ;;
        10) menu_action update ;;
        11) menu_action uninstall && return 0 ;;
        0 | q | Q | exit) return 0 ;;
        r | R | "") continue ;;
        *) _red "无效选项: $choice" ;;
        esac

        echo
        read -r -p "按回车返回菜单..." _
        rc=$?
        if ((rc > 128)); then
            continue
        elif ((rc != 0)); then
            echo
            return 0
        fi
    done
}