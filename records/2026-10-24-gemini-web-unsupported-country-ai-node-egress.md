# Gemini 网页端「Gemini isn't currently supported in your country」：网页走 🤖AI网站 廉价中转、出口被 Google 判到香港；Antigravity 因 `PROCESS-PATH` 固定圣何塞干净美国出口而正常 —— 固定 Gemini 出口后恢复，并验证跨 FlClash 重启不丢

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（用户指派；全程只做只读诊断 + 最小改动，改动前均备份，可回滚）
- **问题类型**：Gemini 网页（`gemini.google.com`）地区限制；mihomo/FlClash 分流 + 机场出口 IP 地理判定
- **时间**：2026-10-24 16:38–17:00（Asia/Shanghai）
- **最终状态**：✅ 已解决。`gemini.google.com` 固定走与 Antigravity 相同的干净美国出口（🇺🇸美国圣何塞07｜三网推荐，出口 `134.195.101.193/194`，US），Chrome 原窗口（未清缓存、未换 profile）刷新即正常显示 Gemini 对话界面；**完全退出并重启 FlClash 后规则仍在**（配置 17:00:09 重建，规则在第 1628 行、`/rules` 第 5 位），Antigravity 未受影响。
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking) ｜ 辅助脚本：[`scripts/gemini-web-egress-pin.sh`](../scripts/gemini-web-egress-pin.sh)
- **本机留档**：`~/Desktop/gemini-check/Gemini网页端地区限制-排查与修复-20261024.md`、`~/Desktop/gemini-check/backup-20261024-165335/`（config.yaml / database.sqlite / profile 三份备份）、`evidence-1~4*.png`

### 环境

| 项 | 值 |
| --- | --- |
| 系统 | macOS 26.6（arm64 MacBook Air） |
| 客户端 | FlClash v0.9.0（内核 mihomo v1.19.32，TUN `utun4` + 规则模式；系统代理关闭，TUN 全量接管） |
| 订阅 | 「赔钱机场」（profile `369768027173949440`，143 节点） |
| 浏览器 | Google Chrome（Default profile，**页面显示未登录**；被拦窗口与无痕窗口的差异是本次关键判据之一） |
| 外网控制 API | `http://127.0.0.1:9090`，secret 见 `config.yaml` 的 `secret:` |

---

## 问题详细描述

1. Chrome 打开 `gemini.google.com`，返回整页「**Gemini isn't currently supported in your country. Stay tuned!**」（营销首页形态：For developers / For business / FAQ，无登录按钮）。
2. 同一时刻、同一台机器，**Antigravity 里的 Gemini 正常**（能正常出结果）。
3. 交叉验证时发现诡异差异：
   - Chrome **普通窗口**（带该 profile 的 Google cookie）→ 地区拦截页；
   - Chrome **无痕窗口**（无 cookie）→ 正常显示 Gemini 对话界面；
   - 同时用 `curl`（无 cookie，走同一 TUN 链路）→ 也能拿到正常页面（HTTP 200，约 808 KB，含 “Sign in”，无拦截文案）。
4. 拦截页在普通窗口里很“顽固”：换 URL（`/app?hl=en&nocache=1`）依然显示拦截页，怀疑被浏览器缓存/Service Worker 影响。

---

## 排查过程与关键技术证据

### 1. 先对照两条链路的实时命中（mihomo `/connections`）

同一时刻抓取：

| 流量 | 命中规则 | 实际出口链路 |
| --- | --- | --- |
| Antigravity 的 Gemini（`language_server` 进程请求 `aicode.googleapis.com` / `daily-cloudcode-pa.googleapis.com` / `www.googleapis.com`） | `PROCESS-PATH,/Users/yusong/Applications/Antigravity.app/Contents/Resources/bin/language_server` | **🇺🇸美国圣何塞07 \\| 三网推荐** |
| Chrome 里的 Gemini 网页（`gemini.google.com`） | `DOMAIN,gemini.google.com → 🤖AI网站`（订阅自带规则） | **🇺🇸美国08-0.1倍**（hysteria2，`pq.us8.globals-download.com:35000`） |

```bash
# 实测输出（节选）
gemini.google.com | rule: Domain gemini.google.com | chains: ['🇺🇸美国08-0.1倍 | 电信联通移动推荐', '🤖AI网站']
daily-cloudcode-pa.googleapis.com | rule: ProcessPath .../language_server | chains: ['🇺🇸美国圣何塞07 | 三网推荐']
```

→ **两条流量根本不是同一个节点**：Antigravity 早就被 2026-10-22 的修复用 `PROCESS-PATH` 钉在干净美国出口；而 Gemini 网页走的是订阅默认的「🤖AI网站」组里选中的 **0.1 倍廉价中转**。

### 2. 证明「这个机场的出口会被 Google 判到香港」

Gemini 网页在香港不提供服务（`google.com.hk` 属 HK），而本机场出口在 Google 眼里正是 HK：

```bash
# 连续 5 次，全部 302
curl -s -o /dev/null -D - https://www.google.com/ | grep -i '^location:'
# → https://www.google.com.hk/url?sa=p&hl=zh-CN&pref=hkredirect&pval=yes&q=https://www.google.com.hk/...
```

同一批出口 IP 的两种地理库结论不一致：

| 出口 IP | Cloudflare trace | Google 判定 |
| --- | --- | --- |
| `67.159.48.146` / `.147` | `loc=SG`（新加坡） | **HK**（`google.com` → `google.com.hk`，`pref=hkredirect`） |

→ 说明该机场大量 IP 与 Google 的地理库不匹配；`gemini.google.com` 又恰好是地区判定最严的服务，**只要网页流量落在这些“Google 认为是 HK”的出口上，就会拿到地区拦截页**。而 Antigravity 被固定到的 `134.195.101.x`（圣何塞07）是 Google 判定为 US 的干净出口，所以一直正常。

### 3. 节点切换实验（定位“变量”）

```bash
# 把 🤖AI网站 组切到与 Antigravity 相同的干净美国出口
PUT /proxies/🤖AI网站  {"name":"🇺🇸美国圣何塞07 | 三网推荐"}
```

- 切换后，Chrome **普通窗口**刷新 → 立即恢复正常（不再显示地区拦截页）。
- 再切回「美国08」重拨 → 依然正常（此时该节点出口已变为 `203.10.96.139`，Cloudflare `loc=US`）。
- 结论：**美国08 这类 0.1 倍中转的出口 IP 会漂移**，故障期间它的出口被判为受限地区，重拨换到干净出口后就通了；这也是“时好时坏”的来源。固定出口即可消除这个变量。

### 4. 顺带确认 Antigravity 侧无问题（未改动其规则）

```bash
tail ~/Library/Logs/Antigravity/language_server.log
# 16:53 仍正常：URL: https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse
grep -c "User location is not supported for the API use" ~/Library/Logs/Antigravity/language_server.log
# → 0
```

### 5. 被拦页面的“顽固”来自浏览器缓存

同一 profile 的普通窗口在节点已切换后仍短时间显示拦截页；无痕窗口/curl 一直正常。强刷或站点数据清除后即恢复。说明**拦截页 HTML 被 Chrome 缓存**，光刷新普通窗口可能看到旧页面（这也解释了“换个 URL 还是拦截页”）。

---

## 根因分析

1. **直接原因（可证实）**：`gemini.google.com` 命中的 `🤖AI网站` 组当前选的是 **0.1 倍廉价中转**（美国08），该节点出口 IP 会漂移，且本机场大量 IP 被 Google 地理库判为 **香港**（`google.com → google.com.hk`）。Gemini 不支持香港 → 返回地区拦截页。
2. **为什么 Antigravity 正常**：它有一条进程级覆写 `PROCESS-PATH …/language_server → 🇺🇸美国圣何塞07｜三网推荐`，固定走 Google 判定为 US 的干净出口，与网页流量互不影响。
3. **为什么表现“偶发/顽固”**：
   - 出口 IP 漂移 → 命中受限 IP 时被拦，重拨换到干净 IP 就通；
   - Chrome 会缓存被拦页面 → 即使网络已恢复，普通窗口还显示旧拦截页（无痕/curl 正常）。

> 未能事后取证的部分：故障瞬间「美国08」的具体出口 IP 没有留存（连接已断开）。但两条旁证一致——①该机场多个出口实测被 Google 判为 HK；②切到 Google 判定为 US 的固定出口后立刻恢复。因此处置方向是**把 Gemini 网页固定到干净美国出口**，而不是继续依赖廉价中转。

---

## 解决方案

给 Gemini 网页加一条**域名级覆写规则**，固定到与 Antigravity 相同的干净美国出口（不动订阅自带规则、不动其它 AI 站点）：

```
DOMAIN,gemini.google.com,🇺🇸美国圣何塞07 | 三网推荐
```

| 项目 | 内容 |
| --- | --- |
| 生效位置 | 覆写规则最前面，排在订阅规则之前（`config.yaml` 第 1628 行；`/rules` 第 5 位） |
| 持久化 | 写入 FlClash 持久库 `database.sqlite` 的 `rules` 表（`id=1792832024816`，`rule_action=DOMAIN`，`content=gemini.google.com`，`order=0b`，profile `369768027173949440`） |
| 生效方式 | 先 `PUT /configs` 热重载；随后**完全退出并重启 FlClash 复验**：配置 17:00:09 由库重建，规则仍在 → 跨重启不丢 |
| 未改动 | 「🤖AI网站」组选择保持原样（🇺🇸美国08），ChatGPT/Claude 等不受影响；Antigravity 的 `PROCESS-PATH` 规则未动；系统代理状态未改（TUN 全量接管） |
| 备份 | `~/Desktop/gemini-check/backup-20261024-165335/`（config.yaml、database.sqlite、profile 三份） |
| 一键脚本 | [`scripts/gemini-web-egress-pin.sh`](../scripts/gemini-web-egress-pin.sh)：`check` / `apply` / `rollback`（幂等） |

### 关于「写库时机」的一次实测修正

既往记录（Qoder 轮次）提示“FlClash 运行中写库会在退出时被内存回写覆盖”。本次实测相反：

- 在 FlClash 运行中写入 `rules` 表 + 热重载 → 可用；
- 随后退出 FlClash（`osascript -e 'quit app "FlClash"'` 返回 `-128 用户已取消`，**但进程实际已退出**，数据库 mtime 未变、规则行仍在）；
- 重启 FlClash 后，`config.yaml` 于 17:00:09 重建，规则仍在且已生效。

→ 结论：**`rules` 表会在启动时被读取并合入配置，正常退出不会清空它**；旧结论中的“回写覆盖”更可能只针对 `selected_map` 这类 UI 会话态。仍建议改动前备份，并保留 rollback。

---

## 验证

1. **路由生效**（重启后）：

```bash
# /connections 最新连接
2026-10-24T17:00:29 -> ['🇺🇸美国圣何塞07 | 三网推荐']

# /rules 前 7 条
DomainSuffix qoder.sh → DIRECT
...
Domain gemini.google.com → 🇺🇸美国圣何塞07 | 三网推荐     ← 第 5 位
ProcessPath .../language_server → 🇺🇸美国圣何塞07 | 三网推荐
```

2. **页面恢复**：`curl https://gemini.google.com/app` → `200`、`808488` 字节、无 `not currently supported / stay tuned` 文案；Chrome 原窗口刷新后正常显示「认识 Gemini：你的私人 AI 助理」对话界面（`evidence-2-after-fixed.png`）。
3. **跨 FlClash 重启**：`database.sqlite` 规则行保留、`config.yaml` 重建后仍含该规则、TUN（`utun4`，`198.18.0.1/30`，规则模式）恢复、`🤖AI网站` 选择仍是原来的「美国08」。
4. **Antigravity 不受影响**：`language_server.log` 正常返回 `streamGenerateContent`；`/connections` 中其链路仍是圣何塞07。

---

## 回退

```bash
# 方式一：脚本
bash scripts/gemini-web-egress-pin.sh rollback

# 方式二：手工
sqlite3 ~/Library/Application\ Support/com.follow.clash/database.sqlite \
  "delete from rules where content='gemini.google.com' and rule_target='🇺🇸美国圣何塞07 | 三网推荐';"
# 再删掉 config.yaml 中 "DOMAIN,gemini.google.com,🇺🇸美国圣何塞07 | 三网推荐" 一行，然后热重载：
#   PUT /configs {"path":"~/Library/Application Support/com.follow.clash/config.yaml"}
```

或直接恢复 `backup-20261024-165335/` 中的 `database.sqlite` / `config.yaml`。

---

## 后续建议

1. **Gemini / ChatGPT 这类“地区敏感”服务不要用 0.1 倍 / 0.01 倍廉价中转**：出口 IP 共享、漂移，被判 HK/受限的概率高；本机场大量出口 Google 判为 HK（`google.com → google.com.hk`），属结构性问题。
2. 若圣何塞07 本身失效，可换 `🇺🇸美国洛杉矶08｜三网推荐`（`203.10.96.139`，US，本次实测 Gemini 首屏 2.46s，比圣何塞07 的 4.06s 更快）。
3. 复查顺序：先 **Cmd+Shift+R 强刷**（拦截页会被缓存），再查 `DOMAIN,gemini.google.com` 规则是否存在，再采样出口 IP 是否依旧是 US。
4. 采样小技巧：AI 分组路径可以用 `https://chatgpt.com/cdn-cgi/trace` 拿出口 IP（`chatgpt.com` 命中 `🤖AI网站`）；判断 Google 归属可用 `curl -s -o /dev/null -D - https://www.google.com/` 看是否 302 到 `google.com.hk`。

---

## 附录：本次关键命令速查

```bash
SEC=$(grep -m1 '^secret:' ~/Library/Application\ Support/com.follow.clash/config.yaml | sed 's/secret: *"\(.*\)"/\1/')
CTRL=http://127.0.0.1:9090

# 当前分组选择
curl -s -H "Authorization: Bearer $SEC" "$CTRL/proxies/%F0%9F%A4%96AI%E7%BD%91%E7%AB%99"

# 规则前 8 条
curl -s -H "Authorization: Bearer $SEC" "$CTRL/rules" | python3 -c 'import sys,json;[print(r["type"],r["payload"],"->",r["proxy"]) for r in json.load(sys.stdin)["rules"][:8]]'

# 实时连接（看规则与链路）
curl -s -H "Authorization: Bearer $SEC" "$CTRL/connections" | python3 -c 'import sys,json;[print(c["metadata"].get("host"),c.get("rule"),c.get("chains")) for c in json.load(sys.stdin)["connections"] if "gemini" in str(c["metadata"].get("host",""))]'

# 切节点
curl -s -X PUT -H "Authorization: Bearer $SEC" -H "Content-Type: application/json" \
  --data '{"name":"🇺🇸美国圣何塞07 | 三网推荐"}' "$CTRL/proxies/%F0%9F%A4%96AI%E7%BD%91%E7%AB%99"

# 热重载运行配置
curl -s -X PUT -H "Authorization: Bearer $SEC" -H "Content-Type: application/json" \
  --data "{\"path\":\"$HOME/Library/Application Support/com.follow.clash/config.yaml\"}" "$CTRL/configs"

# 出口采样
curl -s https://chatgpt.com/cdn-cgi/trace | grep -E '^(ip|loc)='
curl -s -o /dev/null -D - https://www.google.com/ | grep -i '^location:'
```
