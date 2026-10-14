#!/bin/bash

install_service() {
    local service_file=/lib/systemd/system/$is_core.service
    [[ -d /etc/systemd/system ]] && service_file=/etc/systemd/system/$is_core.service

    _cyan "写入 systemd 服务: $service_file"
    cat >$service_file <<EOF
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

    systemctl daemon-reload
    _green "服务已写入"
}
