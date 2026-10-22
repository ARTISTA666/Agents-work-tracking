#!/usr/bin/env bash
# Qoder 直连规则持久化回滚（第三轮）
# 作用：删除 database.sqlite rules 表里所有 qoder DIRECT 规则，恢复 FlClash 默认路由。
# 每次删除前时间戳备份 database.sqlite；需退出 FlClash 离线删库，写完自动重启。
# 用法：bash qoder-flclash-persist-rollback.sh
# 彻底还原：也可直接用 backup/db-<时间戳>/database.sqlite.bak 覆盖回库。
set -u

DB="$HOME/Library/Application Support/com.follow.clash/database.sqlite"
CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"

if [ ! -f "$DB" ]; then echo "找不到 $DB"; exit 1; fi

TS=$(date +%Y%m%d-%H%M%S)
BK_DIR="$(dirname "$0")/backup/db-$TS-rollback"
mkdir -p "$BK_DIR"
cp "$DB" "$BK_DIR/database.sqlite.bak" && echo "已备份数据库: $BK_DIR/database.sqlite.bak"

# 退出 FlClash
osascript -e 'tell application "FlClash" to quit' 2>/dev/null || true
sleep 5
pkill -f FlClashCore 2>/dev/null || true
pkill -f "/Applications/FlClash.app" 2>/dev/null || true
sleep 2
if pgrep -fl -i flclash >/dev/null; then echo "FlClash 仍在运行，中止"; exit 1; fi

# 删除 qoder 规则
sqlite3 "$DB" "DELETE FROM rules WHERE content IN ('qoder.sh','qoder.com','qoder.ai');"
echo "剩余 qoder 规则数: $(sqlite3 "$DB" "SELECT COUNT(*) FROM rules WHERE content LIKE 'qoder%';")"

# 重启并等待
open -a FlClash
for i in $(seq 1 20); do
  nc -z -G2 127.0.0.1 9090 >/dev/null 2>&1 && break
  sleep 2
done

if [ -f "$CFG" ]; then
  SECRET=$(grep -E '^secret:' "$CFG" | head -1 | sed -E 's/.*secret:[ ]*"?([^"]+)".*/\1/')
  N=$(curl -sS --noproxy '*' --max-time 8 -H "Authorization: Bearer $SECRET" "$CTRL/rules" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(1 for r in d["rules"] if "qoder" in r["payload"]))')
  echo "实时 qoder 规则数: $N（应为 0）"
fi
echo "回滚完成。"
