# Agents Work Tracking

AI 代理工具（Antigravity、ZCode、ChatGPT、Gemini、Qoder 等）在日常使用中遇到的报错、故障、网络问题与代理配置的深度排查记录。每篇记录均包含完整的报错信息、排查过程、根因分析、解决方案与验证结果，可作为同类问题的参考手册。

## 目录结构

```
.
├── README.md                 # 本文件
├── records/                  # 排查记录（按日期命名，Markdown 格式）
│   ├── 2026-09-02-*.md
│   ├── 2026-09-03-*.md
│   ├── 2026-09-04-*.md
│   ├── 2026-10-17-*.md
│   ├── 2026-10-22-*.md
│   ├── 2026-10-23-*.md
│   ├── 2026-10-24-*.md
│   ├── 2026-10-28-*.md
│   ├── 2026-10-29-*.md
│   └── 2026-11-21-*.md
└── scripts/                  # 排查过程中编写的辅助脚本
    ├── apibai-retry-proxy.py
    ├── antigravity-silent-check.sh   # Antigravity 出口静默自检（真实调用）
    ├── antigravity-node-probe.sh     # Antigravity 逐节点静默体检（隔离 mihomo + agy）
    ├── qoder-add-bypass.sh           # Qoder 域名加入 macOS 代理绕过列表（直连，幂等，首轮）
    ├── qoder-rollback-bypass.sh      # Qoder 绕过列表回滚（恢复修复前原始条目，首轮）
    ├── qoder-clash-direct.sh         # 第二轮：mihomo 规则置顶 qoder DIRECT + 备份 + 热重载（幂等，运行时文件，会被重建清空）
    ├── qoder-clash-rollback.sh       # 第二轮：移除运行时 qoder DIRECT 规则并热重载
    ├── qoder-flclash-persist.sh          # 第三轮：qoder DIRECT 写入持久库 database.sqlite 的 rules 表（备份/退出/写库/重启/校验，幂等）
    ├── qoder-flclash-persist-rollback.sh # 第三轮：删除持久库 qoder 规则并重启回滚
    ├── codex-desktop-send-block-check.sh  # Codex 桌面版发送被禁用：check 诊断 / apply 改回 local / rollback（幂等，改动前备份）
    ├── chatgpt-dot-entry-provider-check.sh  # 桌面版 dot 入口消失：check 诊断 / apply 改 model_provider=openai / rollback（幂等，改动前备份）
    ├── qoder-httpdns-ip-direct.sh          # 第四轮：Qoder 自解析裸 IP 绕过分流 → 持久库 IP_CIDR→DIRECT：check / apply / rollback（幂等，改动前备份）
    ├── chatgpt-ai-node-stability.sh        # ChatGPT 桌面版 cf_clearance 失效：检测/固定 AI 分组出口稳定节点：check / apply / rollback（改动前备份）
    ├── gemini-web-egress-pin.sh            # Gemini 网页「不支持你所在地区」：把 gemini.google.com 固定到干净美国出口：check / apply / rollback（幂等，改动前备份，热重载）
    ├── default-egress-pin.sh               # 默认分流出口固定到干净节点（防 400 地区拒绝）：写 FlClash 持久库 selected_map + 退/重启复验：check / apply / rollback
    ├── antigravity-gemini-healthcheck.mjs  # Gemini 报错定性分流：按错误串区分「地域拒绝」与「请求构造被拒」，并汇总 App 版本/Squirrel 滞留、日志计数、代理 chains、界面错误卡
    ├── qoder-win-clash-verge-direct.ps1    # 第五轮（Windows）：Clash Verge 规则覆写补 qoder.com/.sh DIRECT：check / apply / rollback（自动定位当前订阅覆写文件、备份、幂等、重启复验）
    └── qoder-win-mihomo-pipe-watch.ps1     # 第五轮（Windows）：TCP 控制口未开时经命名管道轮询 /connections（HTTP/1.0 防 chunked），过滤 qoder/AWS/兜底组流量去重落盘
```

## 记录列表

按时间倒序排列。

### 2026-11-21

| 文件 | 问题摘要 | 根因 | 状态 |
| --- | --- | --- | --- |
| [zcode-appdata-tcc-prompt-orphan-unresponsive.md](records/2026-11-21-zcode-appdata-tcc-prompt-orphan-unresponsive.md) | ZCode 3.18.2 首次启动弹「“ZCode.app”想访问其他 App 的数据」，『允许』『不允许』点击全无反应；提示视觉上压在豆包窗口内，易误判为豆包或 ZCode 界面卡死 | 两层：① **触发**——ZCode 自带 `bfs` 搜索工具（`Contents/Resources/tools/bfs`）遍历其他 App 容器目录，命中 macOS App 数据保护（`kTCCServiceSystemPolicyAppData`）；② **按钮失灵**——提示窗口由系统进程 `UserNotificationCenter` 承载（layer 8 浮窗），发起进程（ZCode pid 8043 / bfs pid 9326）退出后授权请求失效，窗口成孤儿，按钮对应不到任何活请求。判据：`CGWindowList` 看 owner + `pgrep` 查发起进程 + `log show --predicate 'process == "tccd"'` 看 service 名 | ✅ 已解决（`killall UserNotificationCenter` 清窗（3 秒内消失）+ 复启 ZCode（pid 10429），复启后 4 分钟无 `SystemPolicyAppData` 复发；同刻 Photos / AppleEvents 缺 entitlement 属静默拒绝，不弹窗也不阻塞使用） |

### 2026-10-29

...(original rows)
