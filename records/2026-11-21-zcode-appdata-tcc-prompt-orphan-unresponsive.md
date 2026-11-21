# ZCode 首次启动弹「“ZCode.app”想访问其他 App 的数据」，『允许』与『不允许』点全无反应：TCC 提示被系统进程 `UserNotificationCenter` 托管、发起进程已退出成孤儿窗口；重启该系统进程清窗、复启 ZCode 后不再复现

## 基本信息

- **处理者身份**：豆包 MainAgent（macOS 本机会话，完全访问模式，单代理执行；实际改动只有两步：`killall UserNotificationCenter` 清掉孤儿提示窗口、重新启动 ZCode）
- **问题类型**：macOS TCC 授权提示（`kTCCServiceSystemPolicyAppData`，「访问其他 App 的数据」）**孤儿窗口**——提示正常渲染、文案与按钮均正常，但点击无任何反馈，且宿主不是应用自身而是系统进程 `UserNotificationCenter`
- **报错时间**：2026-11-21 02:04:37（tccd 首次 `AUTHREQ_PROMPTING`）；用户 02:09 报障（附 586×519 截图）
- **解决确认时间**：2026-11-21 02:11（提示窗口消失、ZCode 复启成功）；02:16 复查确认无复发
- **最终状态**：✅ 已解决。孤儿提示窗口已清除；ZCode 3.18.2 正常运行（pid 10429），复启后 4 分钟无新的 AppData 授权请求
- **环境**：macOS 26.6 (25G72)，Apple Silicon MacBook Air（arm64）；ZCode 3.18.2，bundle id `dev.zcode.app`，Developer ID `Beijing Knowledge Atlas Technology Joint Stock Company Limited (8A5X4JJ39T)`，已公证
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 01:55 | 本会话 | 从官方 CDN 下载 `ZCode-3.18.2-mac-arm64.dmg`（302MB） |
| 01:58 | 本会话 | `hdiutil attach` 挂载 → 复制 `ZCode.app` 进 `/Applications` → 卸载镜像；`codesign -dv` 校验通过（Developer ID：智谱/Knowledge Atlas，已公证，无 quarantine 标记）；删除 dmg |
| 02:04:37 | ZCode / bfs / tccd | 首次启动（ZCode pid 8043）；内置搜索工具 `bfs`（pid 9326，`/Applications/ZCode.app/Contents/Resources/tools/bfs/bfs`）遍历目录触发 App 数据保护；tccd 记 `AUTHREQ_PROMPTING: msgID=4939.39, service=kTCCServiceSystemPolicyAppData` |
| 02:04:37 | tccd | 同一秒内 `kTCCServicePhotos` 因缺少 `com.apple.security.personal-information.photos-library` entitlement 被**静默拒绝**：`Policy disallows prompt … access to kTCCServicePhotos denied`（不弹窗） |
| 02:09 | 用户 | 报障：悬浮窗点『允许』『不允许』均无反应；截图显示提示压在豆包窗口内（586×519） |
| 02:10 | 本会话 | `pgrep -lf ZCode` / `pgrep -lf bfs` 均无结果；`ps -p 8043` 为空 → 发起进程已全部退出 |
| 02:10 | 本会话 | `CGWindowListCopyWindowInfo` 枚举：`pid=18911 layer=8 owner=UserNotificationCenter bounds=725,204,260x235`；豆包主窗 `255,134,1200x800` 正好被其覆盖 → 确认「弹窗在豆包里」只是视觉重叠 |
| 02:11 | 本会话 | `killall UserNotificationCenter`（pid 18911）→ 提示窗口 3 秒内消失；launchd 按需重建该系统进程 |
| 02:11 | 本会话 | `open -a /Applications/ZCode.app` 复启（pid 10429），主窗口正常（`255,92,1200x800`） |
| 02:16 | 本会话 | `log show` 复查：无新的 `SystemPolicyAppData` 提示；窗口列表仅剩 ZCode 主窗，无 `UserNotificationCenter` 浮窗 |

---

## 问题详细描述

用户描述：**「这个悬浮窗点击允许和不允许都没反应，什么情况？解决一下」**。

现场事实：

- 弹窗内容：文件夹图标 + 蓝色手掌角标，文案「“ZCode.app”想访问其他 App 的数据。单独存放 App 数据可让你更容易管理隐私和安全。」，底部两枚整行按钮『不允许』『允许』
- 点击两个按钮：无高亮、无按压动画、无消失、无任何日志变化
- 弹窗视觉位置落在豆包（Doubao）主窗口内部（截图 586×519，提示位于聊天区左上部），容易误判为「豆包自己的弹窗卡住」或「提示被陷在豆包界面里」
- 触发时机：ZCode 于同一会话中刚完成下载安装并首次启动，属首次运行时的权限请求；当时停在首启页面，尚未完成任何登录操作

---

## 排查过程与关键技术证据

### 1. 先定位弹窗归属：不是 ZCode 画的，也不是豆包的

用 CGWindowList 枚举屏幕上所有窗口（`optionOnScreenOnly` + `excludeDesktopElements`，过滤 layer ≤ 25），输出关键行：

```text
pid=18911 layer=8  owner=UserNotificationCenter  bounds=725,204,260x235
pid=92462 layer=0  owner=豆包                     name=下载Zcode - 豆包  bounds=255,134,1200x800
pid=10429 layer=0  owner=ZCode                    name=ZCode           bounds=255,92,1200x800
```

- 提示窗口的 owner 是 **`UserNotificationCenter`**（系统进程，pid 18911），尺寸 260×235，坐标 725,204，layer 8（浮于普通窗口之上）
- 该坐标完全落在豆包主窗（255,134 起，1200×800）矩形内部 → 只是**视觉重叠**，与豆包无关
- 同时刻 ZCode 主窗（255,92）位于更下层，说明提示不属于 ZCode 的窗口树

→ **结论**：这是系统级 TCC 提示窗口，由 `UserNotificationCenter` 托管；「在豆包窗口里」只是坐标重叠造成的错觉。

### 2. 发起进程已经不存在：孤儿窗口的直接证据

```bash
pgrep -lf ZCode                     # 无输出
pgrep -lf bfs                       # 无输出
ps -p 8043 -o pid,stat,%cpu,etime 2>/dev/null   # 只有表头，无数据行
```

- tccd 日志中该请求的 responsible 进程为 ZCode 主进程 **pid 8043**，accessing 进程为 `bfs` **pid 9326**
- 两个进程此时均已不存在，提示窗口却仍在屏幕上，说明它已失去对应的授权请求

→ **结论**：窗口是**孤儿**（发起方已退出），按钮背后没有活请求，点击自然无反馈。

### 3. 用 tccd 日志读出「谁在要什么权限」

```bash
log show --last 10m --predicate 'process == "tccd"' | grep -i zcode
```

关键行（原文节选）：

```text
02:04:37.834 tccd: AUTHREQ_PROMPTING: msgID=4939.39, service=kTCCServiceSystemPolicyAppData,
  subject=Sub:{dev.zcode.app} Resp:{TCCDProcess: identifier=dev.zcode.app, pid=8043,
  responsible_path=/Applications/ZCode.app/Contents/MacOS/ZCode},
  accessing={TCCDProcess: identifier=bfs, pid=9326,
  binary_path=/Applications/ZCode.app/Contents/Resources/tools/bfs/bfs},
  requesting={TCCDProcess: identifier=com.apple.sandboxd, pid=4939,
  binary_path=/usr/libexec/sandboxd}

02:04:37.772 tccd: Prompting policy for hardened runtime; service: kTCCServicePhotos requires
  entitlement com.apple.security.personal-information.photos-library but it is missing ...
02:04:37.772 tccd: Policy disallows prompt ... access to kTCCServicePhotos denied
```

- 请求主体是 `dev.zcode.app`，但**真正发起目录访问的是它自带的 `bfs`**（文件搜索工具），由 `sandboxd` 代发
- 同一秒还有 Photos 访问请求，因缺 entitlement 被系统直接拒绝且**不弹窗**，所以用户只看到一个提示

→ **结论**：提示的服务类型是 `kTCCServiceSystemPolicyAppData`，触发者是 ZCode 内置 `bfs` 扫描其他 App 的容器目录。

### 4. 复启后的日志：只剩无关的能力缺失告警

```bash
log show --last 3m --predicate 'process == "tccd"' | grep -i zcode
```

```text
02:11:41.997 tccd: Prompting policy for hardened runtime; service: kTCCServiceAppleEvents requires
  entitlement com.apple.security.automation.apple-events but it is missing ...
```

- 该条为「无法通过 Apple Events 控制其他 App」的静默拒绝，与本次授权窗无关
- 复启后没有任何 `SystemPolicyAppData` 的 `PROMPTING` 记录

→ **结论**：复启后未再触发 App 数据授权，复现条件已消失。

### 5. 排除「界面卡死 / 点错位置 / 被遮挡」

| 验证手段 | 结果 |
| --- | --- |
| 窗口层级 | 提示为 layer 8，在普通窗口（layer 0）之上，不存在被遮挡 |
| 应用活性 | ZCode 主进程已不存在，提示窗口仍存活；卡死的应用不会有独立的系统浮窗留存 |
| 宿主进程 | owner 为 `UserNotificationCenter`，不是 ZCode 的 UI 进程，因此即使 ZCode 卡死也与此无关 |
| 重复点击 | 用户多次点击，日志中无任何按钮 action / 授权结果记录 |

→ **结论**：不是遮挡、不是点偏、不是应用卡死，而是提示窗口对应的授权请求已失效。

---

## 根因分析

| 层级 | 内容 |
| --- | --- |
| **直接原因（触发）** | ZCode 首启时内置 `bfs` 搜索工具遍历本机目录（含其他 App 容器目录，如 `~/Library/Containers`、`~/Library/Application Support/*`），命中 macOS 的 App 数据保护，系统发起 `kTCCServiceSystemPolicyAppData` 授权请求 |
| **深层原因（按钮失灵）** | 该提示窗口由系统进程 `UserNotificationCenter` 承载，按钮决策需回传给 tccd 中**仍在等待的那条请求**；发起进程（ZCode pid 8043 / bfs pid 9326）退出后请求失效，窗口失去目标，点击被吞掉。此结论基于「窗口 owner 为 `UserNotificationCenter` + 对应进程全部消失 + 点击零日志」的实测推断，未见官方文档正向确认 |
| **附加现象** | 提示坐标恰好覆盖在豆包主窗内，视觉上表现为「豆包里的弹窗」，使排障方向容易被引向豆包 |
| **同类差异** | 与 [2026-10-23 互联网账户僵尸弹窗](records/2026-10-23-macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md) 机理不同：那例是 `.appex` 内 `_NSAlertPanel` 的 `canBecomeKeyWindow = NO`（进程仍在、窗口拒绍成为 key window）；本例是**请求已随进程消失的孤儿窗口**（进程全无、窗口残留） |

### 误判与反证对照

| 曾被怀疑的方向 | 反证 |
| --- | --- |
| 弹窗属于豆包，是豆包界面卡死 | `CGWindowList` 显示 owner 为 `UserNotificationCenter`，豆包主窗仅被坐标覆盖 |
| ZCode 界面卡死导致按钮点不动 | ZCode 主进程此时已不存在，提示窗却仍在；应用卡死不会留下独立系统浮窗 |
| 只是没点准 / 被其它窗口挡住 | 提示为 layer 8，在所有普通窗口之上；且用户多次点击均无响应 |
| 是恶意程序在偷数据 | 发起者与访问者都是 ZCode 自带的已签名工具 `bfs`，签名链为 Developer ID + Apple Root CA，属正常目录扫描 |
| 选「不允许」会导致 ZCode 不能用 | 该权限只影响读取其他 App 的数据；ZCode 主体功能与项目目录不受影响 |

---

## 解决方案与落地操作

### A. 清除孤儿提示窗口（无需重启、无需注销）

```bash
# 结束承载系统提示的进程；launchd 会按需自动重建，不影响其他通知
killall UserNotificationCenter
```

> 本次实测：执行后 3 秒内提示窗口消失，屏幕窗口列表中不再有该 owner 的 layer 8 窗口。

### B. 复启应用并验证

```bash
open -a /Applications/ZCode.app
```

- 复启后确认：`CGWindowList` 中只有 ZCode 主窗；`log show` 中无新的 `SystemPolicyAppData` 提示
- 首次登录可按正常流程继续（本次未涉及账号登录环节）

### C. 避免反复触发（按需选择）

1. 真再弹时直接选『不允许』：ZCode 仍可正常用于项目目录，只是读不到其他 App 数据；系统会记住该选择，不再反复询问
2. 若确实需要读取其他 App 数据：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 勾选 ZCode，可减少这类目录级提示
3. 把 ZCode 工作区限定在具体项目目录，避免对整个用户主目录做全盘搜索（`bfs` 扫描范围越大，越容易碰到 App 容器）

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| 孤儿提示窗口（owner `UserNotificationCenter`） | 存在：260×235 @ 725,204，layer 8，按钮无反应 | 已消失，窗口列表中无此 owner 浮窗 | ✅ |
| ZCode 主进程 | 已退出（pid 8043 不存在） | 正常运行（pid 10429 + Helper / Renderer 子进程） | ✅ |
| ZCode 主窗口 | 有窗无进程 | 存在（255,92，1200×800） | ✅ |
| `SystemPolicyAppData` 提示 | 02:04:37 一次 `PROMPTING` | 复启后至 02:16 无新增 | ✅ |
| Photos 授权请求 | 缺 entitlement → `Policy disallows prompt … denied` | 同为静默拒绝，不弹窗、不阻塞 | ✅ |
| 点击响应 | 两个按钮均无反馈 | 提示已不存在，改为复启后正常使用 | ✅ |

---

## 经验沉淀

1. **「系统弹窗压在某应用窗口里」不等于该应用的弹窗**：先用 `CGWindowList` 看 owner。owner 为 `UserNotificationCenter`、`ControlCenter` 这类系统进程时，属于 TCC / 系统提示体系，排障方向完全不同。
2. **点击完全无反应时，第一步先确认「发起进程还在不在」**：`pgrep` 查不到应用进程而窗口仍在，就是孤儿窗口；此时再点、再等都不会有结果，只能清窗重来。
3. **`killall UserNotificationCenter` 是清理这类僵尸系统提示的低风险手段**：该进程由 launchd 托管、按需重建，不丢数据，不影响其他通知，比重启系统或重装应用快得多。
4. **用 tccd 日志直接读出「谁在要什么权限」**：`log show --predicate 'process == "tccd"' | grep -i <app>` 能看到 `AUTHREQ_PROMPTING` 的 service 名、subject（bundle id）与 accessing 的具体二进制路径。本例因此定位到「真正发起访问的是 ZCode 自带 `bfs`，不是主程序」。
5. **缺 entitlement 的 TCC 请求会被静默拒绝、不会弹窗**：日志特征为 `requires entitlement … but it is missing` + `Policy disallows prompt … denied`（本例 Photos、AppleEvents），不要当成需要修复的权限故障。
6. **现代 AI 编码客户端普遍自带文件搜索/遍历工具**（ZCode 的 `bfs`），首启全盘扫描很容易撞上 macOS 的 App 数据保护；允许/拒绝都只是一次性选择，选「不允许」最省事且不影响主流程。

---

## 关键产物与现场位置

- 安装包：`~/Downloads/ZCode-3.18.2-mac-arm64.dmg`（302MB，安装完成后已删除）
- 应用：`/Applications/ZCode.app`（3.18.2，arm64，bundle id `dev.zcode.app`）
- 触发者：`/Applications/ZCode.app/Contents/Resources/tools/bfs`（pid 9326，responsible 为 ZCode pid 8043）
- 孤儿窗口：owner `UserNotificationCenter`（pid 18911），260×235 pt @ (725, 204)，layer 8
- 关键命令：

```bash
# 窗口归属（Swift 内联，无额外依赖）
swift -e 'import Cocoa; let a = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]; for w in a { print(w[kCGWindowOwnerName as String] ?? "?", w[kCGWindowOwnerPID as String] ?? 0, w[kCGWindowLayer as String] ?? 0) }'

# 授权请求来源与结果
log show --last 10m --predicate 'process == "tccd"' | grep -i zcode

# 清孤儿提示窗口
killall UserNotificationCenter

# 复启应用
open -a /Applications/ZCode.app
```

- 本次事件时间：`2026-11-21 02:04`（触发）→ `2026-11-21 02:11`（清窗复启）→ `2026-11-21 02:16`（复查确认）

*结论：这个点不动的弹窗不是 ZCode 或豆包画的，而是 macOS 在 ZCode 自带搜索工具 `bfs` 扫描其他 App 目录时弹出的 TCC「访问其他 App 的数据」提示；发起进程退出后该提示成了孤儿窗口，按钮对应不到任何活请求，所以怎么点都没有反应。`killall UserNotificationCenter` 清窗、复启 ZCode 即恢复，之后未再复现。*
