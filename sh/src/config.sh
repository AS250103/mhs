#!/bin/bash

# 配置操作 (配置完全由用户自行编辑)

# 校验配置, 成功则重启服务并同步系统代理端口; 失败只报错不重启
test_config_restart() {
    if ! $is_core_bin -d $is_core_dir -f $is_conf -t >/tmp/mihomo-test.log 2>&1; then
        _red "配置校验失败:"
        cat /tmp/mihomo-test.log
        _rm -f /tmp/mihomo-test.log
        return 1
    fi
    _rm -f /tmp/mihomo-test.log
    systemctl restart $is_core
    load proxy.sh 2>/dev/null
    sync_proxy_port
    _green "配置已生效, 服务已重启"
}