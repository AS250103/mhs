#!/bin/bash

# 获取最新版本号 (vX.Y.Z)
get_latest_version() {
    local repo=$1
    local url="https://api.github.com/repos/${repo}/releases/latest?v=$RANDOM"
    local ver
    ver=$(curl -fsSL --max-time 20 "$url" 2>/dev/null | grep -oE '"tag_name": *"v[0-9.]+"' | head -n1 | grep -oE 'v[0-9.]+')
    echo "$ver"
}

# 下载 GitHub release 文件
download_github() {
    local repo=$1 tag=$2 name=$3 out=$4
    local url="https://github.com/${repo}/releases/download/${tag}/${name}"
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"; then
        return 0
    fi
    err "下载失败: $url"
}

# 下载 mihomo 核心
download_core() {
    local ver=$(get_latest_version $is_core_repo)
    [[ ! $ver ]] && err "获取 mihomo 最新版本失败, 请检查网络."

    if [[ -f $is_core_bin ]]; then
        local cur=$(extract_core_ver)
        if [[ $cur == $ver ]]; then
            is_core_ver=$cur
            _green "核心已是最新版本: $ver"
            return 0
        fi
        _cyan "当前版本: ${cur:-未知} -> 最新版本: $ver"
    fi

    _cyan "最新版本: $ver"
    _cyan "下载 mihomo-linux-${is_arch}-${ver}.gz ..."

    local tmpdir=$(mktemp -d)
    local pkg="mihomo-linux-${is_arch}-${ver}.gz"
    download_github $is_core_repo "$ver" "$pkg" "$tmpdir/mihomo.gz"

    gzip -dc "$tmpdir/mihomo.gz" >"$tmpdir/mihomo"
    chmod +x "$tmpdir/mihomo"

    # 校验新核心可运行, 再替换 (避免 Text file busy / 坏文件)
    if ! "$tmpdir/mihomo" -v >/dev/null 2>&1; then
        _rm -rf "$tmpdir"
        err "下载的核心文件无法运行, 请重试."
    fi
    mv -f "$tmpdir/mihomo" "$is_core_bin"
    _rm -rf "$tmpdir"

    is_core_ver=$(extract_core_ver)
    _green "核心已安装: $is_core_ver"
}