#!/bin/bash

# mihomo 一键安装脚本
#
# 本地安装:
#   bash install.sh
#
# 远程安装:
#   curl -fsSL https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
#
# 环境变量:
#   MIHOMO_MS_REPO    脚本代码仓库地址
#   MIHOMO_MS_MIRROR  GitHub 加速前缀 (同时用于脚本包和核心等下载)

repo_url=${MIHOMO_MS_REPO:-https://github.com/AS250103/mihomo-ms}
mirror=${MIHOMO_MS_MIRROR:-}
target=/etc/mihomo/sh

if [[ $(id -u) != 0 ]]; then
    echo "请使用 root 用户运行"
    exit 1
fi

missing=
for c in curl tar gzip; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
if [[ $missing ]]; then
    echo "缺少依赖:$missing"
    echo "Debian/Ubuntu: apt-get update && apt-get install -y curl tar gzip"
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
    echo "当前系统没有运行中的 systemd, 暂不支持"
    exit 1
fi

# 脚本自身所在目录 (curl|bash 时该目录没有源码)
self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

install_sh() {
    local src=$1 stage old
    stage=/etc/mihomo/.sh-stage.$$
    old=/etc/mihomo/.sh-old.$$

    _rm_stage() { rm -rf "$stage"; }

    mkdir -p "$stage/src" || return 1
    if ! cp -rf "$src/sh/." "$stage/"; then
        _rm_stage
        return 1
    fi
    if ! chmod +x "$stage/mihomo.sh"; then
        _rm_stage
        return 1
    fi

    if [[ -d $target ]]; then
        if ! mv "$target" "$old"; then
            _rm_stage
            return 1
        fi
    fi
    if ! mv "$stage" "$target"; then
        [[ -d $old ]] && mv "$old" "$target"
        _rm_stage
        return 1
    fi
    [[ -d $old ]] && rm -rf "$old"

    if ! ln -sf "$target/mihomo.sh" /usr/local/bin/mihomo; then
        return 1
    fi
    return 0
}

if [[ -n $self_dir && -f $self_dir/sh/mihomo.sh ]]; then
    # 本地模式: 源码就在脚本旁边
    echo "本地安装: $self_dir"
    if ! install_sh "$self_dir"; then
        echo "安装失败"
        exit 1
    fi
else
    # 远程模式: 从仓库下载代码包
    echo "远程安装: $repo_url"
    tmp=$(mktemp -d) || exit 1
    pkg=$tmp/code.tar.gz

    urls=()
    if [[ $mirror ]]; then
        urls+=("${mirror%/}/${repo_url}/archive/refs/heads/main.tar.gz")
    fi
    urls+=("$repo_url/archive/refs/heads/main.tar.gz")
    urls+=("$repo_url/archive/refs/heads/master.tar.gz")
    if [[ ! $mirror ]]; then
        urls+=("https://ghfast.top/$repo_url/archive/refs/heads/main.tar.gz")
        urls+=("https://gh-proxy.com/$repo_url/archive/refs/heads/main.tar.gz")
    fi

    ok=
    for url in "${urls[@]}"; do
        echo "下载: $url"
        if curl -fL --connect-timeout 15 --max-time 300 --retry 2 -o "$pkg" "$url" 2>/dev/null; then
            ok=1
            break
        fi
        rm -f "$pkg"
    done
    if [[ ! $ok ]]; then
        rm -rf "$tmp"
        echo "下载失败, 请检查仓库地址或网络 (可用 MIHOMO_MS_REPO / MIHOMO_MS_MIRROR 调整)"
        exit 1
    fi

    mkdir -p "$tmp/code"
    if ! tar xzf "$pkg" -C "$tmp/code" --strip-components=1; then
        rm -rf "$tmp"
        echo "解压失败"
        exit 1
    fi
    if [[ ! -f $tmp/code/sh/mihomo.sh ]]; then
        rm -rf "$tmp"
        echo "安装包结构异常, 未找到 sh/mihomo.sh"
        exit 1
    fi

    if ! install_sh "$tmp/code"; then
        rm -rf "$tmp"
        echo "安装失败"
        exit 1
    fi
    rm -rf "$tmp"
fi

echo
echo "脚本已安装: /usr/local/bin/mihomo -> $target/mihomo.sh"
echo

exec /etc/mihomo/sh/mihomo.sh install