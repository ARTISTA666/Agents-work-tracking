#!/bin/bash
# Antigravity × Gemini 静默自检
# ------------------------------------------------------------------
# 作用：不弹窗、不改任何设置，只做一次真实的模型调用，
#       判断「当前出口 IP」是否被 Antigravity 内部端点
#       daily-cloudcode-pa.googleapis.com 的地区校验接受。
#
# 原理：Antigravity 的地区校验发生在认证之后（业务层），
#       所以拿不到凭据的裸请求（无认证 curl）永远只返回 401，
#       无法用来判断地区；必须用官方 CLI 走一次带账号的真实调用。
#
# 用法：bash antigravity-silent-check.sh
# 退出码：0 = 可用；1 = 当前出口被地区拒绝；2 = 环境/网络异常
# ------------------------------------------------------------------
set -u

AGY="${AGY:-$HOME/.local/bin/agy}"
if ! command -v "$AGY" >/dev/null 2>&1; then
  echo "❌ 找不到 Antigravity CLI（agy）：$AGY"
  echo "   可设置 AGY=/path/to/agy 后重试"
  exit 2
fi

IP=$(curl -s -m 10 -4 https://api.ipify.org 2>/dev/null)
LOC=$(curl -s -m 10 -4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^loc=/{print $2}')
echo "当前出口：${IP:-未知}  (${LOC:-未知})"
echo "静默请求 Antigravity 后端（约 10~20 秒）..."

OUT=$("$AGY" -p "Reply with exactly: PONG" --print-timeout 90s 2>&1)

if echo "$OUT" | grep -q "User location is not supported"; then
  echo "❌ 结论：Google 拒绝当前出口 IP —— Antigravity 会报「User location is not supported」"
  echo "   处理：在 FlClash 里换节点（已验证可用：日本JP-HY2 / 新加坡SG-HY2）"
  exit 1
elif echo "$OUT" | grep -q "PONG"; then
  echo "✅ 结论：Antigravity 后端正常，Gemini 可以调用"
  exit 0
else
  echo "⚠️ 结果异常（可能是节点不稳或临时网络抖动），原始输出："
  echo "$OUT" | tail -5
  exit 2
fi
