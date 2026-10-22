# Qoder 第二轮直连规则被 FlClash 重建清空导致复发：运行时 config.yaml 不可持久，把 qoder DIRECT 写入 FlClash 持久库 database.sqlite 的 rules 表，重启后规则置顶且不丢（第三轮，根治）

## 基本信息

- **处理者身份**：豆包办公 Agent（主排查、根因定位、最小修复；改动前均备份，保留回滚）
- **问题类型**：AI 客户端（Qoder 0.4.8）使用中网络故障复发；**FlClash 持久化层缺失导致的分流规则丢失**
- **承接**：首轮 `2026-10-22-qoder-network-ssl-reset-direct-bypass.md`（系统绕过列表）；第二轮 `2026-10-22-qoder-clash-direct-routing.md`（运行时 config.yaml 置顶 DIRECT + 热重载）
- **第三轮报错时间**：2026-10-22 15:00–15:10（Asia/Shanghai，UTC+8），用户截图弹窗「系统发生异常，请重试」
- **最终状态**：路由层已根治并持久化。新会话控制面全绿、致命网络错误 0、qoder 全主机 DIRECT；模型真实对话轮次需用户发一条消息做最终确认（见文末验证表备注）。
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 15:00 | 用户 | 反馈「还是没有解决」，附「系统发生异常，请重试」弹窗截图 |
| 15:02 | 豆包 Agent | 抓最新会话日志：`QODER_EXECUTION_CONTROL_FAILED`、`connection to the model service interrupted`、RemoteControl `ERR_CONNECTION_CLOSED:12`、QCS `NETWORK_ERROR` |
| 15:03 | 豆包 Agent | 实时 `/connections` 发现 `openapi.qoder.sh`、`api2.qoder.sh` 走 `rule Match`→代理节点（日本06/新加坡02→漏网之鱼），而非第二轮的 DIRECT |
| 15:05 | 豆包 Agent | 核对运行时 config.yaml 与实时 `/rules`：**qoder 三条规则全部消失**，首条变回 Antigravity ProcessPath。证实第二轮改动被 FlClash 重建清空 |
| 15:07 | 豆包 Agent | 备份 database.sqlite + config.yaml；定位持久层 `rules` 表 |
| 15:08 | 豆包 Agent | 退出 FlClash 离线写库：`DOMAIN_SUFFIX qoder.sh/.com/.ai → DIRECT`，重启后 `/rules` 第 0–2 位命中 |
| 15:09 | 豆包 Agent | 重启 Qoder：RemoteControl 204、QCS fetch 200、SSE connected、致命错误 0、全 qoder 主机 DIRECT |

---

## 问题详细描述

第二轮把 `DOMAIN-SUFFIX,qoder.sh/.com/.ai,DIRECT` 直接插入运行时 `config.yaml` 顶部并 PUT /configs 热重载，当时全通道 200/101。但第三轮用户再次使用仍弹「系统发生异常，请重试」。第三轮最新失败会话 `20261022-041017.111-68539-c7c57649`（07:03Z 仍失败）关键错误：

- `QODER_EXECUTION_CONTROL_FAILED`，failureDetail `API Error: The connection to the model service was interrupted. Please try again.`
- `QoderRemoteControl` failuresByCode `ERR_CONNECTION_CLOSED:12`
- DesktopUpdate `fetch failed: Client network socket disconnected before secure TLS`
- `QODER_APP_QCS_NETWORK_ERROR`（stage resolve）

---

## 排查过程与关键技术证据

### 1. 实时连接证明：qoder 又被送进代理节点

```
GET /connections
openapi.qoder.sh | dst 47.57.243.249 | chain [🇯🇵AWS日本06, ♻️自动选择, 🚀节点选择, 🐟漏网之鱼] | rule Match
api2.qoder.sh    | dst 8.223.13.163  | chain [🇸🇬AWS新加坡02, ..., 🐟漏网之鱼]        | rule Match
```

两条都落兜底 `Match` 进代理节点，而第二轮置顶的 DIRECT 规则没有命中。代理节点对 qoder 阿里云海外 SNI 的 TLS 握手重置（第二轮已实测：DIRECT 77–79ms OK，代理节点 503/重置，代理→google 200）。

### 2. 复发根因：运行时 config.yaml 是订阅合并产物，被 FlClash 重建清空

```bash
# 文件内 grep 与实时 /rules 都查不到 qoder
grep qoder ~/Library/Application\ Support/com.follow.clash/config.yaml   # 空
curl .../rules | grep qoder                                              # 空，首条变回 Antigravity ProcessPath
```

- FlClash 每次启动/订阅刷新/内部重载都会从订阅源 + 自身持久库**重新合并生成** `config.yaml`；第二轮用 awk 写进运行时文件的规则不在持久层，重建时被丢弃。
- 第二轮记录里「已解决」只在当时热重载内存里成立，未跨重建保留——该结论本轮被证伪，特此修正。

### 3. 定位持久层：database.sqlite 的 rules 表

FlClash 数据目录 `~/Library/Application Support/com.follow.clash/`，用户自定义规则存于 `database.sqlite` 的 `rules` 表（不是运行时 config.yaml）。表结构：

```sql
CREATE TABLE rules (
  id INTEGER PRIMARY KEY,
  profile_id INTEGER REFERENCES profiles(id) ON DELETE CASCADE,
  rule_action TEXT NOT NULL,      -- DOMAIN_SUFFIX / PROCESS_PATH 等（下划线枚举）
  content TEXT,                   -- 匹配值（后缀/路径）
  rule_target TEXT,               -- DIRECT 或代理组/节点名
  rule_provider TEXT, sub_rule TEXT,
  no_resolve INTEGER DEFAULT 0,
  src INTEGER DEFAULT 0,
  "order" TEXT                    -- 排序键，小者靠前
);
```

现有样例为一条 `PROCESS_PATH ... → 🇺🇸美国圣何塞07`。实证：写入 `rule_action=DOMAIN_SUFFIX` 后，重启加载为 mihomo 的 `DomainSuffix`（DB 用下划线枚举，构建时转 Clash 原生格式）。

### 4. 离线写库（避免内存回写覆盖）

FlClash 运行时把 rules 缓存在内存，直接改库可能被退出时的内存回写覆盖。故：先优雅退出 FlClash（必要时兜底 pkill），确认无进程后再写 sqlite，最后 `open -a FlClash` 重启。

---

## 根因分析

| 层级 | 归因 |
| --- | --- |
| 直接原因 | qoder 无持久 DIRECT 规则，落兜底 Match 进代理节点，TLS 握手被重置 |
| 复发原因 | 第二轮改的是运行时 config.yaml（订阅合并产物），FlClash 重建即清空 |
| 深层原因 | 自定义分流必须写 FlClash 持久层（rules 表 / GUI 自定义规则），运行时合并文件不可作为持久位置 |
| 为什么能短暂工作 | PUT /configs force 只改内存与当前文件，重建后失效 |

---

## 解决方案与落地操作

把 qoder 三条后缀写入持久库 `rules` 表，重启 FlClash 后由客户端自己构建进配置，跨重启/订阅更新/重建不丢。

### 备份（改动前必做）

```bash
D=~/Library/Application\ Support/com.follow.clash
BK=backup/db-$(date +%Y%m%d-%H%M%S); mkdir -p "$BK"
cp "$D/database.sqlite" "$BK/database.sqlite.bak"
cp "$D/config.yaml"     "$BK/config.yaml.bak"
```

### 离线写库（退出 FlClash 后）

```sql
DELETE FROM rules WHERE content IN ('qoder.sh','qoder.com','qoder.ai');
INSERT INTO rules (id,profile_id,rule_action,content,rule_target,rule_provider,sub_rule,no_resolve,src,"order")
SELECT <id>, p.id, 'DOMAIN_SUFFIX', s.dom, 'DIRECT', NULL, NULL, 0, 0, s.ord
FROM profiles p
CROSS JOIN (SELECT 'qoder.sh' dom,'00' ord UNION ALL
            SELECT 'qoder.com','01' UNION ALL
            SELECT 'qoder.ai','02') s;
```

- 为**每个 profile** 都插入，避免切换订阅后失效。
- `order` 用 `00/01/02`，排在既有自定义规则之前。
- secret 不入库，重启后从重建的 config.yaml 运行时读取。

仓库脚本：

- `scripts/qoder-flclash-persist.sh`：备份 DB → 退出 FlClash → 幂等清旧插新 → 重启 → `/rules` 校验 qoder DIRECT
- `scripts/qoder-flclash-persist-rollback.sh`：备份 → 退出 → 删除 qoder 规则 → 重启 → 校验为 0；彻底还原可直接用 `backup/db-*/database.sqlite.bak` 覆盖

### 回滚

1. 运行 `scripts/qoder-flclash-persist-rollback.sh`（删除 DB 内 qoder 规则并重启）；
2. 或用改动前 `backup/db-<时间戳>/database.sqlite.bak` 覆盖回库后重启 FlClash；
3. 首轮系统绕过列表、第二轮运行时热重载均为冗余，保留无害。

---

## 验证与效果（新会话 20261022-070859.510-2778-20682846）

| 验证项 | 结果 | 状态 |
| --- | --- | --- |
| `/rules` 第 0–2 位 | `DomainSuffix qoder.sh/.com/.ai → DIRECT`，qoder.sh hitCount=52 | ✅ |
| 重启 FlClash 后规则仍在 | 在（持久层，非运行时文件） | ✅ |
| openapi/api2/api3/center.qoder.sh 经 7890 | 均 404 / 149–195ms（根路径正常响应=可达） | ✅ |
| `/connections` 出口 | openapi/api2/api3/center 全 `DIRECT`，无 Match→代理 | ✅ |
| RemoteControl 账号状态 | 204 已开启，117ms | ✅ |
| QCS resolve / SSE | fetch 200（292ms）、SSE connected | ✅ |
| daemon / 插件 | generation committed，host-api failedCount 0 | ✅ |
| 致命错误（CLOSED/EXECUTION_CONTROL_FAILED/interrupted/socket disconnected） | 全日志 0 | ✅ |
| 其他流量 | google 等仍走代理，未受影响 | ✅ |
| **真实模型对话轮次** | 需用户在 Qoder 发一条消息验收（控制面/路由已通，见备注） | ⏳ 待用户实发 |

> 备注：Qoder 聊天输入框为自定义 web 编辑器，AX 读不到，无法由 Agent 自动发消息；控制面、路由、SSE 已全绿，最终以用户实发一条消息能收到回复为准。若仍报错，按最新 main.log 的失败主机补后缀即可。

---

## 经验沉淀

1. **运行时合并配置（config.yaml）不是持久层**：Clash/FlClash 类客户端会从订阅+持久库重建，手写进运行时文件的规则重启/刷新即丢；自定义规则必须放客户端持久层（rules 表 / GUI 自定义规则 / Override）。
2. **改客户端 sqlite 要先退出再写**：运行中内存会回写覆盖离线修改；退出→写库→重启最稳。
3. **DB 枚举与内核格式不同**：FlClash DB 存 `DOMAIN_SUFFIX`（下划线），构建后变 mihomo `DomainSuffix`；写入后用 `/rules` 实证，不靠猜。
4. **复发先核对「规则还在不在」**：第二次失败先查文件与 `/rules`，直接定位到规则被清空，而非重新排查连通性。
5. 冷启动瞬间的 QCS resolve 失败、ACCOUNT_CHANGED、marketplace 告警是竞态，通常数秒后自愈，不计入网络故障。

---

## 关键产物与现场位置（不含密钥）

- 持久库：`~/Library/Application Support/com.follow.clash/database.sqlite`（`rules` 表）
- 运行时配置（会被重建，勿手改持久化）：`~/Library/Application Support/com.follow.clash/config.yaml`，controller 127.0.0.1:9090，secret 仅本地读取
- Qoder 日志：`~/Library/Application Support/com.qoder.app.stable/logs/<session>/{main.log,collaboration.log}`
- 生产主机：`openapi/api2/api3/center.qoder.sh`（阿里云海外，DIRECT 可达）
- 仓库脚本：`scripts/qoder-flclash-persist.sh` / `qoder-flclash-persist-rollback.sh`
