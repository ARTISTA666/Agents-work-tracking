# Antigravity 界面突然回到英文：汉化 CDP 注入器的 LaunchAgent plist 在 10-20 被「offload agents」清理挪出 `~/Library/LaunchAgents`，随后 10-22 那次开机没有 RunAtLoad 入口，注入器静默停摆 9 天；同日复制回 + bootstrap 恢复，并实测 KeepAlive 自愈

## 基本信息

- **处理者身份**：Qoder（本次会话 AI 协作代理；发现停摆、定位成因、恢复并验证）
- **问题类型**：Antigravity「零侵入 CDP 注入汉化」方案的基础设施失效（LaunchAgent 未加载），非 App 故障、非网络问题
- **发现时间**：2026-10-29 13:37（Asia/Shanghai，UTC+8）——在复测 Gemini 400 时顺带读界面文案发现
- **实际停摆起点**：注入器日志最后一条 2026-10-19 14:16:39；plist 被挪走于 2026-10-20 17:57；此后 10-22 23:15 开机再未自启
- **解决确认时间**：2026-10-29 13:41（Asia/Shanghai，UTC+8）
- **最终状态**：已解决（plist 复制回 `~/Library/LaunchAgents/` → `launchctl bootstrap gui/501` → 注入器 pid 51917 附着成功、界面回到中文；`kill` 掉进程后 launchd 22 秒内拉起 pid 52583，`runs = 2`，KeepAlive 自愈复验通过）
- **关联记录**：[2026-10-29 Antigravity Gemini 400 INVALID_ARGUMENT](2026-10-29-antigravity-gemini-400-invalid-argument-client-build-and-stuck-squirrel-update.md)（同一天、同一 App；本次是它的附带发现）
- **关联仓库/机制说明**：汉化采用**零侵入 CDP 注入**——不改 app bundle，官方自更新不会被冲掉。引擎与注入器都在 bundle 外：`~/Library/Application Support/Antigravity-zh/i18n.js`（词典+引擎，159KB）与 `injector.mjs`（5KB，无依赖 Node 常驻进程）

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 10-19 14:16 | — | `injector.log` 写下最后一行 `port 64541 is not serving an Antigravity endpoint (app closed?)`，此后进程不再活动（无退出日志，属被外部终止/卸载） |
| 10-20 17:57 | 另一次清理动作 | 生成 `~/Desktop/feiniao-check/_offloaded-agents-1020-1757/`，把 6 个 LaunchAgent plist 从 `~/Library/LaunchAgents/` 挪进去，其中包含 `local.antigravity-zh.injector.plist` |
| 10-22 23:15 | 系统 | 一次正常开机（`kern.boottime`）。此时 LaunchAgents 目录里已无该 plist → **没有自启入口**，汉化从此不会自己回来 |
| 10-29 13:37 | Qoder | 复测 Gemini 时读界面文案：`New Conversation / Automations / Customizations / Projects`，中文只有 81 个字（多为用户自己的项目名/对话标题）→ 判定注入未生效；`launchctl print gui/501/local.antigravity-zh.injector` 报 `Could not find service` |
| 13:38 | Qoder | 检查 `~/Library/LaunchAgents/` 发现 plist 文件本身**不存在**（不是未加载，是被移走）；`mdfind` + 目录核对在 offload 归档里找到原件，内容完整未改 |
| 13:39 | Qoder | 依赖项复核：`injector.mjs`(5252B)、`i18n.js`(159006B) 均在位且仍是 9-21 版本；plist 里写死的 node 绝对路径 `/Users/yusong/.local/share/fnm/node-versions/v24.18.0/installation/bin/node` 存在；`plutil -lint` OK |
| 13:40 | Qoder | **复制**（非移动，保留归档）回 `~/Library/LaunchAgents/` → `launchctl bootstrap gui/501 <plist>` → 6 秒内 `state = running, pid = 51917`，日志出现 `devtools endpoint on port 56542` + `attached … engine started` |
| 13:41 | Qoder | CDP 实测界面：`新建对话 / 自定义配置 / 项目`，`window.__agZhLocale` 存在；菜单也变中文（重命名/置顶/标记为未读/归档/删除） |
| 13:42 | Qoder | 韧性复验：`kill 51917` → 22 秒后 launchd 拉起 `pid = 52583`、`runs = 2`，日志重新 `attached … engine started` → KeepAlive（`SuccessfulExit=false`）仍有效 |

---

## 问题详细描述

Antigravity 的中文界面是「零侵入 CDP 注入」实现的：官方 main 进程自带 `remote-debugging-port 0`，端口写在 `~/Library/Application Support/Antigravity/DevToolsActivePort`；一个常驻 Node 进程轮询该文件，对每个 page target 注册 `Page.addScriptToEvaluateOnNewDocument` 并补一次 `Runtime.evaluate` 注入词典引擎。常驻进程由 LaunchAgent `local.antigravity-zh.injector`（`RunAtLoad` + `KeepAlive.SuccessfulExit=false`）拉起。

10-29 复测 Gemini 时顺带发现界面文案是英文。用户确认要恢复。要点在于：**这不是 App 出问题，而是自启基础设施在 9 天前的一次「整理 LaunchAgents」中被连带清掉**，且清理者把 plist 归档在桌面目录里而不是保留软链，导致下次登录不再自动恢复，表现为「汉化悄悄没了，没人报错」。

---

## 排查过程与关键技术证据

### 1. 先确认「是没注入」而不是「词典失效」

```bash
P=$(head -1 "$HOME/Library/Application Support/Antigravity/DevToolsActivePort")
curl -s "http://127.0.0.1:$P/json/version" | grep -o '"User-Agent": "[^"]*"'   # 确认端口属于 Antigravity
launchctl print gui/501/local.antigravity-zh.injector
tail -2 ~/Library/Logs/Antigravity-zh/injector.log
```

* **证据**：UA 为 `Antigravity/2.28.0 … Electron/44.5.1`（App 正常、CDP 可用）；`launchctl print` 返回 `Bad request. Could not find service … in domain for user gui: 501`；日志停在 `2026-10-19T14:16:39 port 64541 is not serving an Antigravity endpoint`
* **结论**：引擎侧无需改动，缺的是常驻进程本身。App 端 CDP 一切正常——这也顺带说明 10-29 那次升级（Squirrel 原地换 bundle）**没有**破坏注入通道，端口文件机制仍然可用（升级后端口从 63882 变为 56542，注入器靠轮询文件自动跟上新端口）。

### 2. plist 是「不见了」而不是「被禁用」

```bash
ls -la ~/Library/LaunchAgents/                 # 只有 4 个第三方 plist，没有 local.antigravity-zh.injector.plist
launchctl print-disabled gui/501 | grep -i antigravity   # 无输出：不存在 disabled=true 的记录
mdfind -name "local.antigravity-zh.injector"
```

* **证据**：`mdfind` 命中 `/Users/yusong/Desktop/feiniao-check/_offloaded-agents-1020-1757/local.antigravity-zh.injector.plist`（mtime Sep 21 13:37，内容完整）；`print-disabled` 里没有该 label
* **结论**：既不是 `bootout` 残留、也不是 SIP/登录项被拒（那种情况 plist 文件仍在目录里、`print-disabled` 会出现 `enabled = 0`），而是**文件被移走**。目录名 `_offloaded-agents-1020-1757` 自带时间戳＝2026-10-20 17:57。

### 3. 为什么"重启电脑也不会自己回来"

```bash
sysctl -n kern.boottime     # Thu Oct 22 23:15:17 2026
```

* **证据**：offload 发生在 10-20 17:57，而本机最近一次开机是 10-22 23:15——**开机晚于清理**
* **结论**：`RunAtLoad` 需要 plist 位于 `~/Library/LaunchAgents/` 才会在新登录时被 launchd 扫描装载。文件已不在，于是 10-22 那次开机没有重建服务，停摆一直持续到本次手动恢复。这条时间顺序也解释了「明明重启过电脑，汉化却回不来」。

### 4. 恢复前依赖项体检（避免"装回来就崩"）

| 依赖 | 检查 | 结果 |
| --- | --- | --- |
| 注入器脚本 | `ls -l ~/Library/Application Support/Antigravity-zh/injector.mjs` | 5252 字节，Sep 21 未变；内容含 UA 校验（`who.includes('Antigravity')`）与 `--once` 支持 |
| 词典引擎 | `ls -l …/i18n.js` | 159006 字节，Sep 21 未变 |
| node 绝对路径 | `ls -l /Users/yusong/.local/share/fnm/node-versions/v24.18.0/installation/bin/node` | 存在（fnm 版本目录未被清理，这是最容易断的一环） |
| plist 合法性 | `plutil -lint` | `OK` |
| 日志可写目录 | `ls ~/Library/Logs/Antigravity-zh/` | 存在，`StandardOutPath`/`StandardErrorPath` 均指向日志文件 |

### 5. 恢复动作（可回滚，未删除任何原件）

```bash
cp ~/Desktop/feiniao-check/_offloaded-agents-1020-1757/local.antigravity-zh.injector.plist ~/Library/LaunchAgents/
plutil -lint ~/Library/LaunchAgents/local.antigravity-zh.injector.plist
launchctl bootstrap gui/501 ~/Library/LaunchAgents/local.antigravity-zh.injector.plist
launchctl print gui/501/local.antigravity-zh.injector | grep -E "state|pid|last exit"
tail -3 ~/Library/Logs/Antigravity-zh/injector.log
```

* **证据**：`state = running`、`pid = 51917`、`last exit code = (never exited)`；日志新增
  ```
  2026-10-29T05:37:48 watching …/Antigravity/DevToolsActivePort
  2026-10-29T05:37:48 devtools endpoint on port 56542
  2026-10-29T05:37:48 attached BD687DF3 engine started | Reading Project README First Line - Mini
  ```
  （日志时间戳是 UTC，`05:37:48Z` = 本地 13:37:48）
* **选择复制而非移动**：保留 offload 归档的原样，避免破坏别人那次清理的留档；回滚只需 `launchctl bootout gui/501/local.antigravity-zh.injector` 并删掉复制出来的那一份。

### 6. 生效验证与 KeepAlive 复验

```bash
# 界面文案（只读 CDP，不改任何状态）
node - <<'EOF'   # 读 document.body.innerText 的中文计数 + window.__agZhLocale
EOF
kill 51917; sleep 22; pgrep -fl injector.mjs
launchctl print gui/501/local.antigravity-zh.injector | grep -E "runs =|pid ="
```

* **界面**：`新建对话 / 自定义配置 / 项目`，`guard(window.__agZhLocale) = "object"`；对话右键菜单为 `重命名 / 置顶⌥⌘P / 标记为未读 / Copy / Split / 归档⌥⌘A / 删除`
* **自愈**：kill 后 22 秒出现新 pid 52583，`runs = 2`，日志重新 `attached … engine started`
* **未覆盖项（已知限制，非本次故障）**：`Automations` 等少数标签仍是英文；确认弹窗只有标题被译（`删除对话`），正文 `Are you sure you want to delete this conversation?` 仍是英文；原生菜单栏与托盘由 bundle 内 JS 绘制，CDP 够不到，按设计会回到英文

---

## 根因分析

### 1. 直接原因

承载自启的 `local.antigravity-zh.injector.plist` 在 2026-10-20 17:57 被一次 LaunchAgents 批量清理（「offload」）移出 `~/Library/LaunchAgents/`，注入进程从此不再被 launchd 拉起，页面失去注入 → 界面回到英文。

### 2. 为什么拖了 9 天才被发现

* **零失败信号**：注入器不在跑，App 完全正常、日志无错误，用户只会觉得"有些词没译"，不会当成故障
* **归档方式**：清理动作把 plist 收进桌面 `_offloaded-agents-*` 目录（当作"暂时收起"），没有留下「已卸载的自启项清单」，恢复入口不显眼
* **时间顺序不利**：offload(10-20) 早于最后一次开机(10-22)，所以"重启一下就好"这类常规自救根本不会触发装载

### 3. 结构性风险（值得长期注意）

这套汉化的可用性依赖**四个同时成立**的环节，任一断掉表现都一样（界面变英文，且无报错）：

| 环节 | 断掉的典型方式 | 本次判据 |
| --- | --- | --- |
| 官方仍开 `remote-debugging-port` | Google 哪天关掉该开关 | CDP `/json/version` UA 含 `Antigravity` → 仍开着 |
| 端口文件位置不变 | userData 目录改名 | `~/Library/Application Support/Antigravity/DevToolsActivePort` 有效 |
| LaunchAgent 在位且已装载 | **本次即栽在此**（plist 被移走） | `launchctl print gui/501/<label>` |
| node 绝对路径存在 | fnm 版本被卸载/升级 | 文件存在 |

**退路资产仍在**：`~/Library/Application Support/Antigravity-zh/fallback-2.12.2/`（未打补丁的原始 asar + 补丁前后 5 个文件对照），一旦官方去掉 CDP 开关可退回「改包 + 重签」方案。

---

## 解决方案与落地操作

### 步骤 1：确认是"没在跑"还是"跑了没生效"

```bash
launchctl print gui/501/local.antigravity-zh.injector | head -5     # 报错 = 未装载
pgrep -fl injector.mjs                                              # 空 = 进程不在
tail -3 ~/Library/Logs/Antigravity-zh/injector.log                  # 停在某天 = 那之后停摆
ls ~/Library/LaunchAgents/local.antigravity-zh.injector.plist       # 不存在 = 被移走/删除
```

### 步骤 2：找回 plist（本机命中过归档目录）

```bash
mdfind -name "local.antigravity-zh.injector"
ls ~/Desktop/*/_offloaded-agents-*/*.plist 2>/dev/null
```

### 步骤 3：复制回位并装载

```bash
cp <找到的.plist 路径> ~/Library/LaunchAgents/
plutil -lint ~/Library/LaunchAgents/local.antigravity-zh.injector.plist
launchctl bootstrap gui/501 ~/Library/LaunchAgents/local.antigravity-zh.injector.plist
sleep 6 && launchctl print gui/501/local.antigravity-zh.injector | grep -E "state|pid"
```

> 若 App 当时不在前台，注入器会打印 `app not running (no port file)` 并空转等待；打开 Antigravity 后 4 秒内自动附着，无需重启 App。

### 步骤 4：验证

```bash
tail -3 ~/Library/Logs/Antigravity-zh/injector.log    # 期望 devtools endpoint on port <n> + attached … engine started
kill $(pgrep -f injector.mjs | head -1); sleep 22; pgrep -fl injector.mjs   # KeepAlive 自愈
```

界面看 `新建对话 / 项目 / 自定义配置` 即确认生效。

### 步骤 5：回滚（如需）

```bash
launchctl bootout gui/501/local.antigravity-zh.injector
rm ~/Library/LaunchAgents/local.antigravity-zh.injector.plist
```

---

## 验证与效果

| 验证项 | 方式 | 实际结果 | 状态 |
| :--- | :--- | :--- | :--- |
| plist 复位 | `plutil -lint` | `OK` | ✅ |
| 服务装载 | `launchctl print gui/501/local.antigravity-zh.injector` | `state = running`，`pid = 51917`，`last exit code = (never exited)` | ✅ |
| 附着新端口 | `tail injector.log` | `devtools endpoint on port 56542` + `attached … engine started`（升级后端口已从 63882 变为 56542） | ✅ |
| 界面中文化 | 只读 CDP 取 `document.body.innerText` | `新建对话 / 自定义配置 / 项目`，`window.__agZhLocale = object` | ✅ |
| 菜单中文化 | 打开对话 More options | `重命名 / 置顶 / 标记为未读 / 归档 / 删除` | ✅ |
| KeepAlive 自愈 | `kill` 后等 22 秒 | 新 pid 52583，`runs = 2`，日志重新附着 | ✅ |
| 对 App 无副作用 | App 状态 + Gemini 调用 | App 正常在 2.28.0；删除对话等操作均走 UI 正常完成 | ✅ |
| 已知未覆盖 | 界面文案 | `Automations`、确认弹窗正文、原生菜单/托盘仍英文（设计限制/词典缺口） | ⚠️ 记录在案 |

---

## 经验沉淀与后续建议

1. **「没有报错」不等于「还在跑」**：这类无失败信号的基础设施（LaunchAgent 常驻进程、注入器、代理钩子）必须留一条主动体检命令，别靠肉眼发现界面变英文。建议把 `pgrep -fl injector.mjs` + `launchctl print … | grep state` 固定进例行自检。
2. **批量"整理 LaunchAgents"是最危险的静默破坏**：清理前应该把每个 label 的 `launchctl print` 状态与用途记成一张表；把 plist 移到"看起来是归档"的目录，等于让恢复入口消失。凡是 `RunAtLoad` 型服务，被移走后**不会有任何报错**。
3. **注意 offload 与重启的先后顺序**：只要清理发生在最后一次开机之前，"重启电脑试试"这类自救就完全无效——这是本次拖 9 天的直接机制。
4. **多环节依赖要在恢复时逐项体检**：这次运气好在 node 绝对路径（fnm 版本目录）、`i18n.js`、`injector.mjs` 都还在；只要 fnm 升过一次版本，plist 就会变成"装载即退"，那时症状相同而根因不同。恢复前先 `ls` 那条 node 路径，比事后 debug 便宜得多。
5. **复制而不是移动**归档里的文件：既恢复功能，又不破坏别人那次清理的留档，回滚只需删掉自己复制出来的那份。
6. **升级 App 不影响这套汉化**（本次顺带证实）：Squirrel 原地换 bundle 后 CDP 仍然开着，端口号会变，而注入器是**轮询端口文件**而不是记死端口号，因此能自动跟上。这就是"零侵入"设计的实际收益。
7. 词典缺口可继续补：直接编辑 `~/Library/Application Support/Antigravity-zh/i18n.js`，注入器每 4 秒轮询文件变化会热重注入（无需重启 App）。已知缺口样本：`Automations`、确认弹窗正文；已知够不到：原生菜单栏、托盘菜单。

---

## 关键产物与现场位置（不含密钥）

- **恢复的 LaunchAgent**：`~/Library/LaunchAgents/local.antigravity-zh.injector.plist`（label `local.antigravity-zh.injector`，`RunAtLoad` + `KeepAlive.SuccessfulExit=false` + `ThrottleInterval=15` + `Nice=10` + `ProcessType=Background`）
- **归档原件（本次未动）**：`~/Desktop/feiniao-check/_offloaded-agents-1020-1757/local.antigravity-zh.injector.plist`（同目录另有 4 个至今未加载的 agent：`com.codex.xpreview.proxy`、`com.openai.codex.restore-autoupdate`、`com.yusong.feiniaoyun.aiheal`、`com.yusong.feiniaoyun.aiwatch`，**是否恢复由用户决定，本次未处理**）
- **引擎与注入器**：`~/Library/Application Support/Antigravity-zh/i18n.js`（159006 字节）、`injector.mjs`（5252 字节，轮询 4000ms，`--once` 可用）
- **日志**：`~/Library/Logs/Antigravity-zh/injector.log`（时间戳为 UTC；停摆期 10-19 14:16 → 10-29 13:37）
- **注入通道依赖**：`~/Library/Application Support/Antigravity/DevToolsActivePort`（升级后端口 63882 → 56542）；`/json/version` 的 `User-Agent` 必须含 `Antigravity` 才附着（本机还有 Qoder、豆包等 Electron 应用）
- **退路资产**：`~/Library/Application Support/Antigravity-zh/fallback-2.12.2/`（原始 asar + 补丁前后对照，CDP 方案失效时退回改包）
- **本次涉及的 App 版本**：Antigravity **2.28.0**（`Electron/44.5.1`，见同日另一篇记录）
- **恢复后 pid 轨迹**：51917（bootstrap）→ 手动 kill → 52583（launchd 自愈，`runs = 2`）

---

*本篇的价值不在"改了什么"，而在揭示一类静默故障：无失败信号的常驻基础设施（LaunchAgent 注入器）被一次整理动作连带清掉后，可以停摆 9 天而没有任何报错，并且"重启电脑"这种常规自救在「清理早于开机」的时间顺序下完全无效。恢复四步：`launchctl print` 定性 → `mdfind` 找回 plist → 复制回位 `bootstrap` → 看日志与界面验证，并用 `kill` 复验 KeepAlive。*
