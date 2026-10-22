# Antigravity 反复打不开、Gemini 无法使用：修复后端代理继承与无效更新地址，持久化专用出口，完成真实生成和冷启动验证

## 基本信息

- **处理者身份**：Codex（本次会话 AI 协作代理，独立完成现场排查、修复和验证；未使用子代理）。
- **用户反馈**：「antigravity 有时打不开，有时打开后 gemini 无法使用，反反复复出现很久这类问题了，帮我深度排查，彻底解决掉。」
- **问题类型**：桌面启动超时、Go 后端代理环境不完整、自动更新地址异常、Gemini 服务端地区拒绝、代理规则持久化。
- **排查日期**：2026-10-22；文中时间均为 Asia/Shanghai（UTC+8）。
- **故障日志覆盖时段**：当天约 11:17–12:42；修复后首次真实生成成功约 12:50；冷启动复验成功约 13:02。
- **最终状态**：✅ 本次现场已恢复。FlClash 完全重启后专用规则仍然生效；Antigravity 完全退出并从访达启动后，Gemini 再次真实回复成功。**未进行整机重启或长期连续观察**。
- **关联仓库**：[ARTISTA666/Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)。
- **与旧记录关系**：接续 [2026-10-17 的地区错误与 CLI 验证记录](2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md)。本次以桌面版实际请求确认当前可用性，补充进程路径分流、启动环境和更新配置问题。旧节点测试只代表当时样本，不能外推为某订阅永久全部不可用。

> 本文只同步脱敏后的过程与证据摘要。用户目录统一写为 `$HOME` 或 `/Users/<user>`；未上传账号、Token、订阅地址、代理密码、控制器密钥、原始数据库或完整私人配置。示例绝对路径中的 `<user>` 需要按本机替换。

## Agent 分工与时间线

| 时间 | 负责方 | 动作、发现及其意义 |
| --- | --- | --- |
| 现场排查开始 | Codex | 检查安装路径、版本、签名、日志、系统代理、TUN、FlClash 配置和旧排查材料；先保留配置与日志备份 |
| 11:17–12:42（历史日志） | Antigravity | OAuth 超时、多类 Google 域名解析失败、本地页面加载超时及更新 `ERR_UNSAFE_PORT`；这是取证时读取到的历史事件时间 |
| 升级前 | Codex | 直接读取安装内更新配置，发现固定地址 `http://127.0.0.1:1/manifest/`；核查后端如何获取 shell 环境，明确系统代理与 Go 后端环境并不等价 |
| 约 12:46–12:47 | Codex | 安装并验证 Google 官方 2.25.0，恢复官方更新源，加入只对 Antigravity 子 shell 生效的代理继承配置；正常启动和更新检查恢复 |
| 12:47:41 | Antigravity / Gemini | 桌面版首次真实诊断请求仍返回 `FAILED_PRECONDITION (code 400): User location is not supported for the API use.` |
| 随后 | Codex | 读取实际后端连接的规则与代理链；筛选可连通候选节点，仅为该后端设置专用出口，并关闭该后端已有连接使新规则生效 |
| 约 12:50:01 | Antigravity / Gemini | 同一账号、版本、模型和诊断请求得到真实回复 `GEMINI_CONNECTION_OK_20261022` |
| 首次成功后 | Codex | 将规则写入当前配置的持久附加规则；完全退出并重启 FlClash，确认配置重新生成、规则命中及实际代理链 |
| 13:01–13:02 | Codex / Antigravity | 完全退出应用，经访达打开正式安装包，确认后端自动获取代理环境；Gemini 真实回复 `GEMINI_COLD_START_OK_20261022` |
| 收尾 | Codex | 开启 FlClash 自启动并确认自动运行，保存本地报告及受限权限备份；记录回退方法和验证边界 |

## 问题详细描述

用户遇到的是两种反复交替的表象：有时应用无法正常打开；有时界面可以打开，但 Gemini 无法完成任务。过去换节点或短时恢复后，又可能复发。

现场为 Apple Silicon macOS。Antigravity 安装于 `$HOME/Applications/Antigravity.app`，Bundle ID 为 `com.google.antigravity`，修复前版本 **2.23.1**，修复后 **2.25.0**。Gemini 验证模型为 **Gemini 3.8 Flash High**，使用无项目诊断会话。

网络由 FlClash 管理，核心为 mihomo 1.19.32，使用规则模式、系统代理及 TUN：

| 项目 | 现场配置 |
| --- | --- |
| 系统 HTTP / HTTPS / SOCKS 代理 | `127.0.0.1:7890` |
| mihomo 模式 | `rule` |
| 进程识别 | `find-process-mode: always` |
| TUN | 启用、自动路由，现场接口 `utun4` |
| DNS | 劫持 `any:53`，fake-ip 网段 `198.18.0.1/16` |
| IPv6 | 核心配置为 `false` |
| 当前订阅配置 | 「赔钱机场」 |
| 原后端连接 | 命中一般 Google 规则，再跟随自动选择分组 |

浏览器能打开 Google、系统代理已开启、TUN 存在，均只能说明部分路径可用。桌面主进程、后端、更新器和模型调用需要分别取证。

## 排查过程与关键技术证据

### 1. 先排除安装损坏，保留现场

对修复前后应用均执行严格签名校验：

```sh
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/Antigravity.app"
codesign -dv --verbose=4 "$HOME/Applications/Antigravity.app"
```

现场签名有效，开发者为 Google LLC，Team Identifier 为 `EQHXZ8M8AV`。未发现相应系统崩溃报告，磁盘空间充足，因此没有把重装、清空缓存或账号重置作为盲目起点。

机器上存在旧汉化注入材料，包括 `/Library/Application Support/Antigravity-zh/injector.mjs` 和 `i18n.js`，但本次未发现它们正在执行，也没有证据证明它们导致了当前故障。**不能因为文件存在就归因于汉化工具。**

### 2. 日志显示启动相关网络失败，但不能把所有打不开都归为一个原因

主要日志：

```text
$HOME/Library/Logs/Antigravity/main.log
$HOME/Library/Logs/Antigravity/language_server.log
```

历史记录包括：

```text
oauth2.googleapis.com: dial tcp 74.125.195.95:443: i/o timeout
daily-cloudcode-pa.googleapis.com: no such host
www.googleapis.com: no such host
jetski-webchannel.googleapis.com: no such host
play.googleapis.com: no such host

11:18:16  本地页面 https://127.0.0.1:64188/ 加载 ERR_TIMED_OUT
更新检查   net::ERR_UNSAFE_PORT
```

其中 `daily-cloudcode-pa.googleapis.com` 相关失败涉及用户信息、模型和 Code Assist 初始化。前端本地页面超时与后端认证、DNS 故障同一阶段出现，支持优先修复启动网络链路；但这些日志不足以证明每次打不开都由同一项故障单独造成。

还分别通过显式 `7890` 代理及不显式使用代理的 curl 路径检查相关主机。主机根路径返回 HTTP 404，说明当时相应路径能够建立 HTTP 连接；后者仍可能经过 TUN。**404 不代表授权、地区校验或 Gemini 生成成功。**

### 3. Go 后端通过登录 shell 获取环境，不能只依赖 macOS 系统代理

对安装包 ASAR 中启动逻辑做了只读检查。该版本 `languageServer.js` 将进程环境与 `shellEnvSync()` 合并；后者通过子进程 `zsh -ilc` 获取 shell 环境。

Go 后端支持 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量，但没有自动把 macOS 系统代理设置转换成这些变量。没有找到可替代这条路径的应用代理设置或启动参数。

这解释了为什么「其他应用正常」「从某个终端启动偶尔正常」「界面能打开」均不能充分验证后端。TUN 虽可承接直接连接，仍需要明确后端的网络入口与实际出口。

修复后，从访达正常启动时主进程无需由诊断命令额外注入代理，后端已自动获得大小写代理变量及回环排除配置；普通终端的登录 shell 不会触发新增代理块。

### 4. 更新器并非随机端口冲突，而是固定无效地址

直接读取：

```text
$HOME/Applications/Antigravity.app/Contents/Resources/app-update.yml
```

实际更新 URL 是：

```text
http://127.0.0.1:1/manifest/
```

固定回环端口 **1** 对应日志中的 `ERR_UNSAFE_PORT`。此前桌面上的旧排查材料把它解释为「随机更新端口偶发冲突」，本次直接配置证据纠正了这一说法。**未确定是谁或什么工具修改了地址。**

从 [Google 官方下载页](https://antigravity.google/download) 获取 2.25.0 Apple Silicon 安装包，先校验安装包内应用签名，再替换正式应用并复核签名。使用的官方下载资源：

```text
https://storage.googleapis.com/antigravity-public/antigravity-hub/2.25.0-6535192714805248/darwin-arm/Antigravity.dmg
```

官方包恢复的更新 URL：

```text
https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/
```

12:47:08 及冷启动后的 13:02:05 日志均报告 `Up to date (2.25.0)`。这验证了本次更新配置恢复，不构成未来版本状态保证，也不能据此说升级单独解决了 Gemini。

### 5. 升级与启动恢复后，真实 Gemini 请求仍失败

诊断请求明确禁止工具调用和文件访问：

```text
Connection diagnostic only. Do not call tools or read/write files. Reply exactly: GEMINI_CONNECTION_OK_20261022
```

模型：`Gemini 3.8 Flash High`。12:47:41 仍实际出现：

```text
agent executor error: generating and executing:
FAILED_PRECONDITION (code 400): User location is not supported for the API use.
```

这一步把「可打开」「已登录」「模型列表加载」「更新正常」与「模型可真实生成」分开。不能在前几项恢复后就宣布任务完成。

### 6. 通过实际连接追踪分流，而不是根据节点名称或普通查 IP 结论

读取 mihomo 控制器的后端连接元数据，发现 `language_server` 的连接命中 `DomainKeyword google`，不同连接的链分别包含：

```text
🇸🇬AWS新加坡04 | 电信移动联通推荐 ← ♻️自动选择 ← 🚀节点选择
🇯🇵AWS日本09 | 电信移动联通推荐 ← ♻️自动选择 ← 🚀节点选择
```

这些是同一后端的实际连接证据，说明自动选择会让其网络路径发生变化。连接快照不能精确证明某一次失败请求对应哪一个出口 IP，也没有据此推断 Google 的完整判定算法。

通过控制器对候选节点做 `gstatic generate_204` 延迟测试：

| 候选 | 当时测试结果 | 可支持的结论 |
| --- | --- | --- |
| 东京 01 / 东京 06 | 控制器测试返回 503 | 当时该测试失败，未作为最终节点 |
| 新加坡 HY2 候选 | 超时 / 504 | 当时该测试失败 |
| 🇺🇸美国圣何塞07 \| 三网推荐 | 约 174 ms | 当时基本连通；仍需真实 Gemini 验证 |

在临时生成配置中试规则后，最终采用**精确进程路径**，不让所有 Google 流量或所有应用跟随诊断切换。应用规则后只关闭这个后端已有连接，使其重新选路，没有清空所有应用连接。

保持账号、版本、模型及诊断请求一致，改用美国圣何塞 07 后，约 12:50:01 出现真实 `streamGenerateContent` 响应，界面完整回复：

```text
GEMINI_CONNECTION_OK_20261022
```

这一对照支持「原出站路径关联的服务端拒绝」判断。没有修改账号地区或付款资料；也没有证明所有日本、新加坡或所有机房 IP 都会失败。

### 7. 把临时修复变为持久规则，并测试两次冷启动路径

只修改 FlClash 生成的 YAML 不够：客户端可能在重启或重新加载配置时覆盖它。因此将单条规则保存到**当前配置对应的持久附加规则**中。

本次在备份 SQLite 数据库后，保存的规则字段为：

| 字段 | 含义 / 值 |
| --- | --- |
| `rule_action` | `PROCESS_PATH` |
| `content` | 当前安装包内 `Contents/Resources/bin/language_server` 的完整绝对路径 |
| `rule_target` | `🇺🇸美国圣何塞07 \| 三网推荐` |
| `profile_id` | 当前使用的配置，内部 ID 未公开 |
| `no_resolve` / `src` | `0` / `0` |
| `order` | `a0`，保证先于一般 Google 规则 |

随后完全退出并重新打开 FlClash，确认进程变化、生成配置首条规则恢复、命中计数增加、实际后端连接经过目标节点。诊断涉及的其他运行时分组选项恢复到诊断前值。

再完全退出 Antigravity，从访达打开正式应用。约 13:01:53 主进程重新启动，13:02 更新正常，后端代理环境自动就绪。第二个禁止工具与文件访问的请求：

```text
Cold-start verification only. Do not use tools or access files. Reply exactly: GEMINI_COLD_START_OK_20261022
```

Gemini 在界面实际回复：

```text
GEMINI_COLD_START_OK_20261022
```

冷启动后日志未再出现本次 DNS、连接超时或地区拒绝错误。

## 根因分析

| 故障层 | 直接证据 | 修复 | 归因边界 |
| --- | --- | --- | --- |
| 后端启动网络路径不完整 | OAuth 连接超时、多个域名解析失败；启动代码读取 shell 环境；Go 后端不自动读系统代理 | 为 Antigravity 的子登录 shell 继承当前系统代理并排除回环 | 网络故障与页面超时相关，不能证明所有历史启动失败只有此因 |
| 自动更新配置异常 | 安装内 URL 固定为 `127.0.0.1:1`；反复 `ERR_UNSAFE_PORT` | 安装签名有效官方 2.25.0，恢复官方更新配置 | 修改来源未查明；更新失败不能单独解释模型地区拒绝 |
| 模型请求的出口拒绝 | 同账号/版本/模型，请求经原自动路径失败，专用节点后生成成功 | 为后端固定经真实生成验证的专用出口 | 不能推断全部 IP、订阅或账号地区判定规则 |
| 修复易失效 | 自动选择路径变化；生成 YAML 会重建；FlClash 自启动关闭 | 配置级持久规则，开启自启动并确认自动运行，重启验证 | 规则仍依赖安装路径、当前配置和节点存在 |

「只换节点」「只重装」「只看登录成功」都只能覆盖其中一部分。本次把启动入口、更新器和真实生成分别验证后，才认定现场恢复。

## 解决方案与落地操作

### 1. 备份与官方安装

改动前保留 `.zshrc`、更新配置、FlClash SQLite 一致性备份、偏好、生成配置和关键日志。备份目录仅当前用户可访问，配置文件限制权限。安装步骤为：官方下载 DMG → 只读挂载 → 对包内应用严格验签 → 暂存并替换正式应用 → 再验签 → 卸载镜像。

旧应用保留为不被 LaunchServices 识别的备份，避免正式应用与备份被重复注册。排查过程中曾遇到自动化启动定位重复备份的问题，已处理注册并用访达打开正式安装包；该诊断现象没有被混同为用户原始故障。

### 2. 只给 Antigravity 子 shell 补齐代理

在 `$HOME/.zshrc` 中加入以下带标记块。它读取系统当前 HTTPS 代理，不硬编码端口；仅当父进程为 Antigravity 时导出。以下为现场采用内容，依赖本次版本的 shell 环境读取方式：

```zsh
# BEGIN Antigravity proxy fix (2026-10-22)
# Antigravity's Go backend reads shell env, but does not read macOS system proxy.
# Scope this to the shell Antigravity itself spawns; leave other apps unchanged.
case "$(/bin/ps -p "$PPID" -o comm= 2>/dev/null)" in
  */Antigravity.app/Contents/MacOS/Antigravity)
    _ag_proxy=$(/usr/sbin/scutil --proxy)
    _ag_enabled=$(print -r -- "$_ag_proxy" | /usr/bin/awk '/HTTPSEnable :/ {print $3}')
    _ag_host=$(print -r -- "$_ag_proxy" | /usr/bin/awk '/HTTPSProxy :/ {print $3}')
    _ag_port=$(print -r -- "$_ag_proxy" | /usr/bin/awk '/HTTPSPort :/ {print $3}')
    if [[ "$_ag_enabled" == 1 && -n "$_ag_host" && "$_ag_port" == <1-65535> ]]; then
      export HTTP_PROXY="http://$_ag_host:$_ag_port" HTTPS_PROXY="http://$_ag_host:$_ag_port"
      export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY"
      export NO_PROXY="localhost,127.0.0.1,::1${NO_PROXY:+,$NO_PROXY}"
      export no_proxy="$NO_PROXY"
    fi
    unset _ag_proxy _ag_enabled _ag_host _ag_port
    ;;
esac
# END Antigravity proxy fix
```

`zsh -n "$HOME/.zshrc"` 语法检查通过；普通登录 shell 未因该块新增代理环境。没有覆盖整份 shell 配置，也没有设置全系统永久代理环境变量。

### 3. 保存精确进程规则

mihomo 生成后的目标规则形式如下；这里的路径已脱敏，**实际保存的是本机完整绝对路径，不能直接使用占位符，也不能指望 YAML 自动展开 `$HOME`**：

```yaml
rules:
  - "PROCESS-PATH,/Users/<user>/Applications/Antigravity.app/Contents/Resources/bin/language_server,🇺🇸美国圣何塞07 | 三网推荐"
  # 后接原有规则
```

规则放在一般 Google 分流之前，并且保存到当前 FlClash 配置的附加规则来源。控制器热重载只用于当次验证；最终以 FlClash 完全重启重新生成后仍存在为准。

不提供可在其他机器直接执行的数据库写入脚本：字段结构、当前配置 ID、规则顺序和节点名称都依赖现场。复现时优先在客户端附加规则中设置同等规则，检查生成结果和实际连接；若直接维护数据库，必须先停用相应写入并做一致性备份。

### 4. 保证代理可自动恢复

FlClash「工具 → 常规 → 自启动」由关闭改为开启；确认「自动运行」仍开启，系统代理和原有 TUN 保持启用。启动项设置已检查，尚未通过整机重启实测。

整个修复保留账号、项目和会话，没有清空用户数据、重置登录或降低证书校验。

## 验证与效果

| 验证对象 | 方法 / 证据 | 结果 |
| --- | --- | --- |
| 官方应用完整性 | 更新前后 `codesign --verify --deep --strict`；开发者与 Team ID 核查 | ✅ 均通过；最终 Google 官方 2.25.0 |
| 更新配置 | 查看 `app-update.yml` 与主日志 | ✅ 官方 HTTPS 更新源，12:47 / 13:02 检查正常 |
| shell 配置 | `zsh -n`，普通登录 shell 与应用后端环境对照 | ✅ 语法通过，普通终端不触发专用块，正常启动后后端自动获得代理 |
| 模型对照 | 同账号 / 同版本 / 同模型，改变后端分流 | ✅ 原路径 400，专用节点后真实回复 `GEMINI_CONNECTION_OK_20261022` |
| 持久规则 | 完全退出并重启 FlClash，检查生成配置、命中计数及实际代理链 | ✅ 专用规则恢复并命中 |
| 应用冷启动 | 完全退出 Antigravity，再通过访达打开正式应用 | ✅ 正常启动、模型与用户界面可用 |
| 第二次模型生成 | 冷启动后桌面版真实请求 | ✅ 回复 `GEMINI_COLD_START_OK_20261022` |
| 最终日志 | 检查本次冷启动后日志区间 | ✅ 未再出现此次 DNS、连接超时和地区拒绝错误 |
| 自动启动设置 | 客户端界面与保存偏好 | ✅ 自启动、自动运行开启；整机重启未测试 |

两次成功均为 Antigravity 桌面版中真实 Gemini 生成。HTTP 404、无认证 401、普通网页、模型列表和节点延迟测试均未作为最终成功判据。

## 经验沉淀与后续建议

1. **按组件拆开判断。** Electron 界面、Go 后端、更新器和模型请求可能失败在不同位置，重复重装或反复换总节点不能替代证据。
2. **追踪应用的实际代理链。** 普通查 IP 请求不一定走同一条规则；节点显示国家也不能替代该请求的真实路径或服务端响应。
3. **修复必须经重建验证。** 生成配置的手工改动可能消失。配置来源持久化、FlClash 重启和应用正常冷启动都要验证。
4. **CLI 成功有适用范围。** 仓库现有 `antigravity-silent-check.sh`、`antigravity-node-probe.sh` 使用独立 `agy` CLI。CLI 进程路径不同，不命中本次桌面 `language_server` 的 `PROCESS-PATH` 规则；模型与运行环境也应核对。它们仍可验证各自路径，但不能直接替代桌面版验收。
5. **历史节点结论有时效性。** 10 月 17 日对「赔钱机场」样本的失败不能扩大为整个订阅永久不可用；本次同订阅美国圣何塞 07 在桌面版两次成功。反过来，本次成功也不保证运营商不换 IP、Google 不调整策略。
6. **规则维护触发条件明确。** 移动应用、切换 FlClash 配置、节点删除或改名时，要同步调整专用规则；复发时先检查是否命中，再做无工具、无文件访问的桌面 Gemini 真实请求。
7. **不越过证据归因。** 本次未证明账号付款资料、所有机房 IP、汉化文件或每一次历史启动失败的完整因果关系。

地区与账号的一般要求可参考 [官方 FAQ](https://antigravity.google/docs/faq)，版本信息参考 [官方 changelog](https://antigravity.google/docs/changelog)。这些说明不能替代本次实际账号和网络路径的调用结果。

## 关键产物与现场位置

| 位置（已脱敏） | 用途与公开范围 |
| --- | --- |
| `$HOME/Applications/Antigravity.app` | 正式应用，2.25.0 |
| `$HOME/.zshrc` | 仅追加带 BEGIN / END 标记的专用代理块 |
| `$HOME/Library/Logs/Antigravity/` | 主日志、后端日志；后端日志会随启动覆盖，关键成功片段已另存本地 |
| `$HOME/Library/Application Support/Antigravity/` | Electron 用户数据，未公开 |
| `$HOME/.gemini/antigravity/` | 桌面后端数据，未公开 |
| `$HOME/.gemini/antigravity-cli/` | 独立 CLI 数据，与桌面版区分，未公开 |
| `$HOME/Library/Application Support/com.follow.clash/` | FlClash 持久数据与生成配置，未公开 |
| 本次工作目录下 `work/antigravity-diagnosis/` | 本地受限权限备份，包括原 shell 配置、SQLite 备份、偏好、配置及日志，未上传 |
| 本次工作目录下 `outputs/Antigravity-排查与修复报告.txt` | 本地用户报告；本文为适配仓库格式的详细脱敏记录 |

### 回退方法

- **撤销 shell 修复**：从 `.zshrc` 删除 `BEGIN Antigravity proxy fix (2026-10-22)` 到 `END Antigravity proxy fix` 的完整块，运行语法检查，再完整重启应用。
- **撤销专用分流**：在当前配置的附加规则中删除该条后端 `PROCESS-PATH` 规则，再重载并确认生成配置；不要用旧数据库整体覆盖后续用户改动。
- **撤销自启动**：在 FlClash「工具 → 常规」关闭自启动；该操作会影响下次登录时的代理就绪，需要结合实际使用决定。
- **应用版本回退**：旧包保存在 `Antigravity-2.23.1.before.bundle-backup`。为避免重复应用注册，`Contents/Info.plist` 改名为 `Info.plist.backup`。必须先退出应用，再恢复文件名及 `.app` 扩展名并核查签名、注册和更新源。旧包含失效更新地址，**不建议直接回退使用**。
- 备份用于局部恢复与证据回溯，不应把含凭据的完整配置、日志或数据库提交到公开仓库。
