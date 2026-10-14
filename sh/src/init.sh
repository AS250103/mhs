#!/bin/bash

author=mihomo-ms
# mihomo 一键管理脚本 (自用)

# bash fonts colors
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

_red() { echo -e "${red}$*${none}"; }
_blue() { echo -e "${blue}$*${none}"; }
_cyan() { echo -e "${cyan}$*${none}"; }
_green() { echo -e "${green}$*${none}"; }
_yellow() { echo -e "${yellow}$*${none}"; }
_magenta() { echo -e "${magenta}$*${none}"; }
_gray() { echo -e "${gray}$*${none}"; }
_red_bg() { echo -e "\e[41m$*${none}"; }

_rm() { rm -rf "$@"; }
_cp() { cp -rf "$@"; }
_sed() { sed -i "$@"; }
_mkdir() { mkdir -p "$@"; }

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() {
    echo
    echo -e "$is_err $*"
    echo
    [[ ! $is_dont_auto_exit ]] && exit 1
}

warn() {
    echo
    echo -e "$is_warn $*"
    echo
}

# load bash script.
load() {
    . $is_sh_dir/src/$1
}

# random secret
_random() {
    if [[ $(type -P openssl) ]]; then
        openssl rand -hex 8
    else
        head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# 64-bit only
case $(uname -m) in
amd64 | x86_64)
    is_arch=amd64
    ;;
*aarch64* | *armv8*)
    is_arch=arm64
    ;;
*)
    err "此脚本仅支持 64 位系统..."
    ;;
esac

is_core=mihomo
is_core_name=mihomo
is_core_dir=/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=MetaCubeX/$is_core
is_geo_repo=MetaCubeX/meta-rules-dat
is_conf=$is_core_dir/config.yaml
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_proxy_file=/etc/profile.d/mihomo-proxy.sh
is_bashrc=/root/.bashrc
is_default_mixed_port=7890
is_default_ctrl_port=9090

is_systemd=$(type -P systemctl)
if [[ ! $is_systemd ]]; then
    err "当前系统没有 systemd, 暂不支持..."
fi

# 解析核心版本 (mihomo -v 输出: Mihomo Meta vX.Y.Z ...)
extract_core_ver() {
    $is_core_bin -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

# core ver
if [[ -f $is_core_bin ]]; then
    is_core_ver=$(extract_core_ver)
    [[ ! $is_core_ver ]] && is_core_ver=unknown
else
    is_core_ver=未安装
fi

# 刷新运行状态 (菜单/状态显示时实时调用)
refresh_core_status() {
    if pgrep -f $is_core_bin >/dev/null 2>&1; then
        is_core_status=$(_green running)
        is_core_stop=
    else
        is_core_status=$(_red_bg stopped)
        is_core_stop=1
    fi
}

refresh_core_status

# 读取配置项 (get_conf_value key)
get_conf_value() {
    local key=$1
    [[ ! -f $is_conf ]] && return
    grep -E "^$key:" $is_conf 2>/dev/null | head -n1 | sed -E "s/^$key:[[:space:]]*//; s/^['\"]//; s/['\"]$//"
}

# 混合代理端口
get_mixed_port() {
    local p
    p=$(get_conf_value mixed-port)
    echo "${p:-$is_default_mixed_port}"
}

# 代理文件里的端口
proxy_file_port() {
    grep -oE 'http://127\.0\.0\.1:[0-9]+' $is_proxy_file 2>/dev/null | head -n1 | grep -oE '[0-9]+$'
}


load core.sh
[[ ! $args ]] && args=main
main $args