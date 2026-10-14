#!/bin/bash

# 命令分发: 菜单和命令行共用同一入口, 统一权限检查与返回码

check_root() {
    if [[ $(id -u) != 0 ]]; then
        _red "请使用 root 用户运行此脚本."
        return 1
    fi
    return 0
}

check_installed() {
    if [[ ! -f $is_core_bin ]]; then
        _red "mihomo 未安装, 请先执行: mihomo install"
        return 1
    fi
    return 0
}

dispatch() {
    local cmd=$1
    shift
    case $cmd in
    install)
        check_root || return 1
        load service.sh
        do_install "$@"
        ;;
    update)
        check_root || return 1
        load service.sh
        do_update "$@"
        ;;
    start | stop | restart)
        check_root || return 1
        load service.sh
        do_service "$cmd" "$@"
        ;;
    status)
        load service.sh
        show_status "$@"
        ;;
    log)
        load service.sh
        show_log "$@"
        ;;
    config | conf)
        check_root || return 1
        load config.sh
        edit_config "$@"
        ;;
    proxy)
        check_root || return 1
        load proxy.sh
        do_proxy "$@"
        ;;
    sync)
        load proxy.sh
        sync_proxy_port
        ;;
    geo)
        check_root || return 1
        load download.sh
        download_geo force
        ;;
    test)
        load proxy.sh
        do_test "$@"
        ;;
    uninstall)
        check_root || return 1
        load service.sh
        do_uninstall "$@"
        ;;
    version | -v | --version)
        _cyan "$is_core_name $(core_version)"
        ;;
    help | -h | --help)
        load help.sh
        show_help
        ;;
    *)
        warn "未知命令: $cmd"
        load help.sh
        show_help
        return 2
        ;;
    esac
}

main() {
    if [[ $# == 0 ]]; then
        load menu.sh
        show_menu
        return $?
    fi
    dispatch "$@"
}