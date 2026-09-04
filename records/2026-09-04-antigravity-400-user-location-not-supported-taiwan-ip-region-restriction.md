# Antigravity Agent 执行终止 HTTP 400「User location is not supported for the API use」：台湾中华电信出口 IP 触发 Google 内部端点地域白名单限制，切换节点后 14 次 API 调用全量恢复实录

## 基本信息

- **处理者身份**：Doubao（本次会话 AI 协作代理，主排查与根因定位）
- **问题类型**：
  1. Antigravity Agent 模式运行约 44 秒后弹窗报错 `Agent execution terminated due to error`
  2. 后端 API 返回 `HTTP 400 Bad Request`，gRPC 状态 `FAILED_PRECONDITION`，错误信息 `User location is not supported for the API use.`
  3. 台湾中华电信出口 IP 触发 Google Antigravity 内部端点（`daily-cloudcode-pa.googleapis.com`）独立地域白名单限制
  4. 标准 Gemini API 官方支持台湾，但 Antigravity 内部端点策略不一致，导致「Gemini 网页版能用、Antigravity 不能用」的割裂现象
- **报错时间**：2026-09-04 19:11:57（Asia/Shanghai，UTC+8）
- **解决确认时间**：2026-09-04 19:35:16（Asia/Shanghai，UTC+8）
- **最终状态**：已解决（用户在 FIIClash 中切换代理节点，出口 IP 从台湾中华电信 `111.243.99.217` 切换至 `216.195.192.183`；完全退出并重启 Antigravity；重启后 14 次 Google API 调用全部成功，0 次地域错误，Agent 正常工作）
- **关联项目/仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)
- **与上一篇关系**：本篇与 `2026-09-04-chatgpt-unsupported-country-clash-meta-migration.md` 和 `2026-09-04-flclash-not-running-dns-pollution-macos-network-troubleshooting.md` 同属 macOS 代理生态与 AI 工具地域限制排查系列，但本篇核心是「Antigravity 内部端点独立地域白名单」而非「客户端未运行」或「OpenAI 香港封锁」。**值得特别注意的是**：本次解决所使用的节点 IP（`216.195.192.183`，香港屯门）正是前文中导致 ChatGPT 被 OpenAI 封锁的同一个 IP——同一出口 IP 对不同平台的地域判定结果完全相反，印证了各 AI 平台的地域白名单相互独立、不可类推。

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 19:11 前后 | 用户 | 在 Antigravity 中运行 Agent 任务，约 44 秒后弹窗报错 `Agent execution terminated due to error`，点击 Copy debug info 获取完整错误日志 |
| 19:15–19:18 | Doubao | 初步解析报错日志：定位到 `HTTP 400 / FAILED_PRECONDITION / User location is not supported for the API use.`，识别 Response Header 中 `Server: ESF`、`X-Cloudaicompanion-Trace-Id: 38dd420b7a40821e`，判断为服务端地域准入拦截而非程序 bug |
| 19:18–19:22 | Doubao | 切换工作模式深度排查：检测出口 IP 为 `111.243.99.217`（台湾台北，中华电信 HiNet，AS3462）；系统代理与环境变量代理均关闭；确认 Antigravity 为 Google 出品（`com.google.antigravity`），版本 2.12.0，模型配置 `Gemini 3.7 Flash (High)` |
| 19:22–19:28 | Doubao | 深度分析 `language_server.log`：还原完整调用链，确认 Antigravity 实际调用端点为 `https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent`（Google 内部 Daily 通道，非公开 Gemini API）；报错前 9 次 API 调用无错误记录，第 10 次触发地域拦截；Trajectory ID `fd5efc71-9b7f-4428-8b29-0ce1c8e04f5d` |
| 19:28–19:32 | Doubao | 交叉查证地域策略：确认标准 Gemini API 官方文档明确列出台湾为支持地区，但 Antigravity 内部端点无公开地区列表；GitHub issue #219 证实「同样账号和网络，Gemini web 能用、Antigravity CLI 报地域错误」；格鲁吉亚案例证实「官方 FAQ 列为支持但后端白名单实际拒绝」的不一致现象 |
| 19:32 | 用户 | 在 FIIClash 中切换代理节点（节点名称显示为新加坡） |
| 19:33–19:34 | Doubao | 验证切换后出口 IP 为 `216.195.192.183`；多 IP 数据库交叉验证结果不一致（ipinfo→香港屯门、ip-api→新加坡、淘宝→美国），但直接向 Antigravity 端点发完整请求返回 `HTTP 401 UNAUTHENTICATED / CREDENTIALS_MISSING`（而非 400 地域错误），证明 Google 服务端已判定该 IP 在支持地区内 |
| 19:34 | Doubao | 执行 `killall` 完全退出 Antigravity 主进程、Renderer、GPU、language_server 等所有子进程，确认清理干净后 `open -a Antigravity` 重启 |
| 19:34–19:36 | Doubao | 实时监控 `language_server.log`：重启后认证成功（`Auth succeeded`），远程控制连接正常（`Connection status: Connected`）；用户触发 Agent 任务后，`streamGenerateContent` 与 `generateContent` 交替调用共 14 次，每次流式调用均带 `ResponseID`，**0 次 `FAILED_PRECONDITION` 错误**，确认完全恢复 |

---

## 问题详细描述

用户在 macOS 系统上使用 Google Antigravity v2.12.0（AI 编码 Agent 工具），在 Agent 模式下运行任务时，程序运行约 44 秒后突然弹窗报错：

```
Agent execution terminated due to error
```

用户点击「Copy debug info」获取到完整错误日志，核心内容如下：

```
Trajectory ID: fd5efc71-9b7f-4428-8b29-0ce1c8e04f5d
Error: HTTP 400 Bad Request
Sherlog: TraceID: 0x38dd420b7a40821e
Headers: {
  "Server": ["ESF"],
  "Content-Type": ["text/event-stream"],
  "X-Cloudaicompanion-Trace-Id": ["38dd420b7a40821e"],
  ...
}
{
  "error": {
    "code": 400,
    "message": "User location is not supported for the API use.",
    "status": "FAILED_PRECONDITION"
  }
}
```

用户此前已能正常使用 Antigravity，本次报错为突然出现。用户的工作环境高度依赖 Google 系列服务与 AI 编程工具，Agent 模式不可用直接影响编码效率。用户同时使用 FIIClash 作为代理客户端，此前在同一系列排查中已完成从 ClashX Meta 到 FlClash/FIIClash 的迁移，并修复了 DNS 污染与客户端未运行等问题。

---

## 排查过程与关键技术证据

### 1. 报错日志初步解析（区分程序 bug 与服务端拦截）

对用户提供的 debug info 逐字段分析：

```
HTTP 400 Bad Request
error.code: 400
error.status: FAILED_PRECONDITION
error.message: "User location is not supported for the API use."
```

* **关键判断**：
  - `FAILED_PRECONDITION` 是 gRPC 标准状态码 9，表示**前置条件不满足**——请求格式正确，但执行环境不满足要求，而非程序内部错误
  - `User location is not supported for the API use` 明确指向**地理位置准入校验**
  - Response Header 中 `Server: ESF`（Edge Security Frontend，边缘安全网关）和 `X-Cloudaicompanion-Trace-Id`（Google Cloud AI Companion 追踪 ID）证明请求已到达 Google 服务端，是服务端业务层拒绝，而非网络不通或 DNS 解析失败
  - `Content-Type: text/event-stream` 表明 Antigravity 以 SSE 流式方式调用，错误在流建立阶段返回
* **结论**：不是 Antigravity 程序 bug、不是 token 超限、不是上下文溢出、不是 MCP 工具冲突，而是 **Google API 服务端的地域准入拦截**。

### 2. 出口网络环境检测（定位实际出口 IP）

```bash
# 出口 IP 与地理位置
curl -s https://ipinfo.io/json
curl -s https://api.ipify.org?format=json

# 系统代理与环境变量代理
scutil --proxy
env | grep -i proxy
```

* **证据发现**：
  - 出口 IP：`111.243.99.217`
  - 主机名：`111-243-99-217.dynamic-ip.hinet.net`
  - 城市：Taipei（台北）
  - 地区：Taiwan
  - 国家：`TW`
  - ISP：`AS3462 Data Communication Business Group`（中华电信 HiNet）
  - 时区：`Asia/Taipei`
  - 系统代理：全部关闭（`HTTPEnable: 0`、`HTTPSEnable: 0`、`SOCKSEnable: 0`、`ProxyAutoConfigEnable: 0`）
  - 环境变量代理：全部为空
* **结论**：当前出口 IP 在台湾，且无系统级 HTTP 代理——说明代理客户端运行在 **TUN 透明代理模式**（全部流量经虚拟网卡转发，不依赖系统代理设置）。台湾 IP 是触发地域限制的直接嫌疑对象。

### 3. Antigravity 进程与配置深度分析（确认软件身份与调用端点）

```bash
# 进程检测
ps aux | grep -i antigravity | grep -v grep

# 版本信息
defaults read /Applications/Antigravity.app/Contents/Info.plist CFBundleShortVersionString

# 配置与状态
ls -la ~/.gemini/
cat ~/.gemini/antigravity/antigravity_state.pbtxt
cat ~/.gemini/antigravity-cli/settings.json
```

* **证据发现**：
  - 软件身份：**Google Antigravity**（Bundle ID `com.google.antigravity`），非第三方产品
  - 版本：`2.12.0`（当前最新 2.12.2，非强制升级）
  - 安装路径：`/Applications/Antigravity.app`
  - 模型配置：`Gemini 3.7 Flash (High)`，provider: `gemini`
  - 关键进程：`language_server`（Go 编写的子进程，负责实际 API 调用）
  - language_server 启动参数中硬编码了两个端点：
    ```
    --api_server_url https://generativelanguage.googleapis.com
    --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com
    ```
  - Antigravity 状态文件显示 Agent onboarding 已完成，安装 UUID `35c928d6-a6c8-494d-bcc3-fd63e33d3bfd`
* **结论**：Antigravity 是 Google 官方产品，底层调用的不是标准公开 Gemini API 端点，而是 Google 内部的 **Cloud Code Daily 通道**（`daily-cloudcode-pa.googleapis.com`）。这个内部端点的地域策略可能与公开 Gemini API 不同。

### 4. language_server 日志深度分析（还原完整调用链与报错时序）

```bash
# 实时日志路径
tail -f ~/Library/Logs/Antigravity/language_server.log

# 报错前后的 API 调用记录
grep "http_helpers.go:246" ~/Library/Logs/Antigravity/language_server.log
grep -E "FAILED_PRECONDITION|User location|agent executor error" ~/Library/Logs/Antigravity/language_server.log
```

* **证据发现（报错 Trajectory `fd5efc71-9b7f-4428-8b29-0ce1c8e04f5d` 的完整时序）**：

  | 时间 | 事件 | 状态 |
  | --- | --- | --- |
  | 19:11:12 | Agent 启动，cascade_id 生成，配置加载 | 正常 |
  | 19:11:16 | 第 1 次 `streamGenerateContent` 调用 | 无错误 |
  | 19:11:22 | 第 2 次 `generateContent` 调用 | 无错误 |
  | 19:11:25 | 第 3 次 `streamGenerateContent` 调用 | 无错误 |
  | 19:11:31 | 第 4 次 `generateContent` 调用 | 无错误 |
  | 19:11:33 | 第 5 次 `streamGenerateContent` 调用 | 无错误 |
  | 19:11:36 | 第 6 次 `streamGenerateContent` 调用 | 无错误 |
  | 19:11:39 | 第 7 次 `generateContent` 调用 | 无错误 |
  | 19:11:43 | 第 8、9 次 `streamGenerateContent` 调用 | 无错误 |
  | 19:11:56 | 第 10 次 `generateContent` 调用 | 触发拦截 |
  | 19:11:57 | ❌ `agent executor error: calling model: FAILED_PRECONDITION (code 400): User location is not supported for the API use.` | 报错 |
  | 19:12:19 | ❌ 用户点击 Retry 后再次报同样错误 | 重试失败 |

  实际调用的 URL 格式：
  ```
  https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse
  https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent
  ```

* **关键发现**：
  - 前 9 次 API 调用没有报错，Agent 正常运行了约 44 秒
  - 第 10 次调用才触发地域拦截，说明**不是所有请求都被一刀切拦截**
  - 可能原因：Daily 端点的地域校验是灰度/概率性的；或不同子路由（streamGenerateContent vs generateContent）有不同地域策略；或前面的调用走了缓存/降级路径
  - `Server-Timing: gfet4t7; dur=115` 表明服务端处理仅 115ms 即返回，属于**快速拒绝**（准入校验直接拦截，非推理超时）
* **结论**：报错发生在 Agent 执行过程中的第 10 次模型调用，由 `daily-cloudcode-pa.googleapis.com` 内部端点的地域准入校验触发。前 9 次成功不代表地域校验通过——可能是灰度策略或路由差异。

### 5. 地域策略交叉查证（标准 Gemini API ≠ Antigravity 内部端点）

为确认「台湾是否被 Antigravity 正式封禁」，进行多源查证：

```bash
# 标准 Gemini API 官方支持地区查询
# 访问 https://ai.google.dev/gemini-api/docs/available-regions
```

* **证据发现**：
  1. **标准 Gemini API 官方支持台湾**：Google 官方文档 `ai.google.dev/gemini-api/docs/available-regions` 明确列出「台湾」（Taiwan）。多个第三方汇总（TransferLLM、SeaCode 等）也确认台湾在 Gemini API 支持列表中。
  2. **Antigravity 内部端点无公开地区列表**：`daily-cloudcode-pa.googleapis.com` 是 Google 内部 Daily 构建通道，没有公开的支持地区文档。
  3. **GitHub issue #219 证实割裂现象**：[google-antigravity/antigravity-cli#219](https://github.com/google-antigravity/antigravity-cli/issues/219) 标题即为「User location is not supported for the API use in agy CLI while Gemini web works」——多名用户确认同样的账号和网络，Gemini 网页版正常使用，但 Antigravity CLI 报地域错误。Google 工作人员（manirajc）回复让用户查看支持地区列表并检查 Google 账号关联地区，但未给出明确的内部端点地区列表。
  4. **格鲁吉亚案例证实官方文档与后端白名单不一致**：issue #219 中用户 speech115 报告，Antigravity 官方 FAQ 明确列出格鲁吉亚为欧洲支持地区，但 CLI 仍然返回 `Your current account is not eligible for Antigravity, because it is not currently available in your location`。该用户另开 issue #828 追踪此问题。这证明 **Antigravity 的后端白名单和官方文档之间存在已知的不一致**。
  5. **2026 年 8 月底 Google 加强地域校验**：多个社区报告指出，2026 年 8 月 24-25 日左右，大量用户突然遭遇 `User location is not supported` 错误，此前可用的 SmartDNS 等绕过方式全部失效。本次报错时间（9 月 4 日）正好在这轮收紧之后。
  6. **Antigravity 同时校验 IP 和账号地区**：社区资料显示，Antigravity 比标准 Gemini 多一层校验——Gemini 只查 IP，Antigravity 同时查 IP 地理位置和 Google 账号关联地区。
* **结论**：不能 100% 断定 Google 官方政策上把台湾排除了，但可以确定：**在当前时间点，台湾 IP 调用 Antigravity 的 daily 内部端点时，被服务端以地域不支持拒绝**。可能原因包括：内部端点独立白名单不含台湾、8 月底收紧后的新限制、灰度校验误杀、或官方文档与实际行为不一致（已有先例）。

### 6. 切换节点后验证（确认新出口 IP 通过地域校验）

用户在 FIIClash 中切换节点后，重新检测：

```bash
# 新出口 IP 检测
curl -s https://ipinfo.io/json
curl -s http://ip-api.com/json/216.195.192.183?lang=zh-CN

# 直接向 Antigravity 端点发完整请求，看返回的是 400 地域错误还是 401 认证错误
curl -s "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"models/gemini-3.7-flash","contents":[{"role":"user","parts":[{"text":"hi"}]}]}'
```

* **证据发现**：
  - 新出口 IP：`216.195.192.183`
  - 多 IP 数据库交叉验证结果**不一致**：
    - ipinfo.io → 香港屯门（Tuen Mun, HK），AS138997 Eons Data Communications Limited
    - ip-api.com → 新加坡中部（Central Singapore, SG），同一 ASN
    - 淘宝 IP 库 → 美国（US），但城市/ISP 均为「XX」（未知）
    - FIIClash 节点名称 → 新加坡
  - DNS 解析返回 `198.18.0.10`（fake-ip），确认 TUN 透明代理模式生效
  - **直接向 Antigravity 端点发完整请求的返回结果**：
    ```json
    {
      "error": {
        "code": 401,
        "message": "Request is missing required authentication credential...",
        "status": "UNAUTHENTICATED",
        "details": [{
          "reason": "CREDENTIALS_MISSING",
          "service": "cloudcode-pa.googleapis.com",
          "method": "google.internal.cloud.code.v1internal.PredictionService.GenerateContent"
        }]
      }
    }
    ```
  - 返回 `HTTP 401 / UNAUTHENTICATED / CREDENTIALS_MISSING`，**完全没有提到地域限制**
* **关键判断逻辑**：Google API 的处理顺序是「网络接入 → 地域/准入校验 → 认证校验 → 授权/配额 → 业务处理」。请求已经走到了第 3 步（认证校验，返回 401），说明第 2 步（地域校验）**已经通过了**。如果地域不支持，会在第 2 步直接返回 400，根本不会到认证这一步。
* **关于 IP 归属地不一致**：第三方数据库怎么说不重要，**Google 服务端自己的判定才是唯一权威**。Google 返回 401 而非 400，就是它认为该 IP 在支持地区内的最直接证据。IP `216.195.192.183` 归属地在第三方数据库中的混乱（香港/新加坡/美国各执一词）是跨境 IDC IP 的典型现象——Eons Data Communications Limited 在多地有机房，IP 段注册地与实际部署地可能不同。
* **结论**：切换节点后，Google 服务端已判定新出口 IP 在支持地区内，地域限制已绕过。

### 7. 重启 Antigravity 并实时监控（确认完全恢复）

```bash
# 完全退出所有 Antigravity 进程（确保连接状态不残留）
killall Antigravity "Antigravity Helper" "Antigravity Helper (Renderer)" "Antigravity Helper (GPU)" language_server
sleep 3
ps aux | grep -iE "antigravity|language_server" | grep -v grep  # 应无输出

# 重启
open -a Antigravity

# 实时监控日志
tail -f ~/Library/Logs/Antigravity/language_server.log | grep -E "(http_helpers|FAILED_PRECONDITION|User location|errorreport|agent executor|Auth succeeded|Connection status)"
```

* **证据发现**：
  - 重启后认证成功：`Auth succeeded, refreshing features and managers`
  - 远程控制连接成功：`Connection status: Connected`（到 `jetski-webchannel.googleapis.com`）
  - 服务器初始化完成：`initialized server successfully in 5.722643666s`
  - 启动阶段 API 调用正常：`loadCodeAssist`、`fetchAvailableModels` 均成功
  - 用户触发 Agent 任务后，API 调用序列健康：

    | 时间 | 调用类型 | Trace ID | ResponseID |
    | --- | --- | --- | --- |
    | 19:34:43 | streamGenerateContent | 0x540f3be0f05e4255 | z6yaap2hG7rg1e8Pve2R2Qc ✅ |
    | 19:34:48 | generateContent | 0x5d652e5a775ea64c | — |
    | 19:34:52 | streamGenerateContent | 0x9ac333672fa0bd15 | 2ayaapK0KczN1e8PvPCi2AY ✅ |
    | 19:34:58 | generateContent | 0xd3b0301f7d7e3692 | — |
    | 19:35:01 | streamGenerateContent | 0xab32de107c1d44b1 | 46yaap6HIKeGvr0Pna6O0AY ✅ |
    | 19:35:05 | generateContent | 0x2aabca9b1e32471 | — |
    | 19:35:07 | streamGenerateContent | 0x91b392804ee21832 | 6qyaaoLfC4fcvr0P-faNyAY ✅ |
    | 19:35:10 | generateContent | 0x8529ea468af04399 | — |
    | 19:35:12 | streamGenerateContent | 0xee27a86be8977300 | 7qyaaqPZNOy4vr0PqvXGgAc ✅ |
    | 19:35:16 | generateContent | 0x6d7e3856f3215b5f | — |

  - `streamGenerateContent`（流式输出）和 `generateContent`（工具/函数调用）交替出现，是 Antigravity Agent 的正常工作模式
  - 每次 `streamGenerateContent` 都带有 `ResponseID`，说明 Google 服务端正常返回了推理结果
  - **重启后地域错误次数：0**
  - **重启后 Agent 执行错误次数：0**
* **结论**：Antigravity 完全恢复正常，Agent 模式可稳定使用。

---

## 根因分析

综合各项证据，本次故障的根因是 **Google Antigravity 内部端点的独立地域白名单限制**，具体分层如下：

### 1. 直接原因：台湾出口 IP 不在 Antigravity 内部端点的地域白名单中

- 出口 IP `111.243.99.217`（台湾中华电信）调用 `daily-cloudcode-pa.googleapis.com/v1internal:generateContent` 时，Google 服务端返回 `HTTP 400 / FAILED_PRECONDITION / User location is not supported for the API use`
- 这是服务端准入层的确定性拒绝，不是网络问题、不是认证问题、不是程序 bug
- 切换到 `216.195.192.183` 后，同样的端点返回 401（认证错误）而非 400（地域错误），证明地域校验已通过

### 2. 深层原因一：Antigravity 内部端点与公开 Gemini API 的地域策略不一致

- 标准 Gemini API（`generativelanguage.googleapis.com`）官方文档明确支持台湾
- 但 Antigravity 实际调用的是内部 Daily 通道（`daily-cloudcode-pa.googleapis.com`，`v1internal` 版本），这个端点有独立的、未公开的地域白名单
- GitHub issue #219 已证实「同样账号和网络，Gemini web 能用、Antigravity 不能用」的割裂现象
- Antigravity 还比标准 Gemini 多一层 Google 账号关联地区校验

### 3. 深层原因二：2026 年 8 月底 Google 加强了地域校验

- 多个社区报告确认 2026 年 8 月 24-25 日左右，Google 对 Antigravity/Gemini 的地域校验进行了一轮收紧
- 此前可用的 SmartDNS 等绕过方式全部失效
- 本次报错（9 月 4 日）正好在这轮收紧之后，台湾 IP 可能是在这轮调整中被加入了限制

### 4. 附加现象：地域校验的灰度/概率性特征

- 报错前 9 次 API 调用无错误，第 10 次才触发地域拦截
- 这说明 Daily 端点的地域校验可能不是 100% 一刀切，而是灰度/概率性的，或不同子路由有不同策略
- 这也解释了为什么用户「此前能正常使用，突然报错」——可能是灰度比例调整或路由变化

### 5. 关键对比：同一 IP 对不同平台的地域判定完全相反

| 平台 | 出口 IP 216.195.192.183（香港屯门） | 出口 IP 111.243.99.217（台湾台北） |
| --- | --- | --- |
| **OpenAI / ChatGPT** | ❌ 封锁（香港不在支持列表） | 未测试 |
| **Google Antigravity** | ✅ 正常（在支持列表内） | ❌ 封锁（User location not supported） |
| **标准 Gemini API** | ✅ 正常 | ✅ 官方支持 |

这一对比有力地证明了：**各 AI 平台的地域白名单相互独立，不可根据一个平台的可用性类推另一个平台**。香港 IP 对 OpenAI 是禁区，但对 Google Antigravity 是安全区；台湾 IP 对标准 Gemini API 可用，但对 Antigravity 内部端点被限制。

---

## 解决方案与落地操作

### 步骤 1：在 FIIClash 中切换到支持地区的节点

1. 打开 FIIClash，在节点列表中选择一个出口 IP 不在受限地区的节点；
2. 节点名称仅供参考，**不能单凭名称（如「新加坡」「美国」）判断实际出口**，必须实测验证；
3. 切换后验证出口 IP：
   ```bash
   curl -s https://ipinfo.io/json
   # 关注 country 字段
   ```

### 步骤 2：验证新 IP 是否通过 Google 地域校验（关键步骤）

不能只看 IP 归属地，必须直接向 Antigravity 端点发请求验证：

```bash
curl -s "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"models/gemini-3.7-flash","contents":[{"role":"user","parts":[{"text":"hi"}]}]}'
```

* **返回 `401 UNAUTHENTICATED / CREDENTIALS_MISSING`** → ✅ 地域校验通过，可以继续下一步
* **返回 `400 FAILED_PRECONDITION / User location is not supported`** → ❌ 地域仍受限，需要换节点重试

### 步骤 3：完全退出并重启 Antigravity

切换节点后必须重启 Antigravity，否则旧的连接状态可能残留：

```bash
# 完全退出所有相关进程
killall Antigravity "Antigravity Helper" "Antigravity Helper (Renderer)" "Antigravity Helper (GPU)" language_server 2>/dev/null

# 等待进程清理
sleep 3

# 确认无残留进程
ps aux | grep -iE "antigravity|language_server" | grep -v grep
# 应无输出

# 重启
open -a Antigravity
```

### 步骤 4：验证 Antigravity 恢复正常

```bash
# 实时监控日志，触发 Agent 任务后观察
tail -f ~/Library/Logs/Antigravity/language_server.log | grep -E "(http_helpers|FAILED_PRECONDITION|User location|ResponseID)"
```

正常表现：`streamGenerateContent` 调用带有 `ResponseID`，无 `FAILED_PRECONDITION` 错误。

---

## 验证与效果

| 验证项 | 验证命令 / 测试方式 | 实际返回结果 | 状态 |
| :--- | :--- | :--- | :--- |
| **出口 IP 切换** | `curl -s https://ipinfo.io/json` | 从 `111.243.99.217`（台湾）变为 `216.195.192.183` | ✅ 验证通过 |
| **Google 地域校验** | 直接 POST `daily-cloudcode-pa.googleapis.com/v1internal:generateContent` | 返回 `401 UNAUTHENTICATED / CREDENTIALS_MISSING`（非 400 地域错误） | ✅ 验证通过 |
| **Antigravity 认证** | 日志中 `Auth succeeded` | 重启后认证成功，刷新 features 和 managers | ✅ 验证通过 |
| **远程控制连接** | 日志中 `Connection status: Connected` | 已连接到 `jetski-webchannel.googleapis.com` | ✅ 验证通过 |
| **API 调用总数** | `grep http_helpers.go:246 language_server.log`（重启后） | 14 次调用（含启动配置加载 + Agent 推理） | ✅ 验证通过 |
| **流式调用 ResponseID** | 日志中 `streamGenerateContent` 行 | 6 次流式调用全部带 ResponseID，服务端正常返回 | ✅ 验证通过 |
| **地域错误次数** | `grep FAILED_PRECONDITION language_server.log`（重启后） | 0 次 | ✅ 验证通过 |
| **Agent 执行错误** | `grep "agent executor error" language_server.log`（重启后） | 0 次 | ✅ 验证通过 |
| **用户主观使用** | 在 Antigravity 中运行 Agent 任务 | 正常执行，无报错弹窗 | ✅ 确认解决 |

---

## 经验沉淀与后续建议

1. **「User location is not supported」是服务端地域拦截，不是程序 bug**：遇到此报错时，不要浪费时间升级 Antigravity 版本、清理缓存、重建会话——这些都无法解决服务端地域校验。直接检查出口 IP。

2. **标准 Gemini API 支持的地区 ≠ Antigravity 支持的地区**：Antigravity 调用的是 Google 内部 Daily 通道（`daily-cloudcode-pa.googleapis.com`），有独立的、未公开的地域白名单。不要根据 Gemini API 的官方支持列表推断 Antigravity 的可用性。GitHub issue #219 和格鲁吉亚案例都证实了这种不一致。

3. **验证地域是否通过的最可靠方法：直接发请求看返回码**：不要依赖第三方 IP 数据库的归属地判断（同一 IP 在不同数据库中可能给出不同国家）。最权威的判断是直接向目标端点发请求——返回 `401`（认证错误）说明地域已通过，返回 `400 + User location not supported` 说明地域仍受限。Google 服务端自己的判定是唯一标准。

4. **各 AI 平台的地域白名单相互独立，不可类推**：同一出口 IP 对不同平台的判定可能完全相反。本次案例中，香港 IP（`216.195.192.183`）对 OpenAI/ChatGPT 是封锁区，但对 Google Antigravity 是安全区；台湾 IP 对标准 Gemini API 可用，但对 Antigravity 内部端点被限制。切换节点时需要针对具体平台逐一验证。

5. **切换代理节点后必须重启 Antigravity**：Antigravity 的 language_server 是长连接进程，切换节点后旧的连接状态可能残留。必须 `killall` 完全退出所有子进程（包括 Renderer、GPU、language_server），再重新启动，才能确保新的出口 IP 生效。

6. **地域校验可能是灰度/概率性的**：本次案例中前 9 次 API 调用成功、第 10 次才报错，说明 Antigravity 的地域校验可能不是 100% 一刀切。「之前能用、突然不能用」不一定是用户操作变化，可能是 Google 侧灰度比例调整或路由变化。

7. **关注 2026 年 8 月底后的地域政策变化**：Google 在 8 月 24-25 日左右对 Antigravity/Gemini 的地域校验进行了一轮收紧，此前可用的绕过方式失效。如果在 8 月底后突然遇到地域报错，优先考虑是否被新政策覆盖。

8. **Antigravity 同时校验 IP 和 Google 账号关联地区**：与标准 Gemini 只查 IP 不同，Antigravity 还会检查 Google 账号的关联地区。如果切换 IP 后仍报错，需要检查 Google 账号的服务条款页面显示的国家/地区是否正确，必要时提交地区变更申请。

9. **节点名称不可信，实测出口 IP 才是王道**：FIIClash 中节点显示为「新加坡」，但实际出口 IP 的归属地在第三方数据库中存在香港/新加坡/美国三种说法。机场运营商标注的节点名称和实际物理出口可能不一致，遇到地域问题时必须用 `curl https://ipinfo.io/json` 实测。

---

## 关键产物与现场位置（不含密钥）

- **Antigravity 应用路径**：`/Applications/Antigravity.app`（Google 出品，版本 2.12.0，Bundle ID `com.google.antigravity`）
- **Antigravity language_server 日志**：`~/Library/Logs/Antigravity/language_server.log`（本次排查核心证据来源，含完整 API 调用时序与报错记录）
- **Antigravity 主进程日志**：`~/Library/Logs/Antigravity/main.log`
- **Antigravity 用户数据目录**：`~/Library/Application Support/Antigravity/`
- **Antigravity 状态文件**：`~/.gemini/antigravity/antigravity_state.pbtxt`（含 Agent onboarding 状态、安装 UUID、模型配置）
- **Antigravity CLI 设置**：`~/.gemini/antigravity-cli/settings.json`（模型 `Gemini 3.7 Flash (High)`，provider `gemini`）
- **Google OAuth Token**：`~/.gemini/jetski-standalone-oauth-token`（权限敏感，不在本文档中记录内容）
- **报错 Trajectory ID**：`fd5efc71-9b7f-4428-8b29-0ce1c8e04f5d`
- **报错 Trace ID**：`0x38dd420b7a40821e`（`X-Cloudaicompanion-Trace-Id: 38dd420b7a40821e`）
- **受限出口 IP（报错时）**：`111.243.99.217`，台湾台北，中华电信 HiNet（AS3462）
- **恢复后出口 IP**：`216.195.192.183`，Eons Data Communications Limited（AS138997），第三方数据库归属地不一致（ipinfo→香港屯门、ip-api→新加坡、淘宝→美国），Google 服务端判定为支持地区
- **Antigravity 实际 API 端点**：`https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse`（流式）和 `https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent`（非流式/工具调用）
- **地域校验验证命令**：
  ```bash
  curl -s "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent" \
    -X POST -H "Content-Type: application/json" \
    -d '{"model":"models/gemini-3.7-flash","contents":[{"role":"user","parts":[{"text":"hi"}]}]}'
  # 返回 401 = 地域通过；返回 400 + User location not supported = 地域受限
  ```
- **完全重启 Antigravity 命令**：
  ```bash
  killall Antigravity "Antigravity Helper" "Antigravity Helper (Renderer)" "Antigravity Helper (GPU)" language_server 2>/dev/null
  sleep 3 && open -a Antigravity
  ```
- **关联 GitHub issue**：[google-antigravity/antigravity-cli#219](https://github.com/google-antigravity/antigravity-cli/issues/219)（Gemini web 能用但 Antigravity 报地域错误的割裂现象）
- **标准 Gemini API 官方支持地区列表**：https://ai.google.dev/gemini-api/docs/available-regions（明确列出台湾，但不适用于 Antigravity 内部端点）

---

*本文档记录了一次完整的 Google Antigravity 内部端点地域白名单限制排查过程，核心教训：Antigravity 走的是 Google 内部 Daily 通道而非公开 Gemini API，其地域策略独立且未公开；验证地域是否通过最可靠的方法是直接向端点发请求看返回 401 还是 400，而非依赖第三方 IP 数据库；各 AI 平台的地域白名单相互独立，同一 IP 对 OpenAI 和 Google 的判定可能完全相反。*
