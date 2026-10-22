#!/usr/bin/env bash
# Qoder 直连规则持久化（第三轮根治）
# 背景：第二轮直接改运行时 config.yaml，会被 FlClash 重建清空导致复发；
#       本脚本把 qoder DIRECT 规则写入 FlClash 持久库 database.sqlite 的 rules 表，
#       FlClash 每次构建配置都会带上，重启/订阅更新/重建 config.yaml 都不丢失。
# 原理：rule_action=DOMAIN_SUFFIX，rule_target=DIRECT，覆盖 qoder.sh / qoder.com / qoder.ai。
# 幂等：先删除所有 qoder 旧规则再插入；每次修改前时间戳备份 database.sqlite。
# 注意：需要退出 FlClash 后离线写库（避免内存回写覆盖），写完自动重启。
# 用法：bash qoder-flclash-persist.sh
set -u

DB="$HOME/Library/Application Support/com.follow.clash/database.sqlite"
CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"

if [ ! -f "$DB" ]; then echo "找不到 $DB"; exit 1; fi

TS=$(date +%Y%m%d-%H%M%S)
BK_DIR="$(dirname "$0")/backup/db-$TS"
mkdir -p "$BK_DIR"
cp "$DB" "$BK_DIR/database.sqlite.bak" && echo "已备份数据库: $BK_DIR/database.sqlite.bak"
[ -f "$CFG" ] && cp "$CFG" "$BK_DIR/config.yaml.bak"

# 1) 退出 FlClash（优雅退出，兜底强杀），确保无内存回写
osascript -e 'tell application "FlClash" to quit' 2>/dev/null || true
sleep 5
pkill -f FlClashCore 2>/dev/null || true
pkill -f "/Applications/FlClash.app" 2>/dev/null || true
sleep 2
if pgrep -fl -i flclash >/dev/null; then echo "FlClash 仍在运行，中止以免写库冲突"; exit 1; fi

# 2) 离线写库：先清旧 qoder 规则，再为每个 profile 插入三条 DIRECT
sqlite3 "$DB" <<'SQL'
DELETE FROM rules WHERE content IN ('qoder.sh','qoder.com','qoder.ai');
SQL

NOW=$(date +%s)
sqlite3 "$DB" <<SQL
INSERT INTO rules (id,profile_id,rule_action,content,rule_target,rule_provider,sub_rule,no_resolve,src,"order")
SELECT $NOW*1000 + ROW_NUMBER() OVER (ORDER BY p.id, s.seq), p.id, 'DOMAIN_SUFFIX', s.dom, 'DIRECT', NULL, NULL, 0, 0, s.ord
FROM profiles p
CROSS JOIN (
  SELECT 'qoder.sh' AS dom, '00' AS ord, 1 AS seq UNION ALL
  SELECT 'qoder.com', '01', 2 UNION ALL
  SELECT 'qoder.ai',  '02', 3
) s;
SQL

echo "已写入 qoder DIRECT 规则："
sqlite3 -line "$DB" "SELECT profile_id,rule_action,content,rule_target,\"order\" FROM rules WHERE content LIKE 'qoder%' ORDER BY profile_id,\"order\";"

# 3) 重启 FlClash 并等待控制器就绪
open -a FlClash
for i in $(seq 1 20); do
  nc -z -G2 127.0.0.1 9090 >/dev/null 2>&1 && break
  sleep 2
done

# 4) 校验实时规则（secret 从重建后的 config.yaml 运行时读取，不入库）
if [ -f "$CFG" ]; then
  SECRET=$(grep -E '^secret:' "$CFG" | head -1 | sed -E 's/.*secret:[ ]*"?([^"]+)".*/\1/')
  curl -sS --noproxy '*' --max-time 8 -H "Authorization: Bearer $SECRET" "$CTRL/rules" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); rows=[(r["type"],r["payload"],r["proxy"]) for r in d["rules"] if "qoder" in r["payload"]]; print("实时规则:", rows if rows else "未找到"); assert any(p=="qoder.sh" and t=="DomainSuffix" and x=="DIRECT" for t,p,x in rows), "校验失败"' \
    && echo "校验通过：qoder 已走 DIRECT"
fi

echo "完成。可在 Qoder 发一条消息验证；回滚用 qoder-flclash-persist-rollback.sh"
