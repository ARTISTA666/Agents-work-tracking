# Antigravity 桌面登录报 `loadCodeAssist: EOF`，重试时 OAuth 回调超时，重新授权后恢复

## 基本信息

- **处理者身份**：Codex 主排查与桌面验证，协作 Agent 分别核对本机日志和 Google 官方资料。用户完成 Google 登录确认。
- **问题类型**：桌面账号初始化请求中断，随后一次 OAuth 重试等待本机回调超时。
- **报错时间**：2026-11-26 14:33 左右（UTC+8）。
- **解决确认时间**：2026-11-26 14:49 左右（UTC+8）。
- **最终状态**：✅ 登录恢复。浏览器显示认证成功，桌面端进入主界面并显示原有项目。
- **环境**：macOS，Google 签名的 Antigravity App 2.35.2，Safari，FlClash 本地代理。
- **关联仓库**：[Agents-work-tracking](https://github.com/ARTISTA666/Agents-work-tracking)

### Agent 分工与时间线

| 时间（UTC+8） | 负责方 | 关键动作与结论 |
| --- | --- | --- |
| 14:33 | Antigravity | 浏览器回调后，账号初始化请求出现 `loadCodeAssist: EOF`。 |
| 14:35–14:36 | Codex、本机诊断 Agent | 查明语言服务使用 FlClash HTTP 代理。对同一域名分路径测试，HTTP 代理一度在隧道建立后中断，直连和 SOCKS 同批可达。HTTP 代理随后复测可达。 |
| 14:36–14:41 | Codex、用户 | 发起第一轮 OAuth 重试，核实待登录账号的 Google One 页面显示 Google AI Pro 已生效。该轮等待本机回调约五分钟后超时。 |
| 14:44–14:49 | Codex、用户 | 发起新请求并确认桌面端的本机回调监听。用户完成 Google 确认，Safari 显示认证成功。 |
| 14:49 左右 | Codex | 在 Safari 允许这一次打开应用，核验桌面端主界面与原有项目。 |

## 问题详细描述

用户刚开通 Google AI Pro，Antigravity 桌面端仍停在账号初始化错误页。界面给出的错误为：

```text
There was an unexpected issue setting up your account.
failed to get load code assist response: Post "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist": EOF
```

第一轮重试的界面错误变为 `context deadline exceeded`。本机日志把这次超时定位在等待浏览器回调的阶段。

## 排查过程与关键技术证据

### 1. 核对会员、客户端与实际代理

- 在 Google One 的 `Current plan` 区域确认同一个待登录账号的 Google AI Pro 已生效。
- 用 `codesign --verify --strict <Antigravity.app 路径>` 核验客户端，签名为 Google LLC。用 `scutil --proxy` 查看 macOS 系统代理，再核对语言服务进程的 `HTTP_PROXY`、`HTTPS_PROXY` 环境，确认后台请求经 FlClash 本地 HTTP 代理。

### 2. 对同一 Google 域名分路径测试

仅访问主机根路径，记录 HTTP 响应与代理隧道握手结果。

```bash
url=https://daily-cloudcode-pa.googleapis.com/
proxy=127.0.0.1:7890
curl -sS -o /dev/null --connect-timeout 4 --max-time 7 -w 'HTTP %{http_code} CONNECT %{http_connect}\n' --proxy "http://$proxy" --noproxy '' "$url"
curl -sS -o /dev/null --connect-timeout 4 --max-time 7 -w 'HTTP %{http_code}\n' --noproxy '*' "$url"
curl -sS -o /dev/null --connect-timeout 4 --max-time 7 -w 'HTTP %{http_code}\n' --proxy "socks5h://$proxy" --noproxy '' "$url"
```

- **首轮**：HTTP 代理返回 `CONNECT 200`，但后续 TLS 握手中断（curl 35，目标 HTTP 状态 `000`）。直连和 SOCKS 均收到根路径的 `404`。
- **复测**：该域名经 HTTP 代理、直连和 SOCKS 各测试三次，全部收到根路径 `404`。登录域名经 HTTP 代理另有一次超时。
- 根路径 `404` 说明探针成功建立 TLS 并收到 HTTP 响应。账号权限需通过正常登录流程确认。

### 3. 区分浏览器回调与账号初始化

语言服务日志在 14:33:35 连续记录 `loadCodeAssist: EOF`。第一轮重试从 14:36:39 等待本机回调，于 14:41:39 超时。新一轮请求建立后，`netstat -anv -p tcp` 显示语言服务同时在 IPv4 与 IPv6 回环地址监听新端口。

## 根因分析

| 阶段 | 直接原因 | 深层原因与证据边界 |
| --- | --- | --- |
| 首次账号初始化 | `loadCodeAssist` 请求在收到完整响应前断开。 | 应用使用的 HTTP 代理路径一度复现 TLS 中断，随后恢复。证据指向这条链路的间歇性连接故障，具体中断点未定位。 |
| 第一轮登录重试 | OAuth 流程在五分钟内未收到浏览器回调，桌面报 `context deadline exceeded`。 | 日志确认等待回调超时。触发这次超时的具体环节未确认。 |

## 解决方案与落地操作

1. HTTP 代理路径恢复响应后，从 Antigravity 的登录入口重新发起 OAuth 请求。
2. 在 Safari 使用已核实开通 Pro 的账号，完成 Google 的来源确认与登录。
3. Safari 显示认证成功后，在打开 Antigravity 的提示里选择单次「允许」，回到桌面端核验。

## 验证与效果

| 验证项 | 操作 | 实际结果 | 状态 |
| --- | --- | --- | --- |
| Google AI Pro | 查看同一账号的 Google One 套餐页 | `Current plan` 为 Google AI Pro | 通过 |
| 浏览器认证 | 使用新发起的请求完成 Google 登录 | Safari 显示 `Google Antigravity Auth Success` | 通过 |
| 桌面登录 | 检查 Antigravity 窗口 | 显示 `New Conversation` 和 `Projects`，可见原有项目 | 通过 |

## 经验沉淀

- 登录后出现 `loadCodeAssist: EOF` 时，先确认桌面后台使用的代理，再用同一域名做分路径复测。浏览器能打开 Google 只说明浏览器自己的请求可达。
- 遇到 `context deadline exceeded`，先从日志确认超时阶段。若卡在 OAuth 回调，重新发起请求并使用最新打开的浏览器标签页。
- 恢复验收以桌面主界面为准，浏览器的认证成功页是流程中的一个检查点。

## 关键产物与现场位置

- 语言服务日志 `~/Library/Logs/Antigravity/language_server.log`。排查时关注 `loadCodeAssist`、`EOF` 和 OAuth 回调时间戳。
- [Google 官方论坛同类 EOF 案例](https://discuss.ai.google.dev/t/bug-macos-27-0-antigravity-2-19-1-desktop-ide-and-cli-fail-with-loadcodeassist-eof-after-successful-authentication/187290/2)
- [本仓库 Antigravity 后台进程代理排查](2026-10-22-antigravity-startup-proxy-update-and-gemini-egress-fix.md)
