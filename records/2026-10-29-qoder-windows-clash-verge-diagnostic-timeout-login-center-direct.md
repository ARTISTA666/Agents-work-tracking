# Qoder Windows 版「网络诊断五服务全 timeout」+「登录无法连接登录服务」两连挂：Clash Verge fake-ip 分流无 qoder 规则、诊断只测 .com 系漏掉 .sh 登录中心，规则覆写补 qoder.com/qoder.sh DIRECT 后全通（Windows 第五轮，承接 macOS FlClash 四轮）

## 基本信息

- **处理者身份**：Trae 工作台 Agent（GLM-5.3-Flash；主排查、根因定位、最小修复；改动均在订阅规则覆写层，可一键回滚）
- **问题类型**：AI 客户端（Qoder 0.4.11 Windows 版，当天新装机）网络故障；**Clash Verge（mihomo）分流路由问题**，两阶段同一根源
- **承接**：macOS FlClash 四轮（[首轮](records/2026-10-22-qoder-network-ssl-reset-direct-bypass.md) / [第二轮](records/2026-10-22-qoder-clash-direct-routing.md) / [第三轮持久化](records/2026-10-22-qoder-flclash-persistent-direct-rules.md) / [第四轮 HTTPDNS 裸 IP](records/2026-10-22-qoder-httpdns-resolved-ip-proxy-reset.md)）；本机为 Windows 新机 + 新代理客户端（Clash Verge），**历史 DIRECT 规则未随迁移**
- **报错时间**：2026-10-29 13:58 起（Asia/Shanghai，UTC+8）；两阶段：诊断全红 → 补规则 → 诊断全绿 → 登录又挂 → 补规则
- **最终状态**：✅ 已解决。两处 DIRECT 规则 curl 验证通过、网络诊断五服务全绿（1003/1336ms）；15:44 用户完成登录全流程复测（网页验证 → 打开 Qoder），`.qoder-app-status.json` 落盘 `logged_in: true`，Qoder 恢复可用
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### 环境底册（Windows 机，与 macOS 四轮环境完全不同）

| 项 | 值 |
| --- | --- |
| 代理客户端 | Clash Verge 2.5.8（verge-mihomo 内核，**服务模式**，clash-verge-service 托管） |
| 代理入口 | 系统代理 127.0.0.1:7897（注册表 ProxyEnable=1），**无 TUN**；代理不入系统环境变量 |
| DNS 模式 | fake-ip（`198.18.0.0/16`，`listen :53`，ipv6 开启） |
| 控制接口 | **TCP 9097 连接拒绝（实际未监听）**，仅命名管道 external-controller-pipe |
| 订阅 | 「赔钱机场」（远程订阅，自动更新 1440min），当前 profile uid `R9N6t03sxH3I` |
| Qoder | 0.4.11 Windows 版，`D:\Qoder`（当天装机），用户数据 junction 到 `D:\QoderData`；`configAdvancedProxyMode="system"` |

---

## Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 13:58 | 用户 | 首次启动 Qoder 跑网络诊断：foundation/model/messaging/resources/feedback **五服务全部 timeout（4011-4013ms）** |
| 14:05–14:15 | Trae Agent | 核对系统代理在位、Clash Verge 进程与 7897 端口正常；curl 对照：qoder.com **走代理 000×3（exit 35，稳定 5s TLS 失败）/ 直连 200 (0.44s)**、api.qoder.com 直连 401；google/baidu 走代理 200 → 节点活着，是 SNI 级掐断 |
| 14:18 | Trae Agent | 翻运行时 clash-verge.yaml：**无任何 qoder 规则**，qoder.com 落 `GEOIP`/`MATCH → 🐟漏网之鱼` 境外组；alicdn 有 DIRECT 规则但走代理仍 000（Clash 自身 DNS/出口路径问题，旁证不追） |
| 14:20 | 用户 | 询问后拍板「直接动手改」；确认 10-22 macOS 档案里「别动 Clash」指**别卸载**，不适用本次改规则 |
| 14:26 | Trae Agent | 规则覆写 `profiles\rI3pS10CmxzW.yaml` prepend 加 `DOMAIN-SUFFIX,qoder.com,DIRECT`，重启 clash-verge GUI（TCP 控制口没开，只能走 GUI 重启；mihomo 由 service 托管，重启期间代理不断） |
| 14:30 | 用户 | Qoder 重启后复测诊断**仍全红**（model 从 timeout 变 network）——差点误判修复失败 |
| 14:40 前后 | 用户 | 几分钟后再次检测：**全绿**（基础 1003ms / 模型 1336ms）。定性：核心刚重启 DNS 冷缓存 + 探测 4s 硬超时 |
| 14:50 | 用户 | 登录报「无法连接登录服务，请检查网络后重试」（错误码 AUTH_NETWORK），问是不是 Qoder 限制登录设备 |
| 14:55 | Trae Agent | 定性排除设备限制：设备顶号会有明确文案；网页端能正常登录 = 账号侧没问题；这是**又一个网络层故障** |
| 15:07–15:16 | Trae Agent | netstat 抓包两轮：Qoder 进程零直连，mihomo 出站只见机场节点健康检查（AWS 东京 IP 集两次爆发完全一致，**观测陷阱**）；app.asar 翻出 AUTH_NETWORK 等 i18n 但无端点 |
| 15:10–15:16 | Trae Agent | 发现 mihomo 实际监听命名管道（配置文件里的名字已过期），用 PowerShell NamedPipeClientStream + HTTP/1.0 调 `/connections` 拿到全量连接表（域名/进程/分流链/规则）；宽口径监视两轮仍只见 qoder.com（登录页），**失败请求不可见** |
| 15:30 | Trae Agent | **换最便宜的取证：`Get-DnsClientCache`** → `center.qoder.sh → 47.57.243.249`（TTL 736s，刚解析过）。curl：center 直连 **404/0.25s 正常**、走代理 **000/2.2s 失败** |
| 15:32 | Trae Agent | 规则覆写 prepend 再加 `DOMAIN-SUFFIX,qoder.sh,DIRECT`，重启 Verge；center 走代理 **000→404/0.25s**、qoder.com 200、google 302 全验证通过 |
| 15:35 | Trae Agent | 固化 check/apply/rollback 脚本与 mihomo 管道监视脚本，写本轮记录并推送仓库、更新索引 |
| 15:44 | 用户 | 完整登录流程复测**成功**；`.qoder-app-status.json` 落盘 `logged_in: true`（含账号名/头像 URL），本轮终局 |

---

## 问题详细描述

### 阶段一：网络诊断五服务全超时

诊断报告 JSON（13:58）：

```json
{"success": false, "services": [
  {"id": "foundation", "status": "failed", "durationMs": 4013, "errorCode": "timeout"},
  {"id": "model",      "status": "failed", "durationMs": 4011, "errorCode": "timeout"},
  {"id": "messaging",  "status": "failed", "durationMs": 4011, "errorCode": "timeout"},
  {"id": "resources",  "status": "failed", "durationMs": 4011, "errorCode": "timeout"},
  {"id": "feedback",   "status": "failed", "durationMs": 4011, "errorCode": "timeout"}]}
```

特征：**统一 4 秒硬超时**，五服务齐挂。

### 阶段二：诊断全绿后，登录仍报「无法连接登录服务」

登录界面红色提示条「无法连接登录服务，请检查网络后重试」（i18n 错误码 `AUTH_NETWORK`）。用户完整流程：点「立即登录」→ 系统浏览器打开在线验证页 → 网页登录成功 → 浏览器弹「打开 Qoder」协议回调 → Qoder 弹「网络错误」。用户疑问：是不是 Qoder 限制登录设备（账号当前登录在另一台主机上）？

---

## 排查过程与关键技术证据

### 1. 基线核对：代理链本身是好的

```powershell
netsh winhttp show proxy                    # Direct access（不影响 Electron）
Get-ItemProperty 'HKCU:\...\Internet Settings'  # ProxyEnable=1, ProxyServer=127.0.0.1:7897
Get-Process clash-verge, verge-mihomo; Test-NetConnection 127.0.0.1 -Port 7897  # 进程在、端口通
```

### 2. curl 分路径对照（阶段一定位根因）

| 目标 | 走代理 7897 | 直连 | 结论 |
| --- | --- | --- | --- |
| qoder.com | **000（exit 35）×3，稳定 5.0s** | **200 / 0.44s** | SNI 级 TLS 掐断，非偶发 |
| api.qoder.com | 000 | 401 / 0.29s（未带凭证的正常拒绝） | 直连完全可达 |
| www.google.com | 200 / 1.7s | — | 节点本身活着 |
| www.baidu.com | 200 / 0.24s | — | 同上 |
| img.alicdn.com | **000 / 5.0s（exit 35）** | — | 阿里系同病旁证 |

### 3. 规则面取证：qoder 零规则

运行时 `clash-verge.yaml`（463KB 合并产物）grep `qoder` = 0 条；末段规则为 `GEOIP,cn,DIRECT` ×2 + `MATCH,🐟漏网之鱼`。qoder.com 解析为阿里云 GA（非 CN IP）→ 落漏网之鱼 → 境外节点 → **阿里系后端对境外出口的 TLS 握手 RST**（与 macOS 首轮/二轮结论一致）。

### 4. 阶段二：静态翻包全部落空

- `app.asar`（189MB）正则挖端点：仅 `api/docs/download.qoder.com`、`static/example.vpc.qoder.com.cn`、`test.qoder.ai`，**无 center/api3/repo2**（.sh 系域名来自服务端下发的 `User\region-config-cache.json`：`api3.qoder.sh` 推理、`repo2.qoder.sh` 代码库）；`AUTH_NETWORK` 只命中 i18n 文案块，错误弹窗文案「网络错误」甚至来自远程登录页，本地无痕。
- Qoder 设置 `configAdvancedProxyMode="system"`、`proxyURL=""`——主进程 Electron 网络层**跟随系统代理**。
- Qoder 本地 `logs/` 目录为空（未落盘）。

### 5. 观测陷阱：netstat 抓到的 AWS 爆发是机场健康检查

两轮 netstat 监视（含 Qoder 全部 PID + mihomo PID）中，mihomo 在 14:52:49 与 15:07:50 各爆发一次 **12+ 个 AWS 东京 IP 的 SynSent**，两组 IP 集 8/10 完全一致（18.183.x/35.78.x/13.230.x/43.207.x/3.112.x…），间隔 15 分钟——这是 mihomo 对机场节点的 **url-test 健康检查**，不是应用流量。Qoder 自身经系统代理的连接对 netstat 只表现为 `127.0.0.1:7897`，无信息量；其直连请求（Node 层）为零。

### 6. 命名管道调 mihomo API（TCP 控制口未开的替代方案）

配置里 `external-controller: 127.0.0.1:9097` 实测**连接拒绝**（未监听），真身是管道，且**配置文件里的管道名已过期**：

```powershell
[System.IO.Directory]::GetFiles('\\.\pipe\') | Where-Object { $_ -match 'mihomo' }
# \\.\pipe\verge-mihomo-production-19e5ce549ce999c2...（配置写的是 sidecar-release-...，作废）
```

用 `NamedPipeClientStream` 发原始 HTTP（**必须 HTTP/1.0**，HTTP/1.1 响应是 chunked，PS 5.1 解析会炸）：

```powershell
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, 'InOut')
$pipe.Connect(2000)
"GET /connections HTTP/1.0`r`nHost: localhost`r`nAuthorization: Bearer $secret`r`n`r`n"
# 返回全量连接：metadata.host / destinationIP / processPath / chains / rule
```

两轮宽口径监视（host 含 qoder / 目标 AWS 段 / rule=Match，100ms 轮询去重）仍只抓到登录页的 `qoder.com → DIRECT`——**失败请求要么太快、要么在 mihomo 记录前就死了**。此路取证成本高、抓不全。

### 7. 最便宜的取证一击命中：系统 DNS 缓存

```powershell
Get-DnsClientCache | Where-Object { $_.Entry -match 'qoder' }
# center.qoder.sh   47.57.243.249   TTL 736s   ← 刚被解析过，登录流量的真实目标
```

```powershell
curl.exe --max-time 10 https://center.qoder.sh            # 直连: 404 / 0.25s ✅（API 根路径 404 = 可达）
curl.exe -x http://127.0.0.1:7897 --max-time 10 https://center.qoder.sh   # 走代理: 000 / 2.2s ❌
```

---

## 根因分析

| 层 | 归因 |
| --- | --- |
| **直接原因** | Clash Verge 分流规则**没有任何 qoder 条目**：阶段一 `qoder.com` 落 `MATCH → 🐟漏网之鱼` 境外组被 TLS 掐断；阶段二登录中心是**另一个域 `center.qoder.sh`**（.sh 不在 .com 规则内），同样被掐。直连全部正常（国内可达的阿里云 GA 后端） |
| **深层原因** | **换机/换客户端规则迁移缺口**：macOS FlClash 四轮已把 `qoder.sh/.com/.ai → DIRECT` 写进持久库根治，但 Windows 新机装的是 Clash Verge + 独立订阅，历史规则没有跟过来；订阅自带规则也无 qoder |
| **为什么诊断全绿登录还挂** | Qoder 的诊断只探测 `.com` 系五个服务；登录中心在 `.sh` 域。**域名分散 + 诊断覆盖不全**，「诊断全绿」≠「全功能可用」 |
| **为什么首轮补规则后诊断还红** | mihomo 刚重启、DNS 冷缓存，首批探测在 4s 硬超时内没跑完；几分钟缓存热了即全绿。**改完规则先重测，别急着判失败** |
| **设备限制假设** | 排除。设备顶号有明确文案；网页端同一账号登录成功；报错是 `AUTH_NETWORK`（连不上登录服务），纯网络层 |

---

## 解决方案与落地操作

思路：与 macOS 四轮同构——**把 qoder 全系域名在规则最顶上强制 DIRECT**；Windows Clash Verge 的正确持久层是**订阅的规则覆写文件**（Verge 会在订阅更新时重新合并，覆写文件不会被冲掉），改完重启 Verge GUI 重新生成运行时配置。

### 步骤 1：编辑规则覆写（幂等，持久）

文件：`%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\rI3pS10CmxzW.yaml`（当前订阅的 rules 增强，`prepend: []` 原为空）

```yaml
prepend:
  - DOMAIN-SUFFIX,qoder.com,DIRECT
  - DOMAIN-SUFFIX,qoder.sh,DIRECT
```

> 注意：覆写文件 uid 随订阅而变（`rI3pS10CmxzW` 是「赔钱机场」的），通用做法是读 `profiles.yaml` 的 `current` → 对应 item 的 `rules` 字段定位（已封装进仓库脚本）。

### 步骤 2：重启 Clash Verge 使其重新合并配置

```powershell
Stop-Process -Name clash-verge -Force; Start-Sleep 2
Start-Process 'C:\Program Files\Clash Verge\clash-verge.exe'; Start-Sleep 9
```

mihomo 内核由 clash-verge-service 托管，GUI 重启期间系统代理与既有连接不断。重启后运行时 `clash-verge.yaml` 可见新规则（qoder.com 在第 1502 行，位于所有 MATCH 之前）。

### 步骤 3：分路径验证

```powershell
curl.exe -x http://127.0.0.1:7897 https://qoder.com        # 000 → 200 / 0.5s
curl.exe -x http://127.0.0.1:7897 https://api.qoder.com    # 000 → 401 / 0.29s（可达）
curl.exe -x http://127.0.0.1:7897 https://center.qoder.sh  # 000 → 404 / 0.25s（可达）
curl.exe -x http://127.0.0.1:7897 https://www.google.com   # 302，外网分流不受影响
```

### 回滚

从覆写文件 `prepend:` 里删掉对应两行（或整文件还原为 `prepend: []`）再重启 Verge 即可；订阅本体与节点配置零改动。仓库脚本：`scripts/qoder-win-clash-verge-direct.ps1 check|apply|rollback`（自动定位当前订阅覆写文件、时间戳备份、幂等去重）。

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| qoder.com 走代理 | 000（exit 35）×3 | 200 / 0.43–0.50s | ✅ |
| api.qoder.com 走代理 | 000 | 401 / 0.29s | ✅ |
| center.qoder.sh 走代理（登录中心） | 000 / 2.2s | 404 / 0.25s | ✅ |
| 网络诊断（Qoder 内置） | 5 服务全 timeout | **全绿，基础 1003ms / 模型 1336ms** | ✅ |
| www.google.com 走代理 | 200/302 | 302 / 1.2s | ✅ 不受影响 |
| 系统代理 / 订阅 / 节点 | — | 未动 | ✅ |
| 登录全流程（网页验证 → 打开 Qoder） | AUTH_NETWORK「网络错误」 | **登录成功**，`logged_in: true`（15:44 落盘验证） | ✅ |

---

## 经验沉淀与后续建议

1. **换机/换代理客户端必须迁移 DIRECT 白名单**：macOS 四轮根治的规则（qoder.sh/.com/.ai）没有跟到 Windows Clash Verge，同根源问题完整重演一遍。迁移清单应包含：订阅覆写规则 + 持久化 IP 段（第四轮的 `IP_CIDR 8.208.0.0/12 / 47.57.0.0/16`，本机 mihomo 若启用 HTTPDNS 同样会踩，**暂未写入，复发时按第四轮脚本补**）。
2. **「诊断全绿但某功能挂」= 域名分散**：Qoder 端点分散在 `qoder.com / qoder.com.cn / qoder.sh` 三系，诊断只覆盖 .com 系。最便宜的取证是 **`Get-DnsClientCache`**——失败请求在 mihomo 连接表里抓不到，但 DNS 解析一定留痕（承接第四轮 HTTPDNS 判据的 Windows 版）。
3. **Windows mihomo 控制口的正确打开方式**：Clash Verge 服务模式下 TCP 控制口可能根本不监听，只有命名管道；管道名以 `[System.IO.Directory]::GetFiles('\\.\pipe\')` 实测为准（配置文件里的名字会过期）；用 `NamedPipeClientStream` + **HTTP/1.0**（1.1 的 chunked 响应 PowerShell 解析不了）即可使用 `/connections` `/rules` 等 API。
4. **netstat 观测陷阱**：mihomo 的 url-test 会对节点服务器定期（15min）爆发一批 SynSent（AWS 东京 IP 集高度稳定），与「应用连不上」时间上可能重叠，鉴别方法是对比两次爆发 IP 集是否一致。Qoder 经系统代理的流量对 netstat 只是 127.0.0.1:7897，无信息量。
5. **改完规则先重测 1-2 次**：核心重启 → DNS 冷缓存 → 4s 硬超时探测先红后绿，别在首轮红时就回滚或换方向。
6. **PS 5.1 写 .ps1 的编码坑（本机档案已两次踩）**：含中文的脚本必须 UTF-8 带 BOM；本仓库两个新脚本注释用纯 ASCII 规避。

---

## 关键产物与现场位置（不含密钥）

- Clash Verge 数据目录：`%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\`（`profiles.yaml` 当前订阅 uid、`profiles\rI3pS10CmxzW.yaml` 规则覆写、`clash-verge.yaml` 运行时合并产物、`dns_config.yaml` fake-ip 配置、`logs\latest.log`）
- mihomo 命名管道：`\\.\pipe\verge-mihomo-production-19e5ce549ce999c2bfbc92e6eadef850e85319861b036fa5667df80df4412617`（secret 从运行时配置读取，不落仓库）
- Qoder 数据：`D:\QoderData\.qoder`（settings）、`D:\QoderData\Roaming_Qoder\User\`（`settings.json` 代理模式、`region-config-cache.json` 含 api3/repo2.qoder.sh 节点、`error-code-cache.json`）
- 关键域名：`qoder.com`（诊断五服务）、`center.qoder.sh`（登录中心，阿里云 GA）、`api3/repo2.qoder.sh`（推理/代码库节点，本轮未单独处理）
- 仓库脚本：
  - [`scripts/qoder-win-clash-verge-direct.ps1`](scripts/qoder-win-clash-verge-direct.ps1)：check / apply / rollback，自动定位当前订阅覆写文件、时间戳备份、幂等（apply 后自动重启 Verge 并 curl 验证）
  - [`scripts/qoder-win-mihomo-pipe-watch.ps1`](scripts/qoder-win-mihomo-pipe-watch.ps1)：TCP 控制口未开时经命名管道轮询 `/connections`，过滤 qoder/AWS/兜底组流量并去重落盘

*第五轮结论：Windows Clash Verge 与 macOS FlClash 病同名、药同方——qoder 全系域名 DIRECT；诊断绿灯不代表全功能可用，登录中心在诊断覆盖之外的 .sh 域；换机先搬规则，取证先查 DNS 缓存。*
