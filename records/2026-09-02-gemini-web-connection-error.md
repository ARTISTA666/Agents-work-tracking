# Gemini 网页端“网络连接失败”排障记录

## 基本信息

- **处理者身份**：OpenAI Codex（本次会话中的 AI 协作代理）
- **问题类型**：Gemini Web 已登录状态无法发送消息
- **解决确认时间**：2026-09-02 16:59:45（Asia/Shanghai，UTC+8）
- **对应 UTC 时间**：2026-09-02 08:59:45 UTC
- **故障首次发生时间**：用户未提供，无法准确记录
- **最终状态**：已解决

## 问题详细描述

用户在 Chrome 普通窗口中打开 Gemini 网页端。页面和已登录账号能够正常加载，但发送消息时失败，左下角提示：

`Check your internet connection and try again`

与此同时，Antigravity 可以正常使用，因此电脑并非完全断网。最初需要判断问题属于以下哪一类：

1. Google/Gemini 服务端故障；
2. 当前代理节点、IP 或地区限制；
3. Google 账号风控；
4. Chrome 主配置中的 Cookie、站点数据、缓存或扩展异常。

## 关键证据

### 1. 普通窗口失败

Gemini 页面能够打开，但发送请求失败并出现网络连接提示。这说明网页静态内容可以加载，故障发生在实际请求阶段，不能仅凭提示认定为本地断网。

### 2. 控制台错误

Chrome DevTools 中观察到：

- Gemini 请求被重定向到 `https://www.google.com/sorry/index?...continue=https://gemini.google.com/...`；
- 随后出现 CORS 错误：响应未包含允许 Gemini 来源访问的 `Access-Control-Allow-Origin`；
- 请求最终显示 `net::ERR_FAILED`；
- 另有 `googletagmanager.com` 请求显示 `net::ERR_BLOCKED_BY_CLIENT`，说明浏览器中存在客户端拦截，但该请求属于统计相关流量，不能据此直接认定它是 Gemini 主请求失败的根因。

Gemini 前端最终把底层请求失败统一显示成了较笼统的网络错误提示。

### 3. 无痕模式对照测试

- 无痕窗口、未登录状态：Gemini 可以使用；
- 无痕窗口登录同一个 Google 账号：Gemini 仍可以使用；
- Chrome 普通窗口、同一个账号：无法发送消息。

这一组对照排除了以下主要可能：

- Google 账号本身不可用；
- 当前网络或代理节点完全不可用；
- Gemini 网页端发生普遍性故障。

问题范围因此收敛到 Chrome 普通配置环境，重点是该配置中的 Cookie、登录会话或站点存储状态。

## 处理过程

1. 打开 Chrome 站点数据管理页面：`chrome://settings/content/all`。
2. 搜索并删除与以下域名相关的站点数据：
   - `gemini.google.com`
   - `google.com`
   - `accounts.google.com`
3. 重新打开 Gemini 并进行发送测试。
4. 用户确认：删除后恢复正常，问题解决。

由于第一步清理站点数据后已经恢复，后续“关闭全部扩展并逐个排查”的备选步骤不再需要执行。

## 结论

### 已确认

故障来自 Chrome 普通配置环境中的 Google/Gemini 本地站点状态；清除相关站点数据后，Gemini 网页端恢复正常。

### 高概率根因

Cookie、登录会话或站点存储中存在过期、冲突或异常状态，使 Gemini 的已登录请求走到了 Google `/sorry/` 页面，继而触发跨域失败。

### 尚未确认

现有证据无法确定具体损坏的是哪一个 Cookie、缓存项或浏览器存储字段，因此不把更细粒度原因写成确定事实。

## 复用排障顺序

以后遇到“Gemini 页面能打开，但发送时提示检查网络”的情况，可依次检查：

1. 用无痕窗口测试；
2. 在无痕窗口登录同一账号再测试；
3. 若无痕登录后正常，优先清理 Gemini、Google 和 Google Accounts 的站点数据；
4. 若仍失败，再暂时关闭广告拦截、隐私保护、油猴、翻译及请求修改类扩展；
5. 只有无痕与普通窗口均失败时，再重点检查节点、IP、账号风控或 Google 服务状态。

## 结果验证

- **修复操作**：删除 Google/Gemini 相关站点数据
- **用户反馈**：“删除之后解决了”
- **验证结论**：修复有效
