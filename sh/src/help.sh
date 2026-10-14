#!/bin/bash

show_help() {
    echo
    _cyan "mihomo 管理脚本 ${is_sh_ver}"
    echo
    echo "用法: mihomo [命令]"
    echo
    _green "安装管理"
    echo "  install              安装/修复 mihomo (核心 + 服务, 不生成配置)"
    echo "  update               更新核心 (不更新脚本, 脚本更新请重跑安装命令)"
    echo "  uninstall            卸载 (先备份配置到 /root, 备份失败则取消)"
    echo "  version              查看版本"
    echo
    _green "服务"
    echo "  start | stop | restart"
    echo "  status               查看运行状态"
    echo "  log [-f]             查看日志 (-f 跟随)"
    echo
    _green "配置"
    echo "  config               编辑配置 (自动校验并重启, 不存在时创建空白模板)"
    echo
    _green "系统代理 (环境变量)"
    echo "  proxy on|off         开启/关闭代理设置 (写入 /etc/profile.d/mihomo-proxy.sh)"
    echo "  proxy status         查看代理状态"
    echo "  test                 直连/代理连通性测试"
    echo
    _green "其他"
    echo "  geo                  更新 GeoIP/GeoSite 数据"
    echo "  help                 显示帮助"
    echo
    echo "说明:"
    echo "  - 端口读取配置里的 mixed-port; 未配置或无效时不会猜测 7890."
    echo "  - 服务启动/重启后会确认端口已监听, 再同步系统代理端口."
    echo "  - 已打开的终端需重新 source 代理文件或重开; 已运行的项目需自行重载环境."
    echo "  - 不带参数运行进入交互菜单."
    echo
}