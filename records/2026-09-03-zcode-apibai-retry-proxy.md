# ZCode 调用 api.b.ai 频繁 401 中断：本地自动重试中转与 chunked 协议 Bug 修复

## 基本信息

- **问题类型**：AI 编程工具 ZCode 经第三方中转 `api.b.ai` 调用 `glm-5.3-flash` 时间歇性 `401 auth_failed` 导致对话中断；为其增加自动重试时，初版本地中转又引入了一个 HTTP chunked 协议级 Bug
- **参与 Agent（多代理协作）**：
  - **Doubao**：主排查、根因定位、本地重试中转初版实现与常驻部署；事后审阅修正版、独立回归验证、归档
  - **ChatGPT（GPT）**：定位初版中转的 chunked 协议级 Bug 并产出修正版脚本
- **解决确认时间**：2026-09-03 05:39（Asia/Shanghai，UTC+8）
- **对应 UTC 时间**：2026-09-02 21:39 UTC
- **最终状态**：已解决（自动重试生效，协议 Bug 修复并通过回归测试）

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责 Agent | 关键动作 |
| --- | --- | --- |
| 2026-09-02 白天 | Doubao | 排查并清理 FlClash 与 ClashX Meta 双代理冲突；确认 ClashX Meta 的 TUN 分流；定位 Antigravity “User location is not supported” 为节点地区问题并切到新加坡 |
| 2026-09-02 下午 | Doubao | 把 ZCode 的 401 定位为 `api.b.ai` 内部鉴权服务间歇性超时（与梯子/密钥无关）；确认 ZCode 内置重试不覆盖 401 |
| 2026-09-02 15:16–15:22 | Doubao | 实现本地重试中转初版、launchd 常驻、把 B.AI provider 的 baseURL 指向本地并实测重试成功 |
| 2026-09-02 16:25–16:26 | ChatGPT（GPT） | 发现初版“已输出部分 SSE 后上游断流会被错误重试、导致 chunked 响应损坏”的协议级 Bug，产出修正版 `apibai_retry_proxy_fixed.py` 并替换上线 |
| 2026-09-03 05:37–05:39 | Doubao | 审阅修正版改动、重启服务、编写并运行断流回归测试（T1/T2 全部通过）、归档到本仓库 |

## 问题详细描述

用户在 macOS 上同时使用代理（ClashX Meta，TUN 分流，国外走新加坡节点）和两个 AI 编程工具 ZCode、Google Antigravity。代理侧问题解决后，ZCode 出现：

```
Turn execution failed provider=374fb4ad-... model=glm-5.3-flash
reason=auth_failed status=401 retryable=false Unauthorized
```

特点是：有的对话重试能成功，有的稳定 401。用户希望“失败自动重试 5 次，仍失败再中断”。

## 根因定位（Doubao）

### 1. 401 来自第三方中转内部故障，与梯子和密钥无关

报错 provider 的 baseURL 是第三方聚合中转 `https://api.b.ai/v1`。用同一密钥连续压测：

- `GET /v1/models` 稳定 200，密钥有效且包含 `glm-5.3-flash`；
- 连续多次推理请求约一半成功、一半在约 10.7 秒后返回 401；
- 失败响应体固定为其内部 K8s 鉴权服务调用超时：

```
鉴权服务请求失败: Post
"http://ainft-chat-service.apenft-market-production.svc.cluster.local:3210/v1/internal/auth/verify":
context deadline exceeded
```

即上游把“内部鉴权微服务临时超时”伪装成了 HTTP 401，属于间歇性服务端故障。

### 2. ZCode 内置重试不会重试 401

在 ZCode 核心包中检索到重试逻辑：虽然存在环境变量 `ZCODE_MODEL_RETRY_MAX_RETRIES` / `ZCODE_MODEL_RETRY_BASE_DELAY_MS` / `ZCODE_MODEL_RETRY_BACKOFF_FACTOR`，但其可重试状态码白名单写死为：

```js
isRetryable = n===408 || n===409 || n===429 || n>=500
```

**401 一律判定为不可重试**，因此仅调环境变量无法满足需求。

## 解决方案：本地重试中转（Doubao 初版）

在 ZCode 与 `api.b.ai` 之间增加一个只监听 `127.0.0.1:18900` 的本地中转（Python3 标准库实现，脚本见 `scripts/apibai-retry-proxy.py`）：

- ZCode 中 B.AI provider 的 baseURL 由 `https://api.b.ai/v1` 改为 `http://127.0.0.1:18900/v1`，其余 7 个 provider 不动；
- 首次失败后最多再重试 5 次（共 6 次尝试），1s 起指数退避、封顶 12s；
- 仅对“伪 401（响应体含 `鉴权服务/ainft-chat-service/context deadline` 等内部故障特征）、429、5xx、网络抖动”重试；真正的密钥错误、400 参数错误立即透传，不空等；
- 成功响应（含 SSE 流式）原样透传；
- 用 launchd 托管（`~/Library/LaunchAgents/com.yusong.apibai-retry.plist`），登录自启、崩溃自动拉起。

实测连打 5 次流式请求全部成功，日志可见两次正是由 401 自动重试到 200。

## 初版的协议级 Bug（GPT 发现并修复）

### 现象

ZCode 端出现：`Invalid character in chunk size`。

### 机理

初版在“已经向 ZCode 写回 `HTTP/1.1 200` 和部分 SSE 数据”之后，如果上游随后断流或超时，异常会被外层统一的 `except` 捕获并再次发起请求；随后又把**第二个** `HTTP/1.1 200 ...` 状态行写进**第一个** chunked 响应体里。客户端按 chunked 解析时，把状态行开头的字母 `H` 当作 chunk 长度，于是报 `Invalid character in chunk size`，同时还可能造成内容重复。

### 修复方式（修正版）

- 增加 `_downstream_started` 标志：在 `_stream_back` / `_return_buffered` 一旦开始向下游写响应时置为真；
- 异常分支中若发现响应已经开始输出，**不再重试整个请求**，而是设置 `close_connection = True` 关闭当前连接，让客户端明确感知流中断、由客户端自行决定是否重发完整请求；
- 响应开始输出之前的故障（伪 401/429/5xx/连接失败）仍按原策略自动重试；
- 逐跳头集合补充 `trailer`。

## 结果验证（Doubao 独立回归）

对部署的修正版用 mock 上游做了两组针对性测试：

- **T1 输出部分 SSE 后上游断流**：断言“只产生 1 个 HTTP 响应、对上游只发起 1 次请求、已发送的数据保留、随后关闭连接”。结果 PASS，日志为“下游响应已开始……不再重试并关闭连接”，`Invalid character in chunk size` 根除；
- **T2 输出响应头之前连续断连 2 次、第 3 次成功**：断言仍会自动重试并最终成功（上游被请求 3 次）。结果 PASS，证明修复没有破坏既有重试能力；
- 另验证：健康检查 `http://127.0.0.1:18900/__retry_proxy_health` 返回 `{"status":"ok"}`；OpenAI `/v1/chat/completions` 与 Anthropic `/v1/messages` 两种协议路径流式均正常；launchd 杀掉进程后可在数秒内自动拉起。

## 结论

### 已确认

1. ZCode 的间歇 401 根因是第三方中转 `api.b.ai` 内部鉴权服务超时，非本地代理或密钥问题；
2. ZCode 内置重试不覆盖 401，需要本地中转实现“伪 401 自动重试 5 次”；
3. 初版中转在“响应已开始后断流”时错误重试，造成 chunked 帧损坏；修正版改为“一旦输出即不重试、只关闭连接”，回归测试通过。

### 经验与复用顺序

1. 给“状态码不可重试但实为临时故障”的上游做重试时，必须区分“响应头/响应体是否已经开始下发”：**输出前可重试，输出后只能关连接**，绝不能在同一连接上重放请求；
2. 重试中间件要对 SSE 流式做专门设计，并补“输出中途断流”的回归用例；
3. 只对可识别的临时故障重试，真正的鉴权/参数错误应立即透传，避免把用户等待放大数倍。

## 部署与回滚清单

- 中转脚本（部署路径）：`~/.zcode/apibai-retry/proxy.py`（仓库副本：`scripts/apibai-retry-proxy.py`，两者 SHA256 一致）；
- 初版备份：`~/.zcode/apibai-retry/proxy.py.bak`；
- 常驻配置：`~/Library/LaunchAgents/com.yusong.apibai-retry.plist`；
- 运行日志：`~/.zcode/apibai-retry/retry.log`；
- 控制命令：
  - 重启：`launchctl kickstart -k "gui/$(id -u)/com.yusong.apibai-retry"`
  - 健康：`curl -s http://127.0.0.1:18900/__retry_proxy_health`
  - 查看重试：`tail -n 50 ~/.zcode/apibai-retry/retry.log`
- ZCode 侧改动：B.AI provider 的 baseURL 指向本地，原配置备份于 `~/.zcode/v2/config.json.bak-*`；修改后需完全退出并重启 ZCode 生效。
