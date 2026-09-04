# Agents Work Tracking

AI 代理工具（Antigravity、ZCode、ChatGPT、Gemini 等）在日常使用中遇到的报错、故障、网络问题与代理配置的深度排查记录。每篇记录均包含完整的报错信息、排查过程、根因分析、解决方案与验证结果，可作为同类问题的参考手册。

## 目录结构

```
.
├── README.md                 # 本文件
├── records/                  # 排查记录（按日期命名，Markdown 格式）
│   ├── 2026-09-02-*.md
│   ├── 2026-09-03-*.md
│   └── 2026-09-04-*.md
└── scripts/                  # 排查过程中编写的辅助脚本
    └── apibai-retry-proxy.py
```

## 记录列表

按时间倒序排列。

### 2026-09-04

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md](records/2026-09-04-antigravity-400-user-location-not-supported-taiwan-ip-region-restriction.md) | Antigravity Agent 运行 44 秒后弹窗 `Agent execution terminated due to error`，后端返回 HTTP 400 `User location is not supported for the API use.` | 台湾中华电信出口 IP 不在 Google Antigravity 内部 Daily 端点（`daily-cloudcode-pa.googleapis.com`）的地域白名单中；该内部端点策略与公开 Gemini API 不一致 | ✅ 已解决（切换节点 + 重启，14 次 API 调用全恢复） |
| [flclash-not-running-dns-pollution-macos-network-troubleshooting.md](records/2026-09-04-flclash-not-running-dns-pollution-macos-network-troubleshooting.md) | FlClash 节点疑似全失效、Google 报地区限制、Antigravity 用不了；系统 DNS 配置 8.8.8.8 遭 GFW 污染 | FlClash 客户端根本未运行（进程/端口/TUN 全空）；系统 DNS 长期用 8.8.8.8 致 DNS 污染注入；国内 DoH 对被墙域名也返回污染结果 | ✅ 已解决（启动 FlClash 规则模式+TUN、修正系统 DNS 为国内 DNS、添加开机自启） |
| [chatgpt-unsupported-country-clash-meta-migration.md](records/2026-09-04-chatgpt-unsupported-country-clash-meta-migration.md) | ChatGPT 登出后再登录报 `unsupported_country_region_territory`；Whoer 显示出口新加坡但 DNS 泄漏中国；Google/Antigravity 需固定节点与 GPT 换节点冲突 | 节点名称标新加坡但实际 IP 归属香港（OpenAI 对港封锁）；ClashX Meta 仅劫持 `0.0.0.0:53` 漏 IPv6 致 DNS 泄漏；老旧客户端 TUN 重载断网 | ✅ 已解决（迁移至 FlClash、彻底卸载 ClashX Meta、台湾原生节点） |

### 2026-09-03

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [zcode-400-invalid-request-long-context.md](records/2026-09-03-zcode-400-invalid-request-long-context.md) | ZCode 超长会话调用 glm-5.3-flash 间歇报 400 `Invalid request body` | `ai_sdk_options` 全量序列化致缓存失效，免费中转超时被误报为参数错误 | ✅ 已解决 |
| [zcode-apibai-retry-proxy.md](records/2026-09-03-zcode-apibai-retry-proxy.md) | ZCode 调用 api.b.ai 频繁 401 中断 | 本地自动重试中转与 chunked 协议 Bug | ✅ 已解决（含 `scripts/apibai-retry-proxy.py`） |

### 2026-09-02

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [gemini-web-connection-error.md](records/2026-09-02-gemini-web-connection-error.md) | Gemini 网页端「网络连接失败」 | 网络代理配置问题 | ✅ 已解决 |

## 按问题类型快速索引

| 问题类型 | 相关记录 |
| --- | --- |
| **地域限制 / IP 白名单** | Antigravity 400 User location not supported、ChatGPT unsupported country |
| **代理客户端故障** | FlClash 未运行、ClashX Meta 架构缺陷与迁移 |
| **DNS 污染 / 泄漏** | FlClash 8.8.8.8 污染、ClashX Meta IPv6 DNS 泄漏 |
| **API 报错 / 参数错** | ZCode 400 Invalid request body、ZCode 401 中断 |
| **Antigravity 专项** | Antigravity 400 地域限制、FlClash 排查中涉及 Antigravity 连通性 |
| **macOS 网络配置** | FlClash DNS 修正与开机自启、ClashX Meta 彻底卸载 |

## 记录格式规范

每篇记录遵循统一结构：

1. **标题** — 长标题，包含报错关键字、根因与结果
2. **基本信息** — 处理者身份、问题类型、报错/解决时间、最终状态、关联仓库
3. **Agent 分工与时间线** — 表格形式，按时间记录各方动作与结论
4. **问题详细描述** — 用户反馈的表象与工作环境
5. **排查过程与关键技术证据** — 分步骤，每步含执行命令、证据发现、结论
6. **根因分析** — 分层归因（直接原因/深层原因/附加现象），含对比表格
7. **解决方案与落地操作** — 可执行的步骤与命令
8. **验证与效果** — 表格形式，逐项列出验证命令、实际结果、状态
9. **经验沉淀与后续建议** — 可复用的教训与最佳实践
10. **关键产物与现场位置** — 配置文件路径、日志位置、关键 ID、关联链接（不含密钥）

## 说明

- 所有记录中的 IP 地址、Trace ID、配置路径均为排查时的真实现场信息，便于回溯
- 涉及密钥、Token、个人隐私的内容已脱敏或省略
- 记录中提到的代理节点名称与实际出口 IP 可能不一致（机场运营商标注问题），以实测 `curl https://ipinfo.io/json` 结果为准
- 各 AI 平台的地域白名单相互独立，不可根据一个平台的可用性类推另一个平台
