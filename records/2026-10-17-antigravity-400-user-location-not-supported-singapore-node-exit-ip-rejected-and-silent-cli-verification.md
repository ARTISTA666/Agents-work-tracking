# Antigravity 调用 Gemini 报 HTTP 400「User location is not supported」：新加坡SG-A 出口 IP 被 Google 内部 Daily 通道拒绝，切日本JP-HY2 后静默 CLI 全量恢复，并修正「无认证 401 可判地域」的错误判据

> **2026-10-22 后续验证与适用范围补充**：见 [Antigravity 启动、代理、更新与桌面 Gemini 修复记录](2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)。10 月 17 日的节点失败是当时已测样本的历史结果，不能扩大为整个订阅永久不可用；10 月 22 日在同一「赔钱机场」订阅的美国圣何塞 07 节点，桌面 Gemini 已两次真实生成成功，其中一次是在 FlClash 重启及 Antigravity 从访达冷启动后。另，本篇独立 `agy` CLI 的进程路径与桌面 `language_server` 不同，不命中后续新增的桌面专用 `PROCESS-PATH` 规则；复用自检时应核对实际分流和模型，桌面故障需补充桌面真实调用。以下原文保留当时的过程与结论。

## 基本信息

- **处理者身份**：DeepSeek Harness（DSH）Agent（本次会话 AI 协作代理，主排查与根因定位；全程采用静默排查方式）
- **问题类型**：
  1. Antigravity 中调用 Gemini 报 `HTTP 400 / FAILED_PRECONDITION / User location is not supported for the API use`，Agent 任务直接终止
  2. 当时 FlClash「节点选择」= 新加坡SG-A，其出口 IP `50.7.253.42` 被 `daily-cloudcode-pa.googleapis.com` 的地区校验拒绝
  3. 前一轮排查遗留的两套判据（`generativelanguage` + API Key；无认证 POST 看 400/401）都无法代表 Antigravity 通道，导致「换了节点仍然报错」
  4. 附加问题：FlClash「自动运行」关闭，冷启动后代理不自动启用，网络一度变成直连
- **报错时间**：2026-10-17 13:04:35（Asia/Shanghai，UTC+8）
- **解决确认时间**：2026-10-17 14:02（Asia/Shanghai，UTC+8）
- **最终状态**：已解决（FlClash 节点选择切为 **日本JP-HY2**，出口 `18.183.159.2`；官方 CLI 静默实测 `agy -p` 连续 2/2 返回 `PONG`、0 次地域错误；同时打开「自动运行」防止冷启动裸连）
- **关联项目/仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)
- **与既有记录关系**：这是本仓库**第 2 次**记录「Antigravity 400 地域限制」。第 1 次见 `2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md`（台湾 HiNet IP）。本篇除记录本次修复外，还用实验**修正**了第 1 次记录中的验证判据（详见「根因分析 · 两次对比」与「经验沉淀」第 1 条），并推翻「机房 IP 一律被拒」的推断。
- **处理环境**：
  - macOS（MacBook Air，Apple Silicon）
  - Antigravity **2.23.1**（Bundle ID `com.google.antigravity`，路径 `/Users/yusong/Applications/Antigravity.app`）
  - FlClash **0.9.0**（build `2026101401`），订阅「魔戒.net(1)」（profile id `368616939334930432`）
  - 代理形态：TUN 透明代理 + 系统代理 `127.0.0.1:7890`
  - 官方 Antigravity CLI：`agy` 1.1.22（`~/.local/bin/agy`）

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 13:04 | 用户 | 在 Antigravity 中执行任务，**会话首次模型调用即失败**；随后退出应用，并先与豆包排查一轮，未解决，留下 `Antigravity_Gemini_排查摘要.md` |
| 13:23 | 用户 | 把摘要交给 DSH，明确要求「先 100% 定位问题，再解决」，并说明后续希望静默排查、不要干扰桌面工作 |
| 13:24–13:31 | DSH | 现场取证：定位报错请求与日志行；确认 TUN 生效；实测出口 IP `50.7.253.42`（SG）；读取 FlClash 数据库确认「节点选择」= 新加坡SG-A；确认 `daily-cloudcode-pa` 无专门规则、走 `MATCH,节点选择` |
| 13:28 | DSH | 用官方 `agy` CLI **无窗口复现**同款报错：`FAILED_PRECONDITION (400): User location is not supported` |
| 13:29–13:34 | DSH | 对照实验：把 `HTTPS_PROXY` 指向不存在的端口 → 得到 `connection refused`，证明 `agy` 确实走指定代理；随后为每个候选节点起独立 mihomo 实例逐节点实测：日本JP-HY2 / 新加坡SG-HY2 ✅，日本JP-A / 美国USLA-A ❌ |
| 13:35–13:50 | DSH | 把 FlClash「节点选择」改为 **日本JP-HY2** 并重启客户端；出口变日本；经**真实 TUN 路径**（不设任何代理环境变量）静默复测得到 `PONG` |
| 13:49–13:53 | 用户/客户端 | 「节点选择」被切回 **新加坡-优化-GPT**（出口 `66.90.98.146`），`agy` 连续 3 次复现 400 → 反向验证「判定跟着出口 IP 走，与账号无关」 |
| 13:55–14:01 | DSH | 发现 FlClash 冷启动后代理未自动启用（7890 未监听、系统代理关闭、出口 `223.241.37.5` 直连）；定位到客户端 `autoRun` 逻辑后打开「自动运行」 |
| 14:02 | DSH | 最终验证：出口 `18.183.159.2`（JP），`agy` 连续 2/2 `PONG`；`antigravity-silent-check.sh` 自检 ✅ |
| 14:05–14:20 | DSH | 按仓库范式归档本篇记录，并提交两个静默排查脚本 |

---

## 问题详细描述

用户在 macOS 上使用 Google Antigravity（AI Agent IDE），在 Agent 面板发起任务后，应用弹窗报错并终止：

```
Agent execution terminated due to error
```

底层日志（`~/Library/Logs/Antigravity/language_server.log`）给出：

```
ERROR: ... errorreport.go:224] agent executor error: generating and executing:
FAILED_PRECONDITION (code 400): User location is not supported for the API use.
```

前一轮排查（豆包）的结论停留在：「Gemini 网页能访问，但 Antigravity 不行」「怀疑出口 IP 的机房属性」，并产出了一份「43 节点体检报告」。用户按照该报告更换节点后仍然失败，因此把问题交给 DSH。

用户对本次排查提出两点硬要求：

1. **先 100% 定位问题，再解决**——不接受「换节点试试」式的碰运气；
2. **排查要静默**——本次排查中 DSH 早期为了复现，多次重启 FlClash、反复激活应用，导致窗口频繁弹出、并一度让网络变成直连；用户明确要求「查归查，别把网络搞崩」。

这两点直接决定了后续的方法论：**改用隔离代理实例 + 无窗口 CLI（`agy`）做真实调用验证，不再触碰 FlClash 的选择与进程**。

---

## 排查过程与关键技术证据

### 1. 报警链定位：不是网络、不是账号、不是程序 bug

```bash
# 报错行与相邻调用
grep -n -E "FAILED_PRECONDITION|User location|http_helpers.go|Auth succeeded" \
  ~/Library/Logs/Antigravity/language_server.log | tail -20
```

证据：

| 时间 | 事件 | 状态 |
| --- | --- | --- |
| 12:59:45 | `daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` | 正常返回 |
| 12:59:49 | `Auth succeeded, refreshing features and managers` | 账号/登录正常 |
| 13:04:35 | `agent executor error: generating and executing: FAILED_PRECONDITION (code 400): User location is not supported for the API use.` | ❌ 被拒 |
| 13:04:39 | `conversation title generation ... FAILED_PRECONDITION (code 400)` | ❌ 被拒 |
| 13:04:56 | `daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` | 请求已发出 |

结论：

- 报错是 **Google 服务端业务层返回的完整错误**（能拿到 `FAILED_PRECONDITION` 结构体），说明请求**已经到达 Google 后端**——不是网络不通、不是 DNS 污染、不是 TUN 失效；
- `loadCodeAssist` 成功 + `Auth succeeded` 说明**账号、登录态、项目都正常**；
- 只有「模型调用 / 标题生成」这类推理请求被地区校验拦下。

### 2. 出口与路由取证

```bash
scutil --proxy                          # 系统代理设置
curl -s -4 https://www.cloudflare.com/cdn-cgi/trace   # 真实出口
curl -s -4 https://api.ipify.org
sqlite3 ~/Library/Application\ Support/com.follow.clash/database.sqlite \
  "select label, selected_map from profiles"
grep -n -iE "cloudcode|googleapis|MATCH" \
  ~/Library/Application\ Support/com.follow.clash/config.yaml | tail -5
```

证据：

```
ip=50.7.253.42
loc=SG
colo=SIN

selected_map = {"节点选择":"新加坡SG-A", ...}
规则末尾： - "MATCH,节点选择"
```

结论：FlClash 处于 TUN 模式且工作正常，**全部流量出口 = 新加坡SG-A = `50.7.253.42`**；`daily-cloudcode-pa.googleapis.com` 在订阅规则里没有任何专门匹配项，命中最后的 `MATCH,节点选择`。

### 3. 无窗口复现（后续所有对照实验的前提）

利用 Antigravity 官方 CLI（与 IDE 共用同一套云后端、同一账号）做无窗口调用：

```bash
agy -p "Reply with exactly: PONG" --print-timeout 120s
```

复现输出：

```
error: FAILED_PRECONDITION (code 400): User location is not supported for the API use.
AGY_ERROR: {"short_error":"FAILED_PRECONDITION (code 400): User location is not supported for the API use.",
            "status":"INVALID_ARGUMENT","error_code":400,"code_kind":"http","retryable":false}
```

**对照实验（证明 `agy` 尊重 `HTTPS_PROXY`，避免「以为走了节点、其实直连」）**：

```bash
HTTPS_PROXY=http://127.0.0.1:22999 HTTP_PROXY=http://127.0.0.1:22999 \
  agy -p "Reply with exactly: PONG" --print-timeout 60s
# 日志：
# Post "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist":
#   proxyconnect tcp: dial tcp 127.0.0.1:22999: connect: connection refused
```

→ 得到的是**代理连接失败**而不是地区错误，说明后续逐节点测试中 `HTTPS_PROXY` 确实生效。

### 4. 逐节点隔离实测（同一账号、同一客户端、同一台机器）

方法：从 FlClash 当前订阅里抽出单个节点，为它单独起一个临时 mihomo 实例（仅监听 `127.0.0.1`，`ipv6: false`，与 FlClash 生成配置一致），再把 `HTTPS_PROXY` 指向该端口，用 `agy` 做一次**真实模型调用**。

实测结果：

| 节点 | 协议 | 实测出口 IP | Antigravity 真实调用 | 证据时间 |
| --- | --- | --- | --- | --- |
| **日本JP-HY2** | hysteria2 | `54.238.201.244` / `52.199.115.225` / `13.208.42.198` / `18.183.159.2`（AWS 东京，出口轮换） | ✅ `PONG`（9/9 次） | 13:29–14:12 |
| **新加坡SG-HY2** | hysteria2 | `13.250.231.23` / `13.212.17.45` / `18.138.236.182`（AWS 新加坡） | ✅ `PONG`（6/6 次） | 13:33–14:14 |
| 新加坡SG-A（故障时选中） | anytls | `50.7.253.42` | ❌ `User location is not supported` | 13:04（IDE 日志）/ 13:28（agy 经真实 TUN） |
| 日本JP-A | anytls | `66.90.99.234` | ❌ `User location is not supported` | 13:29 |
| 美国USLA-A | anytls | `108.181.9.93` | ❌ `User location is not supported` | 13:31 |
| 新加坡-优化-GPT | vmess | `66.90.98.146` | ❌ `User location is not supported` | 13:50 / 13:52 / 13:53 / 14:13（5 次） |

补充说明（如实记录）：

- 日本JP-A、新加坡SG-A 在 14:10 之后复测时出现 `Eligibility check failed ... EOF`（拉取 `www.googleapis.com/oauth2/v2/userinfo`、`lh3.googleusercontent.com` 时连接被断），属于**这两个节点自身不稳定**，不是地域结论；它们在 13:04–13:31 的报错证据已足够。
- 同一节点在不同时间出口 IP 会轮换（见上表 JP-HY2 / SG-HY2），而判定结果按「当次出口 IP」走。

结论：

1. **同一个账号**换到 JP-HY2 / SG-HY2 立刻可用 → 排除账号地区问题；
2. 日本JP-HY2 是 **AWS 机房 IP**，照样可用 → 排除「机房 IP 一律被拒」；
3. 被拒的都是**具体 IP**（`50.7.253.42`、`66.90.99.234`、`108.181.9.93`、`66.90.98.146`）→ 判定粒度是 IP。

### 5. 关键修正一：无认证探测**不能**判断地域（推翻第 1 次记录的判据）

第 1 次记录（2026-09-04）的核心验证方法是：

```bash
curl -s -X POST https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent \
  -H "Content-Type: application/json" -d '{"model":"...","contents":[...]}'
# 返回 401 → 判定"地域已通过"；返回 400 + User location → 判定"地域受限"
```

本次用实验检验这个判据：

| 出口 | 节点真实状态（已验证） | 无认证 POST `loadCodeAssist` |
| --- | --- | --- |
| `13.208.42.198`（日本JP-HY2） | ✅ 可用（agy `PONG`） | `HTTP 401 UNAUTHENTICATED` |
| `66.90.98.146`（新加坡-优化-GPT） | ❌ 被拒（agy 400） | `HTTP 401 UNAUTHENTICATED` |

两者**完全相同**。同理，`generativelanguage.googleapis.com/v1beta/models?key=INVALID` 从任何节点都返回 `400 API_KEY_INVALID`，也无法区分地区。

原因：Antigravity 的地域校验发生在**认证之后**（业务层，`PredictionService.GenerateContent`），无认证请求在认证层就被拦下返回 401，**根本到不了会做地区判定的那一层**。

结论：**「401 = 地域通过」是错误的判据**。第 1 次记录中该步骤的结论只是「碰巧对了」（换节点确实恢复了），判据本身不成立。正确做法是**用同一账号做一次真实模型调用**（`agy -p` 或 Antigravity 本体）。

### 6. 关键修正二：`generativelanguage` 的可用性 ≠ Antigravity 可用

前一轮排查生成过「43 节点体检报告」，其判据是 **Gemini API Key + `generativelanguage.googleapis.com`**。本次实测反例：

| 节点 | 旧报告（generativelanguage + API Key） | 本次（Antigravity 真实调用） |
| --- | --- | --- |
| 日本JP-A（`66.90.99.234`） | ✅ 4/4 通过 | ❌ `User location is not supported` |
| 美国USLA-A（`108.181.9.93`） | ✅ 4/4 通过 | ❌ `User location is not supported` |
| 新加坡-优化-GPT（`66.90.98.146`） | ✅ 4/4 通过 | ❌ `User location is not supported` |
| 日本JP-HY2 / 新加坡SG-HY2 | ✅ 通过 | ✅ 通过 |

→ `daily-cloudcode-pa`（Antigravity / Code Assist 通道）与 `generativelanguage`（公开 Gemini API 通道）**判定集合不同**。这也解释了「按旧报告选节点仍然失败」。

### 7. 修复与真实路径验证

```bash
# 1) 记录当前选择（便于回滚）
sqlite3 "$FLCLASH_DIR/database.sqlite" "select selected_map from profiles"

# 2) 将「节点选择」改为 日本JP-HY2
python3 - <<'PY'
import sqlite3, json, os
db = sqlite3.connect(os.path.expanduser('~/Library/Application Support/com.follow.clash/database.sqlite'))
row = db.execute("select id, selected_map from profiles").fetchone()
m = json.loads(row[1]); m["节点选择"] = "日本JP-HY2"
db.execute("update profiles set selected_map=? where id=?",
           (json.dumps(m, ensure_ascii=False, separators=(',', ':')), row[0]))
db.commit(); db.close()
PY

# 3) 完全退出并重新启动 FlClash（让新选择生效）
osascript -e 'quit app "FlClash"'; sleep 5; open -a FlClash

# 4) 真实 TUN 路径验证（不设 HTTPS_PROXY，等价于 Antigravity 的实际路径）
curl -s -4 https://api.ipify.org            # → 18.183.159.2 (JP)
agy -p "Reply with exactly: PONG" --print-timeout 120s   # → PONG，0 次地域错误
```

验证过程中出现一次**反向验证**：13:49 左右「节点选择」被切换为 新加坡-优化-GPT（出口 `66.90.98.146`），`agy` 立刻连续 3 次复现 `User location is not supported`；再次设回 日本JP-HY2 后恢复。→ 证明故障随出口 IP 走，与账号、客户端版本、缓存都无关。

### 8. 附加问题：FlClash 冷启动后代理不自动启用

现象（排查期间多次重启客户端后出现）：

```bash
nc -z 127.0.0.1 7890        # 关闭
scutil --proxy | grep Enable # HTTPEnable: 0 / HTTPSEnable: 0
curl -s -4 https://api.ipify.org  # 223.241.37.5 → 直连中国出口
```

源码定位（FlClash 0.9.0，`lib/providers/actions/setup.dart:138`）：

```dart
final shouldRun = _isRunning || ref.read(appSettingProvider).autoRun;
```

其中 `_isRunning` 仅表示「本次进程内是否已启动」，冷启动时为 false；`autoRun` 即设置里的「自动运行」（`autoRunDesc`：*自动运行会在打开应用时启动代理*）。当时该选项为 **false**，因此冷启动不会自动开代理。

处理：把 `appSettingProps.autoRun` 置为 `true`（等价于在 FlClash 设置里勾选「自动运行」）：

```bash
defaults export com.follow.clash /tmp/com.follow.clash.prefs.bak   # 先备份
python3 - <<'PY'
import subprocess, json
raw = subprocess.run(['defaults','read','com.follow.clash','flutter.config'],
                     capture_output=True, text=True).stdout
cfg = json.loads(raw); cfg['appSettingProps']['autoRun'] = True
subprocess.run(['defaults','write','com.follow.clash','flutter.config','-string',
                json.dumps(cfg, ensure_ascii=False, separators=(',', ':'))], check=True)
PY
```

验证：重启客户端后 `7890` 监听恢复、系统代理 `HTTPEnable: 1`、出口回到日本节点。

---

## 根因分析

### 1. 直接原因

出口 IP `50.7.253.42`（新加坡SG-A）调用 `daily-cloudcode-pa.googleapis.com/v1internal:generateContent` 时，被 Google 服务端以 `HTTP 400 / FAILED_PRECONDITION / User location is not supported for the API use` 拒绝；换到 `18.183.159.2`（日本JP-HY2）后同一账号、同一客户端、同一网络立刻恢复正常。

### 2. 深层原因一：Antigravity 内部 Daily 通道有独立、未公开的地域判定（延续第 1 次记录）

- Antigravity 实际调用 `daily-cloudcode-pa.googleapis.com`（`v1internal`，Code Assist / Daily 通道），不是公开的 Gemini API；
- 该通道的地域判定与 `generativelanguage.googleapis.com` 不一致（本次有明确反例）；
- 判定粒度是**具体出口 IP**，不是国家、不是 ASN 类型（住宅/机房）。

### 3. 深层原因二：判据错位（本次新发现）

前一轮排查用「`generativelanguage` + API Key」得到的节点可用性，被直接当作 Antigravity 的可用性；同时用「无认证 POST 的 400/401」判断地区。两套判据都与 Antigravity 的实际通道不匹配，导致「换节点仍然失败」的原因为判据错，而不是节点都不行。

### 4. 深层原因三：出口 IP 会轮换，导致同一节点时好时坏

JP-HY2 在不同时间观测到 `54.238.201.244`、`52.199.115.225`、`13.208.42.198`、`18.183.159.2` 等多个出口。机场侧负载均衡/轮换会让「上一分钟能用的节点」在下一分钟换到被拒 IP。因此**结论必须带时间戳，并且要能随时复测**。

### 5. 附因：FlClash 冷启动不自动开代理

`autoRun=false` 时，客户端冷启动只加载配置、不启动代理，表现为「网络突然变直连」。本次排查期间的重启放大了这一现象，也提醒了「排查代理问题不要反复重启全局客户端」的方法论问题。

### 6. 两次 Antigravity 地域限制对比

| 维度 | 第 1 次（2026-09-04） | 第 2 次（2026-10-17，本次） |
| --- | --- | --- |
| Antigravity 版本 | 2.12.0（`/Applications/Antigravity.app`） | 2.23.1（`~/Applications/Antigravity.app`） |
| 被拒出口 IP | `111.243.99.217`（台湾 HiNet 家宽，AS3462） | `50.7.253.42`（新加坡机房，节点名「新加坡SG-A」，AS30058 FDCservers） |
| 节点显示名称 | 台湾原生节点 | 新加坡 |
| 报错时机 | Agent 已跑约 44 秒，第 10 次调用才被拒 | **会话首次**模型调用即被拒，标题生成也失败 |
| 当时验证手段 | 无认证 POST 看 400/401（判据不成立） | 同账号官方 CLI 真实调用（`agy`）+ 死代理对照实验 |
| 修复节点 / 出口 | `216.195.192.183`（Eons，第三方库归属香港/新加坡/美国不一致） | 日本JP-HY2（AWS 东京，出口轮换，取 `18.183.159.2`） |
| 恢复验证 | 重启后 14 次调用 0 地域错误 | `agy` 2/2 `PONG` + 同账号逐节点对照（JP-HY2 9/9、SG-HY2 6/6） |
| 附加问题 | Agent 弹窗终止后需完全重启 | FlClash `autoRun=false` 导致冷启动直连 |

**相同点**：

1. 错误串、端点、层级完全相同：`HTTP 400 / FAILED_PRECONDITION / User location is not supported`，来自 `daily-cloudcode-pa`，属服务端业务层地域准入；
2. 都不是网络不通、不是 DNS 污染、不是账号不可用、不是程序 bug；
3. 根因都是「**当前出口 IP 不在该内部端点的可接受集合里**」；
4. 换节点即可解决，不需要重装/升级/清缓存；
5. 节点名称、第三方 IP 库归属都不可信，只有 Google 服务端的判定才算数；
6. 「Gemini 网页能用」≠「Antigravity 能用」，各平台/各端点白名单相互独立；
7. 换完必须让新连接生效（完全退出重启 Antigravity / 客户端）。

**不同点**：

1. **出口 IP 类型相反**：第 1 次是台湾住宅宽带（HiNet），本次是新加坡机房 —— 说明判定与「住宅/机房」无关，只看具体 IP；本次 AWS 东京机房 IP 可用，直接推翻「机房 IP 必被拒」的猜测。
2. **报错时机不同**：第 1 次「前 9 次成功、第 10 次失败」，当时被归因为「灰度/概率性校验」；本次是**确定性首次即失败**，且同一 IP 多轮稳定复现（同一 IP 下 `agy` 连跑 3 次全部 400）→ 灰度假说至少不是必要条件。
3. **判据有效性不同**：第 1 次的「无认证 400/401」判据本次已被实验证伪；本次改为「带账号真实调用」。
4. **反例类型不同**：第 1 次的反例是「香港 IP 对 OpenAI 封、对 Google 通」；本次的反例是「`generativelanguage` 通过 ≠ `cloudcode-pa` 通过」（JP-A / USLA-A / SG-优化-GPT）。
5. **附加故障不同**：第 1 次是客户端根本没运行（FlClash 未启动）；本次是客户端在运行但冷启动没开代理（`autoRun=false`）——表象都是「看起来没走代理」，原因不同。

### 7. 仓库内全部「Gemini / Google 访问」相关记录速览

| 日期 | 记录 | 表象 | 真正根因 | 与本次关系 |
| --- | --- | --- | --- | --- |
| 2026-09-02 | Gemini 网页端网络连接失败 | 网页发消息失败、提示检查网络 | Chrome 普通配置的站点数据/Cookie 异常（非网络、非地域） | 同为「Gemini 不能用」，但故障在浏览器本地状态，与地域无关 |
| 2026-09-04 | FlClash 未运行 + DNS 污染 | Google 地区限制、Antigravity 用不了 | 客户端未运行 + 系统 DNS 被污染 | 网络层前置故障；本次的「冷启动直连」属于同类表象、不同原因 |
| 2026-09-04 | ChatGPT unsupported country | ChatGPT 登录被拒 | 节点名「伪新加坡」、实为香港 IP + ClashX Meta DNS 泄漏 | 「地域判定按 IP、平台间不类推」的早期证据（同一 IP 对 OpenAI 封、对 Google 通） |
| 2026-09-04 | Antigravity 400 台湾 IP | Antigravity 弹窗终止 | 台湾 HiNet 出口 IP 被 Daily 通道拒绝 | **第 1 次同款** |
| **2026-10-17** | **本篇** | **Antigravity 报错终止** | **新加坡机房出口 IP 被 Daily 通道拒绝 + 判据错位** | **第 2 次同款，并修正第 1 次的验证判据** |

---

## 解决方案与落地操作

### 步骤 1：先用「真实调用」判断当前出口是否可用（静默）

```bash
bash scripts/antigravity-silent-check.sh
# 或直接：
agy -p "Reply with exactly: PONG" --print-timeout 90s
```

- 输出 `PONG` → ✅ 当前出口可用，Antigravity 本身没问题；
- 输出 `User location is not supported` → ❌ 当前出口被拒，进入步骤 2。

> 不要用「无认证 curl 返回 401/400」判断地区，也不要只看第三方 IP 归属地。

### 步骤 2：在 FlClash 中换到已验证可用的节点

已验证可用（2026-10-17）：

- **日本JP-HY2**（推荐，出口日本 AWS）
- **新加坡SG-HY2**

已验证不可用（本次）：

- 新加坡SG-A（`50.7.253.42`）
- 日本JP-A（`66.90.99.234`）
- 美国USLA-A（`108.181.9.93`）
- 新加坡-优化-GPT（`66.90.98.146`）

操作：FlClash → 代理 → 节点选择 → 选中目标节点。
（若用命令行/脚本方式，可直接改 `database.sqlite` 的 `profiles.selected_map`，如第 7 节所示；改完需完全退出重启 FlClash。）

### 步骤 3：让新出口生效并复测

```bash
curl -s -4 https://api.ipify.org     # 确认出口已变
bash scripts/antigravity-silent-check.sh
```

- Antigravity 是长连接进程，切换节点后建议完全退出并重新打开 Antigravity，确保新连接走新出口。

### 步骤 4：可选——批量体检候选节点（静默、不影响 FlClash 当前选择）

```bash
bash scripts/antigravity-node-probe.sh 日本JP-HY2 新加坡SG-HY2 新加坡SG-A 日本JP-A
```

脚本会为每个节点起独立临时 mihomo 实例，用 `agy` 做真实调用，输出 `✅ 可用 / ❌ 地区拒绝 / ⚠️ 其他失败` 与出口 IP。

### 步骤 5：修掉「冷启动直连」

FlClash → 设置 → 打开「自动运行」。
（否则完全退出客户端后重新打开，代理不会自动启用。本次排查中该问题一度让网络变直连。）

---

## 验证与效果

| 验证项 | 验证命令 / 方式 | 实际结果 | 状态 |
| --- | --- | --- | --- |
| 出口 IP 切换 | `curl -s -4 https://api.ipify.org` | `50.7.253.42`（SG）→ `18.183.159.2`（JP） | ✅ |
| 官方 CLI 真实调用（隔离代理） | `HTTPS_PROXY=... agy -p "PONG"` | 日本JP-HY2 ✅ 9/9；新加坡SG-HY2 ✅ 6/6；JP-A/USLA-A/SG-优化-GPT ❌ | ✅ |
| 真实 TUN 路径调用（不设代理环境变量） | `agy -p "PONG"` | `PONG` 2/2，0 次 `User location is not supported` | ✅ |
| 反向验证 | 切到 新加坡-优化-GPT（`66.90.98.146`）后重跑 | 连续 3 次复现 400；切回 JP-HY2 恢复 | ✅ |
| 无认证探测判据检验 | 分别从「可用」与「被拒」出口 POST `loadCodeAssist` | 两者均 `HTTP 401 UNAUTHENTICATED` → 判据无效 | ✅ |
| 静默自检脚本 | `bash scripts/antigravity-silent-check.sh` | 出口 `18.183.159.2`，结论 ✅ | ✅ |
| 节点探针脚本 | `bash scripts/antigravity-node-probe.sh ...` | 2 可用 / 1 地区拒绝，出口 IP 正常打印 | ✅ |
| 自动运行修复 | 重启 FlClash 后检查 | `7890` 监听恢复、`HTTPEnable: 1`、出口为日本节点 | ✅ |

---

## 经验沉淀与后续建议

1. **（重要）判断 Antigravity 地区是否受限，必须用「带账号的真实模型调用」**。无认证请求永远返回 401，`generativelanguage` 的 400/200 也不能代表 `cloudcode-pa`。推荐用官方 CLI：`agy -p "Reply with exactly: PONG"`，返回 `PONG` = 可用，返回 `User location is not supported` = 被拒。**本仓库 2026-09-04 记录中的「无认证 400/401」判据据此作废**（该文其余结论仍然有效）。

2. **Antigravity 走内部 Daily 通道，地域判定独立且未公开**：与公开 Gemini API 的支持地区列表无关，与「Gemini 网页能不能用」也无关。

3. **不能按「机房 IP / 住宅 IP」一刀切**：本次 AWS 东京机房 IP 可用，台湾住宅 IP 反而被拒（第 1 次记录）。判定只认具体 IP。

4. **同一节点出口 IP 会轮换**，所以「上次能用」不代表这次能用；结论要带时间戳，并且要能随时复测。

5. **节点名称、第三方 IP 库归属都不可信**：以 Google 服务端自身判定为准（真实调用结果）。

6. **各平台白名单相互独立**：同一 IP 可能对 OpenAI 封、对 Google 通；`generativelanguage` 通过也可能 `cloudcode-pa` 被拒。换节点只能针对「目标平台」逐一验证。

7. **排查代理问题要静默、可控**：不要反复重启全局客户端、不要反复拉起 GUI。用「独立临时 mihomo 实例 + 无窗口 CLI」做隔离测试，既能保证「测试链路等价于选中该节点」，又不会干扰用户桌面与网络（本仓库 `scripts/antigravity-node-probe.sh` 即为此用途）。

8. **改 FlClash 的选择要改在「节点选择」这个组上**：`daily-cloudcode-pa` 没有专门规则，命中 `MATCH,节点选择`；`generativelanguage` 等走 `Gemini` 组，而 `Gemini` 组只有一个「节点选择」选项，所以两者都跟着「节点选择」走。以后手动切节点会连带影响 Antigravity。

9. **切换节点后要完全退出重启 Antigravity**：长连接进程可能保留旧出口；「重试」按钮不一定重建连接。

10. **顺手修掉「冷启动不自动开代理」**：FlClash 设置里的「自动运行」（`autoRun`）关闭时，重开客户端不会自动启动代理，容易误判为「网络坏了」。把它打开，或每次启动后确认 7890 端口/系统代理状态。

11. **排查记录里不要写未经检验的判据**：第 1 次记录的「401 = 地域通过」看似合理，但从未在「被拒 IP」上做过对照，导致后续排查被误导。以后写判据时，务必给出「正例 + 反例」双向验证。

---

## 关键产物与现场位置（不含密钥）

- **Antigravity 路径 / 版本**：`/Users/yusong/Applications/Antigravity.app`，2.23.1，Bundle ID `com.google.antigravity`
- **Antigravity 日志**：`~/Library/Logs/Antigravity/language_server.log`（本次核心证据，报错在 13:04:35）、`~/Library/Logs/Antigravity/main.log`
- **Antigravity 用户数据**：`~/Library/Application Support/Antigravity/`、`~/.gemini/antigravity/`
- **Antigravity CLI**：`~/.local/bin/agy`（1.1.22）、配置 `~/.gemini/antigravity-cli/settings.json`
- **FlClash 配置 / 数据库**：
  - `~/Library/Application Support/com.follow.clash/config.yaml`（生成的 mihomo 配置）
  - `~/Library/Application Support/com.follow.clash/database.sqlite`（`profiles.selected_map` 保存「节点选择」等分组选择）
  - `~/Library/Application Support/com.follow.clash/profiles/<id>.yaml`（订阅原始节点，本次 id `368616939334930432`）
  - macOS 偏好：`~/Library/Preferences/com.follow.clash.plist`（`flutter.config` 内的 `appSettingProps.autoRun`）
- **Antigravity 实际端点**：`https://daily-cloudcode-pa.googleapis.com/v1internal:{loadCodeAssist,fetchAvailableModels,generateContent,streamGenerateContent}`
- **本次被拒出口 IP**：`50.7.253.42`（新加坡SG-A）、`66.90.99.234`（日本JP-A）、`108.181.9.93`（美国USLA-A）、`66.90.98.146`（新加坡-优化-GPT）
- **本次恢复后出口 IP**：`18.183.159.2`（日本JP-HY2，AWS 东京；该节点出口会轮换）
- **复现 / 自检命令**：

  ```bash
  # 静默自检（真实调用）
  agy -p "Reply with exactly: PONG" --print-timeout 90s

  # 死代理对照（验证 agy 是否真的走指定代理）
  HTTPS_PROXY=http://127.0.0.1:22999 HTTP_PROXY=http://127.0.0.1:22999 \
    agy -p "Reply with exactly: PONG" --print-timeout 60s
  ```

- **本次新增脚本**：
  - `scripts/antigravity-silent-check.sh`：静默自检当前出口是否被 Antigravity 接受
  - `scripts/antigravity-node-probe.sh`：静默逐节点体检（独立临时 mihomo + `agy` 真实调用，不影响 FlClash 当前选择）

---

*本文档记录了同一类 Antigravity 地域限制问题的第二次发生：两次的表象与端点一致，但触发 IP 类型（台湾住宅 vs 新加坡机房）、报错时机（运行中 vs 首次调用）不同；同时用双向对照实验修正了第一次记录中的「无认证 400/401」判据，并给出了可重复的静默验证方法（官方 CLI + 隔离代理实例）。*

---

## 补充：同日 18:00 · 新订阅「赔钱机场」实测（同款问题再次触发）

> 同一自然日傍晚，用户新增并切换到第二个订阅「赔钱机场」后，Antigravity **再次**报同一错误。以下是增量复测结论，主结论无需修改。

### 现象

- 16:46 新增订阅「赔钱机场」（profile id `369768027173949440`，70 个节点）并切换；
- 17:58:26、17:59:00 Antigravity 再次报 `FAILED_PRECONDITION (400): User location is not supported`（`language_server.log`）；
- 当时 TUN 出口 `103.62.49.170`（JP）。

### 发现 1：用户「切换的节点」其实没有生效（GLOBAL ≠ 规则模式）

- 新订阅有独立分组：`🚀节点选择`（select，首选 `♻️自动选择`）、`🐟漏网之鱼`、`🤖AI网站` 等；规则末尾是 `MATCH,🐟漏网之鱼`，而 `🐟漏网之鱼` 首选 `🚀节点选择`；
- 用户实际是在 `GLOBAL` 组里选了「🇸🇬新加坡05-0.1倍」，`selected_map` 里也只记录了 `GLOBAL` 一项；
- 但 FlClash 当前是**规则模式**，`GLOBAL` 组不参与规则路由，真正生效的是 `♻️自动选择`（url-test）；
- 逐节点隔离实测：`103.62.49.170` 正是「🇯🇵日本东京03-0.1倍」的出口 → Antigravity 实际走的是自动选择挑出的日本节点，**不是**用户以为的新加坡节点。

**教训**：选节点必须在「实际参与规则」的组里选（本订阅是 `🚀节点选择`）；`GLOBAL` 只在全局模式下有效。

### 发现 2：该订阅的出口池全部被 Antigravity 拒绝（或不可用）

用隔离实例逐节点拿到出口 IP，再对每个出口做一次真实调用（`agy`）：

| 节点（示例） | 出口 IP | Antigravity |
| --- | --- | --- |
| 🇯🇵日本东京01 / AWS日本01（共用 JP 池） | `103.62.49.138` | ❌ User location is not supported |
| 🇯🇵日本东京03（当时实际生效） | `103.62.49.170` | ❌ User location is not supported |
| 🇸🇬新加坡05 | `67.159.48.150` | ❌ User location is not supported |
| 🇸🇬新加坡01 / AWS新加坡01 / 新加坡hy2（共用 SG 池） | `67.159.48.146` | ❌ User location is not supported |
| 🇺🇸美国圣何塞01 | `162.251.162.203` | ❌ User location is not supported |
| 🇹🇼台湾（HiNet 家宽） | `1.161.55.5` | ⚠️ 无法完成调用：拉 `lh3.googleusercontent.com` 连续 3 次 EOF（节点侧连不通该 Google CDN，非地区判定） |

→ 该订阅出口集中在少数几个共享 IP 池，均不在 Antigravity 的可接受集合内；按目前探测结果，**这个订阅无法支撑 Antigravity**。

### 发现 3：测试方法需绕开 FlClash TUN（否则会误判节点不可用）

FlClash TUN 开启时，临时 mihomo 实例解析订阅服务器域名会得到 `198.18.x.x` 的 fake-ip，连接被 TUN 再劫持一次（双重代理），部分节点会表现为超时或 `REALITY authentication failed`，从而**误判为节点不可用**。

解决办法：给临时 mihomo 配置加 `interface-name: <默认接口>`（本机 `en0`），让「连节点服务器」这一跳直接走物理网卡、绕开 TUN。加完之后，之前「超时」的 AWS / 台湾 / 美国节点全部能正常拿到出口 IP。

该改进已合入 `scripts/antigravity-node-probe.sh`（自动检测默认接口，并优先读取 FlClash 当前 profile）。

### 处理

切回订阅「魔戒.net(1)」→ 节点选择仍为 **日本JP-HY2**：

| 验证项 | 结果 |
| --- | --- |
| 魔戒 / 日本JP-HY2 出口 | `52.69.187.223`（JP） |
| 魔戒 / 日本JP-HY2 真实调用（经真实 TUN） | ✅ `PONG`（2/2），0 次地域错误 |
| 魔戒 / 新加坡SG-HY2 真实调用（对照） | ✅ `PONG` |

### 小结（换订阅 / 换节点时的建议）

1. 换订阅不等于换到可用出口，必须按「Antigravity 真实调用」逐出口验证；
2. 选节点要选在参与规则的分组里，别选 `GLOBAL`（规则模式下无效）；
3. 便宜的共享 IP 池机场（本次新增订阅）大概率整体被拒；`魔戒.net(1)` 的 日本JP-HY2 / 新加坡SG-HY2 目前仍是可用项；
4. 排查时给临时 mihomo 加 `interface-name`，可避免 TUN 双重代理导致的误判。
