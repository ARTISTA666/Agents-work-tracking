# Qoder 能打开但使用仍报网络问题：TUN(fake-ip) 全局接管下系统绕过列表失效，qoder 被送进代理节点被 TLS 重置，在 mihomo 规则置顶 DIRECT 后全通道恢复（第二轮，承接首轮绕过列表）

## 基本信息

- **处理者身份**：豆包办公 Agent（主排查、根因定位、最小修复；改动前均备份，保留回滚）
- **问题类型**：AI 客户端（Qoder 0.4.8，字节系 AI 编程 IDE）使用中网络故障；**TUN 模式下的 Clash 分流路由问题**（承接首轮 macOS 绕过列表修复）
- **首轮**：`records/2026-10-22-qoder-network-ssl-reset-direct-bypass.md`（四项自检全 network，加入系统代理绕过列表后应用能打开）
- **第二轮报错时间**：2026-10-22 11:35–12:10（Asia/Shanghai，UTC+8），会话日志 `20261022-031753.991-55509-6a923a72`
- **解决确认时间**：2026-10-22 12:12（新会话 `20261022-041017.111-68539-c7c57649`）
- **最终状态**：✅ 已解决。新会话 `getUserPlan` 200、RemoteControl 204、协作 REST 全 200、协作实时 wss `101` 建立，main.log 网络错误 0 条。
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 11:35 | 用户 | 反馈「能打开 Qoder 了，但使用还是显示有网络问题」 |
| 11:40–11:55 | 豆包 Agent | 读第二轮日志：模型通道 `ERR_CONNECTION_CLOSED`、协作 wss `ENOTFOUND`、team-profiles `CLOSED`；静态翻 app.asar/配置 JSON 未拿到真实主机 |
| 12:00 | 豆包 Agent | 发现 FlClash TUN（utun4=198.18.0.1）+ fake-ip（198.18.0.0/16）全局接管，系统绕过列表只影响 7890 入口，管不到 TUN 匹配 |
| 12:05 | 豆包 Agent | 经 mihomo 控制器 9090 做分出口延迟对照：DIRECT→qoder 77ms OK，代理节点→qoder 503 重置，代理→google 正常 |
| 12:09 | 豆包 Agent | 备份 config.yaml，规则置顶插入 3 条 `DOMAIN-SUFFIX,...,DIRECT`，PUT /configs force 热重载（204） |
| 12:10 | 豆包 Agent | 重启 Qoder，新会话全通道 200/101，网络错误 0 |
| 12:12 后 | 豆包 Agent | 固化应用/回滚脚本，写本轮记录并推送仓库、更新索引 |

---

## 问题详细描述

首轮把 `*.qoder.sh / qoder.sh / *.qoder.com / qoder.com` 加入 macOS Wi-Fi 代理绕过列表后，Qoder 自检通过、应用能打开、更新检查成功；但**实际发消息/使用时仍报网络问题**。第二轮会话日志关键错误：

- ChatSession 投递失败 `QODER_EXECUTION_CONTROL_FAILED`，failureDetail `The connection to the model service was interrupted`
- `QoderRemoteControl` workerStream 反复 `ERR_CONNECTION_CLOSED`（failuresByCode 4→13）
- `[Auth] account.getUserPlan host=openapi.qoder.sh` 先 `ERR_INTERNET_DISCONNECTED`，后 `ERR_CONNECTION_CLOSED`（434ms）
- collaboration.log：`GET /api/v1/collaboration/team-profiles` → `net::ERR_CONNECTION_CLOSED`；协作实时 wss `/api/v1/collaboration/connections`（protocol `qoder.collaboration.mux.v1`）→ `ENOTFOUND`，重试 40+ 次
- Telemetry 连续失败 30+ 次，accepted:0，队列积压

环境同上轮：macOS Apple Silicon，Wi-Fi en0，FlClash 系统代理 127.0.0.1:7890，Qoder 0.4.8（首轮 0.4.4 已自动升级）。

---

## 排查过程与关键技术证据

### 1. 静态取证先走到死路

- 翻 `qoder-data.v1.json / qoder-data.v1.ext.json`：无任何 URL（运行时下发端点）。
- grep app.asar：只得到文档库引用与少量静态域名；日志只打印 `endpointFingerprint`（哈希），不打印 host。
- 列实时连接：空闲时无外部 ESTABLISHED，抓不到对端。

### 2. 关键发现：TUN + fake-ip 全局接管，系统绕过列表只作用于 7890 入口

```bash
ifconfig | grep -A2 utun4          # utun4 inet 198.18.0.1 --> 198.18.0.1（TUN 开启）
dscacheutil -q host -a name openapi.qoder.sh   # 全部返回 198.18.0.x（Clash fake-ip 池）
nslookup openapi.qoder.sh 223.5.5.5           # 仍被劫持返回 198.18.0.20，拿不到真实 IP
```

- FlClashCore（mihomo）以 **TUN 模式**运行（utun4，fake-ip `198.18.0.0/16`，enhanced-mode fake-ip），**所有流量都进内核按规则匹配**。
- macOS 系统代理绕过列表（首轮改动）只决定 Electron 是否经 7890 发 HTTP CONNECT；**被 TUN 捕获的原始流量仍由 mihomo 规则决定出口**。所以首轮绕过列表对 TUN 匹配到代理节点的 qoder 流量无效——这是「能打开（短请求/更新检查恰好通过）但使用（长连接/模型流）失败」的原因。
- 此刻所有 qoder 主机无论 `--noproxy '*'`（TUN）还是 `-x 7890`，都在 TLS 握手被 `SSL_ERROR_SYSCALL` 重置；而 `google.com` 经代理 200。

### 3. mihomo 控制器分出口对照实验（定位真根因）

FlClash 运行时配置 `~/Library/Application Support/com.follow.clash/config.yaml`，external-controller `127.0.0.1:9090`（secret 从配置读取，不落盘到仓库）。通过 `/proxies/{name}/delay?url=...` 让内核经指定出口探测：

| 出口 | 访问 qoder（openapi.qoder.sh） | 访问 google generate_204 |
| --- | --- | --- |
| **DIRECT** | ✅ OK 77–79ms | ❌ 超时（直连本就到不了 google，符合预期） |
| 🤖AI网站 组 | ❌ 503 delay test 失败（节点重置） | ✅ 158ms |
| 🚀节点选择 / 🇺🇸美国节点 | ❌ 503（节点重置） | ✅ 163–171ms |

> 说明：`/proxies/{group}/delay` 是**强制经该出口**探测、不经过路由规则，所以它失败不代表真实流量；真实流量由规则匹配。该实验证明「DIRECT 到 qoder 通、代理节点到 qoder 被重置」。

结论：**qoder 域名无专属规则，落到兜底/AI 组被送进代理节点（美国），节点在 TLS 握手重置；DIRECT 直达阿里云后端正常。** 修复点在 mihomo 规则把 qoder 强制 DIRECT，而不是系统绕过列表。

### 4. 排除项

| 假设 | 核对 |
| --- | --- |
| 断网 / 普通代理坏 | google 经代理 200，排除 |
| DNS 污染 | 是 fake-ip 劫持，非污染；DIRECT 探测即通，排除 |
| 服务端宕机 | DIRECT 77ms 拿到响应，排除 |
| 账号未登录 | 修复后 `getUserPlan` 返回 `personal_standard` 已登录；首轮误判的 QCS_ACCOUNT_CHANGED 是启动竞态，排除 |
| 应用 bug | 换出口即全通，排除 |

---

## 根因分析

1. **直接原因**：qoder 域名被 Clash 规则送进代理节点，节点对这批阿里云海外 SNI 的 TLS 握手 RST；DIRECT 直达正常。
2. **深层原因**：TUN/fake-ip 模式下，路由决定权在 mihomo 规则，不在 macOS 系统代理绕过列表；首轮只改绕过列表，对 TUN 流量不生效。
3. **为什么「能打开却用不了」**：应用启动阶段的短请求（更新检查、静态资源）恰好通过或走缓存，进入实际模型流/协作长连接时走被重置的节点，表现为「使用中网络问题」。
4. 备注：`openapi.qoder.com`、`gateway.qoder.com` 实测秒级本地拒绝（非生产预留域名，客户端不调用）；生产主站是 `openapi.qoder.sh`。

---

## 解决方案与落地操作

思路：**在 mihomo 规则最顶部把 qoder 三个后缀强制 DIRECT**，其余流量规则不变。改动前备份 config.yaml。

### 步骤 1：备份

```bash
TS=$(date +%Y%m%d-%H%M%S)
cp ~/Library/Application\ Support/com.follow.clash/config.yaml \
   <备份目录>/clash-$TS/config.yaml.bak
```

### 步骤 2：规则置顶插入三条 DIRECT（幂等）

在 `rules:` 后、所有既有规则之前插入：

```yaml
rules:
  - "DOMAIN-SUFFIX,qoder.sh,DIRECT"
  - "DOMAIN-SUFFIX,qoder.com,DIRECT"
  - "DOMAIN-SUFFIX,qoder.ai,DIRECT"
  # ...原有规则
```

仓库脚本 `scripts/qoder-clash-direct.sh`：自动备份、幂等去重、从 config.yaml 读 secret、热重载。

### 步骤 3：热重载（不重启 FlClash）

```bash
SECRET=$(grep '^secret:' config.yaml | sed -E 's/.*"?([^"]+)"?.*/\1/')
curl -X PUT -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
  -d '{"path":"<config.yaml 绝对路径>","force":true}' http://127.0.0.1:9090/configs
# 返回 HTTP 204 即重载成功
```

### 步骤 4：重启 Qoder 清掉积压失败状态

```bash
osascript -e 'tell application "Qoder" to quit'; sleep 4; open -a Qoder
```

### 回滚

- 移除规则并热重载：`scripts/qoder-clash-rollback.sh`
- 整体还原：用 `backup/clash-*/config.yaml.bak` 覆盖 config.yaml 后再 PUT /configs force 重载。
- 首轮 macOS 绕过列表保留无害（冗余），如需还原见首轮 `scripts/qoder-rollback-bypass.sh`。

### 持久化注意（重要）

`config.yaml` 是订阅合并出的**运行时产物**，订阅更新/FlClash 重启后可能被重新生成、清掉置顶规则。复发时二选一：
1. 重跑 `scripts/qoder-clash-direct.sh`；
2. 在 FlClash「自定义规则/Override」里把上述三条置顶（跨更新保留）。

---

## 验证与效果（新会话 20261022-041017）

| 验证项 | 结果 | 状态 |
| --- | --- | --- |
| 规则置顶生效 | GET /rules 前三条 = qoder.sh/.com/.ai → DIRECT | ✅ |
| openapi.qoder.sh 经 7890 | 404/0.21s（根路径正常响应，代表可达） | ✅ |
| account.getUserPlan | status 200，personal_standard，373ms | ✅ |
| RemoteControl 账号状态 | status 204 已开启 | ✅ |
| 协作 team-profiles / agent-profiles / memberships | httpStatus 200 result success | ✅ |
| 协作实时 wss | httpStatus 101，「协作实时连接已建立」mux.v2 | ✅ |
| main.log 网络错误计数 | 0（CLOSED/ENOTFOUND/interrupted/EXECUTION_CONTROL_FAILED） | ✅ |
| 代理访问 google | 200，未影响其他流量 | ✅ |

---

## 经验沉淀

1. **TUN/fake-ip 模式下，先分清「系统代理绕过」和「内核规则出口」**：绕过列表只管 HTTP 代理入口，TUN 捕获的流量由 mihomo 规则决定；改了绕过列表不生效时，要去内核规则里强制 DIRECT。
2. **用控制器 `/proxies/{name}/delay` 分出口对照**，一步区分「DIRECT 通、节点重置」还是「都不通」，比静态翻包高效。
3. **`/proxies/{group}/delay` 强制走指定出口、不过路由规则**，它失败不等于真实流量失败；真实连通以经 7890/TUN 的 curl 与应用日志为准。
4. **运行时合并配置会被订阅更新覆盖**，自定义规则优先放客户端 Override 区，或留一个幂等重放脚本。
5. 启动瞬间的 `QODER_APP_QCS_ACCOUNT_CHANGED`、marketplace governance 告警是竞态/配置，不是网络故障，勿误判。

---

## 关键产物与现场位置（不含密钥）

- mihomo 运行时配置：`~/Library/Application Support/com.follow.clash/config.yaml`（external-controller 127.0.0.1:9090，secret 仅本地读取）
- 订阅源 profile：`~/Library/Application Support/com.follow.clash/profiles/*.yaml`（无 qoder 规则）
- Qoder 日志：`~/Library/Application Support/com.qoder.app.stable/logs/<session>/{main.log,collaboration.log}`
- 生产主站：`https://openapi.qoder.sh`（阿里云 SG/HK，aliyunga0019.com）
- 仓库脚本：
  - `scripts/qoder-clash-direct.sh`：置顶 qoder DIRECT 规则 + 备份 + 热重载（幂等）
  - `scripts/qoder-clash-rollback.sh`：移除规则 + 热重载
  - 首轮：`scripts/qoder-add-bypass.sh` / `qoder-rollback-bypass.sh`（系统绕过列表，冗余保留）

*第二轮结论：TUN 全局接管下权威修复在 mihomo 规则 DIRECT，而非 macOS 绕过列表；首轮绕过列表为冗余保留。*