# macOS「系统设置 → 互联网账户」重新验证 Google 账户时报「无法验证账户名或密码。」，弹窗「好」按钮点击完全无反应：Internet Accounts 扩展的 `_NSAlertPanel` 无法成为 key window（`canBecomeKeyWindow = NO`）→ 僵尸弹窗；终止扩展进程清窗 + 完整重走 OAuth 后恢复

## 基本信息

- **处理者身份**：DeepSeek Harness Agent（DSH 本机会话，单代理执行；全程只读取证，实际改动只有两步：`kill -TERM` 结束卡死的系统扩展进程、重新走授权流程）
- **问题类型**：macOS 系统设置子系统（Internet Accounts `.appex` 扩展）**僵尸弹窗**——窗口渲染正常、内容显示正常，但无法成为 key window，按钮事件永久不生效；伴随 Google OAuth 重新授权被中断
- **报错时间**：2026-10-23 07:37:26（弹窗出现）；用户 07:52 报障
- **解决确认时间**：2026-10-23 08:03:38（凭据验证成功，Mail 账户自动创建）；用户 08:05 确认「可以了」
- **最终状态**：✅ 已解决。卡死弹窗被清除；Google 账户重新授权成功，`maild` 自动创建 `imap.gmail.com` 账户，通讯录子账户 `active:1 / enabled:1`
- **环境**：macOS 26.6 (25G72)，Apple Silicon MacBook Air；系统代理关闭，FlClash TUN（`utun4 198.18.0.1`，`1/2/7 → utun4`）
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 07:37:16.220 | 用户/系统 | 打开「系统设置 → 互联网账户」；`InternetAccountsSettingsExtension` 启动（pid 12493） |
| 07:37:16.767 | 扩展 | `Account is not authenticated. Prompting.`（该 Google 账户凭据缺失，要求重新验证） |
| 07:37:16.929 | AppKit | `_NSAlertPanel`（window 470）`makeKeyWindow` 失败：`canBecomeKeyWindow` 返回 NO（第一次同类告警） |
| 07:37:18.667 | AppKit | 登录进度 `NSPanel`（window 473）同样 `canBecomeKeyWindow = NO`（第二次） |
| 07:37:19.279 | Safari | 入队并启动 `ASWebAuthenticationSession`：`accounts.google.com/o/oauth2/v2/auth`，`client_id` 为 Apple Internet Accounts 内置 ID，`redirect_uri = com.apple.Internet-Accounts-Settings.extension:/`，scope = `profile email mail.google.com calendar carddav`，`login_hint=ch***@gmail.com` |
| 07:37:25.669 | 用户/系统 | `User closed authentication session window` → 认证窗口被关闭（**OAuth 被取消**） |
| 07:37:25.723 | SafariLaunchAgent | `Failed to fulfill authentication session request … error: Code=1`（WebAuthenticationSession 取消） |
| 07:37:26.011–014 | 扩展/accountsd | 仍尝试 `verify-credentials`：`Completed account credential verification: (null) - Error Domain=com.apple.accounts Code=3`（失败） |
| 07:37:26.058 | AppKit | 弹出错误 `_NSAlertPanel`（window 479），**第三次** `makeKeyWindow … returned NO from -[NSWindow canBecomeKeyWindow]` |
| 07:37:28–07:37:37 | 用户 | 连续点击「好」5 次；日志只有 `trackMouse send action on mouseUp` / `sendActionFrom:` / `sendAction:`，弹窗不消失 |
| 07:52 | 用户 | 在 DSH 报障（附 520×352 截图：黄色警告三角 +「无法验证账户名或密码。」+ 单个「好」按钮） |
| 07:53–07:57 | DSH Agent | 只读取证：`CGWindowList` 定位窗口、AX 抓窗口角色/按钮、`log show` 还原 OAuth 链路、`sample` 两个进程主线程（均空闲）、排除网络问题 |
| 07:58 | DSH Agent | `kill -TERM 12493` → 僵尸弹窗窗口 id=1147 立即消失；系统设置恢复正常 |
| 08:01 | 用户 | 「需要」——要求重新走添加/重新授权流程 |
| 08:02:31 | DSH Agent | `open "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"` 重新打开面板（系统设置 pid 15857 / 扩展 pid 15861）；AX 找到已存在的 Google 账户行 |
| 08:02:44 | DSH Agent | 点击 Google 账户行 → 弹出「请输入账户“ch***@gmail.com”的密码。Google 要求在网页浏览器中完成认证。」→ 点击「打开浏览器」 |
| 08:02:51 | Safari | 新的 `ASWebAuthenticationSession` 启动，Safari 无痕窗口显示 Google 登录页（邮箱已预填，页面可正常加载） |
| 08:03:23–08:03:38 | 用户 | 完成 Google 登录（密码 + 验证码 + 同意授权） |
| 08:03:38.767 | 扩展/accountsd | `Completed account credential verification: <private> - (null)`（**成功**）；`Daemon save called for account … verify=0`；通讯录子账户 `active:1, enabled:1` |
| 08:03:38.810 | maild | 收到 `ACAccountStoreDidChangeNotification`（`com.apple.account.Google`），自动创建 `MFIMAPAccount … imap.gmail.com` |
| 08:05 | 用户 | 确认「可以了」 |

---

## 问题详细描述

用户描述：**「这个悬浮窗，点击『好』按钮没有反应，以及这个是弹出的 google 认证导致的」**。

现场事实：

- 弹窗内容：黄色警告三角 + 文案「无法验证账户名或密码。」+ 底部整行「好」按钮（macOS 26 新版警告样式，260×176 pt，即 520×352 px @2x）
- 弹窗**不是** Google 页面，也不是普通应用弹窗，而是 macOS「系统设置 → 互联网账户」子系统扩展弹出的系统警告
- 点击「好」：无高亮、无动画、无消失；按回车同样无效
- 触发链路上游：用户当时在「系统设置 → 互联网账户」里对一个**已存在**的 Google 账户（`ch***@gmail.com`）重新验证，系统通过 Safari 的 `ASWebAuthenticationSession` 打开 Google 登录页；该窗口在 5.4 秒后被关闭（OAuth 取消），随后系统判定「凭据无法验证」并弹出上述错误
- 账户状态：互联网账户列表中 Google 账户仍在，但「邮件 / 通讯录 / 日历 / 备忘录」开关均为关闭，属于**凭据失效的未授权状态**

---

## 排查过程与关键技术证据

### 1. 先定位弹窗归属：是系统扩展，不是 Google

用 `CGWindowListCopyWindowInfo` 枚举窗口（含 `optionAll`），按尺寸/坐标筛选：

```text
id=1147 pid=465  260x176 @922,326 on=1  系统设置 ::
id=1145 pid=12493 260x176 @922,326 on=0  互联网账户 ::
id=1135 pid=12493 723x625 @690,118 on=0  互联网账户 ::
```

- 宿主窗口：`系统设置`（pid 465），弹窗是挂在「互联网账户」页面上的 **AXSheet**
- 远程视图提供方：`InternetAccountsSettingsExtension`（pid 12493），路径 `/System/Library/ExtensionKit/Extensions/InternetAccountsSettingsExtension.appex`

AX 直接读出弹窗内部结构（这也是确认「文案/按钮都存在」的直接证据）：

```text
pid 465 focused window: role=AXSheet  pos=(922.0, 326.0) size=(260.0, 176.0)
  child AXImage
  child AXStaticText v='无法验证账户名或密码。'
  child AXStaticText v=''
  child AXButton t='好'
```

→ 结论：**弹窗是系统设置的 Internet Accounts 扩展弹的，Google 只是触发了这次重新授权。**

### 2. 还原 Google 认证链路：OAuth 被取消，不是密码错

```bash
log show --start '2026-10-23 07:37:19' --end '2026-10-23 07:37:27' --style compact \
  --predicate 'subsystem == "com.apple.Safari" AND category == "AuthenticationSession"'
```

关键行：

```text
07:37:19.279 Enqueued authentication session request:
  URL = https://accounts.google.com/o/oauth2/v2/auth?response_type=code
        &enable_granular_consent=true&include_granted_scopes=true&prompt=consent
        &client_id=946018238758-…apps.googleusercontent.com
        &redirect_uri=com.apple.Internet-Accounts-Settings.extension:/
        &scope=profile email https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav
        &login_hint=ch***@gmail.com&code_challenge=…&code_challenge_method=S256
07:37:19.291 Starting authentication session …
07:37:25.669 User closed authentication session window … ; canceling session
07:37:25.723 Failed to fulfill authentication session request … error: Code=1 "(null)"
```

`client_id 946018238758-…` 是 **Apple Internet Accounts 内置的 Google OAuth 客户端**，可反向证明这次认证来自「系统设置 → 互联网账户」，而不是 Chrome/Drive/Antigravity 等应用。

扩展侧紧接着的日志：

```text
07:37:26.011 accounts/verify-credentials
07:37:26.014 Completed account credential verification: (null) - Error Domain=com.apple.accounts Code=3
```

→ 认证被取消 → 凭据校验失败 → 弹出「无法验证账户名或密码。」（**备注：这句文案很容易被误读成「Google 密码错了」，本次实测与密码无关，重新登录一次即成功**）

### 3. 「好」按钮为什么点不动：`canBecomeKeyWindow = NO`（核心证据）

同一时段 AppKit 直接打出警告：

```text
07:37:16.929 E InternetAccountsSettingsExtension[12493] [com.apple.AppKit:Window]
  Warning: -[NSWindow makeKeyWindow] called on <_NSAlertPanel: 0xc27825680> windowNumber=470
  which returned NO from -[NSWindow canBecomeKeyWindow].
07:37:18.667 E … <NSPanel: 0xc2791aa80> windowNumber=473 … returned NO from -[NSWindow canBecomeKeyWindow].
07:37:26.058 E … <_NSAlertPanel: 0xc2793b480> windowNumber=479 … returned NO from -[NSWindow canBecomeKeyWindow].
```

系统中连续 3 个面板都无法成为 key window；其中 window 479 就是显示「无法验证账户名或密码。」的那一个。

用户点击的证据（按钮被按下但 action 无效）：

```text
07:37:28.003 (AppKit) trackMouse send action on mouseUp
07:37:28.003 (AppKit) sendActionFrom:
07:37:28.003 (AppKit) sendAction:
07:37:29.410 / 07:37:36.259 / 07:37:37.160 / 07:37:37.927 …（共 5 次）
```

Agent 侧做了三项交叉验证，进一步排除「只是没点到」：

| 验证手段 | 结果 |
| --- | --- |
| AX `AXUIElementPerformAction(button, AXPress)` | 返回 `0`（kAXErrorSuccess），但弹窗不消失 |
| CGEvent 真实鼠标事件（move/down/up，点在按钮中心） | 弹窗不消失 |
| `NSRunningApplication.activate` / AX 激活后按钮变蓝（默认按钮高亮） | 仍然无效 |

补充：取证时该弹窗已位于多个窗口之下（z-order 第 25 位，位于 Antigravity / DeepSeek Harness / ChatGPT / 备忘录 / Chrome 之后），所以「点击落在别的窗口上」确实可能叠加；但激活到前台、按钮变蓝后依旧无效，说明**根因是 key window，不是遮挡**。

### 4. 排除网络/代理因素

```bash
scutil --proxy                     # HTTPEnable/HTTPSEnable/SOCKSEnable/ProxyAutoConfigEnable 全 0
ifconfig utun4                     # inet 198.18.0.1 --> 198.18.0.1
netstat -rn -f inet                # 1 / 2/7 / 4/6 … → utun4（FlClash TUN 接管）
curl -o /dev/null -w '%{http_code} %{time_total}s\n' https://accounts.google.com/   # 302 0.49s
```

恢复过程中扩展自身的 CFNetwork 日志也全部 200：

```text
08:03:38.041 Task <FF1CFCBC-…>.<1> summary for task success {response_status=200, protocol="h2", …}
08:03:38.757 Task <DCEA883A-…>.<1> summary for task success {response_status=200, protocol="h2", …}
```

→ 网络链路正常，与本次故障无关。

### 5. 进程活性检查：不是卡死，是「事件进不去」

```bash
sample 465 2    # System Settings 主线程：NSApplication run → mach_msg（空闲事件循环）
sample 12493 2  # 扩展主线程：NSApplication run → mach_msg（空闲事件循环）
```

两个进程都健康、CPU 空闲，窗口也能正常重绘；问题只出在 key window 状态。

---

## 根因分析

| 层级 | 内容 |
| --- | --- |
| **直接原因** | 对已存在的 Google 账户做「重新验证」时，Safari 的 `ASWebAuthenticationSession` 认证窗口在 5.4 秒后被关闭 → OAuth 取消（`error Code=1`）→ 扩展校验凭据失败（`com.apple.accounts Code=3`）→ 弹出「无法验证账户名或密码。」 |
| **深层原因（按钮失灵）** | 该错误提示由 `InternetAccountsSettingsExtension`（后台 `.appex`，UIElement 性质）以 `_NSAlertPanel` 呈现，但面板 `canBecomeKeyWindow` 返回 **NO**，永远无法成为 key window → 按钮的 target/action 不触发，点击被 `trackMouse` 吞掉。属于 macOS 26.6 该扩展的系统缺陷（同一会话内连续 3 次同类告警） |
| **附加现象** | 弹窗是普通层级窗口（layer 0）且会被其它应用窗口覆盖，进一步降低「点到」的概率；但实测激活到前台后仍无效，故不是主因 |
| **触发时机** | 用户在 07:37 进入「系统设置 → 互联网账户」操作已存在的 Google 账户；凭据此前已失效（服务开关全关） |

### 误判与反证对照

| 曾被怀疑的方向 | 反证 |
| --- | --- |
| Google 账号/密码错误 | OAuth 根本没有提交到密码步骤就 `User closed … canceling session` 了；重新完整走一次即成功 |
| 网络 / 代理 / 墙 | 系统代理关闭但 TUN 正常；`curl accounts.google.com` → 302；扩展自身 CFNetwork 200 |
| 「新增账户失败」 | 账户本就存在（互联网账户里可见 `ch***@gmail.com`），本次是**重新验证** |
| 只是被其它窗口挡住 | 确实被挡住；但激活、按钮变蓝、AX 按压均无效 → 根因是 `canBecomeKeyWindow = NO` |
| 系统设置/扩展进程卡死 | `sample` 显示两者主线程均为空闲事件循环；窗口正常渲染 |

---

## 解决方案与落地操作

### A. 清除僵尸弹窗（二选一，均无需重启/注销）

```bash
# 推荐：只结束 Internet Accounts 扩展，系统设置主体不受影响，弹窗立即消失
pkill -f InternetAccountsSettingsExtension

# 备选：强退「系统设置」（⌥⌘⎋ → 系统设置 → 强制退出）
```

> 本次实测：`kill -TERM 12493` 后窗口 id=1147 在 2 秒内消失，系统设置恢复正常。

### B. 重新授权（真正恢复账户）

1. 打开「系统设置 → 互联网账户」
2. 点击列表中已存在的 **Google** 账户（不是「添加账户…」）
3. 系统弹窗提示「请输入账户…的密码。Google 要求在网页浏览器中完成认证。」→ 点 **打开浏览器**
4. 在 Safari 无痕窗口完成 Google 登录（邮箱 → 密码 → 两步验证 → 同意授权）
5. **不要中途关闭这个认证窗口**——关掉即等于取消 OAuth，会再次触发「无法验证账户名或密码。」
6. 授权完成后回到「互联网账户」，按需打开 **邮件 / 通讯录 / 日历 / 备忘录** 开关

本次授权完成后系统自动落地：

- 扩展：`Completed account credential verification: … (null)`（无错误）
- accountsd：`Daemon save called for account … verify=0`
- 通讯录：子账户 `active:1, enabled:1`
- Mail：`MFIMAPAccount "c…@g…" imap.gmail.com` 自动创建

---

## 验证与效果

| 验证项 | 修复前 | 修复后 | 状态 |
| --- | --- | --- | --- |
| 僵尸弹窗（CGWindow id=1147） | 存在且 on-screen、按钮无效 | 已消失 | ✅ |
| OAuth 会话 | `User closed … canceling session`，`Code=1` | 完整完成，扩展网络请求 200 | ✅ |
| 凭据校验 | `Error Domain=com.apple.accounts Code=3` | `Completed … (null)`（成功） | ✅ |
| accountsd 持久化 | 无 | `Daemon save called … verify=0` | ✅ |
| 通讯录子账户 | 无 | `active:1, enabled:1` | ✅ |
| Mail 账户 | 未配置 | `MFIMAPAccount … imap.gmail.com` | ✅ |
| 弹窗复发 | — | 08:03 之后无同类 `canBecomeKeyWindow` 告警（唯一一条来自认证辅助进程，非本弹窗） | ✅ |

---

## 经验沉淀

1. **「系统弹窗点不动」先验证它是不是 key window**：一条日志即可定性——
   `log show --predicate 'eventMessage CONTAINS "canBecomeKeyWindow"'`。
   出现 `makeKeyWindow … returned NO from -[NSWindow canBecomeKeyWindow]`，说明窗口可见但永远接不到事件，点击/回车/`AXPress` 全部无效。
2. **macOS 系统设置的子系统弹窗来自独立 `.appex` 进程**（互联网账户、隐私、扩展等），僵尸窗口只需结束对应扩展进程即可清除，不必重启系统设置、更不必重启 Mac。
3. **「无法验证账户名或密码。」≠ 密码错**：先查 Safari `AuthenticationSession` 日志有没有 `User closed … canceling session`。系统级 Google 账户重新授权走的是 `ASWebAuthenticationSession`，关窗 = 取消。
4. **判断弹窗归属用 `CGWindowList` + AX，而不是只看截图**：截图无法区分窗口是否 key、属于哪个进程；窗口号/owner PID/尺寸/坐标 + AX 角色（`AXSheet`/`AXButton`）才能定位。
5. **系统扩展的按钮可能「AXPress 返回成功但什么都不做」**（ViewBridge 远程视图事件链路异常），验收标准必须是「窗口真的消失/状态真的变化」，不能只看 API 返回值。
6. **先分辨「新增账户」还是「重新验证已有账户」**：互联网账户列表里已有条目时点该条目，走的是补授权，入口和文案完全不同，可避免按「添加账户失败」方向误判。

---

## 关键产物与现场位置

- 僵尸窗口：`CGWindow id=1147`（owner：系统设置 pid 465），260×176 pt @ (922, 326)；扩展侧对应 `id=1145`
- 系统扩展：`/System/Library/ExtensionKit/Extensions/InternetAccountsSettingsExtension.appex`
- 关键日志命令：
  ```bash
  log show --predicate 'subsystem == "com.apple.Safari" AND category == "AuthenticationSession"' --style compact
  log show --predicate 'eventMessage CONTAINS "canBecomeKeyWindow"' --style compact
  log show --predicate 'process == "InternetAccountsSettingsExtension"' --style compact
  ```
- OAuth 参数：`accounts.google.com`，`client_id=946018238758-…`（Apple Internet Accounts 内置），`redirect_uri=com.apple.Internet-Accounts-Settings.extension:/`，scope 含 `mail.google.com / calendar / carddav`
- 涉及账户：`ch***@gmail.com`（已脱敏）
- 处置命令：`pkill -f InternetAccountsSettingsExtension`
- 本次事件时间：`2026-10-23 07:37`（故障）→ `2026-10-23 08:03`（恢复）

*结论：这个「点不动的弹窗」不是 Google 弹的，而是 macOS 系统设置 Internet Accounts 扩展在 Google 重新授权被取消后弹出的错误提示；「好」点不动是该扩展的 `_NSAlertPanel` 无法成为 key window（macOS 26.6 缺陷）。终止扩展进程清掉僵尸窗口，再完整走一遍 Google OAuth 即可恢复。*
