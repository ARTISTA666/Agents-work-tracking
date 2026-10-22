# Qoder 启动自检四项全 `network` 失败：阿里云海外后端直连正常、走 FlClash 代理被 TLS 重置，加入系统代理绕过列表走直连后恢复

## 基本信息

- **处理者身份**：豆包办公 Agent（本次会话 AI 协作代理，主排查、根因定位与最小修复；全程先备份原始状态再改动，保留回滚）
- **问题类型**：AI 客户端（Qoder，字节系 AI 编程 IDE）网络连通性故障；系统代理分流问题（非断网、非 DNS 污染、非服务端宕机、非账号问题）
- **报错时间**：2026-10-22 11:06（Asia/Shanghai，UTC+8，诊断日志 `startedAt 03:06:12Z`）
- **解决确认时间**：2026-10-22 11:15（Asia/Shanghai，UTC+8）
- **最终状态**：✅ 已解决。Qoder 后端改走直连后，新日志网络错误 0 条，`center.qoder.sh` 更新检查成功（`release-verified → ready`）；其余流量仍正常走 FlClash 代理。残留的 `QODER_APP_QCS_ACCOUNT_CHANGED` 为未登录状态，与网络无关。
- **关联项目/仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)
- **与既有记录关系**：与 `2026-09-04-flclash-not-running-dns-pollution-macos-network-troubleshooting.md` 同属「代理/网络层故障」，但那次是「客户端根本没运行 + DNS 污染」，本次是「客户端正常运行、普通站点代理正常，仅 Qoder 域名这条代理路由被重置」，属于**分流/路由**问题而非客户端故障。

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 11:06 | 用户 | 提供 Qoder 自检 JSON：`foundation / model / messaging / resources` 四项全 `failed`，`errorCode: network`，整体 637ms 快速失败，问「链接不上，看看什么原因」 |
| 11:12 | 豆包 Agent | 只读采集：系统代理、DNS、端口、进程；把原始状态快照与 FlClash 配置备份到本地 `qoder-network-fix/backup/` |
| 11:12–11:13 | 豆包 Agent | 直连 vs 走 7890 代理对照实测，定位「直连全通、代理被重置」；读 Qoder 日志确认失败端点 |
| 11:14 | 豆包 Agent | 最小改动：把 Qoder 域名加入 macOS Wi-Fi 代理绕过列表（未关代理、未改 FlClash、未改 DNS） |
| 11:14–11:15 | 豆包 Agent | 优雅退出并重启 Qoder，新日志网络错误归零；普通站点经代理仍 200；写回滚脚本与记录 |
| 11:20 后 | 豆包 Agent | 按本仓库范式归档记录、推送脚本、更新 README 索引 |

---

## 问题详细描述

用户在 macOS 上打开 Qoder（`/Applications/Qoder.app`，版本 0.4.4），内置连通性自检返回：

```json
{
  "startedAt": "2026-10-22T03:06:12.546Z",
  "durationMs": 637,
  "success": false,
  "services": [
    { "id": "foundation",  "status": "failed", "durationMs": 352, "errorCode": "network" },
    { "id": "model",      "status": "failed", "durationMs": 348, "errorCode": "network" },
    { "id": "messaging",  "status": "failed", "durationMs": 348, "errorCode": "network" },
    { "id": "resources",  "status": "failed", "durationMs": 635, "errorCode": "network" }
  ]
}
```

四个服务都在约 350–635ms 内快速失败。环境：

- macOS（Apple Silicon），活跃网络服务 Wi-Fi（`en0`，`192.168.110.14`）
- 代理客户端 **FlClash** 在运行，系统代理 HTTP/HTTPS/SOCKS 全部指向 `127.0.0.1:7890`
- 系统 DNS：`8.8.8.8` + `223.5.5.5`
- Qoder 无内置代理设置，完全跟随系统代理（Electron/Chromium 网络栈，报错为 `net::` 前缀）

---

## 排查过程与关键技术证据

### 1. 系统代理与端口取证

```bash
scutil --proxy                       # 系统代理
networksetup -getwebproxy Wi-Fi      # HTTP 代理 127.0.0.1:7890 启用
networksetup -getsecurewebproxy Wi-Fi
networksetup -getsocksfirewallproxy Wi-Fi
lsof -nP -iTCP:7890 -sTCP:LISTEN    # root 进程持有，普通用户 lsof 看不到
nc -z 127.0.0.1 7890                # 端口可连接
ps aux | grep -iE 'clash|flclash|mihomo'
```

证据：FlClash 进程在运行（`FlClash` + root `FlClashCore`），`7890` 可连接，系统代理三处（HTTP/HTTPS/SOCKS）都指向 `127.0.0.1:7890`。排除「代理客户端没启动」（对照 2026-09-04 记录）。

### 2. DNS 解析正常，排除 DNS 污染

```bash
dscacheutil -q host -a name openapi.qoder.sh
# openapi.qoder.sh → ga-bp1ffcpb88nkvl9saz78t.aliyunga0019.com
#   8.212.124.35 / 47.57.243.249
dscacheutil -q host -a name api2.qoder.sh
#   8.223.13.163 / 47.57.188.188
dscacheutil -q host -a name api.qoder.com
#   8.223.24.252 / 8.223.26.226（aliyunga0019.com CNAME）
```

域名都能正常解析到阿里云海外 IP（新加坡 `8.212/8.223`、香港 `47.57` 段），无 NXDOMAIN、无污染 IP。排除 DNS 问题。

### 3. 关键对照实验：直连 vs 走代理（定位根因）

```bash
# 直连（绕过系统代理）
curl -sS --noproxy '*' --max-time 8 -o /dev/null -w '%{http_code} %{time_total}s\n' \
  https://openapi.qoder.sh/api/v1/deviceToken/poll
# 走本机代理
curl -sS -x http://127.0.0.1:7890 --max-time 8 -o /dev/null -w '%{http_code} %{time_total}s\n' \
  https://openapi.qoder.sh/api/v1/deviceToken/poll
```

实测结果（同一时刻）：

| 目标 | 直连（`--noproxy '*'`） | 走 `127.0.0.1:7890` |
| --- | --- | --- |
| `openapi.qoder.sh/api/v1/deviceToken/poll` | HTTP 400，0.21s 通 | `SSL_ERROR_SYSCALL`，连接被重置 |
| `api2.qoder.sh/otel/v1/logs` | HTTP 405，0.18s 通 | `SSL_ERROR_SYSCALL`，重置 |
| `center.qoder.sh/algo/api/update/...` | HTTP 200，0.18s 通 | `SSL_ERROR_SYSCALL`，重置 |
| `api.qoder.com` | HTTP 401，0.05s 通 | `SSL_ERROR_SYSCALL`，重置 |
| `qoder.com` | HTTP 200，0.39s 通 | `SSL_ERROR_SYSCALL`，重置 |
| 普通站点 `google.com`（经代理） | — | HTTP 200，1.0s 通 |
| `api.ipify.org`（经代理） | — | 正常返回出口 IP `134.195.101.120` |

结论：**代理本身活着、普通站点正常；唯独 Qoder 域名经代理时 TLS 握手被立即重置**（~0.2–0.47s 快速失败，与自检 350ms 失败吻合）。直连这些阿里云海外节点全部可达。

### 4. 从 Qoder 日志确认失败端点与错误形态

日志目录 `~/Library/Application Support/com.qoder.app.stable/logs/<session>/main.log`：

```
[Auth] Device login poll request failed host=openapi.qoder.sh
  path=/api/v1/deviceToken/poll durationMs=347
  error: net::ERR_CONNECTION_CLOSED   (连续 5 次，330ms 左右)
[Auth] Device login failed code=AUTH_NETWORK retryable=true
[DesktopUpdate] Background Desktop update check failed
  error: TypeError: fetch failed
[DesktopUpdate] reason=assignment-check-failed
```

- 错误是 Chromium 网络栈的 `net::ERR_CONNECTION_CLOSED`（TLS 对端关闭/重置），不是 401/403/404 等业务层状态码；
- `center.qoder.sh` 更新检查在修复前是 `fetch failed`；
- Qoder 无内置 proxy 字段（`Preferences`、`qoder-data.v1.json` 均无 proxy 配置），完全吃系统代理。

### 5. 排除项核对

| 假设 | 核对结果 |
| --- | --- |
| 断网 / 宽带不通 | 直连 Qoder 后端 200/400/405，普通站点正常，排除 |
| DNS 污染 / 解析失败 | 解析到正确阿里云海外 IP，排除 |
| FlClash 没启动 / 端口没监听 | 进程在、7890 可连、普通站点经代理 200，排除 |
| Qoder 服务端宕机 | 直连即返回正常业务状态码（200/400/405/401），排除 |
| 账号 / 登录态错误 | 网络层连接都没建立，先于账号层；残留报错为账号态（见下），排除 |
| Qoder 自身 bug | 直连即通、换路由即恢复，排除 |

---

## 根因分析

### 1. 直接原因

Qoder 后端托管在阿里云海外节点（`*.qoder.sh`、`*.qoder.com`，CNAME 到 `*.aliyunga0019.com`，新加坡/香港 IP）。本机直连可达，但 FlClash 按通用规则把这些域名送进代理节点后，**TLS 握手被对端立即重置**（`SSL_ERROR_SYSCALL` / `net::ERR_CONNECTION_CLOSED`），Electron 拿不到任何业务响应，自检四项全部判为 `network` 失败。

### 2. 深层原因：分流路由问题，而非代理故障

- FlClash 订阅配置里**没有针对 qoder 的专属规则**（`grep -i qoder config.yaml` 无命中），Qoder 域名落到通用规则/`MATCH` 进入代理组；
- 当前选中节点对这批阿里云海外 SNI 的连接被重置（可能是节点路由对该段目标干扰、或 SNI 被中间设备 RST），但该节点访问 Google 等普通站点正常；
- 因此表象是「Qoder 连不上」，实质是「**这几个域名不该走代理，应直连**」。

### 3. 为什么快速失败（350ms 级）

TLS 握手阶段就被 RST 关闭，没有等待超时，所以四项都在几百毫秒内失败，而不是等到 connect timeout。这也是 `errorCode=network` 而非 `timeout` 的原因。

### 4. 与本仓库既有「代理故障」记录的区别

| 维度 | 2026-09-04 FlClash 未运行 + DNS 污染 | 本次（2026-10-22 Qoder） |
| --- | --- | --- |
| 代理客户端 | 根本没运行、7890 空 | 运行中、7890 可连、普通站点正常 |
| DNS | 8.8.8.8 被污染注入 | 解析正常 |
| 故障层面 | 网络前置（客户端/DNS） | 单域名分流路由（代理节点重置该 SNI） |
| 修复方向 | 启动客户端 + 改国内 DNS | 该域名直连（加入绕过列表），不动客户端 |

---

## 解决方案与落地操作

思路：**让 Qoder 域名绕过系统代理走直连，其余流量保持走代理**。最小改动，不关闭代理、不改 FlClash 订阅/节点/规则、不改 DNS。

### 步骤 1：先备份原始状态（可回滚前提）

```bash
# 保存系统代理/绕过列表/DNS 快照与 FlClash 配置副本
scutil --proxy > system-proxy.txt
networksetup -getproxybypassdomains Wi-Fi >> system-proxy.txt
cp ~/Library/Application\ Support/com.follow.clash/config.yaml flclash-config.yaml.bak
```

### 步骤 2：把 Qoder 域名加入 Wi-Fi 代理绕过列表

```bash
# 保留原有全部条目，追加 4 条（幂等，重复执行不重复添加）
networksetup -setproxybypassdomains Wi-Fi \
  "*zhihu.com" "*zhimg.com" "*jd.com" "100ime-iat-api.xfyun.cn" "*360buyimg.com" \
  "localhost" "*.local" "127.*" "10.*" "172.16.*" "172.17.*" "172.18.*" "172.19.*" \
  "172.2*" "172.30.*" "172.31.*" "192.168.*" \
  "*.qoder.sh" "qoder.sh" "*.qoder.com" "qoder.com"
```

仓库脚本：`scripts/qoder-add-bypass.sh`（自动读取现有列表并去重追加，兼容 macOS bash 3.2）。

### 步骤 3：重启 Qoder 让新代理规则生效

```bash
osascript -e 'tell application "Qoder" to quit'; sleep 3; open -a Qoder
```

Electron 启动时读取系统代理；长连接需重启才会用新路由。

### 步骤 4（可选替代）：在 FlClash 里给 qoder 设 DIRECT

等价做法：在 FlClash 规则最前面加

```yaml
rules:
  - DOMAIN-SUFFIX,qoder.sh,DIRECT
  - DOMAIN-SUFFIX,qoder.com,DIRECT
  # ...原有规则
```

本次选系统绕过列表，是因为它不依赖订阅更新、不会被覆盖、且只影响本机这台设备；缺点是换网络服务（以太网/热点）需对该服务再执行一次。

---

## 验证与效果

| 验证项 | 验证命令 / 方式 | 实际结果 | 状态 |
| --- | --- | --- | --- |
| 绕过列表生效 | `scutil --proxy \| grep qoder` | ExceptionsList 含 `*.qoder.sh/qoder.sh/*.qoder.com/qoder.com` | ✅ |
| 直连后端可达 | `curl --noproxy '*'` 测三个端点 | 400 / 405 / 200，0.2s 级 | ✅ |
| 重启后新日志网络错误 | grep `ERR_CONNECTION_CLOSED/AUTH_NETWORK/fetch failed/SSL_ERROR/ECONNRESET` | **0 条**，renderer.log 干净 | ✅ |
| 更新检查成功 | 新日志 `DesktopUpdate` | `release-verified → ready`，`targetVersion 0.4.8`（修复前 fetch failed） | ✅ |
| telemetry 端点 | `api2.qoder.sh/otel/v1/logs` | 初始化无报错 | ✅ |
| 普通站点仍走代理 | `curl -x 127.0.0.1:7890 https://google.com` | HTTP 200；出口 IP 正常轮换 | ✅ |
| 未影响其他应用 | 代理全局开关保持开启 | 仅 4 条 qoder 域名改直连 | ✅ |

残留告警（非网络）：`QODER_APP_QCS_ACCOUNT_CHANGED`、市场预装对账失败、全局文案同步失败——均为**未登录/无活动账号**状态，完成设备扫码登录后消失。

---

## 经验沉淀与后续建议

1. **「某客户端连不上」先做直连/代理对照，别急着换节点或重装**。`curl --noproxy '*'`（直连）与 `curl -x 127.0.0.1:7890`（走代理）各打一次同一端点，能一步区分「网络本身不通」还是「代理路由坏」。
2. **快速失败（几百 ms）+ `net::ERR_CONNECTION_CLOSED` / `SSL_ERROR_SYSCALL` 多半是 TLS 握手被 RST**，不是超时、不是 401；先看是不是该域名被错误地送进了代理。
3. **国内可直连的海外云节点（阿里云 SG/HK 等）没必要走代理**；把它们放进绕过列表或 FlClash DIRECT 规则，比换节点更稳。
4. **改动前先备份原始代理/绕过列表**，`networksetup -setproxybypassdomains` 是整表替换，必须保留原有条目，否则会清掉 zhihu/内网网段等既有绕过。
5. **Electron/Chromium 吃系统代理**，改完绕过列表要完全退出重启应用才生效。
6. **换网络服务（Wi-Fi→以太网/热点）后要对新服务重放绕过脚本**；脚本内 `SERVICE` 变量改成对应服务名即可。
7. **区分网络错误与账号错误**：`QODER_APP_QCS_ACCOUNT_CHANGED` 这类是登录态问题，不要误当成网络故障反复折腾代理。
8. **不要用「网页能打开」类推客户端**：网页可能走缓存/不同端点；以客户端自己的日志端点实测为准。

---

## 关键产物与现场位置（不含密钥）

- **Qoder 应用 / 数据**：`/Applications/Qoder.app`（0.4.4）；用户数据 `~/Library/Application Support/com.qoder.app.stable/`；日志 `.../logs/<session>/main.log`、`renderer.log`
- **Qoder 实际端点**：
  - `https://openapi.qoder.sh/api/v1/deviceToken/poll`（设备登录轮询，CNAME `ga-bp1ffcpb88nkvl9saz78t.aliyunga0019.com`，`8.212.124.35 / 47.57.243.249`）
  - `https://api2.qoder.sh/otel/v1/logs`（遥测，`8.223.13.163 / 47.57.188.188`）
  - `https://center.qoder.sh/algo/api/update/desktop/darwin-arm64/stable/0.4.4`（更新检查）
  - `https://api.qoder.com`（`8.223.24.252 / 8.223.26.226`）
- **系统代理**：Wi-Fi HTTP/HTTPS/SOCKS = `127.0.0.1:7890`（FlClash）
- **本次新增绕过条目**：`*.qoder.sh`、`qoder.sh`、`*.qoder.com`、`qoder.com`
- **仓库脚本**：
  - `scripts/qoder-add-bypass.sh`：读取现有绕过列表去重追加 qoder 域名（幂等）
  - `scripts/qoder-rollback-bypass.sh`：恢复为修复前原始 17 条绕过列表
- **复现 / 对照命令**：

  ```bash
  # 直连
  curl -sS --noproxy '*' --max-time 8 -o /dev/null -w '%{http_code} %{time_total}s\n' \
    https://openapi.qoder.sh/api/v1/deviceToken/poll
  # 走代理（故障形态）
  curl -sS -x http://127.0.0.1:7890 --max-time 8 -o /dev/null -w '%{http_code} %{time_total}s\n' \
    https://openapi.qoder.sh/api/v1/deviceToken/poll
  # 查看当前绕过列表
  networksetup -getproxybypassdomains Wi-Fi
  ```

---

*本篇记录的是「代理客户端正常、仅单一应用域名经代理被 TLS 重置」的分流类故障：与 2026-09-04「客户端没启动 + DNS 污染」的网络前置故障不同，修复点在路由（该域名直连），且全程备份可回滚。*
