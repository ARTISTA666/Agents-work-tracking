# Qoder 模型服务连接被中断的真身：Agent SDK 走 HTTPDNS 拿到裸 IP 直连，mihomo 匹配不到域名规则落代理节点被 RST；把阿里云亚太裸 IP 段写入 FlClash 持久库 IP_CIDR→DIRECT（第四轮，接第三轮域名层之后）

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（用户指派接手；主排查、根因定位、最小修复；改动前均备份，保留回滚）
- **问题类型**：AI 客户端（Qoder 0.4.8）真实对话不可用；**HTTPDNS 裸 IP 触发的分流盲区**
- **承接**：
  - 首轮 `2026-10-22-qoder-network-ssl-reset-direct-bypass.md`（系统绕过列表）
  - 第二轮 `2026-10-22-qoder-clash-direct-routing.md`（运行时 config.yaml 置顶 DIRECT）
  - 第三轮 `2026-10-22-qoder-flclash-persistent-direct-rules.md`（持久库 `DOMAIN_SUFFIX qoder.sh/.com/.ai → DIRECT`）
- **本轮报错时间**：2026-10-22 15:19–15:32（Asia/Shanghai）
- **最终状态**：✅ 已解决。网络层定位并持久化修复（裸 IP 实测由 ECONNRESET 变 200），用户实发消息确认 Qoder 真实对话恢复可用。
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 15:19 | 用户 | 反馈「还是没有解决」，Qoder 真实对话弹「系统发生异常，请重试」 |
| 15:20 | Harness Agent | 接手。先复验第三轮成果：`DOMAIN_SUFFIX qoder.sh/.com/.ai → DIRECT` 在位、`openapi.qoder.sh` 连接链为 DIRECT、主机名请求 20/20 通 → **域名层是好的，问题在别处** |
| 15:24 | Harness Agent | 读 Qoder 应用日志：用户 15:19:34 那条消息确实失败（`QODER_EXECUTION_CONTROL_FAILED` / `API Error: The connection to the model service was interrupted.`） |
| 15:26 | Harness Agent | 找到此前未使用的关键日志 `~/.qoder/logs/runs/<run>/qodercli.log`，直接看到 `POST https://api3.qoder.sh/algo/api/v2/service/pro/sse/agent_chat_generation failed: ECONNRESET`、`center.qoder.sh ... ECONNRESET` |
| 15:30 | Harness Agent | 读失败请求的网络轨迹：`route_source: 'httpdns'`、`route_kind: 'resolved-ip'`、`resolved_ip: '8.222.76.136'`、`failure_phase: 'response_headers'` → 定位到「裸 IP 连接」这一层 |
| 15:33 | Harness Agent | 实测对照：主机名访问 200/20 次 0 失败；`curl --resolve ...:8.222.76.136` 必失败(000)。用「重试」再发一次真实消息，13 次重试全 ECONNRESET，最终 `resultErrorCode: 500` |
| 15:36 | Harness Agent | 运行时验证两条候选修法：① 裸 IP 段 `IP-CIDR→DIRECT`；② 开启 mihomo sniffer。两者均让裸 IP 请求变 200 |
| 15:41 | Harness Agent | 选型：写入持久库 `IP_CIDR,8.208.0.0/12 → DIRECT`、`IP_CIDR,47.57.0.0/16 → DIRECT`（每个 profile 各两条），重启 FlClash 后规则仍在、裸 IP 实测 200 |

---

## 问题详细描述

第三轮把 `qoder.sh` 域名写进 FlClash 持久库并验证「控制面全绿」，但用户真实发消息仍然弹「系统发生异常」。第三轮记录本身也标注了「真实模型对话轮次需用户实发确认」——本轮就是补上这一步，结果**它失败了**。

失败消息（会话 `2c76efee-…`，turn `d1dcee04-…`）在应用数据库里的落库结果：

```json
{"failureReason":"Sorry, something went wrong. Please try again. Report Issue (input /feedback)",
 "resultErrorCode":500,
 "durationMs":204663}
```

界面表现：`系统发生异常 / 请重试。如问题持续存在，可点击右下角反馈按钮向我们报告。`

---

## 排查过程与关键技术证据

### 1. 先证伪「域名分流没修好」

```bash
curl .../rules | head -3        # DomainSuffix qoder.sh/.com/.ai -> DIRECT（在位）
curl .../connections | grep qoder
# openapi.qoder.sh | DomainSuffix qoder.sh | DIRECT
for h in openapi api1 api2 api3 center.qoder.sh; do 20 次 TLS 请求; done
# 五个主机 ok=20 fail=0
```

结论：域名（fake-IP）路径完全正常，问题不在第三轮修的那一层。

### 2. 关键日志：Qoder 自己的运行日志直接写明失败请求与错误码

此前几轮都只看 `~/Library/Application Support/com.qoder.app.stable/logs/`（主进程日志），本轮找到 Agent SDK 的运行日志目录 `~/.qoder/logs/runs/<run>/qodercli.log`，里面有完整的网络请求轨迹：

```
ERROR [API Error] POST https://api3.qoder.sh/algo/api/v2/service/pro/sse/agent_chat_generation failed: ECONNRESET
ERROR [API Error] GET  https://center.qoder.sh/algo/api/v3/service/region/endpoints failed: ECONNRESET
WARN  [qoder-server-request] <-- FAILED operation=sendRemoteChatAsk method=POST host=api3.qoder.sh ... error=Network attempt failed at response_headers
```

> 判据修正：**模型服务的真实错误在 `~/.qoder/logs/runs/*/qodercli.log`**，应用日志里只有笼统的「connection to the model service was interrupted」。排 Qoder 类问题应先看这份日志。

### 3. 失败请求的网络轨迹：它连的是「裸 IP」，不是主机名

失败请求自带的 stages 明细（节选）：

```json
{ "stage": "physical_send", "route_source": "httpdns", "route_kind": "resolved-ip",
  "resolved_ip": "8.222.76.136", "transport_timing": "undici" },
{ "stage": "physical_send_error", "failure_phase": "response_headers", "elapsed_ms": 2670 }
```

一次运行里 `route_source` 统计：`httpdns=34`、`fallback=8`、`system-dns=2`；
出现过的 resolved_ip：`8.222.76.136`、`8.222.84.63`（阿里云新加坡）、`8.212.124.35`（阿里云亚太）、
`47.57.243.249`（阿里云香港），以及 `47.103.x / 39.107.x / 39.108.x / 47.106.x / 106.14.x / 120.79.x / 101.132.x`（国内段）。

### 4. 对照实验：同一目标「主机名通、裸 IP 挂」

```bash
# 主机名（fake-IP → 命中 DOMAIN-SUFFIX → DIRECT）
curl -o /dev/null -w '%{http_code}\n' https://api3.qoder.sh/algo/api/v1/ping          # 200
# 裸 IP（mihomo 只能按 IP 匹配 → 落 MATCH → 🐟漏网之鱼 → 代理节点）
curl --resolve api3.qoder.sh:443:8.222.76.136 https://api3.qoder.sh/algo/api/v1/ping  # 000 / ECONNRESET
curl --resolve api3.qoder.sh:443:8.222.84.63  https://api3.qoder.sh/algo/api/v1/ping  # 000 / ECONNRESET
```

### 5. 运行时验证候选修法（两种都可行，最终选持久库）

```bash
# 方案A：裸 IP 段 → DIRECT（写入运行时配置后立即生效）
IP=8.222.76.136 ... -> HTTP 200 t=0.19s     # 修前 000
# 方案B：mihomo sniffer 嗅探 TLS SNI 后按域名重匹配
IP=8.222.76.136 ... -> HTTP 200 t=0.35s
```

选型：FlClash 的运行时 `config.yaml` 会被订阅/重启重建（第三轮已证），sniffer 开关不在其可持久层（`patchClashConfig` 无该字段）；
而 `database.sqlite.rules` 是第三轮已验证的持久层，故采用**方案A 落持久库**。

---

## 根因分析

| 层级 | 归因 |
| --- | --- |
| 直接原因 | Qoder Agent SDK（`networkMode=httpdns`）对 `api3/center/openapi.qoder.sh` 自行解析成**裸 IP** 后直连；mihomo 对裸 IP 连接只能按 IP/GEOIP 匹配，命中不了 `DOMAIN-SUFFIX qoder.sh → DIRECT`，落 `MATCH → 🐟漏网之鱼` 代理节点，TLS 被重置（ECONNRESET），模型 SSE 请求在 response_headers 阶段失败 |
| 复发原因（相对第三轮） | 第三轮只修了「域名路径」；HTTPDNS/自解析产生的裸 IP 路径不在其覆盖范围，故第三轮验收「控制面全绿」仍不能代表真实对话可用 |
| 深层原因 | Qoder 把「控制面 + 模型流」混在两条不同的连接方式上：控制面走主机名、模型流走自解析裸 IP；只要分流规则只覆盖域名，就会出现「能登录、能拉模型列表、一发消息就 500」的割裂现象 |
| 为什么之前几轮看不出来 | 应用日志只给笼统的 `connection to the model service was interrupted`；真实请求地址/解析方式/失败阶段只写在 `~/.qoder/logs/runs/*/qodercli.log` |

### 判别特征（下次可直接套用）

1. Qoder 能打开、能显示模型列表、能登录，但**一发消息就「系统发生异常」**；
2. 应用日志 `resultErrorCode: 500` + `QODER_EXECUTION_CONTROL_FAILED`；
3. `~/.qoder/logs/runs/*/qodercli.log` 出现 `POST .../agent_chat_generation failed: ECONNRESET`，且同请求 `route_source` 为 `httpdns`/`system-dns`、`route_kind: resolved-ip`；
4. 同主机 `curl` 用**主机名**通、用 `--resolve` 指定裸 IP 挂 → 即分流规则只覆盖了域名、没覆盖裸 IP。

---

## 解决方案与落地操作

把 Qoder 实际会连接的境外裸 IP 段写入 FlClash **持久库** `database.sqlite` 的 `rules` 表：

| rule_action | content | rule_target | no_resolve | order |
| --- | --- | --- | --- | --- |
| `IP_CIDR` | `8.208.0.0/12`（阿里云亚太 8.208–8.223） | `DIRECT` | 1 | 03 |
| `IP_CIDR` | `47.57.0.0/16`（阿里云香港） | `DIRECT` | 1 | 04 |

> 国内段（8.212 之外那些 47.103/39.107/47.106/106.14/120.79/101.132）本来就走 `GEOIP,cn → DIRECT`，无需单列。
> 为每个 profile 都插入，避免切订阅后失效。

仓库脚本：`scripts/qoder-httpdns-ip-direct.sh`

```bash
bash qoder-httpdns-ip-direct.sh check      # 只读诊断：持久库规则 + /rules + 裸 IP 实测
bash qoder-httpdns-ip-direct.sh apply      # 备份 → 退出 FlClash → 幂等写库 → 重启 → 校验
bash qoder-httpdns-ip-direct.sh rollback   # 删除本轮 IP 规则并重启
```

说明：

- 必须**退出 FlClash 后离线写库**（运行中内存会回写覆盖，第三轮已踩过）；
- DB 枚举为下划线风格：`DOMAIN_SUFFIX` / `IP_CIDR`，构建后变 mihomo `DomainSuffix` / `IPCIDR`；
- 写完重启 FlClash，由客户端自己把规则构建进配置，跨重启/订阅刷新不丢。

### 回滚

1. `bash scripts/qoder-httpdns-ip-direct.sh rollback`；
2. 或用脚本备份 `scripts/backup/httpdns-<时间戳>/database.sqlite.bak` 覆盖回库后重启 FlClash。

---

## 验证与效果

| 验证项 | 结果 | 状态 |
| --- | --- | --- |
| 域名层（第三轮） | `DomainSuffix qoder.sh/.com/.ai → DIRECT` 仍在位，主机名 20/20 通 | ✅ |
| 裸 IP 轨迹定位 | 失败请求 `route_source=httpdns`、`resolved_ip=8.222.76.136`、`failure_phase=response_headers` | ✅ |
| 修前裸 IP 实测 | `8.222.76.136` / `8.222.84.63` → 000（ECONNRESET） | ❌→ |
| 持久库写入 | `rules` 表 4 条 `IP_CIDR→DIRECT`（2 profile × 2 段），order 03/04 | ✅ |
| 重启 FlClash 后规则仍在 | `/rules` 第 3–4 位 `IPCIDR 8.208.0.0/12 / 47.57.0.0/16 → DIRECT` | ✅ |
| 修后裸 IP 实测 | `8.222.76.136` → 200（0.77s）、`8.222.84.63` → 200（0.52s） | ✅ |
| 模型流端点首包 | `POST .../sse/agent_chat_generation`（裸 IP）→ 200 且保持 SSE | ✅ |
| 其他流量 | 域名规则、国内 GEOIP、Antigravity PROCESS-PATH 等规则未改动 | ✅ |
| **真实模型对话轮次** | ✅ 用户实发消息确认 Qoder 已可正常使用（19:0x 反馈「Coder 现在可以了」） | ✅ |

> 备注：本轮修复的是「连接被 RST」；控制面与裸 IP 通路均已实测 200，最终由用户实发消息验收通过。
> 验收方法备注：Qoder 的聊天输入框是自绘 web 编辑器，后台 AXPress 会被 Chromium 吞掉；不要为此抢占用户鼠标——让用户点一次「重试/发送」比注入全局鼠标事件更可靠。

---

## 边界说明：与同日 ChatGPT 故障无关

当天 19:00 用户反馈「GPT 的网也出现问题了」。经规则作用域与时间线双重核对，**与本轮 Qoder 修复无关**：

- 本轮新增的持久规则只有两条：`IP_CIDR,8.208.0.0/12,DIRECT`、`IP_CIDR,47.57.0.0/16,DIRECT`（阿里云亚太/香港），**不包含任何 OpenAI / Cloudflare 网段**；
- ChatGPT 域名实时命中仍是 `DomainSuffix chatgpt.com → 🤖AI网站 → 美国节点`，未被改动；
- 时间线：本轮改动 15:40；ChatGPT 最后正常 turn-complete 16:00；Cloudflare 挑战风暴出现在 19:00–19:06。

ChatGPT 侧的独立故障（cf_clearance 与出口 IP 轮换不同步 + 一次 DNS 缓存污染 + 额度耗尽）另见
[2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md](2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)。
为写持久规则/固定代理节点，期间重启过 FlClash；重启窗口可能造成一次 DNS 缓存污染（已在另篇记录判据），与本轮规则改动本身无关。

## 经验沉淀与后续建议

1. **「控制面通」≠「模型可用」**：Qoder 的控制面和模型流可能走不同连接方式（主机名 vs 自解析裸 IP）。验收必须实发一条消息看到回复，不能只看 `/connections`、200 计数。
2. **HTTPDNS/自解析是分流盲区**：任何「App 自己解析域名再连 IP」的客户端，`DOMAIN-SUFFIX` 规则都可能失效；要么按 IP 段补规则，要么开 sniffer 让规则匹配 TLS SNI。
3. **Qoder 的真实错误日志在 `~/.qoder/logs/runs/<run>/qodercli.log`**：包含请求 URL、route_source、resolved_ip、failure_phase、底层错误码，是排 Qoder 网络问题的第一现场。
4. **「一发消息就 500」时先分三问**：域名通吗（修好没）、裸 IP 通吗（分流覆盖没）、服务端 500 还是连接断（`failure_phase` 区分 response_headers 还是 connect）。
5. 改 FlClash 仍遵守第三轮铁律：**退客户端 → 写持久库 → 重启实证**；运行时 `config.yaml` 只做临时验证。
6. 若后续 Qoder 升级后 httpdns 池出现新的境外段：先 `grep resolved_ip ~/.qoder/logs/runs/*/qodercli.log` 取全量 IP，再按 CIDR 补规则；或者启用 FlClash 的嗅探（sniffer）一劳永逸（但当前版本其开关不可由持久库直接固定，需在 GUI 侧配置）。

---

## 关键产物与现场位置（不含密钥）

- FlClash 持久库：`~/Library/Application Support/com.follow.clash/database.sqlite`（`rules` 表），运行时配置 `config.yaml`（会被重建，勿手改持久化）
- Qoder SDK 运行日志（本轮关键）：`~/.qoder/logs/runs/<run>/qodercli.log`
- Qoder 应用日志：`~/Library/Application Support/com.qoder.app.stable/logs/<session>/{main.log,collaboration.log}`、`qodercli/qoder-agent-sdk.log`、`qodercli/sessions/<id>.log`
- Qoder 会话落库：`~/Library/Application Support/com.qoder.app.stable/main.sqlite`（`chat_session_messages.payload_json` 里有 `resultErrorCode`）
- 失败会话：`2c76efee-88c6-42b7-87bd-73f2ebc81191`（turn `d1dcee04-…`、`0327cb9c-…`）
- 仓库脚本：`scripts/qoder-httpdns-ip-direct.sh`（check/apply/rollback）
