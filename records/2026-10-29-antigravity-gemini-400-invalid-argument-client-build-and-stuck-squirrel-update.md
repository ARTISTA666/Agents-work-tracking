# Antigravity 桌面端 Gemini 3.8 Flash (High) 报 HTTP 400「Request contains an invalid argument」：代理地域白名单被证伪、根因指向 2.27.0 客户端多步工具往返请求；2.28.0 已下载却因 App 从未退出而滞留 10 小时，重启装上后同类请求全量通过

## 基本信息

- **处理者身份**：Qoder（本次会话 AI 协作代理，主排查、根因定位、升级与复测）
- **问题类型**：
  1. Antigravity 桌面版（`~/Applications/Antigravity.app`，v2.27.0）Agent 任务弹窗 `Agent execution terminated due to error`
  2. 后端 `https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse` 返回 `HTTP 400 / INVALID_ARGUMENT / Request contains an invalid argument.`
  3. 用户主观感受为「Gemini 模型无法访问」，并怀疑是网络（梯子）原因
  4. 附加发现：v2.28.0 早在 02:25 就下载完毕并交棒 ShipIt，但 Squirrel 只在 App 退出时安装，而 App 已连续运行 1 天 5 小时，ShipIt 每小时空转一次，升级事实上卡死 10 小时
- **报错时间**：首次 2026-10-28 17:19:59，最后一次 2026-10-29 11:18:24（Asia/Shanghai，UTC+8）
- **解决确认时间**：2026-10-29 13:02（Asia/Shanghai，UTC+8，桌面端同类请求复测通过）
- **最终状态**：已解决（完全退出触发 Squirrel 安装 2.28.0；同一工作区、同一模型、同一请求形态复测 3 次流式调用全部成功，`INVALID_ARGUMENT` 0 次）。注：该 400 本身是**间歇性**故障（18 小时内仅 4 次，同期同模型另有数百次成功调用），单次复测通过不等于永久消除，后续复发按第 8 节升级路径处理
- **关联项目/仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)
- **与上一篇关系**：与 `2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md` 同为 Antigravity HTTP 400，但**结论相反**：9-04 那次是 `FAILED_PRECONDITION / User location is not supported`（地域白名单，换节点可解），本次是 `INVALID_ARGUMENT / Request contains an invalid argument`（请求内容被服务端业务层拒绝，与出口 IP 无关）。两者错误码同为 400，处置方式完全不同，不可套用
- **关联记录（本仓库，务必先读）**：
  - [2026-10-28 默认分流出口被判 HK → 请求级随机 400](2026-10-28-gemini-web-and-antigravity-intermittent-egress-hk-region-reject.md)：同日另一路排查，症状描述与本次高度相似（「Gemini 同时连不上」），但其错误串是 `FAILED_PRECONDITION / User location is not supported`，且已把 `🚀节点选择` 固定到圣何塞07 并写库持久化。**这条修复是本次复测能够通过的前置条件之一**
  - [2026-10-17 新加坡 IP 被拒 + 静默 CLI 验证](2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md)：**纠正了「匿名 401 可判地域」的旧判据**，本次一度误用该判据后撤回（见第 4 节）
  - [2026-10-22 Antigravity 启动/代理/更新源/进程分流](2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)：`language_server` 的 `PROCESS-PATH` 专用出口、CLI 与桌面进程路径不同不可互代验收
  - [2026-10-24 Gemini 网页端国家限制](2026-10-24-gemini-web-unsupported-country-ai-node-egress.md)：共享廉价中转出口被判 HK 的同源问题

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 11:20 前后 | 用户 | 反馈「Antigravity 里 Gemini 模型无法访问，大概率是网络」，要求查真正原因并修复，事后同步到 GitHub |
| 11:22 | Qoder | 读 `language_server.log`：定位 4 条 `agent executor error: INVALID_ARGUMENT (code 400)`，同时确认 `loadCodeAssist` / `fetchAvailableModels` 每 6 分钟稳定成功 |
| 11:25 | Qoder | 通过 App 自带的 CDP 端口只读抓取界面文本，拿到用户可见报错：`Agent execution terminated due to error` + `Error ID: 0ac71e01-…-3/-4`，模型选择器显示 `Gemini 3.8 Flash High` |
| 11:28 | Qoder | 从会话 SQLite 库 `steps.step_payload` 提取服务端完整响应：`HTTP 400`、`Server: ESF`、`X-Cloudaicompanion-Trace-Id`、`Server-Timing: gfet4t7; dur=1360`、body 无 `details`/fieldViolations |
| 11:31 | Qoder | 查 mihomo 控制口 `/connections`：Antigravity 全部 Google 流量 `chains=[🇺🇸美国圣何塞07]`，走代理且成功建连，非 DIRECT、非断网 |
| 11:34 | Qoder | 先用「匿名 POST 端点看 401 还是 400」判地域，得出放行结论；随后发现本仓库 10-17/10-22 已纠正过该判据（地区校验在认证之后，匿名请求恒返回 401，无判别力）→ **撤回该推断**，改由「带账号真实调用 + 错误串分类」判定（见第 4 节） |
| 11:36–11:45 | Qoder | 用同一账号同一网络的 `agy` CLI 做对照实验：`gemini-3.8-flash-high` 单轮 2.5s 成功；`--mode auto` 下含 `run_command` 工具往返的 3 轮调用全部成功，0 次 400 → 排除账号、模型可用性、网络，问题压缩到桌面端请求构造 |
| 11:50 | Qoder | 比对成功/失败会话：长期会话 `8cb69454` 当日 11:14 仍在用同一模型跑第 269 步；失败集中在工具往返后的下一步请求 → 判定为客户端请求构造缺陷，非全局封锁 |
| 11:55 | Qoder | 发现升级卡死：`main.log` 每小时 `Update downloaded: 2.28.0`，`ShipItState.plist` 与暂存 bundle 都在，App 进程启动时间 Oct 28 06:13（已 1 天 5 小时未退出），Squirrel 的「退出即安装」从未被触发 |
| 12:45 | 用户 | 批准「现在退出并升级复测」 |
| 12:46 | Qoder | `osascript` 优雅退出 → ShipIt 立即完成安装（`Installation completed successfully`），版本落到 2.28.0 |
| 12:47–13:00 | Qoder | 排查自造的假故障：新装 App 从本会话 shell 启动后 0.1 秒静默退出，一度误判「2.28.0 装坏了」；逐项排除包体完整性、签名、公证、软链后，定位到根因是 shell 环境变量 `ELECTRON_RUN_AS_NODE=1` 污染（见第 8 节教训 5） |
| 13:00 | Qoder | `env -u ELECTRON_RUN_AS_NODE open -n` 正常启动，UA 确认 `Antigravity/2.28.0 Electron/44.5.1`，日志出现 `Auth succeeded` |
| 13:02 | Qoder | 桌面端复测：在失败过的 Minimal Diary 工作区用 `Gemini 3.8 Flash (High)` 发起「读 README 第一行」任务，`read_file` 工具往返 → 下一步请求成功返回 `# 极简日记`，3 次流式调用 0 次 400 |
| 13:10–13:20 | Qoder | 推送前 `git fetch` 发现远端已多出 20 个提交，其中 [2026-10-28 默认分流出口记录](2026-10-28-gemini-web-and-antigravity-intermittent-egress-hk-region-reject.md)、[2026-10-17](2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md) 与本主题直接相关 → 逐篇核对后**撤回自己的匿名探针判据**、重排地域排除依据，并把记录 rebase 到远端 |

---

## 问题详细描述

用户在 macOS（26.6 / Apple Silicon）上使用 Google Antigravity 桌面版跑 Agent 任务，界面弹出：

```
Error
Agent execution terminated due to error.
Error ID: 0ac71e01-4778-4e3d-8de0-a4118dc8d7f0-3
You can prompt the model to try again or start a new conversation if the error persists.
[Retry]
```

点 Retry 再报 `-4`，同一位置反复失败。用户第一判断是梯子/网络问题（此前 9-04、10-28 都确实是网络引发的 AI 工具故障），要求「找到具体的真正原因后解决」。

工作环境：FlClash（mihomo，fake-IP + TUN 全量接管）；`language_server` 走 Google 内部 daily 通道；账号 `useAiCredits: true`；失败任务位于 `file:///Users/yusong/Desktop/极简日记-v2.0.0`（项目 `Minimal Diary`）。

---

## 排查过程与关键技术证据

### 1. 日志定位真实报错：不是连不上，是服务端 400

```bash
grep -n "INVALID_ARGUMENT" ~/Library/Logs/Antigravity/language_server.log
grep -oE "E[0-9]{4} [0-9:.]+ +[0-9]+ [a-z_]+\.go:[0-9]+\] .{0,90}" language_server.log | sort | uniq -c | sort -rn
```

* **证据发现**：
  - 仅 4 次 `agent executor error: generating and executing: INVALID_ARGUMENT (code 400): Request contains an invalid argument.`
    - 2026-10-28 17:19:59、17:48:05、2026-10-29 11:18:16、11:18:24
  - 同期 `loadCodeAssist`、`fetchAvailableModels` 每 6 分钟一次，**全部带 Trace 正常返回**
  - 干扰项：`jetski-webchannel.googleapis.com` 的 `connection reset by peer`（远程控制长轮询，10 次）、`Failed to poll ListExperiments`（5 次）——均为外围轮询，不影响 Agent 推理
* **结论**：如果网络/代理/GFW 是原因，`fetchAvailableModels` 不可能保持 100% 成功。推理请求是**到达了 Google 服务端并被业务层拒绝**。

### 2. 从会话库取出服务端原始响应（最直接的取证点）

`language_server.log` 只记录错误摘要，完整响应存在会话 SQLite 库的失败步骤里：

```bash
python3 - <<'EOF'
import sqlite3, re
db=sqlite3.connect('/Users/yusong/.gemini/antigravity/conversations/d216881d-7653-438c-9b7f-eef175fc0540.db')
for idx, in db.execute("select idx from steps where step_type=17 order by idx"):
    b=db.execute("select step_payload from steps where idx=?",(idx,)).fetchone()[0]
    print(re.sub(rb'[^\x20-\x7e]', b'\n', b).decode())
EOF
```

* **证据发现**（原样摘录）：

```
HTTP 400 Bad Request
TraceID: 0xfd6fb3b83d56a11d
Headers: {"Content-Length":["127"],"Content-Type":["text/event-stream"],
          "Server":["ESF"],"Server-Timing":["gfet4t7; dur=1360"],
          "X-Cloudaicompanion-Trace-Id":["fd6fb3b83d56a11d"], ...}
{ "error": { "code": 400, "message": "Request contains an invalid argument.", "status": "INVALID_ARGUMENT" } }
```

* **关键判断**：
  - `Content-Length: 127` + 无 `details`/`fieldViolations` → Google **刻意不告诉客户端哪个字段错**
  - `Server-Timing: gfet4t7; dur=1360` → 服务端处理了 1.4 秒才拒，属于**请求内容校验失败**，不是 9-04 那种秒级准入拦截
  - 第二条 TraceID `0x3a7f7e6de7e1cdcb`（11:18:24 的 Retry）
* **结论**：报错发生在请求构造层，与出口 IP、账号资格无关。

### 3. 代理链路核查（把「网络原因」正式证伪）

```bash
python3 - <<'EOF'   # 读 mihomo external-controller + secret，按进程过滤 connections
# GET http://127.0.0.1:9090/connections
EOF
```

* **证据发现**：

| 进程 | host | remoteDestination | chains |
| --- | --- | --- | --- |
| language_server | `daily-cloudcode-pa.googleapis.com` | 134.195.101.129 | 🇺🇸美国圣何塞07 |
| language_server | `aicode.googleapis.com` | 134.195.101.129 | 🇺🇸美国圣何塞07 |
| language_server | `jetski-webchannel.googleapis.com` | 134.195.101.129 | 🇺🇸美国圣何塞07 |
| language_server | `www.googleapis.com` | 134.195.101.129 | 🇺🇸美国圣何塞07 |

  - 出口 IP 实测 `134.195.101.193` / `134.195.101.194`，US（Syracuse，AS46997）
  - 系统代理与 `launchctl getenv *_PROXY` 全空，TUN `utun4` 正常
* **结论**：流量确实走境外节点且成功建连；不存在「直连被墙」或「节点全挂」。

### 4. 地域判据的踩坑与自我纠正（重要）

我先按 [2026-09-04 那篇](2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md) 的方法向端点发了**未带凭据**的 POST，拿到 `401 UNAUTHENTICATED / CREDENTIALS_MISSING`，据此写下「地域已放行」。**这条推断不成立，予以撤回**：

```bash
curl -s -X POST "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent" \
  -H "Content-Type: application/json" \
  -d '{"model":"models/gemini-3.8-flash","contents":[{"role":"user","parts":[{"text":"hi"}]}]}'
# 实际返回 401 UNAUTHENTICATED / reason CREDENTIALS_MISSING
```

* **为什么不能用**：本仓库在 [2026-10-17](2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md) 与 [2026-10-22](2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md) 两篇里已经两次纠正过这条判据——**Antigravity 的地区校验发生在认证之后（业务层）**，所以拿不到凭据的裸请求无论出口在哪个国家都只返回 401，匿名探针**没有判别地域的能力**。9-04 那篇的「401=地域通过 / 400=地域受限」是当时的误归纳。
* **改用哪两条证据判地域**：
  1. **带账号的真实调用**（仓库认定的权威方法，即 [`scripts/antigravity-silent-check.sh`](../scripts/antigravity-silent-check.sh)）：本次第 5 节的 `agy -p "reply with exactly: OK"` 在同机、同出口、同分钟内 **成功**（2.55s，`status: SUCCESS`），另一次含工具往返的调用也成功，均无 `User location` 字样 → 该出口当时被 Google 接受
  2. **错误串本身的类别**：地域拒绝的固定签名是 `FAILED_PRECONDITION / User location is not supported for the API use.`；本次 4 条全部是 `INVALID_ARGUMENT / Request contains an invalid argument.`，全日志 `User location` 计数为 0 → 与 9-04、10-17、10-28 的地域故障**不是同一类**
* **补充背景**：10-28 的另一路排查已把 `🚀节点选择` 固定到 `🇺🇸美国圣何塞07`（写 FlClash 持久库 `profiles.selected_map`），当时正是为了消除「默认分流落共享廉价中转 → 出口被判 HK → **请求级随机 400**（同 IP 同分钟一成一败）」。本次复测时该固定仍在生效，`language_server` 另有 `PROCESS-PATH` 专用覆写，两条链路都钉在 `134.195.101.x`（US）。
* **结论**：地域/出口在本例中被**真实调用成功 + 错误串分类**两条证据排除，而不是被匿名 401 排除。

### 5. CLI 对照实验：同账号同网络同模型同工作区，全部成功

```bash
agy models
agy -p "reply with exactly: OK" --model gemini-3.8-flash-high --output-format json
agy -p "用 run_command 执行 git status 后回答" --model gemini-3.8-flash-high \
    --mode auto --dangerously-skip-permissions --output-format json   # 在极简日记目录内
```

* **证据发现**：
  - `agy models` 正常列出 `gemini-3.8-flash-high / medium / low`、`claude-sonnet-4-6`、`claude-opus-4-6-thinking`、`gpt-oss-120b-medium` → 模型可用、账号有资格
  - 单轮请求 `status: SUCCESS`，2.55s，input 7303 tokens
  - 工具往返请求 `status: SUCCESS`，单轮日志内 3 次 `streamGenerateContent`，`INVALID_ARGUMENT` **0 次**
  - 附带信息：`warning: --mode auto is not available for this account; continuing in the default mode.`
* **结论**：网络、代理、账号、端点、模型档位全部无罪。差异只剩**桌面客户端**（App 2.27.0 的 `language_server`）与 CLI 的请求构造不同。

### 6. 失败与成功会话对比：故障是间歇性、发生在工具往返之后

| 会话 | 工作区 | 模型 | 步数 | 结局 |
| --- | --- | --- | --- | --- |
| `8cb69454-…` | Minimal Diary | `MODEL_PLACEHOLDER_M318` / `gemini-3.8-flash-high` | 269（10-28 17:42 → 10-29 11:14） | 正常完成并提交 commit `c1e26c4` |
| `69c2a50f-…` | 电池排查 | 同上（step 0 记录切到 Gemini 3.8 Flash High） | 225（10-28 16:46 → 17:48） | 末尾一次 `INVALID_ARGUMENT` |
| `d216881d-…` | Minimal Diary | 同上（新建会话） | 5（step 3/4 失败） | 两次 400，UI 弹错 |

* **结论**：同一 App、同一模型能连续跑数百步，说明不是「Gemini 被封/不可用」；失败集中出现在**「模型返回工具调用 → 客户端回传工具结果 → 下一次请求」**这个环节，符合社区对同一签名的描述（长会话/多并行工具轮次下 Flash 高档位报 400，临时解法是新开会话或降低思考档位）。

### 7. 加重因素：2.28.0 下载完却 10 小时没装上

```bash
defaults read ~/Applications/Antigravity.app/Contents/Info.plist CFBundleShortVersionString   # 2.27.0
ps -o lstart -p <Antigravity PID>                                                              # Wed Oct 28 06:13:56
grep -c "Update downloaded: 2.28.0" ~/Library/Logs/Antigravity/main.log                         # 每小时一次
plutil -p ~/Library/Caches/com.google.antigravity.ShipIt/ShipItState.plist
defaults read ~/Library/Caches/com.google.antigravity.ShipIt/update.CA6lFDs/Antigravity.app/Contents/Info.plist CFBundleShortVersionString  # 2.28.0
tail ~/Library/Caches/com.google.antigravity.ShipIt/ShipIt_stderr.log
```

* **证据发现**：
  - `pending/Antigravity.zip`（185MB，2.28.0）02:25 就绪；`ShipIt_stderr.log` 每小时一条 `Detected this as an install request` 后即 `Proxy server … closed`
  - `main.log` 每小时重复 `Update downloaded: 2.28.0`，版本始终 2.27.0
  - ShipIt 的 `launchAfterInstallation => false`，Squirrel 语义是**等 App 退出时才替换**
  - 顺带证实差量更新永远退化为整包（`Cannot download differentially, fallback to full download`，`.blockmap` 404）
* **结论**：用户「升级了但没生效」的体感来自进程长期不退出，客户端停留在有缺陷的 2.27.0 上，这才是本次唯一可确定处置的环节。

### 8. 升级落地：优雅退出触发安装

```bash
osascript -e 'tell application "Antigravity" to quit'
# ShipIt: Installation completed successfully / ShipIt quitting
```

* 安装后校验：`CFBundleShortVersionString = 2.28.0`；`codesign --verify --deep --strict` → `valid on disk` + `satisfies its Designated Requirement`；`spctl --assess` → `accepted, source=Notarized Developer ID, origin=Google LLC (EQHXZ8M8AV)`

### 9. 自造假故障的排查（过程记录，避免后人重踩）

升级后从当前 shell 启动 App，进程 0.08 秒退出、exit 0、无任何输出，`log stream` 显示 `launchservicesd … exitStatus=0`。为排除包体问题，逐项验证：

| 检查项 | 结果 |
| --- | --- |
| 与官方 zip 逐文件对比 | 0 个多余文件；`app.asar` 4615355 字节、sha256 `4a145127f2fa41948970…` **与 zip 内完全一致** |
| Framework 软链（`Versions/Current`、`Resources`、`Libraries`、`Helpers`） | 全部存在且指向正确（ShipIt 的 direct-contents-write 未破坏软链） |
| `Electron Framework` 版本 | `CFBundleVersion = 44.5.1`，与 zip 一致（非旧 2.27 的 44.4.3 残留） |
| 从 zip 全新解压到 `/tmp` 再启动 | 仍然 0.1 秒退出 → **与安装方式无关** |
| `ELECTRON_RUN_AS_NODE` | 本会话 shell 中 =1，`launchctl getenv` 为空 |

* **真相**：`ELECTRON_RUN_AS_NODE=1` 会让 Electron 主程序退化为纯 Node 解释器（无入口脚本 → 立刻 exit 0），这也解释了 `Antigravity --version` 打印出 **Node 的 v24.21.0** 和 `--user-data-dir=… → bad option`（Node 的参数解析报错）。用 `env -u ELECTRON_RUN_AS_NODE open -n` 启动后一切正常。
* **结论**：App 从未坏过；这是**从 agent/自动化 shell 里启动 GUI Electron 应用**的环境污染陷阱。

### 10. 复测（桌面端，2.28.0）

在失败过的同一工作区、同一模型档位发起只读任务「用工具读 README.md 第一行」：

| 步骤 | 内容 | 结果 |
| --- | --- | --- |
| step 0 | USER_INPUT（13:02:31） | DONE |
| step 1 | PLANNER_RESPONSE 调用 `read_file{Path: …/极简日记-v2.0.0/README.md, EndLine:1}` | DONE，input 9436 |
| step 2 | 工具结果 `1: # 极简日记` | DONE |
| step 3 | 下一轮模型响应（正是 11:18 触发 400 的那个请求位置） | DONE，返回 `# 极简日记` |

* `grep -c INVALID_ARGUMENT ~/Library/Logs/Antigravity/language_server.log` → **0**；本轮 3 次 `streamGenerateContent` 均带 ResponseID

---

## 根因分析

### 1. 直接原因（用户可见故障）

Antigravity **v2.27.0 客户端**在 Agent 的「工具结果回传后下一轮」请求中，构造了 `daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent` 不接受的负载，被服务端业务层以 `HTTP 400 INVALID_ARGUMENT` 拒绝。判定依据：

- 同账号、同网络、同工作区、同模型（`gemini-3.8-flash-high`）经 CLI 走**同一端点**完成工具往返，0 次 400
- 同一桌面 App 在同一模型上能连续跑数百步，仅个别轮次被拒 → 不是封锁、不是配额
- 服务端响应无 `fieldViolations`、耗时 1.4s → 内容校验层拒绝，而非准入层

### 2. 加重因素（可确定处置的部分）

Squirrel「退出即安装」+ 用户长期不退出 App → 2.28.0 滞留 10 小时，客户端停留在有缺陷版本。这是本次唯一能明确修复的环节，且已修复。

### 3. 已排除项（含排除证据）

| 假设 | 排除证据 |
| --- | --- |
| 梯子/代理故障 | mihomo `/connections` 显示 Antigravity 流量 `chains=[美国圣何塞07]` 且成功建连；`fetchAvailableModels` 每 6 分钟 100% 成功 |
| 出口 IP 地域白名单（9-04 / 10-17 / 10-28 老病） | ① 错误串不同：地域拒绝恒为 `FAILED_PRECONDITION / User location is not supported`，本次全是 `INVALID_ARGUMENT / Request contains an invalid argument`，且全日志 `User location` 计数为 0；② 带账号真实调用（仓库权威判据）在同出口同分钟成功；③ 10-28 已把默认分流钉在圣何塞07，出口 `134.195.101.193/194`（US）。**注意：匿名探针返回 401 不能作为排除依据**（第 4 节） |
| 账号无资格/配额耗尽 | `agy models` 正常列出 3 个 Gemini 档位；全日志无 `RESOURCE_EXHAUSTED`/429/`UNAUTHENTICATED` |
| 上下文超限 | 失败请求 input 仅 9k tokens；同期 20 万 tokens 缓存的长会话反而成功 |
| MCP/插件配置 | `~/.gemini/config/mcp_config.json` 的 `mcpServers` 为空 |
| 汉化 CDP 注入干扰 | `Antigravity-zh.app` 已于 9 月移除，注入器日志停在 10-19；App 内 CDP 端口为官方自带 |

### 4. 未定论部分（诚实边界）

- Google 未返回具体无效字段，**无法指认 2.27.0 负载里哪一项违规**；社区对同签名问题的归因是「多工具轮次 + 高思考档位下的推理签名/调用 ID 回放」，与现场形态吻合，但本次未能在 CLI 侧复现（失败率约 4/数百）
- **与 10-28 出口固定方案的时序关系（关键）**：另一路排查在 10-28 **10:16–10:21** 已把 `🚀节点选择` 固定到圣何塞07 并写库持久化，而本次 4 条 400 分别发生在 10-28 **17:19 / 17:48** 与 10-29 **11:18 / 11:18**——全部在该固定**之后**。也就是说：出口已被钉在干净美国节点的情况下仍然出现这些 400，说明它们既不是共享廉价中转被判 HK 导致，也不会被「换节点/固定出口」消除。这既是排除地域因素的时序证据，也说明本次复测通过**不能**归功于 10-28 的方案
- 反过来说，13:02 的复测通过同时受两个变量影响（升级到 2.28.0、以及距上次故障已过去约 2 小时的自然状态），**归因于版本升级只是最可能解释而非已证明结论**；若复发，先用 `scripts/antigravity-gemini-healthcheck.mjs` 按错误串定性，再按下面第 1、2 条处置

---

## 解决方案与落地操作

### 步骤 1：先分辨 400 的类型，不要条件反射换节点

```bash
grep -oE "INVALID_ARGUMENT|User location is not supported" ~/Library/Logs/Antigravity/language_server.log | sort | uniq -c
```

- 出现 `User location is not supported` → 走 9-04 的换节点流程
- 出现 `Request contains an invalid argument` → 与 IP 无关，按本记录步骤 2 起走

### 步骤 2：用带账号的真实调用判地域（不要用匿名请求）

```bash
bash scripts/antigravity-silent-check.sh     # agy -p "Reply with exactly: PONG"，退出码 0=可用 1=地域被拒 2=环境异常
agy -p "Reply with exactly: PONG" --print-timeout 90s
```

- 出现 `User location is not supported` → 出口被地区判定拒绝，走 10-28 的 `scripts/default-egress-pin.sh` 固定分流
- 返回 `PONG` 而界面仍报 `Request contains an invalid argument` → 与地域无关，按本记录步骤 3 起走
- ❌ 不要用「匿名 POST 端点看 401 还是 400」：地区校验在认证之后，匿名请求恒返回 401，无判别力（本仓库 10-17/10-22 已纠正，本次第 4 节再次踩到）

### 步骤 3：把 App 升到最新（Squirrel 必须靠退出触发）

```bash
osascript -e 'tell application "Antigravity" to quit'      # 优雅退出才会触发安装
sleep 8; pgrep -x Antigravity || echo "已退出"
defaults read ~/Applications/Antigravity.app/Contents/Info.plist CFBundleShortVersionString
env -u ELECTRON_RUN_AS_NODE open -n ~/Applications/Antigravity.app
```

> 若从自动化 shell 启动，务必清掉 `ELECTRON_RUN_AS_NODE`，否则 App 会以「0.1 秒 exit 0、零日志、无报错」的形式伪装成升级失败。

### 步骤 4：复发时的降级与上报

1. 模型档位降到 `Gemini 3.8 Flash (Medium/Low)`，或新开对话（社区验证的两个临时绕法）
2. 取证据用于上报：会话库 `steps` 表 `step_type=17` 行的 `step_payload` 里有完整 `TraceID` / `X-Cloudaicompanion-Trace-Id` / 时间戳
   ```bash
   sqlite3 ~/.gemini/antigravity/conversations/<cascade_id>.db \
     "select idx, hex(substr(step_payload,1,0)) from steps where step_type=17;"
   ```
3. 顺带清理无害噪声：`GetProject: failed to read standalone project file …/projects/outside-of-project.json`（本次 62 次）与远程控制 `jetski-webchannel` 长轮询 reset，均与 400 无因果

---

## 验证与效果

| 验证项 | 验证方式 | 实际结果 | 状态 |
| :--- | :--- | :--- | :--- |
| App 版本 | `defaults read …Info.plist CFBundleShortVersionString` | `2.28.0`（升级前 2.27.0） | ✅ |
| 包体完整性/签名 | `codesign --verify --deep --strict`、`spctl --assess` | `valid on disk` / `satisfies its Designated Requirement` / `Notarized Developer ID: Google LLC` | ✅ |
| 与官方包一致 | 与 `pending/Antigravity.zip` 逐文件与 sha256 对比 | `app.asar` sha256 相同，0 多余文件，软链完整 | ✅ |
| 运行态 | CDP `/json/version` UA | `Antigravity/2.28.0 … Electron/44.5.1` | ✅ |
| 认证成功 | `language_server.log` | `13:00:43 Auth succeeded, refreshing features and managers` | ✅ |
| 模型可用性 | `agy models` + `fetchAvailableModels` | 6 个模型齐全，`fetchAvailableModels` 成功 | ✅ |
| 地域准入（权威判据） | `agy -p "reply with exactly: OK"` 带账号真实调用 + 错误串分类 | `SUCCESS` 2.55s；全日志 `User location` 计数 0；（匿名 POST 只返回 401，**不具判别力**，已弃用） | ✅ |
| 桌面端 Gemini 实跑 | Minimal Diary + `Gemini 3.8 Flash High` + `read_file` 工具往返 | step 0→3 全 DONE，返回 `# 极简日记` | ✅ |
| 400 复发计数 | `grep -c INVALID_ARGUMENT language_server.log`（重启后新日志） | `0`（升级前同日志含 4 次） | ✅ |
| 代理链路 | mihomo `/connections` | 全部 `chains=[美国圣何塞07]`，无 DIRECT 失败 | ✅ |

---

## 经验沉淀与后续建议

1. **同为 HTTP 400，`INVALID_ARGUMENT` 与 `User location is not supported` 是两个世界**：前者是请求内容被业务层拒绝（换节点、重启梯子全无效），后者是地域准入。看到 400 先 `grep` 错误串定性，再决定动网络还是动客户端。
2. **判地域只能用带账号的真实调用，匿名请求恒返回 401**：Antigravity 的地区校验发生在认证之后，`daily-cloudcode-pa` 的裸请求无论出口在哪国都只回 `401 CREDENTIALS_MISSING`，所以「401=地域通过 / 400=地域受限」是错的（9-04 那篇的原始归纳，10-17、10-22 两篇已纠正）。本次因为顺着旧记录复用该判据而**又踩一次**，推送前核对远端新增记录才发现并撤回。教训：**复用历史判据前，先看仓库里有没有更新的纠正条目**；判据一旦被纠正，早期记录里的「验证命令」要当失效处理。
3. **对照实验比读日志更快收敛**：`agy` CLI 与桌面 App 同账号、同 `language_server` 内核、同端点。CLI 成功 + App 失败 = 问题一定在 App 侧请求构造，无需再查网络。
4. **会话 SQLite 库是取证金矿**：`~/Library/Logs/Antigravity/language_server.log` 只留摘要，完整 HTTP 状态、响应头、TraceID 与 body 存在 `~/.gemini/antigravity/conversations/<cascade_id>.db` 的 `steps` 表 `step_payload`（`step_type=17` 即错误步）。要上报 Google 就从这里取号。
5. **`ELECTRON_RUN_AS_NODE=1` 会让任何 Electron App「假死」**：在主程序里它把 App 降级成 Node 解释器，表现为「启动 → 0.1s exit 0 → 零日志零报错」，极易误判成升级把包装坏了。判据：`<App> --version` 打印的是 **Node 版本**（如 v24.21.0）而不是 App 版本；`--user-data-dir=x` 报 `bad option` 也是 Node 的报错格式。自动化 shell 里启动 GUI 一律 `env -u ELECTRON_RUN_AS_NODE open -n <App>`。
6. **Squirrel.Mac 只认「退出」**：`autoInstallOnAppQuit` 下，不退出就永远停在旧版，且 `main.log` 会每小时重复 `Update downloaded: <新号>`、ShipIt 每小时 `Detected this as an install request` 后无事离开。看到这套重复签名就该明白「不是更新坏了，是没人退出 App」。长期挂机用户建议主动 `osascript … quit`，别用 `kill -9`（会跳过安装钩子）。
7. **间歇性 400 不要用「一次复测通过」当结论**：本次 18 小时只 4 次，而同期同模型成功数百次。升级后复测通过只是必要条件；复发时先降到 Flash (Medium/Low) 或新开对话（社区验证有效的两个临时项），并带 TraceID 上报。
8. **顺手记录环境噪声，避免下次误归因**：`outside-of-project.json` 缺失（62 次）、`jetski-webchannel` 长轮询 reset（26 次）、`.blockmap` 404 导致差量更新永远整包（185MB/次）都是既有噪声，与 Gemini 400 无因果。

---

## 关键产物与现场位置（不含密钥）

- **失败会话**：cascade `d216881d-7653-438c-9b7f-eef175fc0540`，trajectory `0ac71e01-4778-4e3e-8de0-a4118dc8d7f0`，Error ID `…-3` / `…-4`
- **服务端 TraceID**：`0xfd6fb3b83d56a11d`（11:18:16）、`0x3a7f7e6de7e1cdcb`（11:18:24）
- **完整 400 报文位置**：`~/.gemini/antigravity/conversations/d216881d-7653-438c-9b7f-eef175fc0540.db` → 表 `steps`，`idx=3/4`，`step_type=17`，列 `step_payload`
- **模型标识**：UI 名 `Gemini 3.8 Flash (High)`，CLI id `gemini-3.8-flash-high`，内部枚举 `MODEL_PLACEHOLDER_M318`（见 `~/.gemini/antigravity/antigravity_state.pbtxt` 的 `last_selected_agent_model`）
- **调用端点**（`language_server` 启动参数原样）：`--api_server_url https://generativelanguage.googleapis.com`、`--cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com`
- **App 与日志**：`~/Applications/Antigravity.app`（Bundle ID `com.google.antigravity`）；`~/Library/Logs/Antigravity/{language_server.log,main.log}`
- **升级现场**：`~/Library/Caches/com.google.antigravity/pending/Antigravity.zip`（185MB, 2.28.0）、`~/Library/Caches/com.google.antigravity.ShipIt/{ShipItState.plist,ShipIt_stderr.log,update.CA6lFDs/}`
- **CDP 端口文件**：`~/Library/Application Support/Antigravity/DevToolsActivePort`（重启后端口会变；本次 63882 → 56542）
- **本次复测会话**：cascade `c1afc5db-6b58-4da6-b455-c9c280fce7b7`（标题 `Reading Project README First Line`，位于 Minimal Diary 项目，用户可在界面删除）
- **辅助脚本**：[`scripts/antigravity-gemini-healthcheck.mjs`](../scripts/antigravity-gemini-healthcheck.mjs) —— 一条命令输出 App 版本与 Squirrel 滞留、按错误串给 400 定性（地域拒绝 vs 请求构造被拒）、`agy` 带账号真实调用（权威地域判据）、匿名端点可达性、代理 `chains` 与界面错误卡；匿名 401 在脚本里只作连通性检查，不再当作地域结论
- **关联记录**：`2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md`（同为 400 但根因相反）
- **社区同签名参考**：oh-my-pi #9638「Gemini 3.7 Flash fails with 400 "Request contains an invalid argument" during long sessions」（临时项：新开会话 / 降思考档位）；Google IssueTracker 549870877（Android Studio Gemini 面板在文件读取后立刻 INVALID_ARGUMENT）；antigravity-cli #219（地域割裂现象，本次已排除）

---

*本文档记录了一次「用户以为是网络、实际是客户端」的完整反证过程：先用代理 `chains`、带账号真实调用与错误串分类三条独立证据排除网络与地域，再把故障面压缩到桌面客户端的请求构造；同时暴露出 Squirrel「退出才安装」在长期不退出场景下的静默失效，App 因此在带缺陷的 2.27.0 上多跑了 10 小时。另有两条附带教训：自动化 shell 里的 `ELECTRON_RUN_AS_NODE=1` 会让 Electron 应用以 0 状态秒退且零日志，极易被误判为升级失败；而「匿名请求返回 401 就代表地域通过」这一早期记录里的判据是错的（地区校验发生在认证之后），本次复用旧判据被远端新记录纠正并撤回。*
