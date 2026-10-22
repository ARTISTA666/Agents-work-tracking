# ChatGPT 桌面版侧栏 dot 入口消失、网页端仍正常：本地 `model_provider = "custom"` 触发「要求第一方推理」的能力门控，隐藏了 orbit（dot）侧栏入口；改回 `openai` 并完全重启后恢复

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（DSH 本机会话，单代理执行；全程只读取证，最终只改 1 行配置并保留备份与回滚）
- **问题类型**：AI 桌面客户端（ChatGPT.app / Codex 桌面版 26.1016.61520）**能力门控导致导航入口静默隐藏**，被误读为「dot 被删除 / 账号权限丢失 / 地区限制 / 应用版本 bug」
- **报错时间**：10-21 应用自更新后开始找不到入口（用户于 2026-10-22 13:52 报障：「桌面版的 gpt 里面的 dot 入口找不到了，但是网页端还能看到」）
- **解决确认时间**：2026-10-22 14:00（改配置 + 完全重启后，侧栏出现「你的 dot」，听写麦克风同时恢复）
- **最终状态**：✅ 已解决。桌面端侧栏恢复 dot 入口；dot 数据本身自始至终未丢失（当日 13:21 仍在正常同步）
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 10-20 | 应用 | `ChatGPT.app` build 20770（正常，dot 入口可用） |
| 10-21 | 应用自更新 | 升级到 build 21161（`26.1016.51333`），dot 侧栏入口开始消失；同一版本在官方仓库有多个同类报告 |
| 10-22 06:10 左右 | 应用自更新 | 再升级到 build 21421（`26.1016.61520`），入口仍未恢复 |
| **13:52** | 用户 | 报障：「桌面版的 gpt 里面的 dot 入口找不到了，但是网页端还能看到」 |
| 13:52–13:57 | DSH Agent | 只读取证：版本/升级史、`~/.codex/config.toml`、`auth.json`、应用状态、App 日志、`app.asar` 渲染层代码 |
| 13:57 | DSH Agent | 定位到侧栏 dot 入口的显示条件：`orbit` 能力要求「第一方推理」，判断式为 `(model_provider ?? "openai") === "openai"`，而本机为 `"custom"` |
| 13:58 | DSH Agent | 交叉验证：本地 dot 档案 `status=available`、`is_paused=false`，13:21 仍同步；排除删除/权限丢失 |
| 14:00 | DSH Agent | 完全退出 App → 备份 `config.toml` → 第 7 行改 `openai` → 重启 |
| **14:00:30** | DSH Agent | 截图验证：侧栏「新聊天」下方出现「你的 dot」（带 1 条未读），输入框麦克风恢复 |
| 14:03 | 用户 | 要求同步过程到本仓库，并到官方 issue 补充英文评论 |

---

## 问题详细描述

用户描述：**「桌面版的 gpt 里面的 dot 入口找不到了，但是网页端还能看到」**。

现场事实：

- 网页端 `chatgpt.com/dots` 正常显示同一账号的 dot，可对话；说明账号资格与 dot 数据都在
- 桌面端（ChatGPT.app 26.1016.61520，macOS，Apple Silicon）侧栏可正常看到「新聊天 / 置顶 / 项目 / 最近」，但**没有 dot 入口**
- 桌面端当时的窗口停在 **Codex 模式**（左上角显示「Codex ⌄」），但模式切换并非原因：修复后同一 Codex 模式下入口也正常出现
- 应用日志无报错、无崩溃；账号检索 `[chatgpt-account-lookup] completed … authMethod=chatgpt result=succeeded`
- dot 相关网络请求此前有一次 `500 / ERR_CONNECTION_REFUSED / TIMED_OUT`（12:50–12:58，与当时重启 FlClash 的时间重叠），属于旁支噪声，不是入口消失的原因

环境：macOS 26.6，Apple Silicon；`ChatGPT.app` 26.1016.61520（build 21421），`Codex Framework 155.0.8059.80`；账号为个人 Pro（`prolite`）；FlClash 系统代理 `127.0.0.1:7890` + TUN(utun4) + fake-ip。

---

## 排查过程与关键技术证据

### 1. 先确认「入口消失」不是 dot 被删

`~/.codex/.codex-global-state.json` → `electron-persisted-atom-state`：

```json
"primary-aeon-selection-v1": {"response": {"selection": {
  "aeon_id": "<accountId>~6ac11daf…", "available": true,
  "messaging_room_id": "0f4a3bcde3488196bbf7568d167576fc" }}}
"cloud-aeon-profiles-v1:[…]": {"…": {"status": "available",
  "profile": {"aeon_kind": "orbit", "status": "active", "is_paused": false,
              "last_check_in_at": "2026-10-22T00:35:36Z",
              "updated_at": "2026-10-22T05:21:50Z"}}}
```

> 结论：dot 档案存在且 `available / active / is_paused:false`，当日 13:21（UTC+8）仍在同步 → **不是删除、不是权限丢失**。

### 2. 查「桌面端 vs 网页端」差异的合理落点

网页端只按账号资格判断；桌面端还受本地 Codex 配置影响。先看 `~/.codex/config.toml`：

```toml
model = "gpt-6.1-sol"
model_provider = "custom"          # ← 第 7 行

[model_providers.custom]
name = "OpenAI"
requires_openai_auth = true
supports_websockets = false
wire_api = "responses"
```

官方仓库同期报告：[openai/codex#55783](https://github.com/openai/codex/issues/55783)（macOS 桌面端 dot 消失、网页正常）、#51213、#50283、#55996；其中一条评论明确给出「把 `model_provider` 从自定义改回默认后，dot 入口和听写一起恢复」的复现。

### 3. 从 App 代码验证门控逻辑（关键证据）

解包 `ChatGPT.app/Contents/Resources/app.asar`，取渲染层主包 `webview/assets/app-initial-*.js`：

能力定义（`orbit` 与 `dictation` 都要求第一方推理）：

```js
{ orbit: { accessPolicy: "orbit", requiresFirstPartyInference: true },
  dictation: { accessPolicy: "workspace-dictation", requiresFirstPartyInference: true, … },
  "voice.realtime": { requiresFirstPartyInference: true, … } }
```

能力解析器（第一方推理检查）：

```js
if (n.requiresFirstPartyInference && t(Fh, "3683713372")) {   // 服务端 gate
  let e = t(xh, { hostId: Do, cwd: null, failClosed: true }),
      a = e.data == null ? null : Xm(e.data.config).model_provider;
  r.push({ isLoading: i, isError: n,
           isCapable: !i && !n && (a ?? "openai") === "openai" });
}
```

侧栏 dot 入口的显示条件：

```js
Ssc = W(J, ({ get: e }) => {
  if (!e(sy, { name: "orbit" }).isCapable) return false;   // ← 命中即隐藏
  …
});
// 组件内：if (!r || bnr()) return null;  → 侧栏不渲染 dot 入口
```

`orbit` 的 `isCapable` 由两项同时决定：

| 检查项 | 本机结果 |
| --- | --- |
| `accounts/check` 返回 `accounts[<id>].account.tbo_config.tbo_available === true` | ✅（日志 `chatgpt-account-lookup … result=succeeded`；网页端也正常） |
| 命中 gate `3683713372` 时，`(model_provider ?? "openai") === "openai"` | ❌ 本机为 `"custom"` |

> 结论：**本地配置里的 `model_provider = "custom"` 让「第一方推理」检查判 false → `orbit` 能力不可用 → 侧栏 dot 入口被静默移除；听写同因**。网页端不读这份本地配置，所以照常显示。

### 4. 排除其他可能

| 怀疑方向 | 反证 |
| --- | --- |
| dot 被删除 / 归档 | `cloud-aeon-profiles` 显示 `available/active`，13:21 仍在同步 |
| 账号资格 / 地区限制 | 网页端同一账号正常；桌面 `accounts/check` 检索成功 |
| 停留在 Codex 模式导致 | 修复后仍处 Codex 模式，入口正常出现（说明该入口在 Codex 侧栏同样渲染） |
| 网络 / 代理（12:50–12:58 的 500/超时） | 入口缺失早于这些报错；且改配置后未动网络即恢复 |
| 应用版本 bug | 版本只是让门控生效的时间背景；通过改配置可恢复，说明是可配置触发的门控行为 |

---

## 根因分析

| 层级 | 内容 |
| --- | --- |
| **直接原因** | 侧栏 dot 入口依赖 `orbit` 能力；该能力带 `requiresFirstPartyInference: true`，在 gate `3683713372` 生效时要求本地 `model_provider === "openai"`。本机为 `"custom"` → 能力判 false → 入口组件返回 `null` |
| **深层原因** | App 用「是否字面等于 openai」来判断是否第一方推理，未考虑 `requires_openai_auth = true` 且无自定义 `base_url` 的“自定义 provider 别名”场景（本机 custom 实际就是 OpenAI 端点） |
| **触发时机** | 10-21 自更新到 build 21161（`26.1016.51333`）后出现；官方仓库同一版本有多个同类报告，属该版本开始生效的门控 |
| **附加现象** | 听写（dictation）同时消失；`voice.realtime`、图片生成、朗读等同样带该标记的能力在自定义 provider 下也可能受影响 |
| **为何网页端正常** | 网页端不读取 `~/.codex/config.toml`，只按账号资格渲染 |

---

## 解决方案与落地操作

思路：**让本地配置回到第一方（默认 `openai`）provider，保留自定义 provider 定义备用**。

```bash
# 1) 完全退出 App（必须；否则退出时可能被运行实例写回）
osascript -e 'tell application "ChatGPT" to quit'
# 若未退出：Cmd+Q，或确认进程消失
pgrep -fl "ChatGPT.app/Contents/MacOS/ChatGPT" || echo QUIT_OK

# 2) 备份
cp -p ~/.codex/config.toml ~/.codex/config.toml.bak-dot-$(date +%Y%m%d-%H%M%S)

# 3) 第 7 行 custom → openai（[model_providers.custom] 段保留）
sed -i '' 's/^model_provider = "custom"$/model_provider = "openai"/' ~/.codex/config.toml
grep -n "^model_provider" ~/.codex/config.toml

# 4) 启动
open -a /Applications/ChatGPT.app
```

仓库脚本：`scripts/chatgpt-dot-entry-provider-check.sh`（`check` 只读诊断 / `apply` 修复 / `rollback` 还原，幂等，改动前自动备份）。

> 判别口诀：**网页端 dot 正常 + 桌面端侧栏无 dot + 听写按钮也消失 + `config.toml` 里 `model_provider` 不是 `openai` = 本故障**。

### 回滚

```bash
# 先退出 App，再用备份覆盖
cp -p ~/.codex/config.toml.bak-dot-<时间戳> ~/.codex/config.toml
```

本次实际备份：`~/.codex/config.toml.bak-dot-20261022-1405`

### 长期取舍

- 改回 `openai` 后模型请求走内置 provider；本机 custom provider 没有自定义 `base_url`（只是 OpenAI 的别名），实际行为基本一致，模型仍为 `gpt-6.1-sol`
- 若以后必须走自定义网关而把 `model_provider` 改回 `custom`，**dot 入口会再次消失**（当前客户端逻辑如此）；期间可先用 `chatgpt.com/dots` 或手机端，等待官方修复

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| 侧栏 dot 入口 | 无 | 「新聊天」下方出现「你的 dot」（带 1 条未读） | ✅ |
| 听写麦克风 | 无 | 输入框右侧恢复 | ✅ |
| dot 数据 | `available/active` | 不变，仍同步 | ✅ 未受影响 |
| 模型 | `gpt-6.1-sol` | `gpt-6.1-sol`（内置 provider） | ✅ |
| 重启后持久性 | — | 配置保持 `openai`，入口仍显示 | ✅ |
| 网络 / 代理 | — | 全程未改动 | ✅ 无副作用 |

截图：`~/Desktop/dot入口恢复-2026-10-22-1400.png`（侧栏已出现「你的 dot」）

---

## 经验沉淀与后续建议

1. **「网页端正常、桌面端入口消失」先怀疑本地配置驱动的能力门控，而不是账号/地区。** 网页与桌面读取的判定输入不同：桌面额外受 `~/.codex/config.toml` 影响。
2. **入口消失但数据仍在（`cloud-aeon-profiles` 显示 available）时，不要急着重装/清缓存**，先查导航渲染条件；重装会丢本地工作状态且无效。
3. **读 App 自带 bundle 验证门控是低成本高确定性手段**：`app.asar` 可用 Python 解析头部（`4 / headerSize / …`）直接抽取 `webview/assets/app-initial-*.js`，再用关键字定位能力表与判断式。
4. **`requiresFirstPartyInference` 是这批功能（dot、听写、语音、图片生成、朗读）的共同开关。** 只要 `model_provider` 不是 `openai`，这些入口可能一起消失——排查时把「同类入口是否同时消失」作为强特征。
5. **改配置前必须完全退出 App**，否则运行实例可能在退出时写回；改后必须做「退出 + 重启」复测。
6. **凡是“官方疑似 bug”的结论，配套给出可恢复的本地动作 + 上游 issue 链接**，便于后续版本修复后回切。
7. 官方同类报告：[#55783](https://github.com/openai/codex/issues/55783)（macOS dot 消失）、#51213（侧栏消失、后台任务继续）、#50283（升级后消失 + `/accounts/check` 432）、#55996（iPhone/桌面同时消失 + 账号不可用弹窗）。

---

## 关键产物与现场位置（不含密钥）

- 应用：`/Applications/ChatGPT.app`（26.1016.61520 / build 21421 / Codex Framework 155.0.8059.80）
- 修复点：`~/.codex/config.toml` 第 7 行 `model_provider`（`custom` → `openai`）
- 本次备份：`~/.codex/config.toml.bak-dot-20261022-1405`
- 自定义 provider 定义（保留未删）：`[model_providers.custom]`（`requires_openai_auth = true`，无 `base_url`）
- 门控代码位置：`ChatGPT.app/Contents/Resources/app.asar` → `webview/assets/app-initial-*.js`
  - 能力表：`orbit: { accessPolicy: "orbit", requiresFirstPartyInference: true }`
  - 判断式：`(model_provider ?? "openai") === "openai"`，gate `3683713372`
- dot 状态：`~/.codex/.codex-global-state.json` → `electron-persisted-atom-state`
  - `primary-aeon-selection-v1`（主 dot 选择）
  - `cloud-aeon-profiles-v1:[…]`（dot 档案，`aeon_kind: orbit`，`status: available`）
- 应用日志：`~/Library/Logs/com.openai.codex/2026/10/22/codex-desktop-*-<pid>-t0-i1-*.log`
- 版本历史：10-20 build 20770 → 10-21 build 21161（`26.1016.51333`）→ 10-22 build 21421（`26.1016.61520`）
- 验证截图：`~/Desktop/dot入口恢复-2026-10-22-1400.png`
- 仓库脚本：`scripts/chatgpt-dot-entry-provider-check.sh`

*结论：本故障不是 dot 丢失、不是账号权限、也不是网络问题，而是本地 `model_provider = "custom"` 触发「第一方推理」能力门控，导致桌面端隐藏 dot 侧栏入口与听写按钮；改回 `openai` 并完全重启即恢复，dot 数据无任何丢失。*
