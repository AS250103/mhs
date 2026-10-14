#!/bin/bash

# ---------------- 下载 (核心与 Geo 数据) ----------------

# 可选镜像前缀, 例如: MIHOMO_MS_MIRROR=https://ghfast.top/
mirror_url() {
    local url=$1
    if [[ $MIHOMO_MS_MIRROR && $url == https://github.com/* ]]; then
        printf '%s%s\n' "${MIHOMO_MS_MIRROR%/}/" "$url"
    else
        printf '%s\n' "$url"
    fi
}

# 下载 URL 到文件: 优先用户镜像, 再直连, 最后内置镜像
download_url() {
    local url=$1 out=$2
    local -a urls=()
    local p

    if [[ $MIHOMO_MS_MIRROR ]]; then
        urls+=("$(mirror_url "$url")")
    fi
    urls+=("$url")
    if [[ ! $MIHOMO_MS_MIRROR ]]; then
        for p in "https://ghfast.top/" "https://gh-proxy.com/"; do
            urls+=("${p}${url}")
        done
    fi

    local u
    for u in "${urls[@]}"; do
        _gray "下载: $u"
        if curl -fL --connect-timeout 15 --max-time 900 --retry 2 -o "$out" "$u" 2>/dev/null; then
            return 0
        fi
        _rm -f "$out"
    done
    return 1
}

# 获取最新版本号 (vX.Y.Z)
get_latest_version() {
    local api="https://api.github.com/repos/${is_core_repo}/releases/latest"
    local ver
    ver=$(curl -fsSL --max-time 20 "$api?v=$RANDOM" 2>/dev/null \
        | grep -oE '"tag_name": *"v[0-9.]+"' | head -n1 | grep -oE 'v[0-9.]+')
    if [[ ! $ver ]]; then
        ver=$(curl -fsSL --max-time 20 -o /dev/null -w '%{url_effective}' -L \
            "https://github.com/${is_core_repo}/releases/latest" 2>/dev/null | grep -oE 'v[0-9.]+$')
    fi
    [[ $ver ]] || return 1
    printf '%s\n' "$ver"
}

download_core() {
    need_cmd curl gzip || return 1

    local ver
    if ! ver=$(get_latest_version); then
        _red "获取 mihomo 最新版本失败, 请检查网络"
        return 1
    fi

    if [[ -f $is_core_bin ]]; then
        local cur
        cur=$(core_version)
        if [[ $cur == "$ver" ]]; then
            _green "核心已是最新版本: $ver"
            return 0
        fi
        _cyan "当前版本: $cur -> 最新版本: $ver"
    else
        _cyan "安装核心: $ver"
    fi

    local tmpdir
    tmpdir=$(mktemp -d) || return 1
    local pkg="mihomo-linux-${is_arch}-${ver}.gz"
    local url="https://github.com/${is_core_repo}/releases/download/${ver}/${pkg}"

    if ! download_url "$url" "$tmpdir/mihomo.gz"; then
        _rm -rf "$tmpdir"
        _red "核心下载失败: $pkg"
        return 1
    fi

    if ! gzip -dc "$tmpdir/mihomo.gz" >"$tmpdir/mihomo"; then
        _rm -rf "$tmpdir"
        _red "核心解压失败"
        return 1
    fi

    if ! chmod +x "$tmpdir/mihomo"; then
        _rm -rf "$tmpdir"
        _red "设置核心可执行权限失败"
        return 1
    fi

    if ! "$tmpdir/mihomo" -v >/dev/null 2>&1; then
        _rm -rf "$tmpdir"
        _red "下载的核心文件无法运行, 已保留原核心"
        return 1
    fi

    if ! mv -f "$tmpdir/mihomo" "$is_core_bin"; then
        _rm -rf "$tmpdir"
        _red "替换核心文件失败, 已保留原核心"
        return 1
    fi

    _rm -rf "$tmpdir"
    _green "核心已安装: $(core_version)"
    return 0
}

# 下载 GeoIP / GeoSite: 先写临时文件, 成功才替换; 失败保留旧数据
download_geo() {
    local force=$1
    local base="https://github.com/${is_geo_repo}/releases/download/latest"
    local name dest tmp rc=0

    for name in geoip.metadb geosite.dat; do
        dest=$is_core_dir/$name
        if [[ -f $dest && $force != force ]]; then
            _green "$name 已存在"
            continue
        fi

        tmp=$(mktemp "$is_core_dir/.$name.XXXXXX") || {
            rc=1
            continue
        }
        _cyan "下载 $name ..."
        if download_url "$base/$name" "$tmp" && [[ -s $tmp ]]; then
            if mv -f "$tmp" "$dest"; then
                _green "$name 下载完成"
                continue
            fi
        fi
        _rm -f "$tmp"
        _yellow "$name 下载失败 (已保留原文件, 可稍后执行: mihomo geo)"
        rc=1
    done
    return $rc
}