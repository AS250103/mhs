#!/bin/bash

show_help() {
    echo
    _cyan "mihomo 管理脚本 ${is_sh_ver}"
    echo
    echo "用法: mihomo [命令]"
    echo
    _green "安装管理"
    echo "  install              安装/修复 mihomo (核心 + 配置 + 服务)"
    echo "  update               更新核心"
    echo "  uninstall            卸载 (配置自动备份到 /root)"
    echo "  version              查看版本"
    echo
    _green "服务"
    echo "  start | stop | restart"
    echo "  status               查看运行状态"
    echo "  log [-f]             查看日志 (-f 跟随)"
    echo
    _green "配置"
    echo "  config               编辑配置 (自动校验并重启)"
    echo
    _green "系统代理 (环境变量)"
    echo "  proxy on|off         开启/关闭 http_proxy 等环境变量"
    echo "  proxy status         查看代理状态"
    echo "  test                 直连/代理连通性测试"
    echo
    _green "其他"
    echo "  geo                  更新 GeoIP/GeoSite 数据"
    echo "  help                 显示帮助"
    echo
    echo "不带参数运行进入交互菜单."
    echo
}

show_banner() {
    refresh_core_status
    echo
    _cyan "=========================================="
    _cyan "            mihomo 管理脚本 ${is_sh_ver}"
    _cyan "=========================================="
    echo -e " 核心: ${green}${is_core_ver}${none}    服务: ${is_core_status}"
    if [[ -f $is_conf ]]; then
        echo -e " 配置: $is_conf"
    else
        echo -e " 配置: ${gray}${is_conf} (未创建)${none}"
    fi
    if [[ -f $is_proxy_file ]]; then
        echo -e " 系统代理: ${green}已开启${none}  (127.0.0.1:$(get_mixed_port))"
    else
        echo -e " 系统代理: ${gray}未开启${none}"
    fi
    echo
}