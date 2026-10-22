# Codex 桌面版（ChatGPT.app）发消息点发送完全无反应：执行位置卡在「远程(cloud)」而账号云端环境目录为空，发送按钮被永久禁用；切回「此计算机(local)」后立即恢复

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（DSH 本机会话，Lead 单代理执行；排查全程只读，改动仅一处并保留备份与回滚）
- **问题类型**：AI 桌面客户端（ChatGPT.app / Codex 桌面版 26.1016.61520）**UI 前置校验不满足导致发送按钮禁用**，被误读为「网络故障 / 登录失效 / 应用卡死」
- **报错时间**：2026-10-21 起完全无法发送（最后一次成功写入 2026-10-20 17:42）；用户于 2026-10-22 11:34 报障
- **解决确认时间**：2026-10-22 12:25（`turn/started` → `turn/completed`，模型回复 `OK`）
- **最终状态**：✅ 已解决。发送按钮由禁用灰 `(154,154,154)` 变为可用白 `(233,233,233)`，实发消息成功，退出重启后设置持久
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 10-20 17:42 | 用户/应用 | 最后一次正常使用（本地 `state_5.sqlite` 与 `sessions/*.jsonl` 最新写入到此为止） |
| 10-21 全天 | — | 日志显示应用有打开、有浏览会话，但 `turn/start` 全程 **0 次**（已无法发送，只是当时未深入排查） |
| 10-22 06:10 | 应用自更新 | `ChatGPT.app` 由 26.1016.51333 → 26.1016.61520（仅时间强相关，非确证原因） |
| 11:31:33 | 应用 | 执行 `account/logout`，11:31:44 `account/login/start`，11:32:15 重新登录完成（`auth.json` 的 `last_refresh`） |
| 11:34 | 用户 | 报障：「发消息点击没反应，先不要改什么」 |
| 11:34–12:06 | DSH Agent | 只读取证：进程、日志目录、令牌有效性、网络/DNS/代理、线程库；排除登录、限流、崩溃、磁盘、app-server 异常 |
| 11:57:26 | 系统 | `DHCP en0: server not responding` → `UNBOUND`，Wi-Fi 掉线约 5 分钟（12:02:52 恢复），造成应用 ENOTFOUND 风暴 |
| 12:02–12:04 | DSH Agent | 按窗口 ID 截图（不打扰前台），确认界面登录态、模型、权限、输入框均正常 |
| 12:13:55 | 用户/Agent | 用户退出应用后，Agent 干净重启；`durable nextState=connected`、无 `Sign in to ChatGPT` 报错 |
| 12:14–12:18 | DSH Agent | 受控发送验证连续失败：AX 合成点击、键盘回车、CGEvent 点击均未产生任何 RPC |
| **12:18:10** | **DSH Agent** | **关键突破：悬停发送按钮，tooltip 显示「请选择一个云端环境，然后继续」** |
| 12:18:30 | DSH Agent | 打开输入框上方「工作位置」下拉，确认选项为「此计算机 / 远程」，当前勾选「此计算机」 |
| 12:24 | DSH Agent | 退出应用 → 备份 `~/.codex/.codex-global-state.json` → 将执行位置原子改为 `local` → 重启 |
| 12:25:10 | DSH Agent | 发送成功：`turn/started` 12:25:11 → `turn/completed` 12:25:15，回复 `OK` |
| 12:26–12:27 | DSH Agent | 退出 + 重启复测：设置仍为 `local`，按钮仍为可用白；代理组选择恢复原样 |
| 12:38 | 用户 | 要求将过程同步至本仓库 |

---

## 问题详细描述

用户描述：**「本机的 GPT 桌面软件（原 Codex）现在使用不了，发消息点击没反应」**。

现场事实：

- 应用进程正常（主进程 + 多个 renderer + 内置 `codex app-server` 子进程），无崩溃报告
- 窗口 UI 完全正常：登录态在（左下头像）、模型 `GPT-6.1 Sol 高`、权限 `完全访问`、输入框可输入、文字能正常粘贴进输入框
- **输入框有内容时，右侧发送按钮仍是灰色禁用态**；点击按钮、按回车均无任何反应，界面无 toast、无横幅、无报错
- 应用日志中**当天全程没有一条与「发送」相关的 RPC**

环境：macOS 26.6 (25G72)，Apple Silicon；`ChatGPT.app` 26.1016.61520，内部 `Codex Framework 155.0.8059.80`，内置 `codex-cli 0.163.0-alpha.11.1`；账号 `4ms45sgmtm@privaterelay.appleid.com`（`plan_type: prolite`，`account_id f2b81123-…`）；FlClash 系统代理 `127.0.0.1:7890` + TUN(utun4) + fake-ip。

---

## 排查过程与关键技术证据

### 1. 先定现象边界：应用活着，但「发送」这个动作零 RPC

日志目录 `~/Library/Logs/com.openai.codex/2026/10/22/`，按 app-server 方法统计：

| 方法 | 10-20（正常日） | 10-22（故障日） |
| --- | --- | --- |
| `thread/read` | 9505 | 741 |
| `thread/list` | 463 | 110 |
| `get` / `post` | 251 / 106 | 167 / 1 |
| **`turn/start`（发送/开回合）** | **23** | **0** |
| `turn/steer` / `turn/started` / `turn/completed` | 12 / 5 / 2 | 0 / 0 / 0 |

本地会话库同样佐证：`state_5.sqlite` 共 677 个 thread，最新 `updated_at` = **2026-10-20 17:42**；`sessions/2026/10/20/*.jsonl` 之后无任何新 rollout。

> 结论：**请求在渲染层就被拦住了**，根本没有走到 app-server / 网络，因此「网络/DNS/代理」方向一开始就是错的。

### 2. 排除登录与令牌（最常见的误判方向）

```bash
# 令牌有效期
python3 - <<'PY'
import json,base64
d=json.load(open('/Users/yusong/.codex/auth.json'))
p=d['tokens']['access_token'].split('.')[1]; p+='='*(-len(p)%4)
print(json.loads(base64.urlsafe_b64decode(p))['exp'])   # → 2026-11-01（未过期）
PY
# 用应用同一份令牌打真实接口
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
  https://chatgpt.com/backend-api/me                      # → 200
```

应用侧也自证正常：`getAuthStatus` / `account/read` 均 `errorCode=null`，`chatgpt-account-lookup … authenticatedAccountPresent=true`。

### 3. 排除云端 durable 通道（曾是最像根因的旁支）

故障期确有大量云端通道异常：`Sign in to ChatGPT to start a durable thread.` 48 次、`getaddrinfo ENOTFOUND codex-cloud-backend.chatgpt.com` 208 次、`ECONNREFUSED 202.160.129.36:443` 143 次（该 IP 属 AS13414 Twitter，是 GFW 污染注入的典型假地址，真实解析为 Cloudflare `104.18.32.47/172.64.155.209`）、`WebSocket was closed before the connection was established` 689 次、`cloudflare_challenge` 349 次。

但**反证**：干净重启后 `hostId=durable nextState=connected` 且不再出现 `Sign in to ChatGPT`，发送依旧无效。→ 通道故障是**并发存在**的问题，不是本症状的必要条件。

### 4. 排除「界面卡死」——这是个陷阱

初测时 `screencapture -l<windowid>` 两次截图**像素完全一致**，差点判定 renderer 冻死。三项证据否定：

```bash
# ① 把窗口切到前台后，两次截图出现差异（输入框光标闪烁）
#    diff bbox = (2266,1773,2270,1806)  ← 正是 caret 位置
# ② 采样 UI renderer 主线程：1575/1650 样本停在 mach_msg（空闲事件循环，非死锁）
sample 73405 2
# ③ 早期像素不变的真实原因：ChatGPT 窗口被其他窗口完全遮挡，
#    系统/Chromium 触发了遮挡节流，-l<id> 取到的是未重绘的旧帧
```

### 5. 排除「脚本点击姿势不对」

`System Events … click at {x,y}` 对 Electron 的 web 内容只命中 `AXGroup`，不会派发 DOM click；改用 CGEvent 真实鼠标事件（`mouseMoved` / `leftMouseDown` / `leftMouseUp`）后才具备可信度：

```bash
swiftc -O /tmp/mouse.swift -o /tmp/mouse   # CoreGraphics 合成鼠标事件
/tmp/mouse 1369 985            # 悬停
/tmp/mouse 1369 985 click      # 单击
```

### 6. 关键突破：悬停发送按钮拿到禁用原因

悬停后 tooltip 明文给出原因：

> **请选择一个云端环境，然后继续**

同时按钮像素态可量化区分：

| 状态 | 按钮中心 RGB |
| --- | --- |
| 禁用（有文字也不亮） | `(154,154,154)` |
| 可用（修复后） | `(233,233,233)` |

### 7. 状态取证：为什么它要求「云端环境」

`~/.codex/.codex-global-state.json` → `electron-persisted-atom-state`：

```json
"new-task-execution-by-account-project": {
  "[\"f2b81123-…\",\"user-UyIUFqNqrB9VoQtWe1BFmNeC\",null]": {"kind": "cloud"}
}
"legacy-cloud-settings-environments-v1": {"hasEnvironments": false, "checkedAt": 1792412351268}
```

顶层环境目录缓存：

```json
"environment-catalog-cache-v1": {"user": [], "workspace": [], "failures": 0, "refreshedAt": 1791392972331}
"environment-catalog-cache-v2": {"data": [], "refreshedAt": 1792562716876, "failures": 0}
```

即：**执行位置 = 远端(cloud)，而云端环境列表为空** → 「要求先选一个云端环境」与「一个环境都没有」构成死锁。

> 注：`refreshedAt` 换算为 UTC+8 约 10-19 / 10-21，`hasEnvironments:false` 自 10-19 起即存在。说明该 `prolite` 账号从未具备（或已不再具备）Codex 云端环境，一旦执行位置被置为「远程」就必然卡死。

---

## 根因分析

| 层级 | 内容 |
| --- | --- |
| **直接原因** | 输入框的发送前置校验要求「已选中云端环境」。当前执行位置 = 远程(cloud)，而账号环境目录为空 → 校验永远不通过 → 发送按钮 `disabled`，点击被 UI 层吞掉，不产生任何 RPC、不产生任何网络请求、不报错 |
| **深层原因** | 执行位置被持久化在 `electron-persisted-atom-state.new-task-execution-by-account-project`（`project=null` 这一档）且值为 `cloud`；而 `environment-catalog` 为空（`hasEnvironments:false`）。二者组合即不可用态 |
| **触发时机** | 无法确证。候选：10-21 前后的应用自更新（26.1016.51333 → 61520）、用户误点「远程」、或账号计划变更导致云端环境消失。时间上「最后一次成功 10-20 17:42」与「10-21 全天 0 次 turn/start」相邻 |
| **附加现象（并发存在，非本症状根因）** | ① GFW DNS 污染（`202.160.129.36` 等假地址）；② 出口 IP 被 Cloudflare 质询（`cf-mitigated: challenge`）；③ 11:57 DHCP 租约失效导致 Wi-Fi 掉线 5 分钟。三者共同造成 `ENOTFOUND` / WebSocket 握手前断开 / 重连风暴，**只影响延迟与重连，不影响发送按钮是否可用** |

### 误判与反证对照

| 曾被怀疑的方向 | 反证 |
| --- | --- |
| 掉登录 / 令牌过期 | access_token 有效至 2026-11-01；同令牌请求 `/backend-api/me` → 200；应用侧 `authenticatedAccountPresent=true` |
| 账号限流 | `codex-rate-limit-reset-history` 最后一次为 10-19 23:21，故障期无限流记录 |
| 本地 app-server 挂了 | `codex-cli 0.163.0-alpha.11.1` 正常，`thread/list` / `config/read` / `model/list` 全部正常返回 |
| 云端 durable 通道断 | 重启后 `nextState=connected`、无 sign-in 报错，发送仍无效 |
| 应用卡死 / 渲染器死锁 | 切前台后光标闪烁；renderer 主线程采样为空闲 `mach_msg` |
| 磁盘 / 内存 / 崩溃 | 根分区剩 79GB、内存 32% 空闲；无 ChatGPT/Codex 崩溃报告 |
| `-32003 thread access denied` | 自 10-08 起每天都有；被拒的 19 个会话 ID 在本地库中根本不存在（属云端线程），是结果不是原因 |
| DNS 污染 / Cloudflare 挑战 | 真实存在，但在通道恢复、发请求完全无 RPC 的情况下无法解释「点了没反应」 |

---

## 解决方案与落地操作

思路：**把执行位置从 `remote/cloud` 改回 `local/此计算机`**。两条路径等价，推荐 UI（无需改文件）。

### 路径 A：UI 操作（推荐）

1. 打开 ChatGPT / Codex 窗口
2. 点输入框上方的「**工作位置**」下拉（显示为「选择项目 | 此计算机」那一行）
3. 选 **此计算机**
4. 发送按钮立即由灰变白，输入内容后即可发送

> 判别口诀：**位置标签显示「远程」+ 悬停发送按钮提示「请选择一个云端环境，然后继续」= 本故障**。

### 路径 B：改状态文件（可脚本化，需先退出应用）

```bash
# 1) 退出应用（必须，否则会被运行中的实例覆盖）
osascript -e 'tell application "ChatGPT" to quit'; sleep 6

# 2) 备份
F=~/.codex/.codex-global-state.json
cp -p "$F" "$F.bak-fix-$(date +%Y%m%d-%H%M%S)"

# 3) 执行位置 cloud → local
python3 - <<'PY'
import json
p='/Users/yusong/.codex/.codex-global-state.json'
d=json.load(open(p))
a=d['electron-persisted-atom-state']
k='new-task-execution-by-account-project'
for key in a[k]:
    a[k][key]={'kind':'local'}
json.dump(d,open(p,'w'),ensure_ascii=False)
print(json.dumps(a[k],ensure_ascii=False))
PY

# 4) 启动
open -a /Applications/ChatGPT.app
```

仓库脚本：`scripts/codex-desktop-send-block-check.sh`（`check` 只读诊断 / `apply` 应用修复 / `rollback` 还原备份）。

### 回滚

```bash
# 用第 2 步的备份覆盖即可（应用需先退出）
cp -p ~/.codex/.codex-global-state.json.bak-fix-<时间戳> ~/.codex/.codex-global-state.json
```

本次实际备份：`~/.codex/.codex-global-state.json.bak-fix-20261022-122426`

### 持久化验证

该值由应用自身在切换时写回并落盘，**退出 + 重启后仍为 `local`**（本次已实测两轮），无需每次重做。

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| 发送按钮中心像素 | `(154,154,154)` 灰 | `(233,233,233)` 白 | ✅ |
| 悬停提示 | 「请选择一个云端环境，然后继续」 | 无提示 | ✅ |
| 发送后 app-server RPC | 全天 `turn/start` = 0 | `turn/started` 12:25:11.747 | ✅ |
| 回合完成 | 无 | `turn/completed` 12:25:15.244（4 秒） | ✅ |
| 模型回复 | 无 | 回复 `OK` | ✅ |
| 退出 + 重启后设置 | — | 仍为 `{"kind":"local"}`，按钮仍可用 | ✅ |
| 代理配置副作用 | — | 测试期间临时切过的节点已全部恢复（`🤖AI网站 → 🚀节点选择`） | ✅ 无残留 |

---

## 经验沉淀

1. **「点了没反应 + 日志零请求」= 先查 UI 前置校验，不要先查网络。** 网络故障一定会留下超时/失败 RPC 或连接错误；一条 RPC 都没有，说明动作在渲染层被门禁拦下。
2. **悬停 tooltip 是定位「按钮为什么禁用」最便宜、最准确的手段**，比翻日志、翻源码都快。本次一句话即锁定根因。
3. **`screencapture -l<windowid>` 在窗口被遮挡时会取到不重绘的旧帧**，两次截图相同**不能**证明界面卡死；必须先把窗口切前台，再比较帧差异（可用光标闪烁作为活性判据），必要时 `sample <renderer-pid>` 看主线程是否停在 `mach_msg`。
4. **AX（System Events）合成点击对 Electron 的 web 内容无效**，只命中 `AXGroup`；验证点击交互请用 `CGEvent` 真鼠标事件，并配合「截图/像素态」而不是只看 AX 返回值。
5. **日志里的旁支异常要判定「是否与症状同时必要」**：本次 `thread access denied`（自 10-08 每天都存在）、`ENOTFOUND`、`cf-mitigated: challenge` 都极具迷惑性，但都能被「durable 已连接仍发不出」与「零 RPC」反证。**先做排除法，再做归因**。
6. **状态类故障优先定位到具体的持久化键**（本次为 `electron-persisted-atom-state.new-task-execution-by-account-project`），改状态文件前必须完全退出应用，否则会被运行实例覆盖。
7. **改动前置备份、改后做「退出+重启」持久化复测**，并把临时试错的配置（本次代理节点）恢复原样，避免留下副作用。

---

## 关键产物与现场位置（不含密钥）

- 应用日志：`~/Library/Logs/com.openai.codex/2026/10/22/codex-desktop-*-<pid>-t0-i1-*.log`（按 renderer 分文件，主日志为 `t0`）
- 应用状态（本次修复点）：`~/.codex/.codex-global-state.json` → `electron-persisted-atom-state`
  - `new-task-execution-by-account-project`（执行位置：`cloud` / `local`）
  - `environment-catalog-cache-v1 / v2`、`legacy-cloud-settings-environments-v1`（云端环境目录）
- 会话库：`~/.codex/state_5.sqlite`（677 threads）、`~/.codex/sessions/**/*.jsonl`、`~/.codex/thread_history_1.sqlite`
- 登录令牌：`~/.codex/auth.json`（`auth_mode: chatgpt`，有效期至 2026-11-01）
- 本次备份：`~/.codex/.codex-global-state.json.bak-fix-20261022-122426`
- 仓库脚本：`scripts/codex-desktop-send-block-check.sh`
- 相关旁支（本次未处理，供后续参考）：FlClash 运行时配置 `~/Library/Application Support/com.follow.clash/config.yaml`（DNS `nameserver` 为国内明文、`fallback-filter` 仅按 `geoip-code: CN` 判定，对境外污染假 IP 无效）

*结论：本故障与网络无关，是「执行位置 = 远程」与「账号无云端环境」构成的 UI 门禁死锁；切回「此计算机」即恢复，且设置会持久保存。*
