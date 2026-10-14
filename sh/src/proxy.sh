#!/bin/bash

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
        err "用法: mihomo proxy on|off|status"
        ;;
    esac
}

# 生成代理环境变量文件
write_proxy_file() {
    local port=$1
    local proxy="http://127.0.0.1:$port"
    cat >$is_proxy_file <<EOF
# mihomo 系统代理环境变量 - 由 mihomo-ms 生成
# 关闭: mihomo proxy off
export http_proxy=$proxy
export https_proxy=$proxy
export HTTP_PROXY=$proxy
export HTTPS_PROXY=$proxy
export all_proxy=socks5://127.0.0.1:$port
export ALL_PROXY=socks5://127.0.0.1:$port
export no_proxy=localhost,127.0.0.1,::1,0.0.0.0,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,*.lan
export NO_PROXY=\$no_proxy
EOF
    chmod 644 $is_proxy_file
}

# 服务启动/重启后, 按配置里的端口同步代理文件 (仅当代理已开启)
sync_proxy_port() {
    [[ ! -f $is_proxy_file ]] && return 0
    local port=$(get_mixed_port)
    local cur=$(proxy_file_port)
    [[ $cur == $port ]] && return 0
    write_proxy_file $port
    _yellow "系统代理端口已同步: ${cur:-未知} -> $port"
    _gray "已打开的 shell 需重新加载: . $is_proxy_file"
}

# 开启系统代理 (写入环境变量)
proxy_on() {
    local port=$(get_mixed_port)
    local proxy="http://127.0.0.1:$port"

    if ! systemctl is-active --quiet $is_core; then
        _yellow "注意: mihomo 服务未运行, 代理将不可用 (先执行: mihomo start)"
    fi

    write_proxy_file $port

    # 让 /root/.bashrc 也生效 (非登录 shell)
    if ! grep -q "$is_proxy_file" $is_bashrc 2>/dev/null; then
        printf '\n[ -f %s ] && . %s\n' "$is_proxy_file" "$is_proxy_file" >>$is_bashrc
    fi

    # 当前会话立即生效
    export http_proxy="$proxy" https_proxy="$proxy" HTTP_PROXY="$proxy" HTTPS_PROXY="$proxy"
    export all_proxy="socks5://127.0.0.1:$port" ALL_PROXY="socks5://127.0.0.1:$port"
    export no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,*.local,*.lan"
    export NO_PROXY="$no_proxy"

    echo
    _green "系统代理已开启"
    echo "  http(s)_proxy  = $proxy"
    echo "  all_proxy      = socks5://127.0.0.1:$port"
    echo "  no_proxy       = $no_proxy"
    echo
    _yellow "当前已运行的进程不会自动生效, 请重开终端或重启对应项目."
    echo "  验证: mihomo test"
}

# 关闭系统代理
proxy_off() {
    _rm -f $is_proxy_file
    if [[ -f $is_bashrc ]]; then
        _sed "\|$is_proxy_file|d" $is_bashrc 2>/dev/null
    fi
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    echo
    _green "系统代理已关闭"
    echo "  请重开终端使新会话不再携带代理变量."
}

proxy_status() {
    echo
    if [[ -f $is_proxy_file ]]; then
        echo -e "系统代理: $(_green 已开启)"
        _gray "  $is_proxy_file"
    else
        echo -e "系统代理: $(_gray 未开启)"
    fi
    echo "  当前会话 http_proxy: ${http_proxy:-未设置}"
    echo "  mihomo 混合端口:    $(get_mixed_port)"
    if systemctl is-active --quiet $is_core 2>/dev/null; then
        echo -e "  mihomo 服务:        $(_green running)"
    else
        echo -e "  mihomo 服务:        $(_red_bg stopped)"
    fi
    echo
}

# 连通性测试
do_test() {
    local port=$(get_mixed_port)
    local url="http://cp.cloudflare.com/generate_204"

    echo
    _cyan "连通性测试"
    echo "----------------------------------------"
    echo -n "直连   ... "
    local direct_code=$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 8 "$url" 2>/dev/null)
    [[ $direct_code == 204 ]] && _green "OK ($direct_code)" || _red "失败 ($direct_code)"

    echo -n "代理   ... "
    local proxy_code=$(curl -s -o /dev/null -w '%{http_code}' --proxy "http://127.0.0.1:$port" --max-time 8 "$url" 2>/dev/null)
    [[ $proxy_code == 204 ]] && _green "OK ($proxy_code)" || _red "失败 ($proxy_code)"

    echo -n "出口IP ... "
    local ip=$(curl -s --proxy "http://127.0.0.1:$port" --max-time 10 https://api.ip.sb/ip 2>/dev/null || curl -s --proxy "http://127.0.0.1:$port" --max-time 10 https://ifconfig.me 2>/dev/null)
    if [[ $ip ]]; then
        echo "$(_cyan $ip)"
    else
        _red "获取失败"
    fi
    echo -n "直连IP ... "
    local dip=$(curl -s --noproxy '*' --max-time 10 https://api.ip.sb/ip 2>/dev/null || curl -s --noproxy '*' --max-time 10 https://ifconfig.me 2>/dev/null)
    [[ $dip ]] && echo "$dip" || _red "获取失败"
    echo "----------------------------------------"
}