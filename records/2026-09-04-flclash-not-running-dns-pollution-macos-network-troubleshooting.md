# FlClash 未运行致代理全断 + 系统 DNS 配置 8.8.8.8 遭 GFW 污染：macOS 26 网络代理与 Antigravity/Google 地区限制深度排查实录

## 基本信息

- **处理者身份**：Doubao（本次会话 AI 协作代理，主排查与根因定位）
- **问题类型**：
  1. FlClash 代理客户端两个订阅（几鸡订阅 / 魔戒.net）节点疑似全部失效
  2. Google 服务出现「地区限制」提示，无法正常访问
  3. AI 编码工具 Antigravity 无法连接后端（依赖 Google API `generativelanguage.googleapis.com`）
  4. 系统 DNS 长期配置 `8.8.8.8`，在国内网络环境下遭 GFW DNS 污染注入
- **报错时间**：2026-09-04 16:00 前后（Asia/Shanghai，UTC+8）
- **解决确认时间**：2026-09-04 16:35 前后（Asia/Shanghai，UTC+8）
- **最终状态**：已解决（用户手动启动 FlClash 规则模式 + TUN 透明代理；系统 DNS 修正为国内 DNS；FlClash 添加开机自启；Google / YouTube / Antigravity 全部恢复正常）
- **关联项目/仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)
- **与上一篇关系**：本篇与 `2026-09-04-chatgpt-unsupported-country-clash-meta-migration.md` 同属 macOS 代理生态排查，但本篇核心是「客户端未运行 + DNS 污染」而非「节点伪地区 + 老旧客户端架构缺陷」。

### Agent 分工与时间线

| 时间（本地，UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 16:00 | 用户 | 反馈三大网络问题：FlClash 节点不行了、Google 地区限制、Antigravity 用不了，要求深度排查 |
| 16:05–16:10 | Doubao | 基础网络层诊断：确认国内网络正常（百度 200），Google 直连超时；发现系统 DNS 为 `8.8.8.8` 且解析 google.com 返回污染 IP（Facebook 段 31.13.92.37） |
| 16:10–16:15 | Doubao | 代理软件状态排查：发现 FlClash GUI 与 FlClashCore 进程均不存在，7890 端口未监听，无 TUN 虚拟网卡，系统代理全部关闭——**确认 FlClash 根本未运行** |
| 16:15–16:25 | Doubao | 独立 mihomo 命令行对照测试：验证配置文件语法正确、节点端口可达；定位 global 模式下首个「代理」实为流量信息节点（`[ss]剩余流量：42.89 GB`）导致连接超时；发现国内 DoH（223.6.6.6）也返回污染结果 |
| 16:30 | 用户 | 指出「F clash 都没有运行，我刚刚点了一个运行，开的是规则模式」，手动启动 FlClash |
| 16:30–16:35 | Doubao | 重新验证 FlClash 运行状态：TUN 接口 utun4 (198.18.0.1) 已创建，全部 IPv4 路由导入 TUN；实测 Google 200 (0.33s)、YouTube 200 (0.97s)、出口 IP 台湾台北 HiNet；Antigravity 依赖的 Google API 可达 |
| 16:35–16:40 | Doubao | 执行根治修复：系统 DNS 从 `8.8.8.8 + 223.5.5.5` 修正为 `223.5.5.5 + 119.29.29.29`；FlClash 添加到 macOS 登录项实现开机自启 |
| 16:40–16:50 | Doubao | 编写本次排障追踪文档，按仓库范式归档至 `records/` |

---

## 问题详细描述

用户在 macOS 26.6 (Tahoe) 系统上使用 FlClash v0.8.91 作为代理客户端，配置了两个订阅：「几鸡订阅」（SS / Hysteria2 节点，覆盖台湾/日本/越南）和「魔戒.net」（AnyTLS / Hysteria2 / VMess 节点）。

用户反馈三个表象问题：

1. **「Fi clash 是一个梯子平台，我的两个节点好像都不行了」**——怀疑两个订阅的节点全部失效，代理无法连接。
2. **「Google 开始跟我说有地区限制」**——访问 Google 服务时出现地区不可用的提示。
3. **「Anti-gravity 也用不了」**——AI 编码工具 Antigravity 无法正常工作，后端连接失败。

用户的工作环境高度依赖 Google 系列服务与 AI 编程工具，代理中断导致全部海外服务不可用。

---

## 排查过程与关键技术证据

### 1. 基础网络连通性核验（排除物理断网嫌疑）

通过终端检测网卡、路由、DNS 与外网连通性：
```bash
# 网卡与默认路由
ifconfig | grep -E "^[a-z]|inet |status"
netstat -rn | head -20

# 系统 DNS 配置
scutil --dns | grep "nameserver\["
cat /etc/resolv.conf

# 国内/国际连通性对照
ping -c 3 -t 5 223.5.5.5
curl -s -o /dev/null -w "%{http_code}" https://www.baidu.com
curl -s -o /dev/null -w "%{http_code}" --noproxy '*' https://www.google.com

# 多 DNS 服务器解析对照（污染检测）
nslookup www.google.com 8.8.8.8
nslookup www.google.com 223.5.5.5
nslookup www.google.com 114.114.114.114
```

* **证据发现**：
  - 网卡 en0 正常（IP 192.168.110.231），默认网关 192.168.110.1 可达
  - 国内网络正常：ping 223.5.5.5 通，百度返回 HTTP 200
  - Google 直连超时（预期内，国内直连被墙）
  - **系统 DNS 配置为 `8.8.8.8` + `223.5.5.5`**，其中 8.8.8.8 在国内直连必遭污染
  - **DNS 污染验证**：三组 DNS 解析 www.google.com 均返回错误 IP：
    - 8.8.8.8 → `174.132.167.252`（非 Google IP）
    - 223.5.5.5 → `31.13.92.37`（Facebook/Meta IP 段，典型污染注入结果）
    - 114.114.114.114 → `31.13.92.37`（同样污染）
    - youtube.com → `69.171.235.22`（Facebook IP，污染）
* **结论**：物理网络正常，但系统 DNS 存在严重污染，且代理客户端状态未知。

### 2. 代理软件状态排查（定位直接原因）

检测 FlClash 进程、监听端口、系统代理与 TUN 接口：
```bash
# 进程检测
ps aux | grep -iE "clash|mihomo|flclash" | grep -v grep

# 代理标准端口监听
lsof -iTCP -sTCP:LISTEN -P -n | grep -E "7890|1080|10808"

# 系统代理设置
scutil --proxy

# TUN 虚拟网卡
ifconfig | grep -A4 "utun|FlClash"

# 路由表中 TUN 相关路由
netstat -rn | grep -E "utun|198.18"
```

* **证据发现（排查初期）**：
  - ❌ FlClash GUI 进程不存在
  - ❌ FlClashCore（mihomo 核心）进程不存在
  - ❌ 7890 混合代理端口未监听
  - ❌ 无 FlClash TUN 虚拟网卡（utun4 不存在）
  - ❌ 系统代理全部关闭：`HTTPEnable: 0`、`HTTPSEnable: 0`、`SOCKSEnable: 0`
  - ❌ 路由表中无 198.18.0.0/16（fake-ip 段）相关路由
* **关键结论**：**FlClash 根本没有运行**，这是代理全断的直接原因。所谓「两个节点不行了」实为客户端未启动导致所有代理流量无出口。

> 用户后续确认：「F clash 都没有运行，我刚刚点了一个运行」，印证了此结论。

### 3. FlClash 配置与节点独立验证（排除节点本身故障）

为确认节点是否真的失效，使用独立 mihomo 命令行对配置文件做对照测试：
```bash
# 配置文件位置
ls -la ~/Library/Application\ Support/com.follow.clash/
# 配置语法测试
/opt/homebrew/bin/mihomo -t -f ~/Library/Application\ Support/com.follow.clash/config.yaml

# 节点端口连通性
nc -z -w 3 cdn12.birpagi.cn 15063
nc -z -w 3 cdn1.birpagi.cn 15124

# 启动独立 mihomo 观察 debug 日志
/opt/homebrew/bin/mihomo -f /tmp/test_config.yaml -d ~/Library/Application\ Support/com.follow.clash
```

* **证据发现**：
  - 配置文件语法正确（mihomo `-t` 测试通过），无 YAML 错误
  - 节点服务器端口全部可达（`cdn12.birpagi.cn:15063 OPEN`、`cdn1.birpagi.cn:15124 OPEN`）
  - **重要发现：配置中前两个「代理」是信息节点，非真正代理节点**：
    ```yaml
    - name: "[ss]剩余流量：42.89 GB"    # 流量信息，非代理
    - name: "[ss]套餐到期：2026-10-03"   # 到期信息，非代理
    ```
  - 在 global 模式下，mihomo 默认使用首个代理，导致连接到信息节点而超时（`dial tcp ... i/o timeout`）
  - 台湾 HiNet Hysteria2 节点健康检查通过，延迟 60–400ms，节点本身可用
  - **国内 DoH 也返回污染结果**：mihomo debug 日志捕获 `[DNS] www.google.com --> [31.13.92.37] A from https://223.6.6.6:443/dns-query`，证实阿里 DNS 的 DoH 接口对被墙域名也返回污染注入结果
* **结论**：节点本身正常，故障不在节点侧；global 模式的信息节点陷阱和 DNS 污染是配置层面的附加隐患。

### 4. 用户手动启动 FlClash 后状态验证（确认修复）

用户手动启动 FlClash 并切换为规则模式后，重新检测全链路状态：
```bash
# 进程与端口
ps aux | grep -E "[F]lClash|[F]lClashCore"
lsof -nP -iTCP:7890 -sTCP:LISTEN

# TUN 接口与路由
ifconfig | grep -A4 "utun4"
netstat -rn | grep -E "utun4|198.18"

# 实际连通性（不指定代理，走 TUN 透明代理）
curl -s -o /dev/null -w "Google: %{http_code} (%{time_total}s)\n" https://www.google.com
curl -s -o /dev/null -w "YouTube: %{http_code} (%{time_total}s)\n" https://www.youtube.com
curl -s https://api.ipify.org  # 出口 IP
curl -s https://ipinfo.io/json  # 出口地理位置

# DNS 劫持验证
nslookup www.google.com  # 应返回 fake-ip 198.18.x.x
```

* **证据发现**：
  - FlClash GUI (PID 53585) 与 FlClashCore (PID 55262, root) 均在运行
  - TUN 接口 utun4 已创建：`inet 198.18.0.1 --> 198.18.0.1 netmask 0xfffffffc`，MTU 9000
  - **全部 IPv4 流量被分段路由导入 utun4**：`1/8`、`2/7`、`4/6`、`8/5`、`16/4`、`32/3`、`64/2`、`128.0/1` 均指向 198.18.0.1 (utun4)
  - Google：HTTP 200，0.33s
  - YouTube：HTTP 200，0.97s
  - 出口 IP：`114.37.213.178`，地理位置台湾台北，ISP 中华电信 HiNet (AS3462)
  - DNS 劫持生效：www.google.com 解析到 `198.18.0.24`（fake-ip），真实解析在代理节点端完成
  - Antigravity 依赖的 `generativelanguage.googleapis.com` 可达（返回 404 为正常无端点响应，说明网络连通）
* **结论**：FlClash 规则模式 + TUN 透明代理完全正常，三大表象问题全部消除。

---

## 根因分析

综合各项证据，本次故障是典型的**「客户端未运行 + DNS 配置不当 + DNS 污染」三重叠加问题**：

1. **直接原因：FlClash 代理客户端未运行**
   - 进程不存在、端口未监听、无 TUN 接口、系统代理关闭，四重证据确认客户端完全未启动。
   - 用户误以为「节点不行了」，实则是客户端没开，所有代理流量无出口。
   - FlClash 未配置开机自启，重启或意外退出后代理不自动恢复，是反复出现此问题的诱因。

2. **深层原因一：系统 DNS 配置不当**
   - 系统 DNS 长期配置 `8.8.8.8`（Google Public DNS），在国内直连时 DNS 查询包被 GFW 深度包检测并抢先注入伪造响应。
   - 8.8.8.8 的查询响应在到达真实 Google DNS 服务器之前，已被 GFW 注入的伪造包（Facebook IP 段）抢先命中，客户端丢弃真实响应。
   - 即使代理开着，部分不走 TUN 的应用（如某些系统进程、命令行工具）仍可能直接使用系统 DNS 而遭遇污染。

3. **深层原因二：DNS 污染是基础设施级手段**
   - GFW 在国际出口处对所有 UDP 53 端口 DNS 查询进行 DPI 识别，对被墙域名（google.com、youtube.com 等）抢先注入伪造响应。
   - 不仅 8.8.8.8 等国外 DNS 被污染，**国内 DoH 服务器（阿里 dns.alidns.com / 223.6.6.6、腾讯 doh.pub）对被墙域名也返回污染结果**——因为国内 DNS 服务器的递归查询同样经过 GFW 国际出口，收到污染响应后缓存并返回给用户。
   - 污染特征：Google/Facebook/YouTube 等被墙域名被解析到 Facebook/Meta IP 段（31.13.x.x、69.171.x.x）或其他无关 IP。

4. **附加隐患：global 模式信息节点陷阱**
   - 订阅配置中前两个「代理」是流量/到期信息节点（`[ss]剩余流量：42.89 GB`），非真正代理节点。
   - 在 global 模式下 mihomo 默认使用首个代理，会连接到信息节点而超时。用户当前使用规则模式规避了此问题，但切换到全局模式时可能踩坑。

### 三个表象问题的真实原因映射

| 用户报告 | 真实原因 |
| --- | --- |
| 两个节点不行了 | FlClash 未运行，节点本身正常（台湾 HiNet 节点延迟 60–400ms 可用） |
| Google 地区限制 | 代理未开时直连被墙 + DNS 污染解析到错误 IP；台湾出口 IP 本身无地区限制 |
| Antigravity 用不了 | Antigravity 是 AI 编码工具，依赖 Google API (`generativelanguage.googleapis.com`)，代理未开导致后端连接失败 |

---

## 解决方案与落地操作

### 步骤 1：启动 FlClash 并确认规则模式 + TUN 模式

1. 用户手动启动 FlClash（`open -a FlClash`），在界面中选择**规则模式（Rule）**而非全局模式；
2. 确认 TUN 模式已开启（FlClash 设置 → VPN/TUN → 启用）；
3. 验证 TUN 透明代理生效：
   ```bash
   # 应返回 fake-ip 198.18.x.x，说明 DNS 劫持生效
   nslookup www.google.com
   # 应返回台湾 IP，说明出口正常
   curl -s https://api.ipify.org
   ```

### 步骤 2：修正系统 DNS（去掉被污染的 8.8.8.8）

```bash
# 将系统 DNS 从 8.8.8.8 + 223.5.5.5 修正为纯国内 DNS
networksetup -setdnsservers Wi-Fi 223.5.5.5 119.29.29.29

# 验证
networksetup -getdnsservers Wi-Fi
# 预期输出：
# 223.5.5.5
# 119.29.29.29
```

* **223.5.5.5**：阿里 DNS（AliDNS）
* **119.29.29.29**：腾讯 DNS（DNSPod Public DNS+）
* **原则**：系统 DNS 只用国内 DNS，保证国内域名解析稳定；国外域名由 FlClash TUN 的 fake-ip + 节点端解析处理，不依赖系统 DNS。

### 步骤 3：添加 FlClash 开机自启（防止再次「忘了开」）

```bash
# 通过 AppleScript 添加到 macOS 登录项
osascript -e 'tell application "System Events" to make new login item at end with properties {name:"FlClash", path:"/Applications/FlClash.app", hidden:false}'

# 验证
osascript -e 'tell application "System Events" to get the name of every login item' | tr ',' '\n' | grep -i clash
```

### 步骤 4（可选进阶）：DNS 污染四层防护体系

如需彻底根治 DNS 污染（不依赖代理是否运行），可搭建以下四层防护：

| 层级 | 措施 | 状态 |
| --- | --- | --- |
| 第一层：系统 DNS | 使用国内 DNS（223.5.5.5 + 119.29.29.29），不使用 8.8.8.8 | ✅ 已执行 |
| 第二层：TUN + fake-ip | FlClash TUN 模式劫持全部 DNS 查询，返回 fake-ip，真实解析在节点端完成 | ✅ 已启用 |
| 第三层：本地 SmartDNS | 搭建本地 SmartDNS (127.0.0.1:53)，国内域名→国内 DNS，国外域名→加密 DNS 经代理转发 | ⏳ 可选，后续按需搭建 |
| 第四层：浏览器安全 DNS | Chrome/Edge/Firefox 配置 DoH（须用国外 DoH 且走代理） | ⏳ 可选补充 |

---

## 验证与效果

| 验证项 | 验证命令 / 测试方式 | 实际返回结果 | 状态 |
| :--- | :--- | :--- | :--- |
| **FlClash 进程** | `ps aux \| grep FlClash` | GUI + FlClashCore (root) 均在运行 | ✅ 验证通过 |
| **TUN 接口** | `ifconfig \| grep -A4 utun4` | utun4 (198.18.0.1) RUNNING，MTU 9000 | ✅ 验证通过 |
| **全流量路由** | `netstat -rn \| grep utun4` | 全部 IPv4 网段 (1/8 ~ 128.0/1) 导入 utun4 | ✅ 验证通过 |
| **Google 连通性** | `curl -s -I https://www.google.com` | HTTP 200，0.33s | ✅ 验证通过 |
| **YouTube 连通性** | `curl -s -I https://www.youtube.com` | HTTP 200，0.97s | ✅ 验证通过 |
| **出口 IP 地理位置** | `curl -s https://ipinfo.io/json` | 114.37.213.178，台湾台北，HiNet (AS3462) | ✅ 验证通过 |
| **DNS 劫持生效** | `nslookup www.google.com` | 返回 198.18.0.24（fake-ip），非污染 IP | ✅ 验证通过 |
| **Google API (Antigravity)** | `curl -s -I https://generativelanguage.googleapis.com` | 可达（404 为正常无端点响应） | ✅ 验证通过 |
| **系统 DNS 修正** | `networksetup -getdnsservers Wi-Fi` | 223.5.5.5, 119.29.29.29（无 8.8.8.8） | ✅ 验证通过 |
| **开机自启** | `osascript -e 'get name of every login item'` | 包含 FlClash | ✅ 验证通过 |
| **用户主观使用** | 浏览器访问 Google / Antigravity 编码 | 正常访问，Antigravity 恢复工作 | ✅ 确认解决 |

---

## 经验沉淀与后续建议

1. **「节点不行了」先查客户端在不在运行**：代理故障的第一检查项应是进程状态（`ps aux | grep clash`）和端口监听（`lsof -i:7890`），而非直接怀疑节点。很多「节点全挂」实为客户端未启动。

2. **系统 DNS 不要用 8.8.8.8 / 1.1.1.1**：在国内网络环境下，国外公共 DNS 的 UDP 53 查询必遭 GFW 污染注入。系统 DNS 应使用国内 DNS（223.5.5.5 / 119.29.29.29），国外域名解析交由代理客户端的 TUN + fake-ip 处理。

3. **国内 DoH 对被墙域名也返回污染结果**：不要以为用了 DoH（DNS over HTTPS）就能规避污染。国内 DoH 服务器（阿里 dns.alidns.com、腾讯 doh.pub）的递归查询同样经过 GFW 国际出口，收到污染响应后缓存返回。只有通过代理节点访问的国外 DoH（1.1.1.1、8.8.8.8）才能获得真实解析。

4. **DNS 污染的快速识别方法**：被墙域名（google.com、youtube.com、facebook.com 等）被解析到 Facebook/Meta IP 段（31.13.x.x、69.171.x.x）或其他明显无关 IP，即可确认是 DNS 污染。用多个不同 DNS 服务器对比解析结果，若均返回相同错误 IP，则为污染而非单个 DNS 故障。

5. **TUN + fake-ip 是规避 DNS 污染最有效的方案**：TUN 模式劫持全部流量（包括 DNS 查询），返回 fake-ip（198.18.0.0/16），真实域名解析在代理节点端完成，完全不经过国内网络。相比系统代理模式（部分应用绕过），TUN 透明代理覆盖更彻底。

6. **注意订阅中的信息节点陷阱**：部分机场订阅的前几个「代理」是流量信息、到期时间等非代理节点。在 global（全局）模式下，mihomo 默认使用首个代理，会连接到信息节点而超时。建议使用规则模式，或在全局模式下手动选择真实代理节点。

7. **代理客户端务必配置开机自启**：macOS 登录项（`osascript` 添加）或客户端内置自启选项，避免重启或意外退出后代理不自动恢复，导致「又断网了」的反复困扰。

8. **FlClash 版本偏老需关注更新**：当前 FlClash v0.8.91（2025-12 构建），而系统为 macOS 26.6（非常新的版本）。macOS 大版本升级后网络扩展、虚拟网卡机制可能变化，老旧客户端易出现隐蔽兼容性问题，应关注 FlClash 官方更新。

---

## 关键产物与现场位置（不含密钥）

- **FlClash 配置文件**：`~/Library/Application Support/com.follow.clash/config.yaml`（当前生效配置，规则模式 + TUN）
- **FlClash 订阅文件**：
  - 几鸡订阅：`~/Library/Application Support/com.follow.clash/profiles/1783268229663.yaml`
  - 魔戒.net：`~/Library/Application Support/com.follow.clash/profiles/1788507274317.yaml`
- **FlClash 偏好设置**：`defaults read com.follow.clash`（含 flutter.config JSON 块）
- **FlClash Core 二进制**：`/Applications/FlClash.app/Contents/MacOS/FlClashCore`（setuid root，mihomo 核心）
- **FlClash Unix Socket**：`/tmp/FlClashSocket_*.sock`（GUI 与 Core 通信通道）
- **独立 mihomo 测试配置**：`/tmp/test_mihomo_config.yaml`（排查期间用于对照测试，已废弃）
- **独立 mihomo 测试日志**：`/tmp/mihomo_*.log`（含 DNS 污染证据：`www.google.com --> [31.13.92.37]`）
- **系统 DNS 修正命令**：`networksetup -setdnsservers Wi-Fi 223.5.5.5 119.29.29.29`
- **开机自启添加命令**：`osascript -e 'tell application "System Events" to make new login item at end with properties {name:"FlClash", path:"/Applications/FlClash.app", hidden:false}'`
- **出口 IP 验证**：`curl -s https://ipinfo.io/json` → `114.37.213.178`（台湾台北 HiNet）
- **DNS 污染特征 IP 段**：`31.13.0.0/16`、`69.171.0.0/16`（Facebook/Meta，google.com/youtube.com 被污染后常指向此段）

---

*本文档记录了一次完整的 macOS 代理客户端未运行 + DNS 污染排查过程，核心教训：先查进程在不在，再查 DNS 干不干净，最后才查节点行不行。*
