#!/bin/bash

# mhs 初始化: 只定义变量和函数, 由入口脚本调用 main

# bash fonts colors
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'
red_bg='\e[41m'

# 非终端输出关闭颜色, 避免管道里出现转义码
if [[ ! -t 1 ]]; then
    red= yellow= gray= green= blue= magenta= cyan= none= red_bg=
fi

_red() { printf '%b%s%b\n' "$red" "$*" "$none"; }
_blue() { printf '%b%s%b\n' "$blue" "$*" "$none"; }
_cyan() { printf '%b%s%b\n' "$cyan" "$*" "$none"; }
_green() { printf '%b%s%b\n' "$green" "$*" "$none"; }
_yellow() { printf '%b%s%b\n' "$yellow" "$*" "$none"; }
_magenta() { printf '%b%s%b\n' "$magenta" "$*" "$none"; }
_gray() { printf '%b%s%b\n' "$gray" "$*" "$none"; }
_red_bg() { printf '%b%s%b\n' "$red_bg" "$*" "$none"; }

_rm() { rm -rf "$@"; }
_cp() { cp -rf "$@"; }
_mkdir() { mkdir -p "$@"; }

err() {
    echo
    _red_bg "错误! $*"
    echo
    exit 1
}

warn() {
    echo
    _red_bg "警告! $*"
    echo
}

# 加载模块
load() {
    . "$is_sh_dir/src/$1"
}

# 检查外部命令
need_cmd() {
    local c missing=
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
    done
    if [[ $missing ]]; then
        _red "缺少依赖:$missing"
        _gray "Debian/Ubuntu: apt-get update && apt-get install -y curl tar gzip"
        return 1
    fi
    return 0
}

# 是否可用 PyYAML (用于可靠读取 YAML)
have_pyyaml() {
    command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1
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
is_core_dir=/etc/mihomo
is_core_bin=$is_core_dir/bin/mihomo
is_core_repo=MetaCubeX/mihomo
is_geo_repo=MetaCubeX/meta-rules-dat
is_conf=$is_core_dir/config.yaml
is_sh_bin=/usr/local/bin/mihomo
is_sh_dir=/etc/mihomo/sh
is_proxy_file=/etc/profile.d/mihomo-proxy.sh
is_bashrc=/root/.bashrc

is_systemd=$(type -P systemctl)
if [[ ! $is_systemd || ! -d /run/systemd/system ]]; then
    err "当前系统没有运行中的 systemd, 暂不支持..."
fi

# -------------------- 核心版本与 systemd 状态 --------------------

core_version() {
    if [[ -f $is_core_bin ]]; then
        local v
        v=$($is_core_bin -v 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        printf '%s\n' "${v:-unknown}"
    else
        printf '未安装\n'
    fi
}

service_file_path() {
    local f
    for f in /etc/systemd/system/$is_core.service /lib/systemd/system/$is_core.service; do
        if [[ -f $f ]]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

service_state() {
    if ! service_file_path >/dev/null; then
        printf 'not-installed\n'
        return 0
    fi
    local s
    s=$(systemctl show -p ActiveState --value $is_core 2>/dev/null)
    printf '%s\n' "${s:-unknown}"
}

service_state_text() {
    case $1 in
    not-installed) printf '未安装\n' ;;
    active) printf '运行中\n' ;;
    activating | reloading) printf '启动中\n' ;;
    deactivating) printf '停止中\n' ;;
    failed) printf '启动失败\n' ;;
    inactive | dead) printf '已停止\n' ;;
    *) printf '%s\n' "${1:-未知}" ;;
    esac
}

core_pid() {
    systemctl show -p MainPID --value $is_core 2>/dev/null
}

# 指定端口的 TCP 监听是否为指定进程 (无 ss 时不做断言)
port_listened_by_pid() {
    local port=$1 pid=$2
    [[ $pid && $pid != 0 ]] || return 1
    command -v ss >/dev/null 2>&1 || return 0
    ss -H -tlnp 2>/dev/null | awk -v port=":$port" -v pid="$pid" '
        $4 ~ port "$" && index($0, "pid=" pid ",") { found = 1 }
        END { exit !found }
    '
}

port_listened_by_core() {
    port_listened_by_pid "$1" "$(core_pid)"
}

# -------------------- 配置读取 --------------------

# 读取顶层配置项; 失败返回非 0
config_read_value() {
    local key=$1
    [[ -f $is_conf ]] || return 1

    if have_pyyaml; then
        python3 - "$is_conf" "$key" <<'PY'
import sys
import yaml

path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding='utf-8') as fh:
        data = yaml.safe_load(fh)
except Exception:
    sys.exit(2)
if not isinstance(data, dict) or key not in data:
    sys.exit(3)
value = data[key]
if value is None or isinstance(value, (dict, list)):
    sys.exit(3)
print(value)
PY
        return $?
    fi

    # 无 PyYAML: 只接受简单的顶层 key: value
    local line value
    line=$(grep -E "^[[:space:]]*$key[[:space:]]*:" "$is_conf" 2>/dev/null | tail -n1) || return 1
    [[ $line ]] || return 1
    value=${line#*:}
    value=${value%%#*}
    value=$(printf '%s' "$value" | tr -d "[:space:]'\"")
    [[ $value ]] || return 1
    printf '%s\n' "$value"
}

# 混合代理端口; 未配置/无效/禁用时返回非 0
get_mixed_port() {
    local p
    p=$(config_read_value mixed-port) || return 1
    [[ $p =~ ^[0-9]{1,5}$ ]] || return 1
    ((p >= 1 && p <= 65535)) || return 1
    printf '%s\n' "$p"
}

# 端口冲突预检: mixed-port 与其它监听项重复时明确报错
config_check_port_conflicts() {
    local port=$1 other ctrl
    if other=$(config_read_value port) && [[ $other == "$port" ]]; then
        _red "mixed-port ($port) 与 port 设置重复"
        return 1
    fi
    if other=$(config_read_value socks-port) && [[ $other == "$port" ]]; then
        _red "mixed-port ($port) 与 socks-port 设置重复"
        return 1
    fi
    if ctrl=$(config_read_value external-controller) && [[ ${ctrl##*:} == "$port" ]]; then
        _red "mixed-port ($port) 与外部控制端口重复"
        return 1
    fi
    return 0
}

# 配置是否只有注释/空白
config_is_blank() {
    [[ -f $is_conf ]] || return 0
    ! grep -qE '^[[:space:]]*[^#[:space:]]' "$is_conf"
}

# 代理文件里的端口
proxy_file_port() {
    grep -oE 'http://127\.0\.0\.1:[0-9]+' "$is_proxy_file" 2>/dev/null | head -n1 | grep -oE '[0-9]+$'
}

load core.sh