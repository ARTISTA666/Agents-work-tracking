#!/bin/bash
# FlClash「默认出口固定到干净节点」：check / apply / rollback
# ------------------------------------------------------------------
# 背景：机场共享 NAT 池里部分出口被 Google 地理库判为香港，
#       Gemini 网页（未固定域名时）与 Antigravity 内部端点会请求级偶发
#       400 `User location is not supported`。把默认分流组
#       `🚀节点选择` 从「🇺🇸美国节点 / 廉价中转」直接固定到一个实测干净的
#       美国出口，可消除这个变量。
#
# 为什么必须写数据库：FlClash 的分组选择持久化在
#   `database.sqlite` → `profiles.selected_map`（JSON）。
#   只用 mihomo API 切换，FlClash 重启后会被库里的旧值打回。
#   本脚本顺序：备份 → 退出 FlClash → 写库 → 重启 → 复验。
#
# 用法：
#   bash default-egress-pin.sh check              # 只读诊断（安全）
#   bash default-egress-pin.sh apply [节点名]      # 固定出口（默认圣何塞07）
#   bash default-egress-pin.sh rollback [备份目录] # 回滚到 apply 前的选择
#
# 退出码：0 成功；1 失败；2 环境异常
# ------------------------------------------------------------------
set -u

TARGET="${TARGET:-🇺🇸美国圣何塞07 | 三网推荐}"
GROUP="${GROUP:-🚀节点选择}"
PROFILE_ID="${PROFILE_ID:-369768027173949440}"
CLASH_DIR="$HOME/Library/Application Support/com.follow.clash"
DB="$CLASH_DIR/database.sqlite"
CONF="$CLASH_DIR/config.yaml"
CTRL="http://127.0.0.1:9090"
CTRL_GROUP="$CTRL/proxies/%F0%9F%9A%80%E8%8A%82%E7%82%B9%E9%80%89%E6%8B%A9"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/Desktop/gemini-check}"

secret() { grep -m1 '^secret:' "$CONF" | sed 's/secret: *"\(.*\)"/\1/'; }
api_wait() { for _ in $(seq 1 "${1:-40}"); do curl -s -m 2 -H "Authorization: Bearer $(secret)" "$CTRL/version" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
api_now() { curl -s -H "Authorization: Bearer $(secret)" "$CTRL/proxies" | python3 -c 'import sys,json;print(json.load(sys.stdin)["proxies"].get("'"$GROUP"'",{}).get("now",""))'; }
db_now() { sqlite3 "$DB" "select selected_map from profiles where id=$PROFILE_ID;" | python3 -c 'import sys,json;print(json.loads(sys.stdin.read()).get("'"$GROUP"'",""))'; }
egress() { curl -s -m 15 https://www.cloudflare.com/cdn-cgi/trace | awk -F= '/^(ip|loc)=/{printf "%s ",$2}'; }
google_hk() { local n; n=$(curl -s -o /dev/null -D - -m 15 https://www.google.com/ | grep -ci 'hkredirect' || true); echo "${n:-0}"; }

stop_flclash() {
  osascript -e 'quit app "FlClash"' >/dev/null 2>&1
  for _ in $(seq 1 15); do pgrep -x FlClash >/dev/null || break; sleep 1; done
  pgrep -x FlClash >/dev/null && { pkill -x FlClash; sleep 2; }
  pgrep -f FlClashCore >/dev/null && { pkill -f FlClashCore; sleep 1; }
  pgrep -x FlClash >/dev/null && return 1
  return 0
}
start_flclash() { open -a FlClash; api_wait 45 || { echo "❌ FlClash 启动后 API 未就绪"; return 1; }; sleep 2; return 0; }

write_db() {
  python3 - "$DB" "$PROFILE_ID" "$GROUP" "$1" <<'PY'
import sqlite3, sys, json
db, pid, group, value = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
con = sqlite3.connect(db)
row = con.execute("select selected_map from profiles where id=?", (pid,)).fetchone()
m = json.loads(row[0]) if row and row[0] else {}
m[group] = value
con.execute("update profiles set selected_map=? where id=?", (json.dumps(m, ensure_ascii=False), pid))
con.commit()
print(json.dumps(m, ensure_ascii=False))
con.close()
PY
}

cmd_check() {
  [ -f "$DB" ] || { echo "❌ 找不到 $DB"; exit 2; }
  echo "API 当前选择 : $(api_now)"
  echo "DB  持久值   : $(db_now)"
  echo -n "当前出口     : "; egress; echo
  echo "google 判 HK : $(google_hk) （0 = 干净）"
  echo "--- Antigravity CLI 真实调用（约 10~20s）---"
  bash "$(dirname "$0")/antigravity-silent-check.sh" 2>&1 | tail -3
}

cmd_apply() {
  [ -f "$DB" ] || { echo "❌ 找不到 $DB"; exit 2; }
  local ts dir orig
  ts=$(date +%Y%m%d-%H%M%S); dir="$BACKUP_ROOT/backup-$ts"
  mkdir -p "$dir" && cp "$CONF" "$DB" "$dir/" || { echo "❌ 备份失败"; exit 2; }
  sqlite3 "$DB" "select selected_map from profiles where id=$PROFILE_ID;" > "$dir/selected_map.json"
  orig=$(db_now); echo "备份 → $dir（含 selected_map.json）"
  echo "原选择：$orig  →  目标：$TARGET"

  if [ "$(db_now)" = "$TARGET" ] && [ "$(api_now)" = "$TARGET" ]; then
    echo "✅ 已经是目标节点，无需改动。"; return 0
  fi

  echo "→ 退出 FlClash…"; stop_flclash || { echo "❌ 无法退出 FlClash"; exit 1; }
  echo "→ 写入 database.sqlite…"; write_db "$TARGET"
  echo "→ 重启 FlClash…"; start_flclash || exit 1

  local now; now=$(api_now)
  if [ "$now" != "$TARGET" ]; then
    echo "⚠️ 启动后选择为「$now」，用 API 补一次…"
    curl -s -o /dev/null -X PUT -H "Authorization: Bearer $(secret)" -H 'Content-Type: application/json' \
      --data "{\"name\":\"$TARGET\"}" "$CTRL_GROUP"; sleep 2; now=$(api_now)
  fi
  echo "启动后选择：$now"
  echo -n "出口："; egress; echo
  echo "google 判 HK：$(google_hk) （0 = 干净）"
  [ "$now" = "$TARGET" ] && echo "✅ apply 完成" || { echo "❌ apply 未达预期"; exit 1; }
}

cmd_rollback() {
  local dir="${1:-}" orig
  if [ -n "$dir" ]; then
    dir="${dir%/}"
  else
    dir=$(ls -dt "$BACKUP_ROOT"/backup-* 2>/dev/null | head -1)
  fi
  [ -n "$dir" ] && [ -f "$dir/selected_map.json" ] || { echo "❌ 找不到含 selected_map.json 的备份目录"; exit 2; }
  orig=$(python3 -c 'import sys,json;print(json.load(open(sys.argv[1])).get("'"$GROUP"'",""))' "$dir/selected_map.json")
  echo "回滚到：$orig （备份：$dir）"
  stop_flclash || { echo "❌ 无法退出 FlClash"; exit 1; }
  write_db "$orig"
  start_flclash || exit 1
  echo "启动后选择：$(api_now)"
}

case "${1:-check}" in
  check)    cmd_check ;;
  apply)    [ -n "${2:-}" ] && TARGET="$2"; cmd_apply ;;
  rollback) cmd_rollback "${2:-}" ;;
  *) echo "用法: $0 {check|apply [节点名]|rollback [备份目录]}"; exit 2 ;;
esac
