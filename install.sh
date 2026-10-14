#!/bin/bash

# mihomo 一键安装脚本
#
# 本地安装:
#   bash install.sh
#
# 远程安装:
#   curl -fsSL https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
#
# 自定义仓库 / 镜像:
#   MIHOMO_MS_REPO=https://ghfast.top/https://github.com/AS250103/mihomo-ms bash install.sh

repo_url=${MIHOMO_MS_REPO:-https://github.com/AS250103/mihomo-ms}
target=/etc/mihomo/sh

if [[ $(id -u) != 0 ]]; then
    echo "请使用 root 用户运行"
    exit 1
fi

# 脚本自身所在目录 (curl|bash 时该目录没有源码)
self_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

install_sh() {
    local src=$1
    mkdir -p $target
    cp -rf "$src/sh/." $target/
    chmod +x $target/mihomo.sh
    ln -sf $target/mihomo.sh /usr/local/bin/mihomo
}

if [[ -n $self_dir && -f $self_dir/sh/mihomo.sh ]]; then
    # 本地模式: 源码就在脚本旁边
    echo "本地安装: $self_dir"
    install_sh "$self_dir"
else
    # 远程模式: 从仓库下载代码包
    echo "远程安装: $repo_url"
    tmp=$(mktemp -d) || exit 1
    pkg=$tmp/code.tar.gz
    ok=
    for url in \
        "$repo_url/archive/refs/heads/main.tar.gz" \
        "$repo_url/archive/refs/heads/master.tar.gz" \
        "https://ghfast.top/$repo_url/archive/refs/heads/main.tar.gz" \
        "https://gh-proxy.com/$repo_url/archive/refs/heads/main.tar.gz"; do
        echo "下载: $url"
        if curl -fL --connect-timeout 15 --retry 2 -o $pkg "$url" 2>/dev/null; then
            ok=1
            break
        fi
    done
    if [[ ! $ok ]]; then
        rm -rf $tmp
        echo "下载失败, 请检查仓库地址或网络 (可用 MIHOMO_MS_REPO 指定镜像)"
        exit 1
    fi

    mkdir -p $tmp/code
    if ! tar xzf $pkg -C $tmp/code --strip-components=1; then
        rm -rf $tmp
        echo "解压失败"
        exit 1
    fi
    if [[ ! -f $tmp/code/sh/mihomo.sh ]]; then
        rm -rf $tmp
        echo "安装包结构异常, 未找到 sh/mihomo.sh"
        exit 1
    fi

    install_sh "$tmp/code"
    rm -rf $tmp
fi

echo
echo "脚本已安装: /usr/local/bin/mihomo -> $target/mihomo.sh"
echo

exec /etc/mihomo/sh/mihomo.sh install