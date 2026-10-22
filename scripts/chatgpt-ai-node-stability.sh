#!/usr/bin/env bash
# ChatGPT 桌面版（Codex）Cloudflare 挑战 / 启动卡死 —— AI 分组出口稳定性处置
#
# 背景：ChatGPT 桌面版的鉴权与后端请求（accounts/check、api/auth/session、pubsub 等）
#       依赖 Cloudflare 的 cf_clearance；而 cf_clearance 是**按出口 IP 绑定**的。
#       机场（本例「赔钱机场」）部分节点使用 NAT 池 / IPv6 轮换出口（实测 134.195.101.193
#       与 .194 几秒内来回切），IP 一变 cf_clearance 即失效 → 部分请求被 403 挑战 →
#       桌面版表现为「刷新成功/失败来回跳」「无法查看工作空间访问权限」甚至卡在启动 logo。
#
# 修复：把 AI 分组的选中节点固定为「出口 IP 稳定」的节点（用
#       https://chatgpt.com/cdn-cgi/trace 采样验证 distinct==1），写入 FlClash
#       持久库 database.sqlite 的 profiles.selected_map，重启客户端后生效。
#
# 用法：
#   bash chatgpt-ai-node-stability.sh check     # 只读诊断：当前 AI 节点、出口 IP 稳定性、日志挑战计数、DNS 是否 fake-ip
#   bash chatgpt-ai-node-stability.sh apply [节点名]   # 固定节点（默认 🇺🇸美国圣何塞02-0.1倍）并重启 FlClash
#   bash chatgpt-ai-node-stability.sh rollback  # 恢复为 🇺🇸美国节点（URLTest 自动选择）
#
# 注意：
#   - 只影响规则里命中 🤖AI网站 的流量（chatgpt/openai/oaistatic 等）；不动 Qoder 的 IP_CIDR 规则。
#   - 改 FlClash 必须先退出进程再离线写库（运行中内存会回写覆盖）。
#   - 若日志里同时出现「You're out of Codex and Work usage」，那是额度问题，与网络无关。
set -u

DB="$HOME/Library/Application Support/com.follow.clash/database.sqlite"
CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"
LOG_DIR="$HOME/Library/Logs/com.openai.codex"
DEFAULT_NODE="🇺🇸美国圣何塞02-0.1倍"
FALLBACK_NODE="🇺🇸美国节点"

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
ctrl() { curl -s -m 6 -H "Authorization: Bearer $(read_secret)" "$CTRL$1"; }
urlq() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

sample_egress() {  # 采样 AI 路径出口 IP（chatgpt.com/cdn-cgi/trace 命中 🤖AI网站）
  local n="${1:-5}" ips=""
  local i ip
  for i in $(seq 1 "$n"); do
    ip=$(curl -s -m 8 https://chatgpt.com/cdn-cgi/trace 2>/dev/null | grep -E '^ip=' | cut -d= -f2)
    [ -n "$ip" ] && ips="$ips $ip"
    sleep 0.4
  done
  printf '%s\n' "$ips" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

latest_app_log() { ls -t "$LOG_DIR"/*/*/*/*.log 2>/dev/null | head -1; }

do_check() {
  say "=== 当前 AI 分组节点 ==="
  ctrl "/proxies/$(urlq '🤖AI网站')" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("🤖AI网站 now =", d.get("now"))' 2>/dev/null || say "（控制器未就绪）"
  say
  say "=== AI 路径出口 IP 采样（distinct 应为 1；>1 说明该节点在轮换出口）==="
  local uniq ips d
  ips=$(sample_egress 5); uniq=$(printf '%s\n' "$ips" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  say "egress:${ips:-（采样失败）}"
  say "distinct=$uniq $([ "$uniq" -le 1 ] && echo '✅ 稳定' || echo '❌ 在轮换，建议 apply')"
  say
  say "=== 系统解析是否走 mihomo fake-ip（应返回 198.18.x）==="
  d=$(dig +short chatgpt.com 2>/dev/null | head -1)
  say "dig chatgpt.com = ${d:-（无）} $([ "${d#198.18.}" != "$d" ] && echo '✅ fake-ip' || echo '⚠️ 非 fake-ip，可能是 DNS 缓存污染，重启客户端或等 TTL')"
  say
  say "=== 桌面版日志中的 Cloudflare 挑战计数（最新实例）==="
  local f; f=$(latest_app_log)
  if [ -n "$f" ]; then
    say "log: $(basename "$f")"
    local cf oc
    cf=$(grep -c cloudflare_challenge "$f" 2>/dev/null); cf=${cf:-0}
    oc=$(grep -c "out of Codex and Work usage" "$f" 2>/dev/null); oc=${oc:-0}
    say "cloudflare_challenge=$cf  out_of_usage=$oc"
  else
    say "（未找到桌面版日志）"
  fi
}

write_selected_map() {
  local node="$1"
  python3 - "$node" <<'PY'
import sqlite3,json,os,sys
node=sys.argv[1]
db=os.path.expanduser('~')+'/Library/Application Support/com.follow.clash/database.sqlite'
con=sqlite3.connect(db); cur=con.cursor(); n=0
for pid,label,sm in cur.execute("SELECT id,label,selected_map FROM profiles").fetchall():
    try: m=json.loads(sm or '{}')
    except Exception: m={}
    if '🤖AI网站' in m:
        m['🤖AI网站']=node
        cur.execute("UPDATE profiles SET selected_map=? WHERE id=?",(json.dumps(m,ensure_ascii=False),pid))
        n+=1
        print('updated',label,'->',node)
con.commit(); con.close()
sys.exit(0 if n else 3)
PY
}

quit_flclash() {
  say "退出 FlClash（离线写库）..."
  osascript -e 'tell application "FlClash" to quit' >/dev/null 2>&1 || true
  sleep 5
  pkill -f FlClashCore >/dev/null 2>&1 || true
  pkill -f "/Applications/FlClash.app" >/dev/null 2>&1 || true
  sleep 2
  pgrep -fl -i flclash >/dev/null 2>&1 && die "FlClash 仍在运行，中止"
  say "FlClash 已退出"
}
start_flclash() {
  say "启动 FlClash ..."
  open -a FlClash
  local i
  for i in $(seq 1 20); do nc -z -G2 127.0.0.1 9090 >/dev/null 2>&1 && break; sleep 1; done
  sleep 1
}

backup_db() {
  local ts bk; ts=$(date +%Y%m%d-%H%M%S)
  bk="$(dirname "$0")/backup/chatgpt-$ts"; mkdir -p "$bk"
  cp "$DB" "$bk/database.sqlite.bak" && say "已备份: $bk/database.sqlite.bak"
  [ -f "$CFG" ] && cp "$CFG" "$bk/config.yaml.bak"
  echo "$bk" > /tmp/.last_chatgpt_fix_backup
}

do_apply() {
  local node="${1:-$DEFAULT_NODE}"
  [ -f "$DB" ] || die "找不到 $DB"
  backup_db
  quit_flclash
  write_selected_map "$node" || die "写入 selected_map 失败（没有包含 🤖AI网站 的 profile？）"
  start_flclash
  say "=== 生效校验 ==="
  ctrl "/proxies/$(urlq '🤖AI网站')" | python3 -c 'import sys,json; print("🤖AI网站 now =", json.load(sys.stdin).get("now"))' 2>/dev/null || true
  local uniq ips
  ips=$(sample_egress 5); uniq=$(printf '%s\n' "$ips" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
  say "egress:${ips}  distinct=$uniq"
  [ "$uniq" -le 1 ] && say "✅ 已固定到稳定出口节点：$node" || say "⚠️ 该节点仍会轮换出口，换一个节点再试"
  say "提示：FlClash 重启后建议把 ChatGPT 桌面版也重启一次（重新加载鉴权 webview）。"
}

do_rollback() {
  [ -f "$DB" ] || die "找不到 $DB"
  backup_db
  quit_flclash
  write_selected_map "$FALLBACK_NODE" || true
  start_flclash
  say "已恢复 🤖AI网站 -> $FALLBACK_NODE（URLTest 自动选择）；彻底还原可覆盖 backup/chatgpt-*/database.sqlite.bak 后重启"
}

case "${1:-}" in
  check)    do_check ;;
  apply)    shift || true; do_apply "${1:-}" ;;
  rollback) do_rollback ;;
  *) say "用法: bash chatgpt-ai-node-stability.sh {check|apply [节点名]|rollback}"; exit 1 ;;
esac
