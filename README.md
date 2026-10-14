# mihomo-ms

mihomo (Clash.Meta) 一键安装管理脚本，用于本机系统代理。

## 安装

远程安装:

```bash
curl -fsSL https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
```

本地安装:

```bash
bash install.sh
```

安装完成后命令为 `mihomo`（软链到 `/etc/mihomo/sh/mihomo.sh`）。

### 国内网络

直连 GitHub 失败时，指定镜像或仓库地址:

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
```

或设置仓库前缀（同时影响脚本与核心的下载）:

```bash
MIHOMO_MS_REPO=https://ghfast.top/https://github.com/AS250103/mihomo-ms \
  bash install.sh
```

## 卸载

```bash
mihomo uninstall     # 停止服务、关闭系统代理、删除程序与脚本(配置备份到 /root)
```

源码目录 `mihomo-ms/` 不会被自动删除，如需彻底清理请自行移除。

## 常用命令

```bash
mihomo                     # 交互菜单
mihomo install             # 安装/修复
mihomo update              # 更新核心
mihomo uninstall           # 卸载(自动备份配置)

mihomo proxy on|off        # 开启/关闭环境变量系统代理
mihomo proxy status
mihomo test                # 直连/代理连通性测试

mihomo start|stop|restart|status|log
mihomo config              # 编辑配置(自动校验重启)
mihomo geo                 # 更新 GeoIP/GeoSite
```

## 系统代理说明

`mihomo proxy on` 会写入 `/etc/profile.d/mihomo-proxy.sh`，并让 `/root/.bashrc` 自动加载：

```
http_proxy / https_proxy = http://127.0.0.1:7890
all_proxy                = socks5://127.0.0.1:7890
no_proxy                 = 内网地址
```

- 新开的终端自动生效，已运行的进程需重启才会读取。
- **端口自动同步**：每次服务启动/重启时，脚本会读取配置里的 `mixed-port`，自动重写代理文件（systemd 单元带 `ExecStartPost` 钩子，开机自启也会同步）。所以直接手改配置里的端口，重启后代理会自动跟上；已打开的 shell 需 `. /etc/profile.d/mihomo-proxy.sh` 或重开。
- `mihomo status` 会检测“代理文件端口 / 配置端口”不一致并提醒。
- `mihomo proxy off` 删除该文件并清理 `.bashrc`。
- 这是应用层代理，只对读取环境变量的程序生效；TUN 全局透明代理默认不启用（避免影响现有服务）。

## 目录结构

```
/etc/mihomo/
├── bin/mihomo           # 核心
├── config.yaml          # 配置(完全由用户编辑, 脚本不自动生成)
├── geoip.metadb         # GeoIP 数据
├── geosite.dat          # GeoSite 数据
└── sh/                  # 脚本本体
/usr/local/bin/mihomo    # 入口软链
/etc/systemd/system/mihomo.service
```

## 配置校验与启动检测

- `mihomo start` / `restart` / `install` 会先用 `mihomo -t` 校验配置；不通过则**拒绝启动并打印错误行**，正在运行的旧进程不受影响。
- systemd 单元也带 `ExecStartPre` 校验：开机自启时配置不对会快速失败（限流 3 次后进入 failed），不会无限重启。
- `mihomo status` 在服务未运行时，会自动显示最近的相关日志。
- 脚本只提示，不自动修改配置；修好后执行 `mihomo start` 即可（脚本会自动清除 failed 状态）。

## 注意事项

- 安装**不会生成默认配置**；`config.yaml` 完全由你自己编辑（`mihomo config`，不存在时会生成空白模板）。
- 卸载时配置自动备份到 `/root/mihomo-backup-*.tar.gz`。
