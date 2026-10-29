# 一次性清理 6 个僵尸 LaunchAgent 的逐项复验法：自动更新已恢复、本地 opencode 转发已无调用方、飞鸟云 AI 看门狗因 profile 删除 + 分组不存在 + 白名单 0 命中而整体失效（移入废纸篓，保留脚本本体）

## 基本信息

- **处理者身份**：Qoder（本次会话 AI 协作代理；逐项复验"问题是否真的解决"后处置）
- **问题类型**：历史排查遗留的 LaunchAgent 与脚本的**去留判定**（非故障修复）。触发点是同日另一篇记录：`_offloaded-agents-*` 这类"把 plist 挪出 LaunchAgents"的整理动作会让 `RunAtLoad` 型服务**静默停摆**（汉化注入器就因此停了 9 天），所以这个归档目录本身就是误导性资产
- **处置时间**：2026-10-29 13:53（Asia/Shanghai，UTC+8）
- **最终状态**：6 项移入废纸篓（可恢复）；2 个仍在用的 agent 未动；看门狗脚本本体**故意保留**
- **判定规则（用户定的）**：先 double check 每个脚本当初要解决的问题现在是否已解决、复发可能性是否很小；都成立才删
- **关联记录**：[汉化注入器静默停摆与恢复](2026-10-29-antigravity-zh-injector-launchagent-offloaded-silent-stoppage.md)、[出口被判 HK 导致请求级 400](2026-10-28-gemini-web-and-antigravity-intermittent-egress-hk-region-reject.md)、[Gemini 400 与 Squirrel 更新滞留](2026-10-29-antigravity-gemini-400-invalid-argument-client-build-and-stuck-squirrel-update.md)

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作 |
| --- | --- | --- |
| 13:45 | Qoder | 读 4 份 plist，还原每个服务的用途、触发方式与自删设计 |
| 13:47 | Qoder | 复验 ①：`defaults read com.openai.codex SUAutomaticallyUpdate / SUEnableAutomaticChecks / SULastCheckTime` 与 ChatGPT.app 版本号 |
| 13:49 | Qoder | 复验 ②：端口占用、`~/.codex/config.toml` 的 provider 与 `base_url`、全盘 `18765` 引用 |
| 13:51 | Qoder | 复验 ③④：FlClash 持久库 `profiles` 表比对脚本里写死的 `PROFILE_ID`、当前订阅分组名、`lists.json` 节点名命中率 |
| 13:53 | Qoder | 6 项 `mv` 进 `~/.Trash`（不用 `rm`，保留可恢复性）；写 `~/Desktop/feiniao-check/README-状态-20261029.md` 标注每一项定论 |

---

## 排查过程与关键技术证据

### ① `com.openai.codex.restore-autoupdate` —— 一次性闹钟，任务已完成

plist 意图：`StartCalendarInterval` = 8 月 26 日 10:00，执行 `defaults write com.openai.codex SUAutomaticallyUpdate/SUEnableAutomaticChecks -bool true`，然后 `launchctl bootout` 自身并删掉 plist 与脚本。

```bash
defaults read com.openai.codex SUAutomaticallyUpdate      # 1
defaults read com.openai.codex SUEnableAutomaticChecks    # 1
defaults read com.openai.codex SULastCheckTime            # 2026-10-28 06:31:05 +0000
plutil -extract CFBundleShortVersionString raw /Applications/ChatGPT.app/Contents/Info.plist  # 26.1023.50603
```

* **结论**：冻结期早已解除、更新检查昨天还在跑、App 版本是 10 月内的构建。且它要执行的脚本在 `~/Library/LaunchAgents/` 下本就不存在了。**问题已解决 + 一次性设计 → 删。**

### ② `com.codex.xpreview.proxy` —— 调用方消失的常驻转发

脚本 `~/Library/x-preview-proxy.js`：在 `127.0.0.1:18765` 反代到 `https://opencode.ai`，并校验流式响应里必须出现**可见的 assistant 输出**（`content` 非空或 `tool_calls`/`function_call`）才算成功，`maxAttempts=3`、`maxTokens=131072`。当年用途：给 Codex 套一个免费模型端点。

```bash
lsof -nP -iTCP:18765                        # 空：无人监听、无人连接
ls /tmp/x-preview-proxy*                     # 空：10-22 开机后没有任何一次运行
grep -rl "18765" ~/.codex --include=*.toml --include=*.json   # 仅命中一串签名哈希的巧合子串
grep -nE "^model_provider|\[model_providers.custom\]" ~/.codex/config.toml -A4
#   model_provider = "openai"
#   [model_providers.custom] name = "OpenAI" / requires_openai_auth = true / wire_api = "responses"   ← 无 base_url
```

* **结论**：Codex 已回到官方 OpenAI 通道（`~/.codex/config.toml` 的 `[model_providers.local-llm]` 也只是别名，不是本地代理；另有 `[mcp_servers.local_llm]` 走 ollama，与 18765 无关）。**问题已解决（不再需要免费中转）→ plist 与脚本一起删。**

### ③④ `com.yusong.feiniaoyun.aiwatch` / `aiheal` —— 逻辑没错，但绑死的世界已经不存在

服务定义：`aiwatch` 每 300 秒（`RunAtLoad` + `StartInterval`）跑 `watch_ai.py`；`aiheal` 每天 07:00 跑 `auto_heal.py`。脚本设计本身是对的——**用带账号的 `agy` 真实调用判健康**（正是本仓库确立的权威判据），失败 20 秒复测，再经 `127.0.0.1:9090` 逐个试分组内成员，每换一次都复验，全挂才触发全量巡检并通知，且从不重启 FlClash。

失效证据（三条独立）：

```bash
# 1) 写死的 profile 已被删除
grep -n "PROFILE_ID" ~/Desktop/feiniao-check/flclash-override/watch_ai.py       # PROFILE_ID = 369860446477357056
ls ".../com.follow.clash/profiles/369860446477357056.yaml"                       # No such file
# 当前 profiles 表：369768027173949440(赔钱机场, current_group_name=🚀节点选择, 今天 09:11 更新) / 372579519762010112(飞鸟云)

# 2) 脚本假定的分组在当前订阅里不存在
grep -c 'name: "AI稳定"' config.yaml    # 0
grep -c 'name: "AI自动"' config.yaml    # 0
grep -c 'name: "🤖AI网站"' config.yaml  # 1  ← 只有一个 select 组，成员是其它分组与 0.1 倍中转

# 3) 白名单整体过期
python3 -c "... lists['allow'] 与当前订阅求交"   # 11 个允许节点，命中 0；source: auto-heal 2026-10-20T07:05
```

* **结论**：**问题没有被解决**（"节点坏了不会自动换、也不会通知"这个缺口仍在，而 10-24 / 10-28 / 10-29 三篇都记录了同一出口池被 Google 随机判 HK 的情况）；但**这两份服务定义已经无法工作**，`bootstrap` 回来只会立刻失败，属于"看起来能救其实救不回"的状态。**plist 删除，脚本本体保留**作为将来重写的底子。
* **改造成本（若日后要复活）**：三处——① 从 FlClash 持久库 `profiles` 表读当前 profile，别写死 ID；② 分组名换成当前订阅真实分组；③ 重新生成 `lists.json`。或者干脆退化成"只报警不换节点"的最小看门狗（每 30 分钟一次 `agy` 真实调用，失败发通知，不碰任何配置）。

---

## 根因分析（为什么这些僵尸值得专门清一次）

1. **"挪走 plist"式整理会制造静默失效**：`RunAtLoad` 服务一旦离开 `~/Library/LaunchAgents/`，下次登录就不再装载，而且**没有任何报错**。汉化注入器就是这么停了 9 天的。同一目录里剩下那 4 个也是同样状态，只是恰好没人依赖。
2. **归档目录本身是误导源**：`_offloaded-agents-1020-1757` 看起来像"待恢复清单"，实际混杂了「已完成使命的一次性任务」「失去调用方的服务」「目标环境已消失的看门狗」三类，光看文件名无法区分，必须逐个复验运行条件。
3. **删除的正确姿势是可恢复**：全部 `mv ~/.Trash`，不用 `rm`；同时把每一项的定论写进 `~/Desktop/feiniao-check/README-状态-20261029.md`，让下一次"整理"不必重新考古。

---

## 解决方案与落地操作

```bash
# 逐项复验（通用套路）
plutil -p <plist>                                   # 看是 KeepAlive 常驻 / RunAtLoad / StartCalendarInterval 一次性
launchctl print gui/501/<label>                     # 现在是否装载
ls <ProgramArguments 里的脚本路径>                   # 执行体是否还在
# 然后按服务性质验证"问题是否已解决"：defaults read / 端口占用 / 配置引用 / 持久库比对

# 删除（可恢复）
mv <plist 或脚本> ~/.Trash/    # 若同名已在废纸篓，加 -20261029 后缀避免覆盖
```

复用到其它机器的判据模板：

| 服务类型 | "问题已解决"的判据 |
| --- | --- |
| 一次性定时任务 | 目标状态当前成立（`defaults read` / 文件存在性），且脚本无其它副作用 |
| 常驻代理 | 端口无人监听、无人连接；所有配置文件都无引用（注意排除哈希/长数字的巧合命中） |
| 看门狗/巡检 | 它写死的 profile / 分组 / 白名单是否仍在现网存在；任一不存在即"救不回"，plist 该删、逻辑该留 |

---

## 验证与效果

| 验证项 | 方式 | 结果 | 状态 |
| :--- | :--- | :--- | :--- |
| ① 自动更新 | `defaults read com.openai.codex …` | `SUAutomaticallyUpdate=1`、`SUEnableAutomaticChecks=1`、`SULastCheckTime=2026-10-28 06:31` | ✅ 已解决，删除 |
| ② 本地转发 | `lsof -iTCP:18765` + 配置引用搜索 | 无监听无连接；`model_provider="openai"`、custom 组无 `base_url`；`18765` 仅巧合命中 | ✅ 无调用方，删除 |
| ③④ 看门狗 | 持久库 profile / 分组名 / `lists.json` 三重比对 | profile 不存在、`AI稳定`/`AI自动` 计数 0、白名单 11→0 命中 | ✅ plist 删除，**脚本保留** |
| 误删防护 | 删除方式 | 6 项全部 `mv ~/.Trash`，未用 `rm` | ✅ 可恢复 |
| 在用服务未受影响 | `launchctl print gui/501/…` | `local.antigravity-zh.injector` `state = running`（pid 52583）；`local.codex.status-capsule.agent` 仍在 `~/Library/LaunchAgents/` 且已加载 | ✅ |
| 现场留档 | `~/Desktop/feiniao-check/README-状态-20261029.md` | 逐项定论 + 复活改造三要点 + 仍存缺口写明 | ✅ |

---

## 经验沉淀与后续建议

1. **删遗留服务前先分类**：一次性任务看"目标状态是否已成立"、常驻代理看"是否还有调用方"、看门狗看"它绑定的世界还在不在"。三类判据不同，混在一起就会变成"不敢删也不敢留"。
2. **"问题没解决"和"代码救不回"要分开表述**：③④ 就是这种——缺口仍在（节点坏了不自愈、不通知），但那份实现已不可能跑起来。正确处置是删掉误导性的服务定义、留下可复用的逻辑，并把缺口显式记录成待办，而不是假装问题解决了。
3. **巧合命中要人工复核**：全盘搜端口号时，`18765` 出现在一串签名哈希里。看到 grep 命中就定罪，会误判"还有调用方"从而留下僵尸。
4. **删除一律走废纸篓**：这类考古式清理的判断依据只有几分钟前的几条命令输出，一旦判错，`rm` 没有回头路。
5. **别让 `_offloaded-agents-*` 这种目录裸奔**：要么当场把每项标注状态，要么干脆不要"挪走"而是 `bootout` + 注释保留。本次的 9 天静默停摆就是这么来的。
6. **仍然开放的下一步**（等你点头再做）：把 `watch_ai.py` 的真实调用逻辑抽成"只报警"的最小 LaunchAgent（每 30 分钟一次 `agy -p "Reply with exactly: PONG"`，失败发 macOS 通知，不改任何代理配置），可以低成本补上"坏了没人说"这个缺口。

---

## 关键产物与现场位置（不含密钥）

- **移入废纸篓的 6 项**：`com.openai.codex.restore-autoupdate.plist`、`restore-chatgpt-autoupdate.sh`、`com.codex.xpreview.proxy.plist`、`x-preview-proxy.js`、`com.yusong.feiniaoyun.aiwatch.plist`、`com.yusong.feiniaoyun.aiheal.plist`（13:53 移入 `~/.Trash`）
- **归档目录现状**：`~/Desktop/feiniao-check/_offloaded-agents-1020-1757/` 仅剩 `local.antigravity-zh.injector.plist`（原件）与 `local.codex.status-capsule.agent.plist`
- **保留的看门狗实现**：`~/Desktop/feiniao-check/flclash-override/` 下 `watch_ai.py`(10519B)、`auto_heal.py`(7388B)、`install_override.py`(7406B)、`render_override.py`(1161B)、`lists.json`(476B，已过期)；探针 `~/Desktop/feiniao-check/probe_antigravity.py`
- **定论清单**：`~/Desktop/feiniao-check/README-状态-20261029.md`
- **判据相关配置**：`~/.codex/config.toml`（`model_provider = "openai"`）、`defaults domain com.openai.codex`
- **现网 FlClash 事实**：生效 profile `369768027173949440`（赔钱机场，`current_group_name=🚀节点选择`），另有 `372579519762010112`（飞鸟云）；AI 相关分组仅 `🤖AI网站`
- **仍在运行的相关服务**：`local.antigravity-zh.injector`（汉化注入，pid 52583）、`local.codex.status-capsule.agent`

---

*本篇是一份"遗留 LaunchAgent 去留判定"的操作范本来回：同一目录里的四个服务，定论分别是"使命已完成的一次性任务""调用方消失的代理""目标环境整体消失的看门狗（定义删、逻辑留）"。判据全部可复核——`defaults` 现值、端口占用与引用搜索、持久库 profile 与分组名比对、白名单命中率。核心提醒是第 5 条：`_offloaded-agents-*` 这种目录不会报错，只会让服务安静地停在那里。*
