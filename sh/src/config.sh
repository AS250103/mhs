#!/bin/bash

# ---------------- 配置编辑与校验 ----------------

# 校验配置; 失败打印错误行
config_test() {
    local log
    log=$(mktemp /tmp/mihomo-test.XXXXXX) || return 1
    if "$is_core_bin" -d "$is_core_dir" -f "$is_conf" -t >"$log" 2>&1; then
        _rm -f "$log"
        return 0
    fi
    _red "配置校验未通过:"
    grep -vE '^[[:space:]]*$' "$log" | tail -n 8
    _rm -f "$log"
    return 1
}

# 创建空白模板 (仅注释, mihomo 可校验通过)
create_config_template() {
    cat >"$is_conf" <<'EOF'
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
}

edit_config() {
    check_installed || return 1

    if [[ ! -f $is_conf ]]; then
        _mkdir $is_core_dir || return 1
        if ! create_config_template; then
            _red "创建空白配置失败: $is_conf"
            return 1
        fi
        _yellow "配置文件不存在, 已创建空白模板: $is_conf"
    fi

    local editor=${EDITOR:-nano}
    command -v "$editor" >/dev/null 2>&1 || editor=vi
    if ! "$editor" "$is_conf"; then
        _yellow "编辑器退出码非 0, 未应用修改"
        return 1
    fi

    if config_is_blank; then
        _yellow "配置仍为空, 未重启服务"
        return 0
    fi

    load service.sh
    apply_config || return 1
    _green "配置已生效, 服务已重启"
    return 0
}