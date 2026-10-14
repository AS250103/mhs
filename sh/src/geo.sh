#!/bin/bash

# 下载 GeoIP / GeoSite 数据
download_geo() {
    local force=$1
    local base="https://github.com/${is_geo_repo}/releases/download/latest"

    for f in geoip.metadb geosite.dat; do
        local dest=$is_core_dir/$f
        if [[ -f $dest && $force != force ]]; then
            _green "$f 已存在"
            continue
        fi
        _cyan "下载 $f ..."
        if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$dest" "$base/$f"; then
            _green "$f 下载完成"
        else
            _rm -f "$dest"
            _yellow "$f 下载失败 (可稍后执行: mihomo geo)"
        fi
    done
}