# mihomo-ms

mihomo (Clash.Meta) 一键安装管理脚本，用于本机系统代理。

命令为 `mihomo`。支持 Debian/Ubuntu 等使用 systemd 的 amd64 / arm64 系统。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
```

本地源码安装:

```bash
bash install.sh
```

安装**不会生成默认配置**。配置完全由你编辑：`mihomo config` 会创建一份注释模板；服务在配置为空或无效时不会启动。

依赖：`curl`、`tar`、`gzip`、systemd。可选 `python3-yaml` 用于精确解析配置中的端口；没有时会采用保守读取，复杂 YAML 会明确提示“无法读取端口”，而不是猜测。

### 国内网络

```bash
# 只加速脚本代码包
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash

# 加速核心/数据下载
MIHOMO_MS_MIRROR=https://ghfast.top \
  curl -fsSL https://raw.githubusercontent.com/AS250103/mihomo-ms/main/install.sh | bash
```

- `MIHOMO_MS_REPO`：脚本代码仓库地址（默认 `https://github.com/AS250103/mihomo-ms`）。
- `MIHOMO_MS_MIRROR`：GitHub 加速前缀，作用于脚本包、核心、Geo 数据等 GitHub 下载。

## 卸载

```bash
mihomo uninstall
```

先备份配置到 `/root/mihomo-backup-*.tar.gz`（**备份失败会取消卸载**），然后停止服务、移除服务、关闭系统代理、删除程序与脚本。源码目录不会自动删除。

## 常用命令

```bash
mihomo                     # 交互菜单
mihomo install             # 安装/修复
mihomo update              # 更新核心(不更新脚本)
mihomo uninstall           # 卸载

mihomo start|stop|restart  # 服务
mihomo status              # 详细状态
mihomo log [-f]            # 日志

mihomo config              # 编辑配置(校验后重启)

mihomo proxy on|off        # 开启/关闭系统代理设置
mihomo proxy status
mihomo test                # 直连/代理连通性测试

mihomo geo                 # 更新 GeoIP/GeoSite
```

> `mihomo update` 只更新核心。脚本本身的更新方式是重新执行安装命令。

## 菜单

```text
 核心版本  v1.19.32        服务状态  已停止
 系统代理  未开启          代理端口  未配置
 配置文件  /etc/mihomo/config.yaml (未创建)
────────────────────────────────────────────
 服务        1 启动   2 停止   3 重启   4 详细状态
 配置与代理  5 编辑配置   6 开启系统代理
 诊断        7 连通性测试   8 查看日志
 维护        9 安装/修复   10 更新核心   11 卸载
             0 退出   R/回车 刷新
```

状态显示说明：

- 服务状态来自 systemd，不是进程名匹配。
- 配置分为“未创建 / 待填写 / 已存在”；文件存在不等于校验通过。
- 端口显示配置值以及是否由本服务的进程监听。
- 系统代理开启但服务未运行时，显示为“已开启（不可用）”。

## 系统代理说明

`mihomo proxy on` 写入 `/etc/profile.d/mihomo-proxy.sh`：

```text
http_proxy / https_proxy = http://127.0.0.1:<mixed-port>
all_proxy                = socks5://127.0.0.1:<mixed-port>
no_proxy                 = 内网地址
```

- 端口取自配置里的 `mixed-port`。未配置或无效时拒绝开启，不会默认写 7890。
- 服务启动/重启后会确认端口确实由 mihomo 监听，再同步代理文件（systemd 单元带 `ExecStartPost` 钩子，开机自启同样生效）。
- 代理设置写入 profile 文件只影响**之后**读取该文件的 shell/程序；当前终端需要 `. /etc/profile.d/mihomo-proxy.sh`，已运行的项目需要重新读取环境变量或重启。
- `mihomo proxy off` 删除文件并清理 `.bashrc` 中的引用。
- 这是应用层环境变量代理；不使用 TUN 透明代理。

## 目录结构

```
/etc/mihomo/
├── bin/mihomo           # 核心
├── config.yaml          # 配置(完全由用户编辑)
├── geoip.metadb         # GeoIP 数据
├── geosite.dat          # GeoSite 数据
└── sh/
    ├── mihomo.sh        # 入口
    └── src/             # init / core / service / config / proxy / download / menu / help
/usr/local/bin/mihomo    # 命令软链
/etc/systemd/system/mihomo.service
```

## 测试

```bash
bash tests/selftest.sh
```

隔离自测：全部在临时目录与模拟命令中执行，不触碰真实服务与配置。

## 配置校验与启动检测

- `mihomo start|restart|config|install` 会先用 `mihomo -t` 校验；不通过则拒绝启动并打印错误行。
- `mixed-port` 与 `port` / `socks-port` / 外部控制端口重复时，会在重启前直接拒绝。
- 校验通过后还会确认：服务进入 running、配置的端口确实由 mihomo 监听（需要 `ss`，来自 iproute2）。端口被其他进程占用时会明确提示。
- systemd 单元带 `ExecStartPre` 校验，开机自启时配置错误会快速失败（限流 3 次），不会无限重启。
- 脚本只提示，不自动修改配置。
