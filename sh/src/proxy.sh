#!/bin/bash

# ---------------- 系统代理 (环境变量) ----------------

do_proxy() {
    case $1 in
    on)
        proxy_on
        ;;
    off)
        proxy_off
        ;;
    status | "")
        proxy_status
        ;;
    *)
        _red "用法: mihomo proxy on|off|status"
        return 2
        ;;
    esac
}

# 生成代理环境变量文件 (先写临时文件再替换)
write_proxy_file() {
    local port=$1 tmp
    tmp=$(mktemp "$(dirname "$is_proxy_file")/.mihomo-proxy.XXXXXX") || return 1
    if ! cat >"$tmp" <<EOF
# mihomo 系统代理环境变量 - 由 mhs 生成
# 关闭: mihomo proxy off
export http_proxy=http://127.0.0.1:$port
export https_proxy=http://127.0.0.1:$port
export HTTP_PROXY=http://127.0.0.1:$port
export HTTPS_PROXY=http://127.0.0.1:$port
export all_proxy=socks5://127.0.0.1:$port
export ALL_PROXY=socks5://127.0.0.1:$port
export no_proxy=localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,*.lan
export NO_PROXY=\$no_proxy
EOF
    then
        _rm -f "$tmp"
        return 1
    fi
    if ! chmod 644 "$tmp" || ! mv -f "$tmp" "$is_proxy_file"; then
        _rm -f "$tmp"
        return 1
    fi
    return 0
}

# 服务启动/重启后, 按配置端口同步代理文件 (代理未开启时不动)
sync_proxy_port() {
    [[ -f $is_proxy_file ]] || return 0

    local port
    if ! port=$(get_mixed_port); then
        _yellow "系统代理未同步: 配置里没有有效的 mixed-port"
        return 1
    fi

    local cur
    cur=$(proxy_file_port)
    [[ $cur == $port ]] && return 0

    if ! config_check_port_conflicts "$port"; then
        _yellow "系统代理未同步: 端口配置冲突"
        return 1
    fi

    # 服务正在启动/运行中时, 确认端口确实已监听再写
    local state
    state=$(service_state)
    if [[ $state == active || $state == activating || $state == reloading ]]; then
        local i
        for i in {1..20}; do
            port_listened_by_core "$port" && break
            sleep 0.1
        done
        if ! port_listened_by_core "$port"; then
            _yellow "系统代理未同步: 端口 $port 尚未监听"
            return 1
        fi
    fi

    if ! write_proxy_file "$port"; then
        _red "系统代理文件写入失败: $is_proxy_file"
        return 1
    fi
    _yellow "系统代理端口已同步: ${cur:-未知} -> $port"
    _gray "已打开的 shell 需重新加载: . $is_proxy_file"
    return 0
}

proxy_on() {
    local port
    if ! port=$(get_mixed_port); then
        _red "无法确定代理端口: 配置里没有有效的 mixed-port"
        _cyan "请在 $is_conf 中设置, 例如: mixed-port: 7890"
        return 1
    fi

    if ! write_proxy_file "$port"; then
        _red "写入代理文件失败: $is_proxy_file"
        return 1
    fi

    # 让 /root/.bashrc 也生效 (非登录 shell)
    if [[ -f $is_bashrc ]] && ! grep -qF "$is_proxy_file" "$is_bashrc" 2>/dev/null; then
        printf '\n[ -f %s ] && . %s\n' "$is_proxy_file" "$is_proxy_file" >>"$is_bashrc"
    fi

    echo
    _green "系统代理设置已开启"
    echo "  http(s)_proxy  = http://127.0.0.1:$port"
    echo "  all_proxy      = socks5://127.0.0.1:$port"
    echo
    _gray "当前终端立即生效: . $is_proxy_file"
    _gray "已运行的进程不会自动生效, 需要重新读取环境变量或重启"
    if [[ $(service_state) != active ]]; then
        _yellow "注意: mihomo 服务未运行, 当前代理不可用 (先执行: mihomo start)"
    fi
    return 0
}

proxy_off() {
    if [[ -f $is_proxy_file ]]; then
        if ! _rm -f "$is_proxy_file"; then
            _red "删除代理文件失败: $is_proxy_file"
            return 1
        fi
    fi
    if [[ -f $is_bashrc ]]; then
        sed -i "\|$is_proxy_file|d" "$is_bashrc" 2>/dev/null
    fi
    echo
    _green "系统代理设置已关闭"
    _gray "当前终端清理: unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY"
    _gray "或重开终端"
    return 0
}

proxy_status() {
    echo
    if [[ -f $is_proxy_file ]]; then
        echo "系统代理:  已开启"
        _gray "  $is_proxy_file"
        local pfile_port
        pfile_port=$(proxy_file_port)
        echo "  代理端口:  ${pfile_port:-未知}"
    else
        echo "系统代理:  未开启"
    fi
    echo "  当前终端 http_proxy: ${http_proxy:-未设置}"
    if [[ $(service_state) == active ]]; then
        echo "  服务状态:  运行中"
    else
        echo "  服务状态:  $(service_state_text "$(service_state)")"
    fi
    echo
    return 0
}

# ---------------- 连通性测试 ----------------

is_test_url="http://cp.cloudflare.com/generate_204"
is_ip_url="https://api.ipify.org"

_test_204_direct() {
    local out=$1 code
    code=$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 6 "$is_test_url" 2>/dev/null)
    printf '%s\n' "${code:-000}" >"$out"
}

_test_204_proxy() {
    local port=$1 out=$2 code
    code=$(curl -s -o /dev/null -w '%{http_code}' --noproxy '' --proxy "http://127.0.0.1:$port" --max-time 6 "$is_test_url" 2>/dev/null)
    printf '%s\n' "${code:-000}" >"$out"
}

_fetch_ip_direct() {
    local out=$1 ip
    ip=$(curl -s --noproxy '*' --max-time 8 "$is_ip_url" 2>/dev/null)
    printf '%s\n' "$ip" >"$out"
}

_fetch_ip_proxy() {
    local port=$1 out=$2 ip
    ip=$(curl -s --noproxy '' --proxy "http://127.0.0.1:$port" --max-time 8 "$is_ip_url" 2>/dev/null)
    printf '%s\n' "$ip" >"$out"
}

is_ip_text() {
    [[ $1 =~ ^[0-9A-Fa-f:.]{3,45}$ && $1 == *[.:]* ]]
}

do_test() {
    local port
    if ! port=$(get_mixed_port); then
        _red "未配置有效端口 (mixed-port), 无法测试"
        return 1
    fi

    local dir
    dir=$(mktemp -d) || return 1

    _cyan "连通性测试 (直连与代理并行, 最多约 10 秒) ..."
    _test_204_direct "$dir/direct" &
    _test_204_proxy "$port" "$dir/proxy" &
    _fetch_ip_direct "$dir/direct_ip" &
    _fetch_ip_proxy "$port" "$dir/proxy_ip" &
    wait

    echo "──────────────────────────────────────────"
    local code ip
    code=$(cat "$dir/direct" 2>/dev/null)
    if [[ $code == 204 ]]; then
        echo -n "直连   ... "
        _green "OK ($code)"
    else
        echo -n "直连   ... "
        _red "失败 (${code:-超时})"
    fi

    code=$(cat "$dir/proxy" 2>/dev/null)
    if [[ $code == 204 ]]; then
        echo -n "代理   ... "
        _green "OK ($code)"
    else
        echo -n "代理   ... "
        _red "失败 (${code:-超时})"
    fi

    ip=$(cat "$dir/direct_ip" 2>/dev/null)
    if is_ip_text "$ip"; then
        echo "直连IP ... $ip"
    else
        echo "直连IP ... 获取失败"
    fi

    ip=$(cat "$dir/proxy_ip" 2>/dev/null)
    if is_ip_text "$ip"; then
        echo "代理IP ... $ip"
    else
        echo "代理IP ... 获取失败"
    fi
    echo "──────────────────────────────────────────"

    _rm -rf "$dir"
    return 0
}