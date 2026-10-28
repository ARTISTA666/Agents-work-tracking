# Agents Work Tracking

AI 代理工具（Antigravity、ZCode、ChatGPT、Gemini、Qoder 等）在日常使用中遇到的报错、故障、网络问题与代理配置的深度排查记录。每篇记录均包含完整的报错信息、排查过程、根因分析、解决方案与验证结果，可作为同类问题的参考手册。

## 目录结构

```
.
├── README.md                 # 本文件
├── records/                  # 排查记录（按日期命名，Markdown 格式）
│   ├── 2026-09-02-*.md
│   ├── 2026-09-03-*.md
│   ├── 2026-09-04-*.md
│   ├── 2026-10-17-*.md
│   ├── 2026-10-22-*.md
│   ├── 2026-10-23-*.md
│   ├── 2026-10-24-*.md
│   └── 2026-10-28-*.md
└── scripts/                  # 排查过程中编写的辅助脚本
    ├── apibai-retry-proxy.py
    ├── antigravity-silent-check.sh   # Antigravity 出口静默自检（真实调用）
    ├── antigravity-node-probe.sh     # Antigravity 逐节点静默体检（隔离 mihomo + agy）
    ├── qoder-add-bypass.sh           # Qoder 域名加入 macOS 代理绕过列表（直连，幂等，首轮）
    ├── qoder-rollback-bypass.sh      # Qoder 绕过列表回滚（恢复修复前原始条目，首轮）
    ├── qoder-clash-direct.sh         # 第二轮：mihomo 规则置顶 qoder DIRECT + 备份 + 热重载（幂等，运行时文件，会被重建清空）
    ├── qoder-clash-rollback.sh       # 第二轮：移除运行时 qoder DIRECT 规则并热重载
    ├── qoder-flclash-persist.sh          # 第三轮：qoder DIRECT 写入持久库 database.sqlite 的 rules 表（备份/退出/写库/重启/校验，幂等）
    ├── qoder-flclash-persist-rollback.sh # 第三轮：删除持久库 qoder 规则并重启回滚
    ├── codex-desktop-send-block-check.sh  # Codex 桌面版发送被禁用：check 诊断 / apply 改回 local / rollback（幂等，改动前备份）
    ├── chatgpt-dot-entry-provider-check.sh  # 桌面版 dot 入口消失：check 诊断 / apply 改 model_provider=openai / rollback（幂等，改动前备份）
    ├── qoder-httpdns-ip-direct.sh          # 第四轮：Qoder 自解析裸 IP 绕过分流 → 持久库 IP_CIDR→DIRECT：check / apply / rollback（幂等，改动前备份）
    ├── chatgpt-ai-node-stability.sh        # ChatGPT 桌面版 cf_clearance 失效：检测/固定 AI 分组出口稳定节点：check / apply / rollback（改动前备份）
    ├── gemini-web-egress-pin.sh            # Gemini 网页「不支持你所在地区」：把 gemini.google.com 固定到干净美国出口：check / apply / rollback（幂等，改动前备份，热重载）
    └── default-egress-pin.sh               # 默认分流出口固定到干净节点（防 400 地区拒绝）：写 FlClash 持久库 selected_map + 退/重启复验：check / apply / rollback
```

## 记录列表

按时间倒序排列。

### 2026-10-28

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [gemini-web-and-antigravity-intermittent-egress-hk-region-reject.md](records/2026-10-28-gemini-web-and-antigravity-intermittent-egress-hk-region-reject.md) | 用户报「Gemini 网页端 + Antigravity 内 Gemini 同时都无法连接」；复核时 `gemini.google.com` 经 TUN / 无头 Chrome 均 `200` 正常（10/10），Antigravity 主程序 7 条连接全部走圣何塞07，但 `agy` 真实调用稳定复现 `400 FAILED_PRECONDITION: User location is not supported` | **结构性根因（10-24 复发）**：默认分流 `🚀节点选择 → 🇺🇸美国节点 → 🇺🇸美国圣何塞03｜三网推荐` 仍落在共享 NAT 池廉价中转，出口 `104.251.122.87` 被 Google 判**香港**（`google.com → google.com.hk`，Cloudflare 却报 US），Antigravity 内部端点 `daily-cloudcode-pa` 地区校验更严 → **请求级随机 400**（同 IP、同分钟，`agy` 连续两次一成一败）。「两者同时挂」的**同时性**来自 09:11–09:16 连续 `connection reset` + 09:16 FlClash 内核重启（`config.yaml` 重建）掐断在途连接；网页端因 10-24 已固定圣何塞07，恢复后不再受影响 | ✅ **已修复（方案 A）**：`🚀节点选择` 固定为 `🇺🇸美国圣何塞07｜三网推荐`，写入持久库 `profiles.selected_map`，**完全退出并重启 FlClash 后仍生效**（config 10:17 重建、`utun4` 恢复、两条覆写规则未动）；修复后出口 `134.195.101.193/194`（US）、`google.com` 无 HK 跳转、Gemini 3/3 `200`、`agy` 2/2 `PONG`；备份 `~/Desktop/gemini-check/backup-20261028-101619/`，含 [`scripts/default-egress-pin.sh`](scripts/default-egress-pin.sh) check/apply/rollback 与方案 B 备选 |

### 2026-10-24

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [gemini-web-unsupported-country-ai-node-egress.md](records/2026-10-24-gemini-web-unsupported-country-ai-node-egress.md) | Gemini 网页端整页「Gemini isn't currently supported in your country. Stay tuned!」，同一台机器上 Antigravity 里的 Gemini 却正常 | 网页流量命中订阅规则 `DOMAIN,gemini.google.com → 🤖AI网站`，该组当时选中 **0.1 倍廉价中转（美国08）**，其出口 IP 会漂移且被 Google 地理库判为**香港**（实测 `www.google.com` 302 到 `google.com.hk`，出口 `67.159.48.146/147` Cloudflare 认为 SG、Google 认为 HK；Gemini 不支持香港）；Antigravity 因早有一条 `PROCESS-PATH` 覆写被固定到圣何塞07（`134.195.101.x`，Google 判 US）所以一直正常。被拦页面还会被 Chrome 缓存 → 表现为“时好时坏 + 强刷也不变”，无痕/curl 正常 | ✅ 已解决（新增覆写规则 `DOMAIN,gemini.google.com → 🇺🇸美国圣何塞07｜三网推荐`：写入持久库 `rules` 表 + 热重载；Chrome 原窗口刷新即恢复；**完全退出并重启 FlClash 后规则仍在**（配置 17:00:09 重建、规则在第 1628 行）；含 [`scripts/gemini-web-egress-pin.sh`](scripts/gemini-web-egress-pin.sh) check/apply/rollback 与备份/回滚） |

### 2026-10-23

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md](records/2026-10-23-macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md) | 系统设置 → 互联网账户里重新验证 Google 账户后弹「无法验证账户名或密码。」，弹窗「好」按钮点击完全无反应（无高亮、无消失、回车也无效） | 两层：① **直接原因**——Safari 的 `ASWebAuthenticationSession` 认证窗口在 5.4 秒后被关闭（OAuth 取消，`Code=1`），扩展校验凭据失败（`com.apple.accounts Code=3`）；② **按钮失灵**——该错误提示由 `InternetAccountsSettingsExtension`（后台 appex）以 `_NSAlertPanel` 弹出，但面板 `canBecomeKeyWindow = NO`，永远无法成为 key window，按钮 action 不触发（macOS 26.6 缺陷；同一会话连续 3 次同类 AppKit 告警）。判据：`log show --predicate 'eventMessage CONTAINS "canBecomeKeyWindow"'` | ✅ 已解决（`pkill -f InternetAccountsSettingsExtension` 清掉僵尸窗口后，点已有 Google 账户「打开浏览器」完整重走 OAuth；08:03:38 凭据校验成功、Mail 自动创建 `imap.gmail.com`、通讯录子账户 active/enabled；用户确认「可以了」） |

### 2026-10-22

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md](records/2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md) | ChatGPT 桌面版（Codex）间歇报错、刷新成功/失败来回跳，最终卡在启动 logo；「无法查看你的工作空间访问权限」 | **cf_clearance 与出口 IP 绑定**：机场 AI 节点用 NAT 池/IPv6 轮换出口（实测 .193/.194 秒级切换），凭证反复失效 → 鉴权/pubsub 请求被 403 挑战并触发重连风暴；另叠加一次 FlClash 重启窗口的 **DNS 缓存污染**（系统解析缓存真实 IP 52.175.9.80）。与同日 Qoder 的 `IP_CIDR` 规则无网段重叠。最终不可用真因是**账号额度耗尽**（Codex/Work usage，10/27 重置） | ✅ 网络层已稳定（固定出口节点后 `cloudflare_challenge` 68→0，桌面版可正常加载，用户确认正常；含出口稳定性诊断/固定/回滚脚本）；⏳ 额度待 10/27 重置 |
| [qoder-httpdns-resolved-ip-proxy-reset.md](records/2026-10-22-qoder-httpdns-resolved-ip-proxy-reset.md) | 第三轮后用户真实发消息仍弹「系统发生异常」；应用日志 `QODER_EXECUTION_CONTROL_FAILED`、`resultErrorCode=500`，控制面全绿但模型流必挂 | **HTTPDNS 裸 IP 分流盲区**：Qoder Agent SDK 以 `networkMode=httpdns` 把 `api3/center/openapi.qoder.sh` 自解析成裸 IP（8.222.76.136、8.212.124.35 等）再直连；mihomo 对裸 IP 只能按 IP/GEOIP 匹配，命中不了第三轮的 `DOMAIN-SUFFIX qoder.sh→DIRECT`，落 MATCH→代理节点被 TLS 重置（ECONNRESET，`failure_phase=response_headers`）。判别：主机名 curl 通、`--resolve` 裸 IP 挂。真实错误只写在 `~/.qoder/logs/runs/*/qodercli.log` | ✅ 已解决（持久库 `IP_CIDR 8.208.0.0/12 + 47.57.0.0/16 → DIRECT` 写进 rules 表，重启 FlClash 后仍在，裸 IP 实测 000→200、模型 SSE 端点 200；用户实发消息确认 Qoder 恢复可用；含 check/apply/rollback 脚本） |
| [qoder-flclash-persistent-direct-rules.md](records/2026-10-22-qoder-flclash-persistent-direct-rules.md) | 第二轮直连规则被 FlClash 重建清空，使用仍弹「系统发生异常，请重试」，模型流 `ERR_CONNECTION_CLOSED`、QCS `NETWORK_ERROR` | 运行时 config.yaml 是订阅合并产物、重建即丢；qoder 落兜底 Match→代理节点被 TLS 重置。改写入持久库 database.sqlite 的 rules 表（`DOMAIN_SUFFIX qoder.sh/.com/.ai → DIRECT`），重启置顶且跨重建不丢 | ✅ 域名路由层根治并持久化（`/rules` 命中 52、全 qoder 主机 DIRECT、致命错误 0、QCS 200/SSE connected；含持久化/回滚脚本）；⚠️ 该轮「真实对话待实发确认」在第四轮被证实**仍失败**——域名层覆盖不到 HTTPDNS 裸 IP 路径，见 [第四轮](records/2026-10-22-qoder-httpdns-resolved-ip-proxy-reset.md) |
| [chatgpt-desktop-dot-sidebar-missing-custom-model-provider.md](records/2026-10-22-chatgpt-desktop-dot-sidebar-missing-custom-model-provider.md) | ChatGPT 桌面版侧栏 dot 入口消失（网页端 `chatgpt.com/dots` 仍正常），听写麦克风同时消失；疑为 dot 被删/账号权限/地区限制 | **本地配置触发的第一方推理能力门控**：侧栏 dot 入口依赖 `orbit` 能力（`requiresFirstPartyInference: true`），gate `3683713372` 生效时校验 `(model_provider ?? "openai") === "openai"`；本机 `~/.codex/config.toml` 为 `model_provider = "custom"`（实际是 OpenAI 别名）→ 判 false → 入口组件返回 `null`。dot 档案本身 `available/active`，网页端不读本地配置故正常。判别特征：网页正常 + 侧栏无 dot + 听写也消失 + provider 非 openai | ✅ 已解决（改回 `openai` + 完全重启，侧栏「你的 dot」与听写恢复；dot 数据零丢失；含诊断/修复/回滚脚本与上游 issue 索引）；⚠️ 同日 22:10 **复发**为第二种成因——启动期网络抖动（52.6s 启动、`ERR_NETWORK*`、Statsig bootstrap 失败 ×6、`Orbit messaging` 0 次）导致账号能力初始化失败，入口不渲染且不自愈；网络稳定后完全重启恢复，配置无需再改（判别表见记录内「复发与二次定位」，网络背景见 [cf_clearance 记录](records/2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)） |
| [antigravity-startup-proxy-update-and-gemini-egress-fix.md](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md) | Antigravity 反复打不开，打开后 Gemini 仍报地区拒绝；更新检查反复 `ERR_UNSAFE_PORT` | 后端未自动继承系统代理；更新地址被改为固定无效端口 `127.0.0.1:1`；一般 Google 分流跟随自动节点，真实生成被拒。恢复官方 2.25.0、补齐应用专用代理环境、持久化后端 `PROCESS-PATH` 专用出口 | ✅ 已解决（桌面 Gemini 两次真实回复，FlClash 重启及访达冷启动复验通过；含证据、配置、回退和旧判据适用边界） |
| [codex-desktop-send-disabled-cloud-env-missing.md](records/2026-10-22-codex-desktop-send-disabled-cloud-env-missing.md) | ChatGPT.app / Codex 桌面版「发消息点击完全没反应」：UI 正常、登录正常、输入框可输入，但发送按钮始终灰态禁用，日志中全天 `turn/start` = 0、无任何网络请求 | **UI 前置校验死锁**：执行位置 `new-task-execution-by-account-project` 被持久化为 `cloud(远程)`，而账号 `environment-catalog` 为空（`hasEnvironments:false`）→ 要求「先选云端环境」却无环境可选 → 发送按钮永久 disabled，点击被 UI 层吞掉。判别特征：位置标签「远程」+ 悬停提示「请选择一个云端环境，然后继续」 | ✅ 已解决（改回「此计算机/local」，按钮由灰变白，实发消息 `turn/started`→`turn/completed` 回复 OK，退出重启后持久；含诊断/修复/回滚脚本） |
| [qoder-clash-direct-routing.md](records/2026-10-22-qoder-clash-direct-routing.md) | 首轮绕过列表后 Qoder 能打开但使用仍报网络问题：模型流 `ERR_CONNECTION_CLOSED`、协作 wss `ENOTFOUND`、team-profiles `CLOSED` | TUN/fake-ip 全局接管，系统绕过列表只管 7890 入口、管不到 TUN 规则；qoder 被送进代理节点被 TLS 重置，DIRECT 77ms 正常。当时在运行时 config.yaml 置顶 `qoder.sh/.com/.ai → DIRECT` 并热重载 | ⚠️ 当时热重载有效但运行时文件被 FlClash 重建清空导致复发，已被[第三轮持久化根治](records/2026-10-22-qoder-flclash-persistent-direct-rules.md)取代；该轮诊断（TUN 接管、DIRECT 通/节点重置）仍成立 |
| [qoder-network-ssl-reset-direct-bypass.md](records/2026-10-22-qoder-network-ssl-reset-direct-bypass.md) | Qoder 启动自检 `foundation/model/messaging/resources` 四项全 `network` 失败（637ms 快速失败），日志 `openapi.qoder.sh` 报 `net::ERR_CONNECTION_CLOSED`、更新检查 `fetch failed` | 代理客户端正常、普通站点经代理 200，唯独 Qoder 阿里云海外后端（`*.qoder.sh`/`*.qoder.com`）经 FlClash 代理时 TLS 握手被重置；直连全部可达。属单域名分流路由问题，非断网/DNS/服务端/账号 | ✅ 首轮解决（把 4 条 qoder 域名加入 macOS Wi-Fi 代理绕过列表走直连；第二轮确认 TUN 下权威修复在 mihomo 规则 DIRECT，绕过列表冗余保留；第三轮固化到持久库） |

### 2026-10-17

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md](records/2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md) | Antigravity 调用 Gemini 报 `HTTP 400 / FAILED_PRECONDITION / User location is not supported for the API use`，Agent 任务首次调用即终止；前一轮排查按旧判据换节点仍失败 | FlClash「节点选择」= 新加坡SG-A，出口 IP `50.7.253.42` 被 `daily-cloudcode-pa.googleapis.com` 地区校验拒绝；且旧判据（`generativelanguage` + API Key、无认证 POST 看 400/401）均不能代表 Antigravity 通道。**本篇同时用实验证伪并修正了 2026-09-04 记录中的「无认证 401 = 地域通过」判据** | ✅ 已解决（切 日本JP-HY2，静默 CLI 实测 2/2 通过；另修复 FlClash 冷启动不自动开代理）；**含同日 18:00 补充：新订阅「赔钱机场」当时已测样本被拒的复测；[10 月 22 日桌面版已在该订阅另一节点成功](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)** |

### 2026-09-04

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md](records/2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md) | Antigravity Agent 运行 44 秒后弹窗 `Agent execution terminated due to error`，后端返回 HTTP 400 `User location is not supported for the API use.` | 台湾中华电信出口 IP 不在 Google Antigravity 内部 Daily 端点（`daily-cloudcode-pa.googleapis.com`）的地域白名单中；该内部端点策略与公开 Gemini API 不一致 | ✅ 已解决（切换节点 + 重启，14 次 API 调用全恢复） |
| [flclash-not-running-dns-pollution-macos-network-troubleshooting.md](records/2026-09-04-flclash-not-running-dns-pollution-macos-network-troubleshooting.md) | FlClash 节点疑似全失效、Google 报地区限制、Antigravity 用不了；系统 DNS 配置 8.8.8.8 遭 GFW 污染 | FlClash 客户端根本未运行（进程/端口/TUN 全空）；系统 DNS 长期用 8.8.8.8 致 DNS 污染注入；国内 DoH 对被墙域名也返回污染结果 | ✅ 已解决（启动 FlClash 规则模式+TUN、修正系统 DNS 为国内 DNS、添加开机自启） |
| [chatgpt-unsupported-country-clash-meta-migration.md](records/2026-09-04-chatgpt-unsupported-country-clash-meta-migration.md) | ChatGPT 登出后再登录报 `unsupported_country_region_territory`；Whoer 显示出口新加坡但 DNS 泄漏中国；Google/Antigravity 需固定节点与 GPT 换节点冲突 | 节点名称标新加坡但实际 IP 归属香港（OpenAI 对港封锁）；ClashX Meta 仅劫持 `0.0.0.0:53` 漏 IPv6 致 DNS 泄漏；老旧客户端 TUN 重载断网 | ✅ 已解决（迁移至 FlClash、彻底卸载 ClashX Meta、台湾原生节点） |

### 2026-09-03

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [zcode-400-invalid-request-long-context.md](records/2026-09-03-zcode-400-invalid-request-long-context.md) | ZCode 超长会话调用 glm-5.3-flash 间歇报 400 `Invalid request body` | `ai_sdk_options` 全量序列化致缓存失效，免费中转超时被误报为参数错误 | ✅ 已解决 |
| [zcode-apibai-retry-proxy.md](records/2026-09-03-zcode-apibai-retry-proxy.md) | ZCode 调用 api.b.ai 频繁 401 中断 | 本地自动重试中转与 chunked 协议 Bug | ✅ 已解决（含 `scripts/apibai-retry-proxy.py`） |

### 2026-09-02

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [gemini-web-connection-error.md](records/2026-09-02-gemini-web-connection-error.md) | Gemini 网页端「网络连接失败」 | 网络代理配置问题 | ✅ 已解决 |

## 按问题类型快速索引

| 问题类型 | 相关记录 |
| --- | --- |
| **地域限制 / IP 白名单** | [2026-10-22 桌面 Gemini 出口对照与真实生成](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)、Antigravity 400 User location not supported（[2026-09-04 台湾 IP](records/2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md)、[2026-10-17 新加坡 IP](records/2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md)）、ChatGPT unsupported country |
| **代理客户端故障** | FlClash 未运行、FlClash `autoRun=false` 冷启动不自动开代理、ClashX Meta 架构缺陷与迁移 |
| **AI 客户端 UI 门禁 / 按钮禁用 / 入口消失（非网络）** | [2026-10-22 Codex 桌面版发送禁用](records/2026-10-22-codex-desktop-send-disabled-cloud-env-missing.md)：执行位置=远程(cloud) 且云端环境目录为空 → 发送按钮永久禁用，「点了没反应」且日志零请求；用悬停 tooltip 取证，改回「此计算机(local)」修复。[2026-10-22 桌面版 dot 入口消失](records/2026-10-22-chatgpt-desktop-dot-sidebar-missing-custom-model-provider.md)：`model_provider` 非 `openai` 触发第一方推理能力门控 → 侧栏 dot 与听写一起隐藏；改回 `openai` + 重启恢复（`scripts/chatgpt-dot-entry-provider-check.sh`，附启动诊断）；**同日 22:10 复发为第二种成因**——启动期网络抖动导致账号能力初始化失败（听写仍在、启动耗时异常、`Orbit messaging` 0 次），网络稳定后完全重启恢复；[2026-10-22 桌面版间歇报错/卡启动](records/2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)：机场出口 IP 轮换导致 Cloudflare `cf_clearance` 失效 → 403 挑战 + 重连风暴；固定出口稳定节点恢复（`scripts/chatgpt-ai-node-stability.sh`），另需区分 DNS 缓存污染与额度耗尽 |
| **代理分流 / 单域名直连绕过** | [2026-10-22 Qoder 首轮](records/2026-10-22-qoder-network-ssl-reset-direct-bypass.md)：系统绕过列表；[第二轮](records/2026-10-22-qoder-clash-direct-routing.md)：TUN/fake-ip 下绕过列表失效，运行时 config.yaml 置顶 DIRECT（会被重建清空）；[第三轮根治](records/2026-10-22-qoder-flclash-persistent-direct-rules.md)：写入持久库 rules 表 `qoder.sh/.com/.ai → DIRECT`（`scripts/qoder-flclash-persist.sh` / `qoder-flclash-persist-rollback.sh`）；[第四轮裸 IP](records/2026-10-22-qoder-httpdns-resolved-ip-proxy-reset.md)：SDK 的 HTTPDNS 自解析裸 IP 绕过分流，按 IP 段补 `IP_CIDR 8.208.0.0/12 / 47.57.0.0/16 → DIRECT`（`scripts/qoder-httpdns-ip-direct.sh`） |
| **DNS 污染 / 泄漏** | FlClash 8.8.8.8 污染、ClashX Meta IPv6 DNS 泄漏 |
| **API 报错 / 参数错** | ZCode 400 Invalid request body、ZCode 401 中断 |
| **Antigravity 专项** | [2026-10-22 启动、后端代理、无效更新源、专用进程分流与冷启动验证](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)；历史 Antigravity 400 地域限制记录、FlClash 连通性排查、静默自检/节点探针脚本 |
| **macOS 网络配置** | FlClash DNS 修正与开机自启、ClashX Meta 彻底卸载、Qoder 代理绕过列表（networksetup bypassdomains） |
| **macOS 系统设置 / 系统扩展僵尸弹窗（非应用故障）** | [2026-10-23 互联网账户重新验证 Google 失败，弹窗「好」点击无反应](records/2026-10-23-macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md)：`_NSAlertPanel` 的 `canBecomeKeyWindow=NO` → 窗口可见但按钮永远无效（点击/回车/AXPress 都不生效）；系统设置子系统跑在独立 `.appex`，`pkill -f InternetAccountsSettingsExtension` 即清窗，再完整走 OAuth 恢复。「无法验证账户名或密码」多为授权被取消而非密码错 |
| **验证判据修正** | [2026-10-22 记录](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)：CLI 与桌面后端进程路径、分流规则可能不同，不能互代验收；节点测试只代表当时样本。[2026-10-17 记录](records/2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md)：无认证 400/401 不能判断地域；`generativelanguage` 可用 ≠ Antigravity 可用 |

## 记录格式规范

每篇记录遵循统一结构：

1. **标题** — 长标题，包含报错关键字、根因与结果
2. **基本信息** — 处理者身份、问题类型、报错/解决时间、最终状态、关联仓库
3. **Agent 分工与时间线** — 表格形式，按时间记录各方动作与结论
4. **问题详细描述** — 用户反馈的表象与工作环境
5. **排查过程与关键技术证据** — 分步骤，每步含执行命令、证据发现、结论
6. **根因分析** — 分层归因（直接原因/深层原因/附加现象），含对比表格
7. **解决方案与落地操作** — 可执行的步骤与命令
8. **验证与效果** — 表格形式，逐项列出验证命令、实际结果、状态
9. **经验沉淀与后续建议** — 可复用的教训与最佳实践
10. **关键产物与现场位置** — 配置文件路径、日志位置、关键 ID、关联链接（不含密钥）

## 说明

- 所有记录中的 IP 地址、Trace ID、配置路径均为排查时的真实现场信息，便于回溯
- 涉及密钥、Token、个人隐私的内容已脱敏或省略
- 记录中提到的代理节点名称与实际出口 IP 可能不一致（机场运营商标注问题），以实测 `curl https://ipinfo.io/json` 结果为准
- 各 AI 平台的地域白名单相互独立，不可根据一个平台的可用性类推另一个平台
- **归因判据修正（2026-10-22）**：当现象是「点击无反应」且应用日志中**完全没有对应 RPC**（如 `turn/start` 恒为 0）时，应优先怀疑**客户端 UI 前置校验/按钮禁用**，而不是网络。网络类故障必然会留下超时、连接重置或失败请求；一条请求都没有说明动作在渲染层就被拦下。最便宜的取证手段是**悬停被禁用的按钮读取 tooltip**。参见 [2026-10-22 Codex 桌面版发送禁用](records/2026-10-22-codex-desktop-send-disabled-cloud-env-missing.md)。
- **验证判据修正（2026-10-17）**：`2026-09-04` Antigravity 记录中「无认证 POST 返回 401 = 地域通过」的判据已被实验证伪——在「被拒 IP」上做同样的无认证请求同样返回 401。判断 Antigravity 地区限制请使用带账号真实调用（`scripts/antigravity-silent-check.sh` / `agy -p`）。同理，`generativelanguage` + API Key 的探测结果也不能代表 Antigravity 是否可用。
- **桌面版验证补充（2026-10-22）**：独立 `agy` CLI 不命中桌面 `language_server` 的 `PROCESS-PATH` 规则；使用 CLI 自检时需核对模型、环境及实际代理链。桌面问题应以桌面版真实 Gemini 生成验收，并验证配置重建和正常冷启动。[本次详细记录](records/2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)同时纠正了旧桌面材料对 `ERR_UNSAFE_PORT` 的解释：现场是固定无效更新 URL，而非已证实的随机端口冲突。
- **能力门控判据（2026-10-22）**：「网页端有、桌面端入口消失」不等于账号/地区问题。ChatGPT 桌面版会读取本地 `~/.codex/config.toml`，`orbit`（dot）、`dictation`（听写）、`voice.realtime`、图片生成、朗读等能力带 `requiresFirstPartyInference: true`，会校验 `(model_provider ?? "openai") === "openai"`；`model_provider` 为自定义值时这些入口会被静默隐藏（无报错、无日志）。判别方法：同类入口是否一起消失 + 检查 `model_provider`。参见 [2026-10-22 桌面版 dot 入口消失](records/2026-10-22-chatgpt-desktop-dot-sidebar-missing-custom-model-provider.md)。
- **入口消失的第二种成因（2026-10-22 22:10 补充）**：若 `model_provider` 已是 `openai`、听写仍在，但 dot 入口缺失，多为 **App 启动期网络抖动导致账号能力初始化失败**（日志特征：`ERR_NETWORK_CHANGED` / `ERR_INTERNET_DISCONNECTED`、`Statsig: error while bootstrapping`、`app_start` 耗时 >30s、`Orbit messaging` 事件 0 次）。此类不会自愈（窗口聚焦强制重取无效），网络稳定后完全重启即可，无需改配置；网络侧背景参见 [cf_clearance / 出口 IP 轮换记录](records/2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)。判别口诀：**听写一起没=配置门控；只有 dot 没=启动期初始化失败**。
- **Cloudflare 凭证 / 出口 IP 判据（2026-10-22 ChatGPT 桌面版）**：桌面客户端「刷新成功/失败来回跳、偶发 403」时，先采样出口 IP（`curl https://chatgpt.com/cdn-cgi/trace` 连续 5 次看 `ip=` 是否唯一）。机场 NAT 池 / IPv6 轮换出口会让 Cloudflare `cf_clearance`（按 IP 绑定）反复失效。另：`dscacheutil -q host` 返回真实 IP 而 `dig` 返回 `198.18.x` = DNS 缓存污染（多见于 FlClash/TUN 重启窗口），与机场故障无关；界面出现 `You're out of Codex and Work usage` 则是额度问题。参见 [记录](records/2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)。
- **HTTPDNS / 自解析裸 IP 判据（2026-10-22 第四轮 Qoder）**：客户端「能登录、能拉模型列表，但一发消息就 500 / 会话异常」时，除看域名分流，必须确认它实际连的是主机名还是**自解析裸 IP**（Qoder SDK `networkMode=httpdns`）。判别：同一目标主机名 `curl` 通、`--resolve` 到指定裸 IP 挂即可复现；`DOMAIN-SUFFIX` 规则对裸 IP 不生效，需补 `IP_CIDR` 或启用 sniffer。真实错误看 `~/.qoder/logs/runs/*/qodercli.log` 的 `route_source/resolved_ip/failure_phase`。参见 [第四轮记录](records/2026-10-22-qoder-httpdns-resolved-ip-proxy-reset.md)。
- **持久化判据修正（2026-10-22 第三轮 Qoder）**：Clash/FlClash 的运行时合并配置（config.yaml）会被订阅更新/重启重建，手写进去的规则会丢；自定义分流必须写客户端持久层（FlClash `database.sqlite` 的 rules 表 / GUI 自定义规则 / Override），并在退出客户端后离线写库、重启实证。
- **系统扩展僵尸弹窗判据（2026-10-23）**：macOS 系统设置的子系统（互联网账户等）运行在独立 `.appex` 进程；其弹出的 `_NSAlertPanel` 若留下 `makeKeyWindow … returned NO from -[NSWindow canBecomeKeyWindow]` 日志，则该窗口可见但按钮永远无效（点击、回车、`AXPress` 都不生效）。不要反复点或直接重启，执行 `pkill -f InternetAccountsSettingsExtension`（或强退系统设置）清窗后重走流程即可。另：系统级「无法验证账户名或密码。」通常是 OAuth 授权被取消（先查 Safari `AuthenticationSession` 日志是否 `User closed … canceling session`），不是密码错误。参见 [2026-10-23 记录](records/2026-10-23-macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md)。
