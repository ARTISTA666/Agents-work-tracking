# ZCode 首次启动弹「ZCode.app 想访问其他 App 的数据」，『允许 / 不允许』点击全无反应：TCC 提示被 `UserNotificationCenter` 托管成僵尸窗口（发起进程已退出）→ 重启该系统进程清窗、复启 ZCode 不再复现

## 基本信息

- **处理者身份**：豆包 MainAgent（macOS 本机会话，完全访问模式，单代理执行；改动只有两步：`killall UserNotificationCenter` 清僵尸提示窗口、重新启动 ZCode）
- **问题类型**：macOS TCC 授权提示**僵尸窗口**——`kTCCServiceSystemPolicyAppData`（访问其他 App 的数据）提示正常渲染、文案正常，但按钮点击无任何反馈；窗口宿主是系统进程 `UserNotificationCenter`，并非应用自身
- **报错时间**：2026-11-21 02:04:37（首次弹出）；用户 02:09 报障（附 586×519 截图）
- **解决时间**：2026-11-21 02:11 前后（清窗并复启 ZCode），至 02:16 观察无复发
- **最终状态**：✅ 已解决。僵尸提示消失；ZCode 3.18.2 正常启动（pid 10429），4 分钟内未再出现 AppData 授权请求
- **环境**：macOS 26.6 (25G72)，Apple Silicon（arm64）MacBook Air；ZCode 3.18.2（bundle id `dev.zcode.app`，Developer ID `Beijing Knowledge Atlas Technology Joint Stock Company Limited (8A5X4JJ39T)`，已公证）
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### 背景与时间线（UTC+8）

| 时间 | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 01:58 | 本会话 | 从官方 CDN 下载 `ZCode-3.18.2-mac-arm64.dmg`（302MB），校验签名后复制进 `/Applications`，删除安装包 |
| 02:04:37 | ZCode / tccd | 首次启动（pid 8043），内置 `bfs`（pid 9326）遍历目录触发 AppData 保护；tccd 记 `AUTHREQ_PROMPTING service=kTCCServiceSystemPolicyAppData` |
| 02:04:37 | tccd | 同时刻 `kTCCServicePhotos` 因缺少 `com.apple.security.personal-information.photos-library` entitlement 被**静默拒绝**（不弹窗） |
| 02:09 | 用户 | 报障：悬浮窗点『允许』『不允许』都没反应（截图显示提示压在豆包窗口上） |
| 02:10 | 本会话 | `pgrep` 已查不到 ZCode 进程，但提示窗口仍在；`CGWindowList` 定位窗口 owner = `UserNotificationCenter`（pid 18911，260×235 @ 725,204） |
| 02:11 | 本会话 | `killall UserNotificationCenter` → 提示窗口立即消失（launchd 自动重建该进程） |
| 02:11 | 本会话 | 复启 ZCode（pid 10429），主窗口正常；`log show` 未再出现 `SystemPolicyAppData` 提示 |
| 02:16 | 本会话 | 复查窗口列表与进程：仅 ZCode 主窗，无 `UserNotificationCenter` 浮窗 |

---

## 问题详细描述

用户描述：**「这个悬浮窗点击允许和不允许都没反应，什么情况？解决一下」**。

现场事实：

- 弹窗文案：「“ZCode.app”想访问其他 App 的数据。单独存放 App 数据可让你更容易管理隐私和安全。」底部两个按钮『不允许』『允许』
- 点击两个按钮均无高亮、无消失、无任何反馈
- 弹窗视觉位置落在豆包（Doubao）主窗口内部，容易误判成「豆包自己的弹窗」或「卡在豆包界面里」
- ZCode 此前刚由本会话完成下载安装并首次启动，属于**首次运行的权限请求**

---

## 排查过程与关键技术证据

### 1. 先用窗口归属定性：弹窗不是 ZCode 画的

用 `CGWindowListCopyWindowInfo` 枚举屏幕窗口（`optionOnScreenOnly`，过滤 layer ≤ 25）：

```text
pid=18911 layer=8  owner=UserNotificationCenter  bounds=725,204,260x235
pid=92462 layer=0  owner=豆包                     name=下载Zcode - 豆包  bounds=255,134,1200x800
pid=10429 layer=0  owner=ZCode                    name=ZCode           bounds=255,92,1200x800
```

- 提示窗口 owner 是 **`UserNotificationCenter`**（系统进程），尺寸 260×235、坐标正好落在豆包窗口（255,134 起、1200×800）内部
- 所以「弹窗在豆包里」只是**视觉重叠**，不是豆包弹的，也不是 ZCode 的界面元素

### 2. 发起进程已经不存在：典型的孤儿提示窗口

```bash
pgrep -lf ZCode            # 无任何输出
ps -p 8043 -o pid,stat,%cpu,etime   # 空
pgrep -lf bfs              # 空
```

即 TCC 请求的 responsible 进程（ZCode 主进程 pid 8043）与 accessing 进程（`bfs` pid 9326）都已退出，但系统提示窗口仍留在屏幕上——按钮背后的授权请求已不存在，点击自然无处可去。

### 3. 用 tccd 日志确认请求的真实来源

```bash
log show --last 10m --predicate 'process == "tccd"' | grep -i zcode
```

关键行：

```text
02:04:37 tccd: AUTHREQ_PROMPTING: msgID=4939.39, service=kTCCServiceSystemPolicyAppData,
  subject=Sub:{dev.zcode.app} Resp:{TCCDProcess: identifier=dev.zcode.app, pid=8043, ...}
  accessing={TCCDProcess: identifier=bfs, pid=9326,
             binary_path=/Applications/ZCode.app/Contents/Resources/tools/bfs/bfs}
  requesting={TCCDProcess: identifier=com.apple.sandboxd, pid=4939}

02:04:37 tccd: Prompting policy for hardened runtime; service: kTCCServicePhotos requires
  entitlement com.apple.security.personal-information.photos-library but it is missing ...
02:04:37 tccd: Policy disallows prompt ... access to kTCCServicePhotos denied
```

- 触发者不是 ZCode 主程序直接读文件，而是它自带的搜索工具 **`bfs`**（`Contents/Resources/tools/bfs`），经 `sandboxd` 发起
- 同一时刻还有 Photos 访问请求，但 ZCode 未声明照片库 entitlement，系统**直接拒绝且不弹窗**（所以用户只看到一个提示）

### 4. 复启后的日志：只剩无关的能力缺失告警

```text
02:11:41 tccd: Prompting policy for hardened runtime; service: kTCCServiceAppleEvents requires
  entitlement com.apple.security.automation.apple-events but it is missing ...
```

该条为「无法自动化控制其他 App」的静默拒绝，与本次授权窗无关，也不影响正常使用。

---

## 根因分析

| 层级 | 内容 |
| --- | --- |
| **触发原因** | ZCode 首启时内置 `bfs` 搜索工具遍历本机目录（含其他 App 的容器目录，如 `~/Library/Containers`、`~/Library/Application Support/*`），命中 macOS 的「App 数据保护」，系统因此要求授权 `kTCCServiceSystemPolicyAppData` |
| **直接原因（按钮失灵）** | 该提示窗口由系统进程 `UserNotificationCenter` 承载（layer 8，独立浮窗）；按钮的决策要回传给 tccd 中**仍在等待的那条请求**。一旦发起进程（ZCode / bfs）退出、请求随之失效，窗口就变成孤儿，按钮不再对应任何活请求 → 点击被吞掉、无任何反馈（基于「窗口 owner 为 UserNotificationCenter + 对应进程已全部退出」的实测推断） |
| **表象误导** | 提示窗口坐标恰好覆盖在豆包主窗口内，肉眼看起来像「豆包里的弹窗卡住」，实际与豆包无关 |
| **同族但不同机理** | 与 [2026-10-23 互联网账户僵尸弹窗](records/2026-10-23-macos-internet-accounts-google-reauth-stuck-alert-cannot-become-key-window.md) 不同：那例是 `.appex` 内 `_NSAlertPanel` 的 `canBecomeKeyWindow = NO`（窗口在、进程也会响应），本例是**请求已消失的孤儿窗口**（进程都不在了） |

### 误判方向与反证

| 曾被怀疑 | 反证 |
| --- | --- |
| 弹窗属于豆包，是豆包界面卡死 | `CGWindowList` 显示 owner 为 `UserNotificationCenter`，豆包主窗只是被压住 |
| ZCode 界面卡死导致点不动 | ZCode 主进程此时已不存在，窗口却仍在；卡死的应用不会有独立系统浮窗留存 |
| 只是没点准 / 被遮挡 | 提示层为 layer 8，在普通窗口（layer 0）之上，不存在被遮挡问题 |
| 是病毒 / 恶意行为 | 发起者与访问者都是 ZCode 自带的签名工具 `bfs`，签名校验为官方开发者证书，属正常目录扫描 |

---

## 解决方案与落地操作

### A. 清除孤儿提示窗口（无需重启、无需注销）

```bash
killall UserNotificationCenter
```

- 该系统进程由 launchd 托管，被结束后按需自动重建，不影响其他系统通知
- 本次实测：执行后提示窗口在 3 秒内消失

### B. 复启应用并确认不再复现

```bash
open -a /Applications/ZCode.app
```

- 复启后检查：`CGWindowList` 只有 ZCode 主窗、无 `UserNotificationCenter` 浮窗；`log show` 无新的 `SystemPolicyAppData` 提示

### C. 避免再次触发（按需选择）

1. 真的再弹时直接选『不允许』即可，ZCode 仍能正常使用，只是读不到其他 App 的数据；选过一次后系统会记住，不再反复询问
2. 若确实需要它读其他 App 数据：系统设置 → 隐私与安全性 → **完全磁盘访问权限** 勾选 ZCode，可减少这类目录级提示
3. 让 ZCode 的工作区限定在具体项目目录，避免对整个用户主目录做全盘搜索（`bfs` 扫描范围越大，越容易碰到 App 容器）

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| 孤儿提示窗口（owner `UserNotificationCenter`） | 存在（260×235 @ 725,204，layer 8），按钮无反应 | 已消失 | ✅ |
| ZCode 主进程 | 已退出（pid 8043 不存在） | 正常运行（pid 10429 + 渲染/Helper 子进程） | ✅ |
| ZCode 主窗口 | 有窗无进程 | 存在（255,92，1200×800） | ✅ |
| `SystemPolicyAppData` 再次提示 | 02:04:37 一次 | 复启后 4 分钟无新增 | ✅ |
| 其他系统提示 | Photos 请求被静默拒（缺 entitlement） | 仍为静默拒，不弹窗，不阻塞使用 | ✅ |

---

## 经验沉淀

1. **「系统弹窗压在某应用窗口里」不等于该应用的弹窗**：先用 `CGWindowList` 看 owner。owner 是 `UserNotificationCenter` / `ControlCenter` 这类系统进程时，弹窗属于 TCC / 系统提示体系，排障方向完全不同。
2. **点击完全无反应时，第一件事是确认「发起进程还在不在」**：`pgrep` 查不到应用进程、窗口还留在屏幕上，就是孤儿窗口；此时再点、再等都不会有结果，只能清掉窗口重来。
3. **`killall UserNotificationCenter` 是清这类僵尸系统提示的低风险手段**：它由 launchd 按需重建，不丢数据、不影响其他通知，比重启系统或重启应用快得多。
4. **用 tccd 日志直接读出「谁在要什么权限」**：`log show --predicate 'process == "tccd"' | grep -i <app>` 能看到 `AUTHREQ_PROMPTING` 的 service 名（本例 `kTCCServiceSystemPolicyAppData`）、subject（应用 bundle id）和 accessing 的具体二进制路径。本例因此定位到「真正发起访问的是 ZCode 自带的 `bfs`，不是主程序」。
5. **缺少 entitlement 的 TCC 请求会被静默拒绝、不会弹窗**：日志里的 `requires entitlement ... but it is missing` + `Policy disallows prompt ... denied` 就是这种情况（本例的 Photos、AppleEvents），不要当成「权限申请失败需要修」。
6. **现代 AI 编码客户端普遍自带文件搜索/遍历工具**（ZCode 的 `bfs`），首启全盘扫描很容易撞上 macOS 的 App 数据保护；遇到这类首启权限风暴，允许/拒绝都只是一次性选择，选「不允许」最省事且不影响主流程。

---

## 关键产物与现场位置

- 安装包：`~/Downloads/ZCode-3.18.2-mac-arm64.dmg`（302MB，安装后已删除）
- 应用：`/Applications/ZCode.app`（3.18.2，arm64，`dev.zcode.app`）
- 触发者：`/Applications/ZCode.app/Contents/Resources/tools/bfs`（pid 9326）
- 孤儿窗口：owner `UserNotificationCenter`（pid 18911），260×235 @ (725, 204)，layer 8
- 关键命令：

```bash
# 窗口归属（Swift，无需额外依赖）
swift -e 'import Cocoa; let a = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]; for w in a { print(w[kCGWindowOwnerName as String] ?? "?", w[kCGWindowOwnerPID as String] ?? 0, w[kCGWindowLayer as String] ?? 0) }'

# 授权请求来源
log show --last 10m --predicate 'process == "tccd"' | grep -i zcode

# 清孤儿提示窗口
killall UserNotificationCenter
```

- 本次事件时间：`2026-11-21 02:04`（触发）→ `2026-11-21 02:11`（恢复）

*结论：这个点不动的弹窗不是 ZCode 或豆包画的，而是 macOS 在 ZCode 自带搜索工具 `bfs` 扫描其他 App 目录时弹出的 TCC「访问其他 App 的数据」提示；应用退出后该提示成了孤儿窗口，按钮对应不到任何活请求，所以怎么点都没反应。`killall UserNotificationCenter` 清窗、复启 ZCode 即恢复，之后 4 分钟无复发。*
