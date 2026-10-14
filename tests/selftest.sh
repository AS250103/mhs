#!/bin/bash

# mihomo-ms 隔离自测: 全部在临时目录/模拟命令中执行, 不触碰真实服务与配置
# 用法: bash tests/selftest.sh

project_dir=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/mihomo-ms-selftest.XXXXXX) || exit 1
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
check() { # desc expected actual
    if [[ $2 == "$3" ]]; then
        ok "$1"
    else
        no "$1 (期望 [$2], 实际 [$3])"
    fi
}
not_contains() { # file pattern desc
    if grep -qE "$2" "$1" 2>/dev/null; then
        no "$3 (不应出现: $2)"
    else
        ok "$3"
    fi
}

. "$project_dir/sh/src/init.sh"

# 测试中始终从项目目录加载模块, 并覆盖 init 的方法
load() { . "$project_dir/sh/src/$1"; }
for _m in core service config proxy download menu help; do
    . "$project_dir/sh/src/$_m.sh"
done
unset _m

is_conf="$work/config.yaml"
is_proxy_file="$work/profile.sh"
is_bashrc="$work/bashrc"
is_core_dir="$work/state"
is_core_bin="$work/state/core"
mkdir -p "$is_core_dir"

printf '\n== 配置读取 ==\n'
printf 'mixed-port: 7891\n' >"$is_conf"
check "普通写法" 7891 "$(get_mixed_port)"
printf '  mixed-port: 7891\n' >"$is_conf"
check "缩进写法" 7891 "$(get_mixed_port)"
printf 'mixed-port : 7891\n' >"$is_conf"
check "冒号前空格" 7891 "$(get_mixed_port)"
printf 'mixed-port: 7891 # 注释\n' >"$is_conf"
check "行内注释" 7891 "$(get_mixed_port)"
printf 'mixed-port: !!int "7891"\n' >"$is_conf"
check "显式类型标签" 7891 "$(get_mixed_port)"
printf '{mixed-port: 7891}\n' >"$is_conf"
check "flow 写法" 7891 "$(get_mixed_port)"
printf 'mixed-port: 0\n' >"$is_conf"
get_mixed_port >/dev/null 2>&1
check "端口 0 视为禁用" 1 "$?"
printf 'port: 7892\n' >"$is_conf"
get_mixed_port >/dev/null 2>&1
check "只有 port 时不可用" 1 "$?"
printf 'mixed-port: abc\n' >"$is_conf"
get_mixed_port >/dev/null 2>&1
check "非数字端口" 1 "$?"
printf '# 只有注释\n# mixed-port: 7890\n' >"$is_conf"
config_is_blank
check "注释模板识别为空" 0 "$?"
get_mixed_port >/dev/null 2>&1
check "空配置不返回端口" 1 "$?"
printf 'rules:\n  - MATCH,DIRECT\n' >"$is_conf"
config_is_blank
check "有内容不算空" 1 "$?"

printf '\n== 无 PyYAML 的保守读取 ==\n'
have_pyyaml() { return 1; }
printf 'mixed-port: 7891\n' >"$is_conf"
check "保守读取普通写法" 7891 "$(get_mixed_port)"
printf 'mixed-port: 7891 # 注释\n' >"$is_conf"
check "保守读取行内注释" 7891 "$(get_mixed_port)"
printf '{mixed-port: 7891}\n' >"$is_conf"
get_mixed_port >/dev/null 2>&1
check "保守读取 flow 明确失败" 1 "$?"
have_pyyaml() { command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; }

# 避免测试读到真实 systemd 状态
service_state() { printf 'inactive\n'; }

printf '\n== 代理文件与同步 ==\n'
printf 'mixed-port: 7891\n' >"$is_conf"
write_proxy_file 7891
check "写代理文件成功" 0 "$?"
grep -q '127.0.0.1:7891' "$is_proxy_file"
check "代理文件内容正确" 0 "$?"
sync_proxy_port >/dev/null 2>&1
check "同步幂等" 0 "$?"
printf 'mixed-port: 7892\n' >"$is_conf"
sync_proxy_port >/dev/null 2>&1
check "同步到新端口" 0 "$?"
check "同步后的端口" 7892 "$(proxy_file_port)"

# 服务启动中但端口未监听时不写代理文件 (ExecStartPost 场景)
service_state() { printf 'activating\n'; }
port_listened_by_core() { return 1; }
printf 'mixed-port: 7893\n' >"$is_conf"
sync_proxy_port >"$work/sync-listen.log" 2>&1
check "启动中未监听时不同步" 1 "$?"
check "文件保持原端口" 7892 "$(proxy_file_port)"
port_listened_by_core() { return 0; }
sync_proxy_port >/dev/null 2>&1
check "监听后同步" 0 "$?"
check "文件更新为 7893" 7893 "$(proxy_file_port)"
service_state() { printf 'inactive\n'; }
printf 'mixed-port: 7899\n' >"$is_conf"
write_proxy_file() { return 1; }
sync_proxy_port >"$work/sync-fail.log" 2>&1
check "写入失败返回非 0" 1 "$?"
grep -q '写入失败' "$work/sync-fail.log" && ok "写入失败有提示" || no "写入失败有提示"
. "$project_dir/sh/src/proxy.sh"

printf '\n== 连通性测试参数 ==\n'
curl() {
    printf '%s\n' '--CALL--' >>"$work/curl-args.log"
    local a
    for a in "$@"; do printf '%s\n' "$a" >>"$work/curl-args.log"; done
    printf '204'
}
_test_204_direct "$work/d1" >/dev/null
_test_204_proxy 7891 "$work/p1" >/dev/null
noproxy_values=$(awk '/^--noproxy$/{getline; print "[" $0 "]"}' "$work/curl-args.log" | sort -u | tr '\n' ' ')
check "noproxy 取值" "[*] [] " "$noproxy_values"
unset -f curl
is_ip_text "1.2.3.4" && ok "IPv4 校验" || no "IPv4 校验"
is_ip_text "2001:db8::1" && ok "IPv6 校验" || no "IPv6 校验"
is_ip_text "Forbidden (review)" && no "错误正文不算 IP" || ok "错误正文不算 IP"

printf '\n== 重启失败处理 ==\n'
(
    load() { :; }
    config_is_blank() { return 1; }
    config_test() { return 0; }
    get_mixed_port() { return 1; }
    sync_proxy_port() { printf 'SYNC CALLED\n'; }
    show_recent_log() { :; }
    systemctl() {
        case $1 in
        restart) return 1 ;;
        reset-failed | show) return 0 ;;
        esac
        return 0
    }
    apply_config >"$work/apply-fail.log" 2>&1
    echo $? >"$work/apply-fail.rc"
)
check "重启失败返回非 0" 1 "$(cat "$work/apply-fail.rc")"
grep -q '服务重启失败' "$work/apply-fail.log" && ok "重启失败有提示" || no "重启失败有提示"
not_contains "$work/apply-fail.log" '已生效|已重启|已启动' "重启失败不报成功"
not_contains "$work/apply-fail.log" 'SYNC CALLED' "重启失败不执行同步"

printf '\n== 成功路径 ==\n'
(
    load() { :; }
    config_is_blank() { return 1; }
    config_test() { return 0; }
    get_mixed_port() { printf '7890\n'; }
    port_listened_by_core() { return 0; }
    sync_proxy_port() { printf 'SYNC CALLED\n'; return 0; }
    show_recent_log() { :; }
    systemctl() {
        case $1 in
        restart) return 0 ;;
        show) printf 'active\n'; return 0 ;;
        reset-failed) return 0 ;;
        esac
        return 0
    }
    apply_config >"$work/apply-ok.log" 2>&1
    echo $? >"$work/apply-ok.rc"
)
check "成功路径返回 0" 0 "$(cat "$work/apply-ok.rc")"
grep -q 'SYNC CALLED' "$work/apply-ok.log" && ok "成功路径执行同步" || no "成功路径执行同步"

printf '\n== 卸载保护 ==\n'
(
    read() { answer=yes; }
    tar() { return 1; }
    systemctl() { printf 'SYSTEMCTL %s\n' "$*" >>"$work/uninstall-calls.log"; }
    _rm() { printf 'RM %s\n' "$*" >>"$work/uninstall-calls.log"; }
    pkill() { :; }
    load() { :; }
    proxy_off() { :; }
    do_uninstall
    echo $? >"$work/uninstall-bad.rc"
)
check "备份失败返回 2" 2 "$(cat "$work/uninstall-bad.rc")"
not_contains "$work/uninstall-calls.log" 'RM -rf' "备份失败不删除目录"
not_contains "$work/uninstall-calls.log" 'SYSTEMCTL stop' "备份失败不停服务"

(
    read() { answer=no; }
    tar() { printf 'TAR CALLED\n' >>"$work/uninstall-cancel.log"; }
    do_uninstall
    echo $? >"$work/uninstall-cancel.rc"
)
check "取消卸载返回 1" 1 "$(cat "$work/uninstall-cancel.rc")"
not_contains "$work/uninstall-cancel.log" 'TAR CALLED' "取消卸载不备份"

printf '\n== 核心下载失败保护 ==\n'
printf '#!/bin/bash\nprintf "Mihomo Meta v0.0.1\\n"\n' >"$is_core_bin"
chmod +x "$is_core_bin"
(
    need_cmd() { :; }
    get_latest_version() { printf 'v0.0.2\n'; }
    download_url() { return 1; }
    download_core >/dev/null 2>&1
    echo $? >"$work/dc.rc"
)
check "下载失败返回非 0" 1 "$(cat "$work/dc.rc")"
grep -q 'v0.0.1' "$is_core_bin" && ok "下载失败保留旧核心" || no "下载失败保留旧核心"

(
    need_cmd() { :; }
    get_latest_version() { printf 'v0.0.2\n'; }
    download_url() { printf 'not-gzip' >"$2"; return 0; }
    download_core >/dev/null 2>&1
    echo $? >"$work/dc2.rc"
)
check "解压失败返回非 0" 1 "$(cat "$work/dc2.rc")"
grep -q 'v0.0.1' "$is_core_bin" && ok "解压失败保留旧核心" || no "解压失败保留旧核心"

printf '\n== Geo 数据保护 ==\n'
is_core_dir="$work/geo"
mkdir -p "$is_core_dir"
printf 'oldgeo' >"$is_core_dir/geoip.metadb"
printf 'oldset' >"$is_core_dir/geosite.dat"
(
    download_url() { return 1; }
    download_geo force >/dev/null 2>&1
    echo $? >"$work/geo.rc"
)
check "Geo 失败返回非 0" 1 "$(cat "$work/geo.rc")"
check "Geo 失败保留 geoip" oldgeo "$(cat "$is_core_dir/geoip.metadb")"
check "Geo 失败保留 geosite" oldset "$(cat "$is_core_dir/geosite.dat")"
(
    download_url() { printf 'newdata' >"$2"; return 0; }
    download_geo force >/dev/null 2>&1
)
check "Geo 成功替换" newdata "$(cat "$is_core_dir/geoip.metadb")"

printf '\n== 权限与返回码 ==\n'
check "root 检测返回 0" 0 "$(check_root; echo $?)"
(
    check_root() { return 1; }
    do_install() { printf 'INSTALL RAN\n'; }
    dispatch install >"$work/root-check.log" 2>&1
    echo $? >"$work/root-check.rc"
)
check "非 root install 返回 1" 1 "$(cat "$work/root-check.rc")"
not_contains "$work/root-check.log" 'INSTALL RAN' "非 root 不执行安装"
(
    dispatch no-such-command >/dev/null 2>&1
)
check "未知命令返回 2" 2 "$?"

printf '\n== 菜单 ==\n'
(
    load() { :; }
    dispatch() { return 0; }
    show_banner() { :; }
    menu_items() { :; }
    show_menu </dev/null >/dev/null 2>&1
)
check "菜单 EOF 退出" 0 "$?"
(
    load() { :; }
    dispatch() { return 1; }
    show_banner() { :; }
    menu_items() { :; }
    printf '1\n\n0\n' | show_menu >/dev/null 2>&1
)
check "菜单操作失败后仍可退出" 0 "$?"

printf '\n== 端口监听归属 ==\n'
python3 - >"$work/port.txt" <<'PY' &
import socket, time
s = socket.socket()
s.bind(('127.0.0.1', 0))
s.listen()
print(s.getsockname()[1], flush=True)
time.sleep(20)
PY
test_pid=$!
sleep 0.5
test_port=$(cat "$work/port.txt")
port_listened_by_pid "$test_port" "$test_pid"
check "识别自己的监听" 0 "$?"
port_listened_by_pid "$test_port" "999999"
check "错误 pid 不匹配" 1 "$?"
kill "$test_pid" 2>/dev/null

printf '\n==============================\n'
printf '通过: %s  失败: %s\n' "$pass" "$fail"
rm -rf "$work"
[[ $fail == 0 ]]