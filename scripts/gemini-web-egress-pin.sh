#!/usr/bin/env bash
# Gemini 网页端「Gemini isn't currently supported in your country」—— 固定 Gemini 网页出口
#
# 背景（2026-10-24）：
#   gemini.google.com 命中订阅自带规则 DOMAIN,gemini.google.com → 🤖AI网站，而该组当时选中
#   「🇺🇸美国08-0.1倍」这类 0.1 倍廉价中转。这类节点出口 IP 共享且会漂移，本机场大量出口被
#   Google 地理库判为**香港**（实测：curl https://www.google.com/ 连续 302 到
#   https://www.google.com.hk/url?...pref=hkredirect；出口 67.159.48.146/147 在 Cloudflare 眼里
#   是 SG、在 Google 眼里是 HK）。Gemini 不支持香港 → 网页返回地区拦截页。
#   同一时刻 Antigravity 正常，是因为它早有一条 PROCESS-PATH 覆写规则，固定走
#   「🇺🇸美国圣何塞07｜三网推荐」（134.195.101.193/194，Google 判 US）。
#
# 修复：给 gemini.google.com 加一条域名级覆写规则，固定到与 Antigravity 相同的干净美国出口。
#       规则写入 FlClash 持久库 database.sqlite 的 rules 表（启动时合入 config.yaml，跨重启不丢），
#       同时插进运行时 config.yaml 并热重载（不重启客户端、不断网）。
#
# 用法：
#   bash gemini-web-egress-pin.sh check          # 只读诊断：规则/链路/出口采样/Google 归属/页面是否被拦
#   bash gemini-web-egress-pin.sh apply [节点名]  # 固定出口（默认 🇺🇸美国圣何塞07 | 三网推荐），幂等
#   bash gemini-web-egress-pin.sh rollback       # 删除本脚本加的规则并热重载
#
# 注意：
#   - 只改 gemini.google.com 一条规则；不动订阅自带规则、不动其它 AI 站点、不动 Antigravity 规则。
#   - 改动前自动备份 database.sqlite 与 config.yaml 到 ~/Desktop/gemini-check/backup-<时间戳>/。
#   - 浏览器里被拦页面会被 Chrome 缓存：规则生效后请 Cmd+Shift+R 强刷，必要时清 gemini.google.com 站点数据。
#   - 实测（2026-10-24）：运行中写 rules 表 + 热重载可用；完全退出 FlClash（osascript quit 报 -128
#     但进程确实退出）后 rules 表未被回写，重启后配置重建仍含该规则。
set -u

CLASH_DIR="$HOME/Library/Application Support/com.follow.clash"
DB="$CLASH_DIR/database.sqlite"
CFG="$CLASH_DIR/config.yaml"
CTRL="http://127.0.0.1:9090"
PROFILE_ID=369768027173949440
DEFAULT_NODE="🇺🇸美国圣何塞07 | 三网推荐"
RULE_DOMAIN="gemini.google.com"
BACKUP_ROOT="$HOME/Desktop/gemini-check"

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

backup() {
  local ts dir
  ts=$(date +%Y%m%d-%H%M%S); dir="$BACKUP_ROOT/backup-$ts"
  mkdir -p "$dir"
  cp "$DB"  "$dir/database.sqlite.bak"  2>/dev/null
  cp "$CFG" "$dir/config.yaml.bak"      2>/dev/null
  cp "$CLASH_DIR/profiles/$PROFILE_ID.yaml" "$dir/profile-$PROFILE_ID.yaml.bak" 2>/dev/null
  say "已备份到 $dir"
}

reload_cfg() {
  python3 - "$CFG" "$(read_secret)" <<'PY'
import json, subprocess, sys
cfg, sec = sys.argv[1], sys.argv[2]
p = subprocess.run(["curl","-s","-o","/dev/null","-w","%{http_code}",
                    "-X","PUT","-H",f"Authorization: Bearer {sec}",
                    "-H","Content-Type: application/json",
                    "--data", json.dumps({"path": cfg}), "http://127.0.0.1:9090/configs"],
                   capture_output=True, text=True)
print("  reload HTTP", p.stdout.strip() or p.returncode)
PY
}

gemini_rule_args() { printf '%s\n%s\n%s\n' "$RULE_DOMAIN" "$1" "0b"; }  # content / target / order

rule_exists_db() {  # $1=target
  sqlite3 "$DB" "select count(*) from rules where content='$RULE_DOMAIN' and rule_target='$1';" 2>/dev/null
}

do_check() {
  say "=== 1. gemini.google.com 当前命中规则与链路 ==="
  (curl -s -m 15 -o /dev/null "https://gemini.google.com/app?_$(date +%s)" &) ; sleep 2
  ctrl "/connections" | python3 -c '
import sys,json
cs=[c for c in json.load(sys.stdin)["connections"] if "gemini.google.com" in str(c["metadata"].get("host",""))]
cs.sort(key=lambda c: str(c.get("start","")))
for c in cs[-2:]: print("  ", c["start"], "->", c.get("chains"))
' 2>/dev/null || say "  （控制器未就绪或暂无连接）"
  ctrl "/rules" | python3 -c '
import sys,json
for r in json.load(sys.stdin)["rules"]:
    if r["payload"]=="gemini.google.com": print("  rule:", r["type"], r["payload"], "->", r["proxy"])
' 2>/dev/null

  say
  say "=== 2. 🤖AI网站 分组当前节点 ==="
  ctrl "/proxies/$(urlq '🤖AI网站')" | python3 -c 'import sys,json;print("  now =",json.load(sys.stdin).get("now"))' 2>/dev/null

  say
  say "=== 3. AI 路径出口采样（chatgpt.com 命中 🤖AI网站）==="
  local i ip ips="" uniq
  for i in 1 2 3 4 5; do
    ip=$(curl -s -m 8 https://chatgpt.com/cdn-cgi/trace 2>/dev/null | grep -E '^ip=' | cut -d= -f2)
    [ -n "$ip" ] && ips="$ips $ip"; sleep 0.4
  done
  uniq=$(printf '%s\n' $ips | sort -u | wc -l | tr -d ' ')
  say "  egress:${ips:-（采样失败）}"
  say "  distinct=$uniq $([ "${uniq:-0}" -le 1 ] && echo '✅ 单出口' || echo '⚠️ 多出口/漂移，建议 apply 固定')"

  say
  say "=== 4. Google 对本机「google 关键字路径」出口的国家判定（302 到 .hk 即被判 HK；gemini 已走独立固定规则）==="
  local loc
  loc=$(curl -s -o /dev/null -D - -m 10 https://www.google.com/ | grep -i '^location:' | head -1)
  say "  ${loc:-（无 302，通常说明 Google 判为 US/当地）}"
  printf '%s' "$loc" | grep -q 'google\.com\.hk' && say "  ❌ Google 认为出口在香港（Gemini 不支持香港）" || say "  ✅ 未被判到 HK"

  say
  say "=== 5. Gemini 页面是否被地区拦截 ==="
  local blk size
  curl -s -m 15 -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140 Safari/537.36" \
    -o /tmp/.gem_check.html -w '' https://gemini.google.com/app 2>/dev/null
  size=$(wc -c < /tmp/.gem_check.html | tr -d ' ')
  blk=$(grep -c -i -E "not currently supported|stay tuned" /tmp/.gem_check.html 2>/dev/null); blk=${blk:-0}
  say "  bytes=$size block_text=$blk $([ "$blk" -eq 0 ] && echo '✅ 未拦截' || echo '❌ 拦截页（浏览器请强刷/清站点数据）')"
  rm -f /tmp/.gem_check.html

  say
  say "=== 6. Antigravity 链路（应同样走固定美国出口，不受本修复影响）==="
  ctrl "/connections" | python3 -c '
import sys,json
seen=set()
for c in json.load(sys.stdin)["connections"]:
    h=str(c["metadata"].get("host",""))
    if ("cloudcode" in h or "aicode.googleapis" in h) and h not in seen:
        seen.add(h); print("  ", h, "->", c.get("chains"))
' 2>/dev/null | head -4
}

do_apply() {
  local node="${1:-$DEFAULT_NODE}" exists
  [ -f "$DB" ] || die "找不到数据库: $DB"
  command -v sqlite3 >/dev/null || die "需要 sqlite3"
  curl -s -m 4 -o /dev/null -H "Authorization: Bearer $(read_secret)" "$CTRL/version" || die "FlClash 内核未运行，请先启动 FlClash"

  backup
  exists=$(rule_exists_db "$node")
  if [ "${exists:-0}" -gt 0 ]; then
    say "规则已存在（content=$RULE_DOMAIN, target=${node}），跳过写库"
  else
    python3 - "$DB" "$PROFILE_ID" "$node" <<'PY'
import sqlite3, sys, time
db, pid, target = sys.argv[1], int(sys.argv[2]), sys.argv[3]
con = sqlite3.connect(db, timeout=10); cur = con.cursor()
cur.execute("select id from rules where profile_id=? and content=? and rule_target=?", (pid, "gemini.google.com", target))
row = cur.fetchone()
if row:
    print("  已存在，id =", row[0])
else:
    rid = int(time.time() * 1000)
    cur.execute('insert into rules (id,profile_id,rule_action,content,rule_target,rule_provider,sub_rule,no_resolve,src,"order") '
                'values (?,?,?,?,?,NULL,NULL,0,0,?)', (rid, pid, "DOMAIN", "gemini.google.com", target, "0b"))
    con.commit(); print("  已写入 rules 表，id =", rid)
con.close()
PY
  fi

  local line="  - \"DOMAIN,$RULE_DOMAIN,$node\""
  if grep -qF "DOMAIN,$RULE_DOMAIN,$node" "$CFG"; then
    say "config.yaml 已有该行"
  else
    python3 - "$CFG" "$line" <<'PY'
import sys
cfg, line = sys.argv[1], sys.argv[2]
txt = open(cfg, encoding="utf-8").read()
anchor = '  - "PROCESS-PATH,/Users/yusong/Applications/Antigravity.app/Contents/Resources/bin/language_server,'
if anchor in txt:
    i = txt.index(anchor)
    open(cfg, "w", encoding="utf-8").write(txt[:i] + line + "\n" + txt[i:])
else:  # 兜底：插到 rules: 之后第一条之前
    i = txt.index("rules:\n") + len("rules:\n")
    open(cfg, "w", encoding="utf-8").write(txt[:i] + line + "\n" + txt[i:])
print("  config.yaml 已插入规则")
PY
  fi

  say "热重载运行配置："
  reload_cfg
  sleep 1
  say "验证："
  ctrl "/rules" | python3 -c '
import sys,json
for r in json.load(sys.stdin)["rules"]:
    if r["payload"]=="gemini.google.com": print("  ", r["type"], r["payload"], "->", r["proxy"])
' 2>/dev/null
  say "完成。如浏览器仍显示地区拦截页：Cmd+Shift+R 强刷；仍不行清 gemini.google.com 站点数据。"
}

do_rollback() {
  local node="${1:-$DEFAULT_NODE}"
  [ -f "$DB" ] || die "找不到数据库: $DB"
  backup
  sqlite3 "$DB" "delete from rules where content='$RULE_DOMAIN' and rule_target='$node';" 2>/dev/null
  say "已从 rules 表删除（如存在）"
  python3 - "$CFG" "$node" <<'PY'
import sys
cfg, node = sys.argv[1], sys.argv[2]
key = f"DOMAIN,gemini.google.com,{node}"
lines = open(cfg, encoding="utf-8").read().splitlines(True)
kept = [l for l in lines if key not in l]
open(cfg, "w", encoding="utf-8").writelines(kept)
print("  config.yaml 已移除规则" if len(kept) != len(lines) else "  config.yaml 无该行")
PY
  say "热重载运行配置："
  reload_cfg
  say "回滚完成（gemini.google.com 恢复走订阅规则 → 🤖AI网站）。"
}

case "${1:-}" in
  check)    do_check ;;
  apply)    do_apply "${2:-}" ;;
  rollback) do_rollback "${2:-}" ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
