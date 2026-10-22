#!/usr/bin/env bash
# Codex 桌面版（ChatGPT.app）「发消息点击没反应」诊断与修复
#
# 根因（2026-10-22 实测）：输入框发送按钮的前置校验要求「已选中云端环境」。
#   若 electron-persisted-atom-state.new-task-execution-by-account-project 为 cloud(远程)，
#   而账号的 environment-catalog 为空（hasEnvironments=false），二者构成死锁：
#   按钮永久 disabled，点击被 UI 层吞掉 —— 日志里不会出现任何 turn/start，也没有网络请求。
#   判别特征：位置标签显示「远程」+ 悬停发送按钮提示「请选择一个云端环境，然后继续」。
#
# 幂等：apply 前自动时间戳备份；已为 local 则跳过。
# 用法：
#   bash codex-desktop-send-block-check.sh check     # 只读诊断（默认）
#   bash codex-desktop-send-block-check.sh apply     # 修复：执行位置改为 local（需先退出应用）
#   bash codex-desktop-send-block-check.sh rollback  # 还原最近一次 apply 的备份
set -u

STATE="$HOME/.codex/.codex-global-state.json"
LOGDIR="$HOME/Library/Logs/com.openai.codex"
KEY="new-task-execution-by-account-project"
APP="/Applications/ChatGPT.app"
PY="${PYTHON:-python3}"

if [ ! -f "$STATE" ]; then echo "找不到状态文件: $STATE"; exit 1; fi

# ---------- 只读诊断 ----------
check() {
  echo "=== 应用版本 ==="
  [ -f "$APP/Contents/Info.plist" ] && \
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null
  pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT$" >/dev/null && echo "进程: 运行中" || echo "进程: 未运行"

  echo
  echo "=== 执行位置 / 云端环境目录 ==="
  "$PY" - "$STATE" "$KEY" <<'PY'
import json,sys,datetime
d=json.load(open(sys.argv[1])); k=sys.argv[2]
a=d.get('electron-persisted-atom-state',{})
val=a.get(k) or {}
kinds=sorted({(v or {}).get('kind') for v in val.values()}) if isinstance(val,dict) else []
print("new-task-execution:", json.dumps(val,ensure_ascii=False))
cat=d.get('environment-catalog-cache-v2') or {}
data=cat.get('data') or []
c1=d.get('environment-catalog-cache-v1') or {}
legacy=(a.get('legacy-cloud-settings-environments-v1') or {})
has_env = any(isinstance(v,dict) and v.get('hasEnvironments') for v in legacy.values()) if isinstance(legacy,dict) else False
print(f"environment-catalog-v2.data = {len(data)} 项")
print(f"environment-catalog-v1.user/workspace = {len(c1.get('user') or [])}/{len(c1.get('workspace') or [])}")
print(f"hasEnvironments = {has_env}")
for kk,v in (cat.get('refreshedAt') and {'refreshedAt':cat['refreshedAt']} or {}).items():
    print(f"{kk} = {datetime.datetime.fromtimestamp(v/1000):%Y-%m-%d %H:%M:%S}")
cloud = ('cloud' in kinds)
if cloud and not data and not has_env:
    print("\n>>> 判定：执行位置=远程(cloud)，但账号云端环境为空 —— 发送按钮会被禁用（命中本故障）")
    print(">>> 修复：bash $0 apply   （或 UI：点「工作位置」下拉 → 选「此计算机」）")
elif cloud:
    print("\n>>> 判定：执行位置=远程(cloud)，云端环境目录非空 —— 需确认目标环境是否选中")
else:
    print("\n>>> 判定：执行位置=本地(local)，不命中本故障；若仍发不出请另查应用日志")
PY

  echo
  echo "=== 最近日志的发送/回合活动 ==="
  latest=$(ls -t "$LOGDIR"/*/*/*/*-t0-i1-*.log 2>/dev/null | head -1)
  if [ -n "${latest:-}" ]; then
    echo "日志: $latest"
    echo "turn/start  次数: $(grep -c 'turn/start' "$latest" 2>/dev/null || echo 0)"
    echo "turn/started 次数: $(grep -c 'turn/started' "$latest" 2>/dev/null || echo 0)"
    echo "最后一条 turn 事件: $(grep -oE '^[0-9T:.Z-]+.*turn/(start|started|completed)' "$latest" 2>/dev/null | tail -1 | cut -c1-80)"
  else
    echo "未找到 t0 主日志"
  fi
}

# ---------- 应用修复 ----------
apply() {
  if pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT$" >/dev/null; then
    echo "应用正在运行，必须先退出（否则运行实例会覆盖改动）"
    echo "执行: osascript -e 'tell application \"ChatGPT\" to quit'; sleep 6"
    exit 1
  fi

  TS=$(date +%Y%m%d-%H%M%S)
  BK="$STATE.bak-fix-$TS"
  cp -p "$STATE" "$BK" && echo "已备份: $BK"

  "$PY" - "$STATE" "$KEY" <<'PY'
import json,sys
p,k=sys.argv[1],sys.argv[2]
d=json.load(open(p)); a=d['electron-persisted-atom-state']
val=a.get(k) or {}
if not val:
    print("状态中不存在该键，未做改动（可能版本不同）"); sys.exit(2)
changed=0
for kk in val:
    if (val[kk] or {}).get('kind')!='local':
        val[kk]={'kind':'local'}; changed+=1
json.dump(d,open(p,'w'),ensure_ascii=False)
print(f"已改为 local（{changed} 条变更）: {json.dumps(val,ensure_ascii=False)}")
PY
  rc=$?
  if [ $rc -ne 0 ]; then echo "改动失败（rc=$rc），可用 rollback 还原"; exit $rc; fi

  echo
  echo "启动应用: open -a \"$APP\""
  open -a "$APP"
  sleep 15
  pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT$" >/dev/null && echo "已启动" || echo "启动失败"
  echo
  echo "验证：输入框上方位置标签应为「此计算机」；输入文字后发送按钮应变为白色可用；"
  echo "      发送后日志应出现 turn/start（跑 check 可复查）"
}

# ---------- 回滚 ----------
rollback() {
  if pgrep -f "ChatGPT.app/Contents/MacOS/ChatGPT$" >/dev/null; then
    echo "应用正在运行，请先退出再回滚"; exit 1
  fi
  last=$(ls -t "$STATE".bak-fix-* 2>/dev/null | head -1)
  [ -z "${last:-}" ] && { echo "没有找到 apply 生成的备份"; exit 1; }
  echo "回滚源: $last"
  cp -p "$last" "$STATE" && echo "已还原（重启应用后生效）"
}

case "${1:-check}" in
  check) check ;;
  apply) apply ;;
  rollback) rollback ;;
  *) echo "用法: $0 [check|apply|rollback]"; exit 2 ;;
esac
