#!/bin/bash

check_root() {
    [[ $(id -u) != 0 ]] && err "请使用 root 用户运行此脚本."
}

check_installed() {
    [[ ! -f $is_core_bin ]] && err "mihomo 未安装, 请先执行: mihomo install"
}

main() {
    case $1 in
    main)
        show_menu
        ;;
    install)
        check_root
        do_install
        ;;
    update)
        check_root
        do_update
        ;;
    start | stop | restart)
        check_root
        do_service $1
        ;;
    status)
        show_status
        ;;
    log)
        load log.sh
        show_log $2
        ;;
    config | conf)
        check_root
        edit_config
        ;;
    sync)
        # systemd ExecStartPost 调用: 按配置同步系统代理端口
        load proxy.sh
        sync_proxy_port
        ;;
    proxy)
        check_root
        load proxy.sh
        do_proxy $2
        ;;
    geo)
        check_root
        load geo.sh
        download_geo force
        ;;
    test)
        load proxy.sh
        do_test
        ;;
    uninstall)
        check_root
        do_uninstall
        ;;
    version | -v | --version)
        _cyan "$is_core_name $is_core_ver"
        ;;
    help | -h | --help)
        load help.sh
        show_help
        ;;
    *)
        warn "未知命令: $1"
        load help.sh
        show_help
        ;;
    esac
}

# -------------------- 安装 / 更新 / 卸载 --------------------

do_install() {
    _mkdir $is_core_dir/bin $is_core_dir/sh/src

    # 核心
    load download.sh
    if [[ ! -f $is_core_bin ]]; then
        download_core
    else
        _green "核心已安装: $is_core_ver"
    fi

    # GeoIP / GeoSite 数据
    load geo.sh
    download_geo

    # 配置: 不自动生成, 由用户自行编辑
    if [[ -f $is_conf ]]; then
        _green "配置文件已存在: $is_conf"
    else
        _yellow "尚未配置, 请自行编辑配置"
    fi

    # systemd 服务
    load systemd.sh
    install_service

    # 入口命令
    chmod +x $is_sh_dir/$is_core.sh 2>/dev/null
    ln -sf $is_sh_dir/$is_core.sh $is_sh_bin

    # 启动 (无配置/配置不对则不启动, 并提示用户)
    if [[ ! -f $is_conf ]]; then
        systemctl enable $is_core >/dev/null 2>&1
        _green "安装完成, 命令: mihomo"
        _cyan "下一步: mihomo config  编辑配置"
        _cyan "配置完成后: mihomo start"
        return 0
    fi
    if ! precheck_config; then
        systemctl enable $is_core >/dev/null 2>&1
        warn "安装完成, 但配置校验未通过, 服务未启动. 修好后执行: mihomo start"
        return 1
    fi
    systemctl enable $is_core >/dev/null 2>&1
    systemctl reset-failed $is_core 2>/dev/null
    systemctl restart $is_core
    if ! postcheck_service restart; then
        warn "服务未能启动, 请检查配置后执行: mihomo start"
        return 1
    fi

    echo
    _green "安装完成, 命令: mihomo"
    _cyan "编辑配置: mihomo config"
    _cyan "开启系统代理: mihomo proxy on"
}

do_update() {
    check_installed
    load download.sh
    local old_ver=$is_core_ver
    download_core
    local new_ver=$($is_core_bin -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if [[ $old_ver != $new_ver ]]; then
        if systemctl is-active --quiet $is_core; then
            systemctl restart $is_core
        fi
        _green "核心已更新: $old_ver -> $new_ver"
    else
        _green "当前已是最新版本: $new_ver"
    fi
}

do_uninstall() {
    echo -n "确认卸载 mihomo? 输入 yes 继续: "
    read answer
    [[ $answer != yes ]] && {
        _yellow "已取消"
        return 0
    }

    local backup=/root/mihomo-backup-$(date +%Y%m%d-%H%M%S).tar.gz
    if [[ -d $is_core_dir ]]; then
        tar --exclude='mihomo/bin' -czf $backup -C /etc mihomo 2>/dev/null
    fi

    # 停止并移除服务 (两个单元目录都清)
    systemctl stop $is_core 2>/dev/null
    systemctl disable $is_core 2>/dev/null
    _rm -f /etc/systemd/system/$is_core.service
    _rm -f /lib/systemd/system/$is_core.service
    systemctl daemon-reload
    systemctl reset-failed $is_core 2>/dev/null
    pkill -f $is_core_bin 2>/dev/null

    # 关闭系统代理 (清理环境变量文件与 .bashrc)
    load proxy.sh
    proxy_off

    # 删除程序与命令
    _rm -rf $is_core_dir
    _rm -f $is_sh_bin

    _green "卸载完成"
    [[ -f $backup ]] && echo "  配置备份: $backup"
}

# -------------------- 服务 --------------------

# 启动前校验配置: 通过返回 0, 失败打印原因并返回 1
precheck_config() {
    if [[ ! -f $is_conf ]]; then
        _red "配置文件不存在: $is_conf"
        _cyan "请编辑配置: mihomo config"
        return 1
    fi
    local log=/tmp/mihomo-precheck-$$.log
    if ! $is_core_bin -d $is_core_dir -f $is_conf -t >$log 2>&1; then
        _red "配置校验未通过, 已取消启动"
        echo
        grep -vE '^[[:space:]]*$' $log | tail -n 8
        _rm -f $log
        echo
        _cyan "请修改配置: mihomo config   (文件: $is_conf)"
        return 1
    fi
    _rm -f $log
    return 0
}

# 启动后确认结果
postcheck_service() {
    sleep 1
    if systemctl is-active --quiet $is_core; then
        case $1 in
        start) _green "已启动" ;;
        restart) _green "已重启" ;;
        esac
        load proxy.sh 2>/dev/null
        sync_proxy_port
        return 0
    fi
    _red "mihomo 未能启动"
    echo
    echo "最近错误日志:"
    journalctl -u $is_core -n 30 --no-pager 2>/dev/null | grep -iE 'error|fail|invalid|cannot|unable|refused' | tail -n 6
    echo
    _cyan "查看完整日志: mihomo log"
    _cyan "编辑配置:     mihomo config"
    return 1
}

do_service() {
    case $1 in
    start)
        precheck_config || return 1
        systemctl reset-failed $is_core 2>/dev/null
        systemctl start $is_core
        postcheck_service start
        ;;
    stop)
        systemctl stop $is_core && _green "已停止"
        ;;
    restart)
        precheck_config || return 1
        systemctl reset-failed $is_core 2>/dev/null
        systemctl restart $is_core
        postcheck_service restart
        ;;
    esac
}

show_status() {
    echo
    _cyan "mihomo 状态"
    echo "----------------------------------------"
    if systemctl is-active --quiet $is_core; then
        echo -e "运行状态:  $(_green running)"
    else
        echo -e "运行状态:  $(_red_bg stopped)"
    fi
    echo -e "核心版本:  $is_core_ver"
    echo -e "配置文件:  $is_conf"
    echo -e "混合端口:  $(get_mixed_port)"
    echo -e "控制端口:  $(get_conf_value external-controller)"
    if [[ -f $is_proxy_file ]]; then
        local cfg_port=$(get_mixed_port)
        local proxy_port=$(proxy_file_port)
        if [[ $proxy_port && $proxy_port != $cfg_port ]]; then
            echo -e "系统代理:  $(_red 端口不一致: 代理$proxy_port / 配置$cfg_port)"
            _gray "            修复: mihomo proxy on"
        else
            echo -e "系统代理:  $(_green 已开启)"
        fi
    else
        echo -e "系统代理:  $(_gray 未开启)"
    fi
    echo "----------------------------------------"
    systemctl status $is_core --no-pager -l 2>/dev/null | head -n 12
    if ! systemctl is-active --quiet $is_core; then
        echo
        _yellow "服务未运行, 最近日志:"
        journalctl -u $is_core -n 10 --no-pager 2>/dev/null | tail -n 10
        _cyan "编辑配置: mihomo config"
    fi
}

# -------------------- 配置 --------------------

edit_config() {
    check_installed
    if [[ ! -f $is_conf ]]; then
        _mkdir $is_core_dir
        cat >$is_conf <<'EOF'
# mihomo 配置
# 文档: https://wiki.metacubex.one/config/
#
# 常用示例:
# mixed-port: 7890
# allow-lan: false
# external-controller: 127.0.0.1:9090
# secret: "你的密钥"
#
# proxies:
#   - ...
# proxy-groups:
#   - ...
# rules:
#   - MATCH,DIRECT
EOF
        _yellow "配置文件不存在, 已创建空配置: $is_conf"
    fi

    local editor=${EDITOR:-nano}
    command -v $editor >/dev/null 2>&1 || editor=vi
    $editor $is_conf

    # 仍为空 (只有注释) 则不重启
    if [[ ! $(grep -vE '^[[:space:]]*(#|$)' $is_conf) ]]; then
        _yellow "配置仍为空, 未重启服务"
        return 0
    fi

    load config.sh
    test_config_restart
}

# -------------------- 交互菜单 --------------------

proxy_toggle() {
    load proxy.sh
    if [[ -f $is_proxy_file ]]; then
        do_proxy off
    else
        do_proxy on
    fi
}

show_menu() {
    load help.sh
    while :; do
        clear
        show_banner
        echo "  1. 安装/重装        2. 更新核心"
        echo "  3. 启动             4. 停止"
        echo "  5. 重启             6. 状态"
        echo "  7. 编辑配置         8. 系统代理 开/关"
        echo "  9. 连通性测试      10. 查看日志"
        echo " 11. 卸载"
        echo "  0. 退出"
        echo
        read -p "请输入数字: " num
        case $num in
        1)
            do_install
            ;;
        2)
            do_update
            ;;
        3)
            do_service start
            ;;
        4)
            do_service stop
            ;;
        5)
            do_service restart
            ;;
        6)
            show_status
            ;;
        7)
            edit_config
            ;;
        8)
            proxy_toggle
            ;;
        9)
            load proxy.sh
            do_test
            ;;
        10)
            load log.sh
            show_log
            ;;
        11)
            do_uninstall
            ;;
        0 | q | exit)
            exit 0
            ;;
        *)
            _red "无效选项"
            ;;
        esac
        echo
        read -p "按回车键返回菜单..." tmp
    done
}