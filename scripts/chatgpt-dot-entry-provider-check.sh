#!/usr/bin/env bash
# ChatGPT 桌面版（ChatGPT.app）侧栏 dot 入口消失：诊断与修复
#
# 根因（2026-10-22 实测）：
#   侧栏 dot 入口依赖 orbit 能力，该能力带 requiresFirstPartyInference: true。
#   服务端 gate 3683713372 生效时，App 会校验本地 config.toml 的 model_provider：
#       (model_provider ?? "openai") === "openai"
#   只要不是字面量 "openai"（例如 "custom"），orbit 能力即判 false —— 侧栏 dot 入口
#   与听写（dictation）等同类入口被静默隐藏。网页端 chatgpt.com/dots 不读本地配置，所以正常。
#
#   判别特征：网页端 dot 正常 + 桌面侧栏无 dot + 听写麦克风也消失 + model_provider 非 openai。
#
# 幂等：apply 前自动时间戳备份；已为 openai 则跳过；rollback 还原最近一次备份。
# 用法：
#   bash chatgpt-dot-entry-provider-check.sh check     # 只读诊断（默认）
#   bash chatgpt-dot-entry-provider-check.sh apply     # 修复：model_provider 改为 openai（需先退出应用）
#   bash chatgpt-dot-entry-provider-check.sh rollback  # 还原最近一次 apply 的备份
set -u

CFG="$HOME/.codex/config.toml"
STATE="$HOME/.codex/.codex-global-state.json"
APP="/Applications/ChatGPT.app"
PY="${PYTHON:-python3}"
PROVIDER="$(grep -m1 '^[[:space:]]*model_provider[[:space:]]*=' "$CFG" 2>/dev/null | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')"
PROVIDER="${PROVIDER:-openai（未显式设置，默认 openai）}"

if [ ! -f "$CFG" ]; then echo "找不到配置文件: $CFG"; exit 1; fi

running() { pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT$" >/dev/null; }

# ---------- 只读诊断 ----------
check() {
  echo "=== 应用 ==="
  [ -f "$APP/Contents/Info.plist" ] && \
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null
  running && echo "进程: 运行中" || echo "进程: 未运行"

  echo
  echo "=== 本地配置（修复点）==="
  echo "model_provider = $PROVIDER"
  grep -n -A4 '^\[model_providers\.' "$CFG" 2>/dev/null | head -20
  echo "备份文件:"
  ls -1t "$HOME/.codex"/config.toml.bak-dot-* 2>/dev/null | head -3 || echo "  （无）"

  echo
  echo "=== dot 是否还在（应 available/active）==="
  [ -f "$STATE" ] && "$PY" - "$STATE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); a=d.get('electron-persisted-atom-state',{})
prof=a.get('cloud-aeon-profiles-v1') or {}
sel=a.get('primary-aeon-selection-v1') or {}
sel=sel.get('response',{}).get('selection',{})
print("primary dot:", {k:sel.get(k) for k in ('aeon_id','available','messaging_room_id')})
for key,val in prof.items():
    if isinstance(val,dict):
        p=val.get('profile') or {}
        print(f"dot profile: status={val.get('status')} kind={p.get('aeon_kind')} paused={p.get('is_paused')} updated_at={p.get('updated_at')}")
PY

  echo
  if [ "$PROVIDER" = "custom" ]; then
    echo ">>> 判定：model_provider=custom —— 会触发「第一方推理」门控，桌面端隐藏 dot 入口与听写（命中本故障）"
    echo ">>> 修复：先完全退出 App，再执行：bash $0 apply"
  elif [ "$PROVIDER" = "openai" ]; then
    echo ">>> 判定：model_provider=openai（或未设置）—— 不命中本故障；若仍无入口请查 App 日志与账号资格"
  else
    echo ">>> 判定：model_provider=$PROVIDER（非 openai）—— 同样会触发门控，命中本故障"
    echo ">>> 修复：先完全退出 App，再执行：bash $0 apply"
  fi
}

# ---------- 修复 ----------
apply() {
  if running; then
    echo "应用正在运行，请先完全退出（Cmd+Q / 菜单「退出 ChatGPT」）后再执行 apply。"
    exit 1
  fi
  if [ "$PROVIDER" = "openai" ]; then
    echo "已是 openai / 未显式设置，无需修改。"; exit 0
  fi
  BAK="$HOME/.codex/config.toml.bak-dot-$(date +%Y%m%d-%H%M%S)"
  cp -p "$CFG" "$BAK" && echo "已备份: $BAK"
  # 兼容原值不是 custom 的情况：统一改为 openai；保留 [model_providers.custom] 定义
  "$PY" - "$CFG" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s2,n=re.subn(r'(?m)^([ \t]*model_provider[ \t]*=[ \t]*)"[^"]*"', r'\1"openai"', s, count=1)
if n==0:
    s2=re.sub(r'(?m)^(model[ \t]*=[ \t]*"[^"]*"\n)', r'\1model_provider = "openai"\n', s, count=1)
open(p,'w',encoding='utf-8').write(s2)
print("model_provider 已改为 openai")
PY
  grep -n '^[[:space:]]*model_provider' "$CFG"
  echo
  echo "完成。请重新打开 ChatGPT.app，切到 ChatGPT/Codex 侧栏查看 dot 入口是否恢复。"
  echo "回滚：bash $0 rollback"
}

# ---------- 回滚 ----------
rollback() {
  if running; then
    echo "应用正在运行，请先完全退出后再 rollback。"; exit 1
  fi
  BAK="$(ls -1t "$HOME/.codex"/config.toml.bak-dot-* 2>/dev/null | head -1)"
  [ -n "$BAK" ] || { echo "没有可用的备份。"; exit 1; }
  cp -p "$BAK" "$CFG" && echo "已还原: $BAK -> $CFG"
  grep -n '^[[:space:]]*model_provider' "$CFG"
}

case "${1:-check}" in
  check) check ;;
  apply) apply ;;
  rollback) rollback ;;
  *) echo "用法: bash $0 {check|apply|rollback}"; exit 2 ;;
esac
