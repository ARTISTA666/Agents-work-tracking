#!/usr/bin/env bash
# Qoder HTTPDNS 裸 IP 直连规则持久化（第四轮根治）
#
# 背景：Qoder Agent SDK 默认 networkMode=httpdns，对 api3/center.qoder.sh 等主机
#       先用 HTTPDNS 解析成“裸 IP”（如 8.222.76.136、8.222.84.63）再直连 IP。
#       mihomo 对裸 IP 连接只能按 IP/GEOIP 匹配，命中不了
#       `DOMAIN-SUFFIX,qoder.sh,DIRECT`（第三轮写入的域名规则），于是落 MATCH →
#       🐟漏网之鱼 → 代理节点，TLS 被重置（ECONNRESET），表现为
#       「API Error: The connection to the model service was interrupted.」/ 500。
#
# 修复：把 Qoder 实际用到的境外裸 IP 段写进 FlClash 持久库 database.sqlite 的
#       rules 表（IP_CIDR → DIRECT），与第三轮 DOMAIN_SUFFIX 规则并存。
#       持久库会被 FlClash 每次构建配置时带上，重启/订阅更新/重建 config.yaml 不丢。
#
# 涉及网段（2026-10-22 全量日志实测 httpdns 池）：
#   - 8.222.76.136 / 8.222.84.63 / 8.212.124.35 → 阿里云亚太（SG/HK），必须直连（本轮问题源）
#     统一覆盖 8.208.0.0/12（8.208–8.223）与 47.57.0.0/16
#   - 39.107.85.235 / 39.107.242.82 / 47.106.88.164 / 47.103.128.242 /
#     47.103.9.44 / 39.108.79.164 → 阿里云国内，本来就走 GEOIP,cn → DIRECT
#
# 用法：
#   bash qoder-httpdns-ip-direct.sh check      # 只读诊断（不退出 FlClash）
#   bash qoder-httpdns-ip-direct.sh apply      # 写入/更新持久规则并重启 FlClash
#   bash qoder-httpdns-ip-direct.sh rollback   # 删除本轮 IP 规则并重启 FlClash
#
# 幂等：apply/rollback 都先删后插/删，重复执行安全；改动前按时间戳备份 database.sqlite。
set -u

DB="$HOME/Library/Application Support/com.follow.clash/database.sqlite"
CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"
IP_RULES=("8.208.0.0/12" "47.57.0.0/16")   # 境外段（阿里云亚太整段 + 香港）；国内 IP 由 GEOIP,cn 覆盖

say() { printf '%s\n' "$*"; }
die() { printf '错误: %s\n' "$*" >&2; exit 1; }

read_secret() {
  [ -f "$CFG" ] || return 0
  python3 - "$CFG" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'^secret:\s*["\']?([^"\'\s]+)',s,re.M)
print(m.group(1) if m else '')
PY
}

ctrl_get() {  # ctrl_get <path>
  local sec; sec=$(read_secret)
  curl -s -m 6 -H "Authorization: Bearer $sec" "$CTRL$1"
}

need_flclash_dir() {
  [ -d "$(dirname "$DB")" ] || die "找不到 FlClash 数据目录: $(dirname "$DB")"
  [ -f "$DB" ] || die "找不到 $DB"
}

backup_db() {
  local ts bk; ts=$(date +%Y%m%d-%H%M%S)
  bk="$(dirname "$0")/backup/httpdns-$ts"
  mkdir -p "$bk"
  cp "$DB" "$bk/database.sqlite.bak" && say "已备份: $bk/database.sqlite.bak"
  [ -f "$CFG" ] && cp "$CFG" "$bk/config.yaml.bak"
}

quit_flclash() {
  say "退出 FlClash（避免内存回写覆盖离线改库）..."
  osascript -e 'tell application "FlClash" to quit' >/dev/null 2>&1 || true
  sleep 5
  pkill -f FlClashCore >/dev/null 2>&1 || true
  pkill -f "/Applications/FlClash.app" >/dev/null 2>&1 || true
  sleep 2
  if pgrep -fl -i flclash >/dev/null 2>&1; then
    die "FlClash 仍在运行，中止（不要带进程写库）"
  fi
  say "FlClash 已完全退出"
}

start_flclash() {
  say "重启 FlClash 并等待控制器就绪..."
  open -a FlClash
  local i
  for i in $(seq 1 20); do
    nc -z -G2 127.0.0.1 9090 >/dev/null 2>&1 && break
    sleep 1
  done
  sleep 1
}

db_count() { sqlite3 "$DB" "SELECT count(*) FROM rules WHERE rule_action='IP_CIDR' AND content IN ('8.208.0.0/12','47.57.0.0/16');" 2>/dev/null || echo 0; }

verify_live() {
  local rules
  rules=$(ctrl_get /rules 2>/dev/null)
  [ -n "$rules" ] || { say "无法读取 /rules（控制器未就绪？）"; return 1; }
  say "--- 实时规则前 6 条 ---"
  printf '%s' "$rules" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for r in d.get("rules",[])[:6]:
    print(r.get("index"), r.get("type"), r.get("payload"), "->", r.get("proxy"))
' 2>/dev/null || printf '%s' "$rules" | head -c 400
  say "--- 裸 IP 连通性实测（模拟 Qoder HTTPDNS 行为）---"
  local ip code ok=0
  for ip in 8.222.76.136 8.222.84.63 8.212.124.35; do
    code=$(curl -s -o /dev/null -m 8 --resolve "api3.qoder.sh:443:$ip" -w '%{http_code}' \
      "https://api3.qoder.sh/algo/api/v1/ping" 2>/dev/null)
    say "  api3.qoder.sh @ $ip -> HTTP $code"
    [ "$code" != "000" ] && ok=$((ok+1))
  done
  [ "$ok" -ge 1 ]
}

do_check() {
  need_flclash_dir
  say "=== 持久库中的本轮 IP 规则（每个 profile 2 条，共 N 条）==="
  sqlite3 -line "$DB" "SELECT profile_id,rule_action,content,rule_target,no_resolve,\"order\" FROM rules WHERE rule_action='IP_CIDR' ORDER BY profile_id,\"order\";" 2>/dev/null || say "（读库失败）"
  say "记录数: $(db_count)"
  if verify_live; then say "结论: 裸 IP 直连正常 ✅"; else say "结论: 裸 IP 直连异常 ❌（用 apply 修复）"; fi
}

do_apply() {
  need_flclash_dir
  backup_db
  quit_flclash
  say "写入持久库 IP_CIDR → DIRECT ..."
  # 先删本轮旧规则（幂等），再为每个 profile 插入
  sqlite3 "$DB" <<'SQL'
DELETE FROM rules WHERE rule_action='IP_CIDR' AND content IN ('8.208.0.0/12','8.222.0.0/15','47.57.0.0/16');
SQL
  sqlite3 "$DB" <<'SQL'
INSERT INTO rules (id,profile_id,rule_action,content,rule_target,rule_provider,sub_rule,no_resolve,src,"order")
SELECT (strftime('%s','now')*1000 + ROW_NUMBER() OVER (ORDER BY p.id, s.seq)), p.id, 'IP_CIDR', s.cidr, 'DIRECT', NULL, NULL, 1, 0, s.ord
FROM profiles p
CROSS JOIN (
  SELECT '8.208.0.0/12' AS cidr, '03' AS ord, 1 AS seq UNION ALL
  SELECT '47.57.0.0/16', '04', 2
) s;
SQL
  say "写入条数: $(db_count)"
  start_flclash
  if verify_live; then
    say "✅ 修复完成：裸 IP 已直连，且规则在持久库（重启/订阅刷新不丢）"
  else
    say "⚠️ 已写库但实测未通过，请用 rollback 回滚后复查"
    return 1
  fi
}

do_rollback() {
  need_flclash_dir
  backup_db
  quit_flclash
  say "删除本轮 IP_CIDR 规则..."
  sqlite3 "$DB" <<'SQL'
DELETE FROM rules WHERE rule_action='IP_CIDR' AND content IN ('8.208.0.0/12','8.222.0.0/15','47.57.0.0/16');
SQL
  say "剩余条数: $(db_count)（应为 0）"
  start_flclash
  say "已回滚；如需彻底还原，用 backup/httpdns-*/database.sqlite.bak 覆盖后重启 FlClash"
}

case "${1:-}" in
  check)    do_check ;;
  apply)    do_apply ;;
  rollback) do_rollback ;;
  *) say "用法: bash qoder-httpdns-ip-direct.sh {check|apply|rollback}"; exit 1 ;;
esac
