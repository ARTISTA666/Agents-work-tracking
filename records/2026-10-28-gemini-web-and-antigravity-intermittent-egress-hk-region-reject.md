# Gemini 网页端 + Antigravity 内 Gemini「同时连不上」：默认分流仍在共享廉价中转、出口被 Google 判香港导致请求级地区拒绝（10-24 同根因复发）；已完成方案 A：默认分流固定到圣何塞07（写库持久化 + 跨 FlClash 重启验证）

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（用户指派；全程只读诊断 + 一次可回滚的节点切换实验，测完立即还原）
- **问题类型**：梯子分流 + 机场出口 IP 地理判定（Gemini 网页端 / Antigravity 的 Gemini 后端通道）
- **时间**：2026-10-28 09:18–10:20（Asia/Shanghai）
- **最终状态**：✅ **已修复**。分两段：① 09:19–10:15 为只读诊断 + 一次可回滚的临时节点切换（已 `trap` 还原）；② **10:16–10:21 执行方案 A**——把 `🚀节点选择` 从 `🇺🇸美国节点`（子组落在共享廉价中转）固定到 `🇺🇸美国圣何塞07｜三网推荐`，并写入 FlClash 持久库 `profiles.selected_map`；**完全退出并重启 FlClash 后选择仍在**（config 10:17 重建、`utun4` 恢复、两条覆写规则未动）。修复后：出口 `134.195.101.193/194`（US）、`google.com` 不再 302 到 `google.com.hk`、`gemini.google.com` 3/3 `200`、`agy` 连续 2/2 `PONG`。
- **备份 / 脚本**：`~/Desktop/gemini-check/backup-20261028-101619/`（config.yaml + database.sqlite）；[`scripts/default-egress-pin.sh`](../scripts/default-egress-pin.sh)（`check` / `apply` / `rollback`，含写库与重启复验）。
- **关联记录**：[2026-10-24 Gemini 网页端地区限制（同根因）](2026-10-24-gemini-web-unsupported-country-ai-node-egress.md)、[2026-10-17 Antigravity 400 User location is not supported](2026-10-17-antigravity-400-user-location-not-supported-singapore-node-exit-ip-rejected-and-silent-cli-verification.md)、[2026-10-22 AI 节点出口 IP 轮换](2026-10-22-chatgpt-desktop-cloudflare-clearance-egress-ip-rotation.md)
- **关联脚本**：[`scripts/antigravity-silent-check.sh`](../scripts/antigravity-silent-check.sh)（本次用它做 Antigravity 侧真实调用判定）
- **本机留档**：本次为只读诊断，未截图、未改配置；证据全部来自下列日志与本记录内的命令输出

### 环境

| 项 | 值 |
| --- | --- |
| 系统 | macOS 26.6（arm64 MacBook Air） |
| 客户端 | FlClash v0.9.0（内核 mihomo v1.19.32，TUN `utun4` + 规则模式；系统代理关闭，TUN 全量接管） |
| 订阅 | 「赔钱机场」（profile `369768027173949440`） |
| Antigravity | **2.27.0**（今天 06:14 由 2.25.0 自动更新；本次确认 10-22 的 `PROCESS-PATH` 规则在 2.27.0 仍匹配 `language_server`） |
| 浏览器 | Google Chrome 155（Default profile） |
| 外网控制 API | `http://127.0.0.1:9090`，secret 见 `config.yaml` 的 `secret:` |
| 故障时段分组 | `🚀节点选择 → 🇺🇸美国节点 → 🇺🇸美国圣何塞03｜三网推荐`（出口 `104.251.122.87`）；`🤖AI网站 → 🇺🇸美国08-0.1倍` |

---

## 问题详细描述

1. 用户 09:18 报告：**「测试本机对梯子网络对 gemini 网页端的访问，以及 Antigravity 中对 gemini 的访问，现在两者都无法连接」**。
2. 复核时（09:19 起）发现：`curl` / 无头 Chrome 访问 `gemini.google.com` 正常，Antigravity 主进程的 Google 通道也正常 —— 但 `agy`（Antigravity CLI）真实调用**稳定复现** `400 FAILED_PRECONDITION: User location is not supported for the API use.`
3. 用户 10:11 确认两者均已恢复。

---

## 排查过程与关键技术证据

### 1. 先排除「梯子整体挂了」

| 检查项 | 结果 |
| --- | --- |
| FlClash 进程 / 内核 | 正常（`FlClashCore` + GUI），mihomo v1.19.32 |
| 监听端口 | `127.0.0.1:7890`（HTTP）、`127.0.0.1:9090`（控制 API） |
| TUN / 路由 | `utun4` UP，`198.18.0.0/16` 分流路由齐备，默认路由仍走 `en0` |
| DNS | mihomo `fake-ip`（`198.18.0.1/16`），系统 DNS `223.5.5.5 / 119.29.29.29` |
| 规则 | `gemini.google.com → 🇺🇸美国圣何塞07`、`PROCESS-PATH .../language_server → 🇺🇸美国圣何塞07` **都在位**（见第 4 节） |

→ **不是断网、不是规则丢失、不是 DNS 污染。**

### 2. 两条链路的实时命中（`/connections`）

| 流量 | 命中规则 | 实际链路 |
| --- | --- | --- |
| Gemini 网页（Chrome） | `DOMAIN,gemini.google.com` | **🇺🇸美国圣何塞07｜三网推荐** |
| Antigravity 的 Gemini（`language_server`） | `PROCESS-PATH,.../Antigravity.app/.../language_server` | **🇺🇸美国圣何塞07｜三网推荐**（实测 7 条连接全部命中） |
| `agy` CLI、`www.google.com`、`signaler-pa.clients6.google.com` 等默认流量 | 未命中覆写（`agy` 不在 `PROCESS-PATH` 里） | `🚀节点选择 → 🇺🇸美国节点 → 🇺🇸美国圣何塞03｜三网推荐`，出口 `104.251.122.87` |

也就是说：**Gemini 网页和 Antigravity 主程序早就被钉在干净出口上，真正裸奔的是默认分流（含 `agy`、Google 通用服务）。**

### 3. 故障时间线（多源日志对齐）

| 时间 | 事件 | 来源 |
| --- | --- | --- |
| 06:14 | Antigravity 自动更新到 2.27.0 并重启 | `~/Library/Logs/Antigravity/main.log` |
| 07:02:24 / 07:03:19 | Read loop `unexpected EOF` | `language_server.log` |
| 08:24:32 | `fetchUserInfo` 失败：`EOF` | `language_server.log` |
| 09:05–09:12 | Chrome 三次打开 `gemini.google.com`（09:05:12 / 09:11:32 / 09:12:17） | Chrome `History` |
| 09:11:52 / 09:11:57 | Read loop `unexpected EOF` | `language_server.log` |
| 09:12:06 | `cascadeNuxes` / `pollSignalingMessages` → `read: connection reset by peer` | `language_server.log` |
| **09:16** | **FlClash 内核重启，`config.yaml` 重建（mtime 09:16）** | 进程启动时间 + 配置文件 mtime |
| 09:16:16 | 又一次 `connection reset by peer`（`jetski-webchannel`） | `language_server.log` |
| 09:20:42 / 09:21:07 | `agy` 真实调用两次 400 | `~/.gemini/antigravity-cli/log/cli-20261028_0920*.log` |
| 09:19–09:30 | 本次诊断与验证 | 本记录 |
| 10:13 | 默认链路 `agy` 连续两次：PONG / 400（同一出口 IP、同一分钟） | 本记录 |
| 10:11 | 用户确认两者恢复 | 用户 |

→ 09:11–09:16 的 **连接重置 + 内核重启**，正好把网页与 Antigravity 的在途连接同时掐断，这就是「两者同时连不上」的**同时性**来源；而**持续性**的地区拒绝只发生在未固定出口的流量上。

### 4. 复现实验：`agy` 真实调用（唯一可信的地区判据）

无认证 curl 打 `daily-cloudcode-pa.googleapis.com` 只会得到 401/404，不能判地区（见 10-17 记录的判据修正），所以必须用带账号的真实调用：

```bash
# 默认链路（未切节点）
~/.local/bin/agy -p "Reply with exactly: PONG" --print-timeout 90s
# → 09:20:42 / 09:21:07 两次：
#   error: FAILED_PRECONDITION (code 400): User location is not supported for the API use.
```

对照实验（可回滚，已还原）：

```bash
SEC=$(grep -m1 '^secret:' ~/Library/Application\ Support/com.follow.clash/config.yaml | sed 's/secret: *"\(.*\)"/\1/')
CTRL=http://127.0.0.1:9090

# 临时把默认出口切到圣何塞07（测完立刻还原为 🇺🇸美国节点）
curl -s -X PUT -H "Authorization: Bearer $SEC" -H 'Content-Type: application/json' \
  --data '{"name":"🇺🇸美国圣何塞07 | 三网推荐"}' \
  "$CTRL/proxies/%F0%9F%9A%80%E8%8A%82%E7%82%B9%E9%80%89%E6%8B%A9"

curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc)='
# → ip=134.195.101.193  loc=US
curl -s -o /dev/null -D - https://www.google.com/ | grep -i '^location:'
# → 无输出（不再 302 到 google.com.hk）
~/.local/bin/agy -p "Reply with exactly: PONG" --print-timeout 90s
# → PONG ✅
```

**请求级偶发的关键证据**（10:13，默认链路，出口 `104.251.122.87`，未做任何改动）：

```
第1次: PONG
第2次: AGY_ERROR: {"short_error":"FAILED_PRECONDITION (code 400): User location is not supported for the API use.", ..., "error_code":400}
```

同一出口 IP、同一分钟、同一命令：**一成一败** → 说明机场出口是共享 NAT 池，每个请求可能落到不同出口；池里既有 Google 判 US 的干净 IP，也有被判 HK 的受限 IP。

同一时刻的旁证：

```bash
curl -s -o /dev/null -D - https://www.google.com/ | grep -i '^location:'
# → https://www.google.com.hk/url?...pref=hkredirect&pval=yes&...   ← Google 认为该出口是香港
# 而 cloudflare trace 同一出口显示：ip=104.251.122.87  loc=US     ← Cloudflare 认为是美国
```

→ **机场 IP 段与 Google 地理库不一致**，这是结构性问题的直接证据（与 10-24 记录一致）。

### 5. 为什么「网页端连不上」没被复现

- `gemini.google.com` 自 10-24 起被 `DOMAIN` 规则固定在圣何塞07（本次实测 `/rules` 第 6 条，命中数从 13 涨到 48），因此不受默认分流的 HK 出口影响。
- 实测：TUN 直连 10/10 次 `HTTP 200`（809KB 左右、含 `Sign in`、无 `isn't currently supported` 文案）；无头 Chrome 打开 `/app` 拿到 1.69MB 正常页面，`gemini` 规则命中数在同一次加载中 +6，确认走圣何塞07。
- 因此网页端当时的「连不上」应归因于：① 09:11–09:16 的连接重置/内核重启；② Chrome 缓存或 Service Worker 残留旧拦截页（10-24 已记录该现象）——强刷/清站点数据即恢复。

---

## 根因分析

1. **结构性根因（复发源）**：机场「赔钱机场」大量出口 IP 被 **Google 地理库判为香港**（`google.com → google.com.hk`，`pref=hkredirect`），而 Gemini 不支持香港；Antigravity 内部端点 `daily-cloudcode-pa.googleapis.com` 的地区校验更严，直接回 `400 FAILED_PRECONDITION / User location is not supported`。
2. **本次直接触发**：默认分流 `🚀节点选择` 落在**共享、轮换的廉价中转**上（今天为 `🇺🇸美国圣何塞03｜三网推荐`，出口 `104.251.122.87`；此前还出现过 `美国08-0.1倍`、`美国07-0.1倍`、`洛杉矶08`），NAT 池内出口好坏混杂 → 每个请求随机通/不通，表现为「时好时坏」。
3. **「同时连不上」的成因**：09:11–09:16 出现连续 `connection reset by peer`，09:16 FlClash 内核重启（`config.yaml` 重建），网页与 Antigravity 的在途连接被同时掐断；对用户就是「两个一起挂」。恢复后网页端因有固定规则直接恢复，`agy` 侧则继续随机 400。
4. **与 10-24 的区别**：上次是 `🤖AI网站` 组选中 `美国08-0.1倍`；本次默认组已换成「美国节点 → 圣何塞03｜三网推荐」，名字看起来“干净”了，但**出口 IP 被 Google 判 HK 的结构性问题没变**，所以同一症状在未固定出口的链路上复发；`agy` 不在 `PROCESS-PATH` 规则内，正好暴露了这一点。
5. **另一处非网络原因（已排除）**：Antigravity 2.27.0 今晨自动更新，但 10-22 配置的 `PROCESS-PATH` 规则仍能匹配新版本的 `language_server`，且 `language_server.log` 中 `User location is not supported` 计数为 0 —— 主程序通道没有地区拒绝，只是被 09:12/09:16 的重置打断过。

---

## 解决方案与处置（已执行方案 A）

### 方案 A（已执行）：默认出口移出共享廉价中转

把 `🚀节点选择` 从 `🇺🇸美国节点` 换到实测干净的固定出口 `🇺🇸美国圣何塞07｜三网推荐`：

```
🇺🇸美国圣何塞07｜三网推荐     出口 134.195.101.193 / .194（US）
  - google.com 不 302 到 google.com.hk
  - agy 真实调用 PONG
```

**执行步骤（10:16–10:21，共约 5 分钟）**

| 步 | 动作 | 结果 |
| --- | --- | --- |
| 1 | 备份 `config.yaml` + `database.sqlite` → `~/Desktop/gemini-check/backup-20261028-101619/` | ✅ |
| 2 | mihomo API `PUT /proxies/🚀节点选择 {"name":"🇺🇸美国圣何塞07 \| 三网推荐"}` | 立即生效：出口 `134.195.101.194`、`google.com` 无 HK 跳转 |
| 3 | 检查持久库：`profiles.selected_map` 仍是旧值 `🇺🇸美国节点`（API 改的是运行时，FlClash 不知道） | 确认必须写库 |
| 4 | **完全退出 FlClash**（`osascript -e 'quit app "FlClash"'`，GUI/core 均退出）→ 写 `profiles.selected_map` → `open -a FlClash` | 重启后选择仍为圣何塞07、`utun4` 恢复 |
| 5 | 复验 | 出口 US、`google.com` 无 HK 跳转、`gemini` 3/3 `200`、`agy` 2/2 `PONG` |

选择 `🚀节点选择` **直接指向节点**（而不是继续指向 `🇺🇸美国节点` 子组）的原因：`selected_map` 只持久化了 3 个顶层分组（`GLOBAL` / `🚀节点选择` / `🤖AI网站`），**嵌套子组 `🇺🇸美国节点` 的当前选择不在库里**，重启后不可控；直接选节点才真正"钉死"。

**未改动**：`🤖AI网站` 仍是 `🇺🇸美国08-0.1倍`（ChatGPT/Claude 等不受影响）；`gemini.google.com` 与 `language_server` 两条覆写规则原样保留；系统代理状态未改（TUN 全量接管）。

### 方案 B（备选，未执行）：只给 `agy` 钉出口

如果以后想保留 `🚀节点选择 = 🇺🇸美国节点` 的灵活性，可改为给 CLI 单独钉出口：

```
PROCESS-PATH,/Users/yusong/.local/bin/agy,🇺🇸美国圣何塞07｜三网推荐
```

写入 FlClash 持久库 `rules` 表后热重载（照 [`scripts/gemini-web-egress-pin.sh`](../scripts/gemini-web-egress-pin.sh) 的 check/apply/rollback 方式）。本次不需要——默认出口已经干净。

> 原则：**Gemini / Antigravity / ChatGPT 这类地区敏感服务，不要用 0.1 倍 / 0.01 倍廉价中转**（出口 IP 共享漂移，被判 HK/CN 的概率显著更高）。

### 复用脚本

[`scripts/default-egress-pin.sh`](../scripts/default-egress-pin.sh)：

```bash
bash scripts/default-egress-pin.sh check       # 只读：API/DB 选择、出口、Google 判 HK、agy 真实调用
bash scripts/default-egress-pin.sh apply       # 备份 → 退 FlClash → 写 selected_map → 重启 → 复验
bash scripts/default-egress-pin.sh rollback    # 回滚到最近一次 apply 前的选择
```

---

## 验证

1. **网页端**：`curl https://gemini.google.com/app` → 09:19 连续 10/10 次 `200`（`time_total` 2.0–3.7s，无拦截文案）；10:12 复测 3/3 次 `200`。
2. **浏览器路径**：无头 Chrome（独立 profile）`--dump-dom https://gemini.google.com/app` → 1.69MB、含 `Sign in`、无 `isn't currently supported`；规则命中数 29→35，确认流量命中 `DOMAIN,gemini.google.com → 圣何塞07`。
3. **Antigravity 主程序**：`/connections` 中 `language_server` 的 7 条连接（`daily-cloudcode-pa`、`aicode`、`jetski-webchannel`、`play`、`www.googleapis` 等）**全部**走圣何塞07；`language_server.log` 当日 `User location is not supported` 计数 0。
4. **Antigravity CLI（真实调用）**：默认链路两次 400；切到圣何塞07 后 `PONG`；10:13 默认链路同 IP 连续两次一成一败 → 复现「请求级偶发」。
5. **用户确认**：10:11 用户确认「两个都通了」。
6. **修复后（10:21 起，跨 FlClash 重启）**：`🚀节点选择` API 值与 `selected_map` 值都是 `🇺🇸美国圣何塞07｜三网推荐`；出口 `134.195.101.193/194`（US）、`google.com` `hkredirect` 计数 **0**；`gemini.google.com/app` 3/3 `200`（2.1/2.4/3.3s，无拦截文案）；`agy` 连续 **2/2 `PONG`**；`config.yaml` 10:17 重建后两条覆写规则仍在（`/rules` 第 6、7 条，即 index 5、6）。
7. **校验脚本**：`bash scripts/default-egress-pin.sh check` → `API 当前选择 = DB 持久值 = 圣何塞07`、`google 判 HK : 0`、`✅ Antigravity 后端正常`。

---

## 回退

改动前原值：`🚀节点选择 = 🇺🇸美国节点`（其子组当时为 `🇺🇸美国圣何塞03｜三网推荐`，该子组选择不受 `selected_map` 持久化影响，重启后本来就会变）。

```bash
# 方式一：脚本（推荐）
bash scripts/default-egress-pin.sh rollback
# 从最近一次 apply 备份的 selected_map.json 恢复，并重启 FlClash

# 方式二：手工（先退出 FlClash）
osascript -e 'quit app "FlClash"'
sqlite3 ~/Library/Application\ Support/com.follow.clash/database.sqlite \
  "update profiles set selected_map=replace(selected_map,'🇺🇸美国圣何塞07 | 三网推荐','🇺🇸美国节点') where id=369768027173949440;"
open -a FlClash

# 方式三：恢复备份
cp ~/Desktop/gemini-check/backup-20261028-101619/database.sqlite \
   ~/Library/Application\ Support/com.follow.clash/database.sqlite
```

- 只在 FlClash **已退出**时写库；运行中写会被内存态覆盖。
- 本次唯一被改的是 `profiles.selected_map`，`config.yaml` 是运行期重建产物、`rules` 表未动。

---

## 后续建议

1. **复发判别三步**（1 分钟内）：① 网页强刷 / 无痕窗口对照（排除缓存）；② 看 `/rules` 前 6 条里 `gemini.google.com` 与 `language_server` 是否还在；③ `curl -s -o /dev/null -D - https://www.google.com/ | grep -i location` 是否 302 到 `google.com.hk`，再用 `agy` 真实调用确认。
2. **出口健康度判据**：用「`google.com` 是否 302 到 `google.com.hk`」比 Cloudflare 的 `loc=` 更贴近 Google 的真实判定（本次 `104.251.122.87`：CF 说 US，Google 说 HK）。
3. **Antigravity 升级后要复验规则**：2.27.0 仍匹配 `language_server` 路径；未来大版本若改路径，`PROCESS-PATH` 会失效且无报错，需重新确认。
4. **`agy` 已不再是"裸奔探针"**：默认组固定到圣何塞07 后它同样走干净出口（2/2 `PONG`）。若将来把 `🚀节点选择` 改回 `🇺🇸美国节点` 之类会随订阅轮换的选择，记得补方案 B 的 `PROCESS-PATH` 规则。
5. **出口失效的应急换法**：圣何塞07 若波动，用 `bash scripts/default-egress-pin.sh apply "🇺🇸美国洛杉矶08 | 三网推荐"` 换节点——**先跑 `check` 确认候选节点 `google 判 HK : 0` + `agy PONG`**，不要凭节点名判断。
6. **重启后自检**（可选）：把 `scripts/default-egress-pin.sh check` 加进开机流程或手动跑一次，确认 `API 当前选择 = DB 持久值 = 干净节点`。

---

## 附录：本次关键命令

```bash
SEC=$(grep -m1 '^secret:' ~/Library/Application\ Support/com.follow.clash/config.yaml | sed 's/secret: *"\(.*\)"/\1/')
CTRL=http://127.0.0.1:9090

# 1) 链路体检
netstat -an -p tcp | grep -E '\.(7890|9090) '
scutil --dns | grep -E 'nameserver|if_index'

# 2) 规则前 10 条（看覆写是否在位）
curl -s -H "Authorization: Bearer $SEC" "$CTRL/rules" | python3 -c '
import sys,json
for i,r in enumerate(json.load(sys.stdin)["rules"][:10]):
    print(i, r["type"], r["payload"][:80], "->", r["proxy"], "hit", r["extra"]["hitCount"])'

# 3) 实时连接（看两条链路各走哪个节点）
curl -s -H "Authorization: Bearer $SEC" "$CTRL/connections" | python3 -c '
import sys,json
for c in json.load(sys.stdin)["connections"]:
    md=c["metadata"]; print(md.get("host"), "|", md.get("process"), "|", c.get("chains"))'

# 4) 出口判定（云厂商视角 vs Google 视角）
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc)='
curl -s -o /dev/null -D - https://www.google.com/ | grep -i '^location:'

# 5) Antigravity 通道真实调用（唯一可信判据）
bash scripts/antigravity-silent-check.sh
# 或直接：
~/.local/bin/agy -p "Reply with exactly: PONG" --print-timeout 90s

# 6) Gemini 网页端（无缓存对照）
curl -s https://gemini.google.com/app -o /tmp/gemini.html
grep -c -i "isn't currently supported" /tmp/gemini.html     # 期望 0
```
