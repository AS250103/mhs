#!/bin/bash

# ---------------- 安装 / 更新 / 卸载 ----------------

install_service() {
    local service_file=/etc/systemd/system/$is_core.service
    [[ -d /etc/systemd/system ]] || service_file=/lib/systemd/system/$is_core.service

    _cyan "写入 systemd 服务: $service_file"
    if ! cat >"$service_file" <<EOF
[Unit]
Description=$is_core_name Service
Documentation=https://wiki.metacubex.one/
After=network.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=3
ExecStartPre=$is_core_bin -d $is_core_dir -f $is_conf -t
ExecStart=$is_core_bin -d $is_core_dir -f $is_conf
ExecStartPost=-$is_sh_dir/$is_core.sh sync
LimitNPROC=10000
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF
    then
        _red "写入服务文件失败: $service_file"
        return 1
    fi

    if ! systemctl daemon-reload; then
        _red "systemctl daemon-reload 失败"
        return 1
    fi
    _green "服务已写入"
}

do_install() {
    need_cmd curl tar gzip || return 1
    _mkdir $is_core_dir/bin $is_core_dir/sh/src || return 1

    load download.sh
    if [[ ! -f $is_core_bin ]]; then
        download_core || return 1
    else
        _green "核心已安装: $(core_version)"
    fi

    download_geo
    if [[ -f $is_conf ]]; then
        _green "配置文件已存在: $is_conf"
    else
        _yellow "尚未配置, 编辑配置: mihomo config"
    fi

    install_service || return 1

    chmod +x $is_sh_dir/$is_core.sh 2>/dev/null
    if ! ln -sf $is_sh_dir/$is_core.sh $is_sh_bin; then
        _red "创建命令软链失败: $is_sh_bin"
        return 1
    fi
    systemctl enable $is_core >/dev/null 2>&1

    if [[ ! -f $is_conf ]] || config_is_blank; then
        echo
        _green "安装完成, 命令: mihomo"
        _cyan "下一步: mihomo config  编辑配置"
        _cyan "配置完成后: mihomo start"
        return 0
    fi

    if ! apply_config; then
        warn "安装完成, 但服务未启动; 修复配置后执行: mihomo start"
        return 1
    fi
    echo
    _green "安装完成, 命令: mihomo"
    _cyan "编辑配置: mihomo config"
    _cyan "开启系统代理: mihomo proxy on"
    return 0
}

do_update() {
    check_installed || return 1
    load download.sh

    local old new
    old=$(core_version)
    download_core || return 1
    new=$(core_version)

    if [[ $old != $new && $(service_state) == active ]]; then
        do_service restart || return 1
    fi
    return 0
}

do_uninstall() {
    echo -n "确认卸载 mihomo? 输入 yes 继续: "
    read -r answer
    if [[ $answer != yes ]]; then
        _yellow "已取消"
        return 1
    fi

    local backup=/root/mihomo-backup-$(date +%Y%m%d-%H%M%S).tar.gz
    if [[ -d $is_core_dir ]]; then
        _cyan "备份配置到 $backup ..."
        if ! tar --exclude='mihomo/bin' -czf "$backup" -C /etc mihomo 2>/dev/null; then
            _red "配置备份失败, 已取消卸载"
            _rm -f "$backup"
            return 2
        fi
        if ! tar -tzf "$backup" >/dev/null 2>&1; then
            _red "备份文件校验失败, 已取消卸载"
            _rm -f "$backup"
            return 2
        fi
        _green "备份完成"
    fi

    systemctl stop $is_core 2>/dev/null
    systemctl disable $is_core 2>/dev/null
    _rm -f /etc/systemd/system/$is_core.service
    _rm -f /lib/systemd/system/$is_core.service
    systemctl daemon-reload 2>/dev/null
    systemctl reset-failed $is_core 2>/dev/null
    pkill -f "$is_core_bin" 2>/dev/null

    load proxy.sh
    proxy_off

    _rm -rf $is_core_dir
    _rm -f $is_sh_bin

    _green "卸载完成"
    [[ -f $backup ]] && echo "  配置备份: $backup"
    return 0
}

# ---------------- 服务 ----------------

wait_service_active() {
    local i state
    for i in {1..30}; do
        state=$(systemctl show -p ActiveState --value $is_core 2>/dev/null)
        [[ $state == active ]] && return 0
        [[ $state == failed ]] && return 1
        sleep 0.1
    done
    return 1
}

check_expected_port() {
    local port=$1
    local i
    for i in {1..30}; do
        port_listened_by_core "$port" && return 0
        sleep 0.1
    done
    return 1
}

show_recent_log() {
    echo
    echo "最近相关日志:"
    journalctl -u $is_core -n 40 --no-pager 2>/dev/null | grep -iE 'error|fail|invalid|cannot|unable|refused|already in use' | tail -n 6
    echo
    _cyan "完整日志: mihomo log"
    _cyan "编辑配置: mihomo config"
}

# 校验配置 -> 重启 -> 确认运行 -> 确认监听 -> 同步代理
apply_config() {
    load config.sh

    if [[ ! -f $is_conf ]]; then
        _red "配置文件不存在: $is_conf"
        _cyan "请先编辑配置: mihomo config"
        return 1
    fi
    if config_is_blank; then
        _yellow "配置为空 (只有注释), 未启动服务"
        return 1
    fi
    if ! config_test; then
        _cyan "请修改配置: mihomo config"
        return 1
    fi

    local port
    if port=$(get_mixed_port); then
        if ! config_check_port_conflicts "$port"; then
            _cyan "请修改配置: mihomo config"
            return 1
        fi
    fi

    systemctl reset-failed $is_core 2>/dev/null
    if ! systemctl restart $is_core; then
        _red "服务重启失败"
        show_recent_log
        return 1
    fi
    if ! wait_service_active; then
        _red "服务未能进入运行状态"
        show_recent_log
        return 1
    fi
    if port=$(get_mixed_port); then
        if ! check_expected_port "$port"; then
            _red "服务已运行, 但未监听预期的代理端口"
            _gray "常见原因: 端口被其他程序占用, 或配置里的 mixed-port 不可用"
            show_recent_log
            return 1
        fi
    fi

    load proxy.sh
    if ! sync_proxy_port; then
        _yellow "服务已启动, 但系统代理设置同步失败"
        return 1
    fi
    return 0
}

do_service() {
    local act=$1
    case $act in
    stop)
        if ! systemctl stop $is_core; then
            _red "停止失败"
            return 1
        fi
        _green "已停止"
        return 0
        ;;
    start | restart)
        apply_config || return 1
        if [[ $act == start ]]; then
            _green "已启动"
        else
            _green "已重启"
        fi
        return 0
        ;;
    *)
        _red "用法: mihomo start|stop|restart"
        return 2
        ;;
    esac
}

show_config_state() {
    if [[ ! -f $is_conf ]]; then
        printf '未创建\n'
    elif config_is_blank; then
        printf '待填写\n'
    else
        printf '已存在\n'
    fi
}

show_port_line() {
    local port
    if ! port=$(get_mixed_port); then
        echo "混合端口:  未配置 (需在配置里设置 mixed-port)"
        return
    fi
    if ! config_check_port_conflicts "$port" >/dev/null 2>&1; then
        echo "混合端口:  $port (端口冲突, 未生效)"
        return
    fi
    if [[ $(service_state) == active ]]; then
        if port_listened_by_core "$port"; then
            echo "混合端口:  $port (监听中)"
        else
            echo "混合端口:  $port (未监听)"
        fi
    else
        echo "混合端口:  $port"
    fi
}

show_proxy_line() {
    if [[ ! -f $is_proxy_file ]]; then
        echo "系统代理:  未开启"
        return
    fi

    local cfg_port pfile_port
    pfile_port=$(proxy_file_port)
    if cfg_port=$(get_mixed_port); then
        if [[ $pfile_port && $pfile_port != $cfg_port ]]; then
            echo "系统代理:  已开启, 端口待同步 (代理 $pfile_port / 配置 $cfg_port)"
            echo "           修复: mihomo restart  或  mihomo proxy on"
            return
        fi
    fi
    if [[ $(service_state) != active ]]; then
        echo "系统代理:  已开启 (服务未运行, 当前不可用)"
    else
        echo "系统代理:  已开启 (127.0.0.1:${pfile_port:-未知})"
    fi
}

show_status() {
    echo
    _cyan "mihomo 状态"
    echo "──────────────────────────────────────────"
    echo "运行状态:  $(service_state_text "$(service_state)")"
    echo "核心版本:  $(core_version)"
    echo "配置文件:  $is_conf ($(show_config_state))"
    show_port_line
    show_proxy_line
    local ctrl
    if ctrl=$(config_read_value external-controller); then
        echo "控制接口:  $ctrl"
    else
        echo "控制接口:  未配置"
    fi
    echo "──────────────────────────────────────────"
    systemctl status $is_core --no-pager -l 2>/dev/null | head -n 12
    if [[ $(service_state) != active ]]; then
        show_recent_log
    fi
}

show_log() {
    local arg=${1:-}
    if [[ $arg == -f || $arg == follow ]]; then
        journalctl -u $is_core -f
    else
        journalctl -u $is_core -n 100 --no-pager
    fi
}