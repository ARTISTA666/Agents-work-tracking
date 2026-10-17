#!/bin/bash
# Antigravity 节点探针（静默）
# ------------------------------------------------------------------
# 作用：逐个测试候选节点的「出口 IP」是否被 Antigravity 内部端点
#       daily-cloudcode-pa.googleapis.com 的地区校验接受。
#
# 特点：
#   - 不弹窗、不改 FlClash 的任何设置，也不影响 FlClash 当前选择；
#   - 为每个节点启动一个独立的临时 mihomo 实例（仅监听 127.0.0.1），
#     再用官方 agy CLI 通过它做一次真实模型调用；
#   - 结论按「真实模型调用」判定，而不是无认证 curl / 第三方 IP 库。
#
# 依赖：mihomo、ruby（macOS 自带）、agy（Antigravity CLI）、sqlite3、curl
# 用法：bash antigravity-node-probe.sh [节点名 ...]
#   不带参数时测试默认候选集。
# ------------------------------------------------------------------
set -u

AGY="${AGY:-$HOME/.local/bin/agy}"
MIHOMO="${MIHOMO:-$(command -v mihomo 2>/dev/null || true)}"
FLCLASH_DIR="$HOME/Library/Application Support/com.follow.clash"

if ! command -v "$AGY" >/dev/null 2>&1; then echo "❌ 找不到 agy：$AGY（可设 AGY=...）"; exit 2; fi
if [ -z "$MIHOMO" ] || [ ! -x "$MIHOMO" ]; then echo "❌ 找不到 mihomo（可设 MIHOMO=...）"; exit 2; fi
if ! command -v ruby >/dev/null 2>&1; then echo "❌ 需要 ruby（macOS 自带）"; exit 2; fi

# 取当前订阅 profile（FlClash 数据库里唯一一条 profile 的 id）
PROFILE=""
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$FLCLASH_DIR/database.sqlite" ]; then
  ID=$(sqlite3 "$FLCLASH_DIR/database.sqlite" "select id from profiles limit 1" 2>/dev/null)
  [ -n "${ID:-}" ] && [ -f "$FLCLASH_DIR/profiles/$ID.yaml" ] && PROFILE="$FLCLASH_DIR/profiles/$ID.yaml"
fi
if [ -z "$PROFILE" ]; then
  PROFILE=$(ls -t "$FLCLASH_DIR"/profiles/*.yaml 2>/dev/null | head -1)
fi
if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then echo "❌ 找不到 FlClash 订阅文件（$FLCLASH_DIR/profiles/*.yaml）"; exit 2; fi

NODES=("$@")
if [ ${#NODES[@]} -eq 0 ]; then
  NODES=("日本JP-HY2" "新加坡SG-HY2" "新加坡SG-A" "日本JP-A")
fi

TMP=$(mktemp -d /tmp/agy-node-probe.XXXXXX)
PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

echo "订阅文件：$PROFILE"
echo "候选节点：${NODES[*]}"
echo

# 用 ruby 从订阅里抽出指定节点，逐个写成独立的 mihomo 配置（每个节点一个本地端口）
ruby -ryaml -e '
  profile = ARGV.shift
  outdir  = ARGV.shift
  data = YAML.load_file(profile)
  by_name = {}
  (data["proxies"] || []).each { |p| by_name[p["name"]] = p }
  ARGV.each_with_index do |name, i|
    p = by_name[name]
    if p.nil?
      puts "MISS\t#{name}"
      next
    end
    dir = File.join(outdir, i.to_s)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    cfg = {
      "mixed-port" => 24100 + i,
      "allow-lan" => false,
      "mode" => "rule",
      "log-level" => "error",
      "ipv6" => false,
      "external-controller" => "",
      "proxies" => [p],
      "proxy-groups" => [{ "name" => "PROBE", "type" => "select", "proxies" => [name] }],
      "rules" => ["MATCH,PROBE"]
    }
    File.write(File.join(dir, "config.yaml"), YAML.dump(cfg))
    puts "OK\t#{i}\t#{name}"
  end
' "$PROFILE" "$TMP" "${NODES[@]}"

pass=0; fail=0
for i in "${!NODES[@]}"; do
  name="${NODES[$i]}"
  dir="$TMP/$i"
  if [ ! -f "$dir/config.yaml" ]; then
    echo "[$((i+1))/${#NODES[@]}] $name → ⚠️ 订阅里找不到这个节点名，跳过"
    continue
  fi
  port=$((24100+i))
  "$MIHOMO" -d "$dir" -f "$dir/config.yaml" >"$dir/mihomo.log" 2>&1 &
  PIDS+=($!)
  for _ in $(seq 1 24); do nc -z -G 1 127.0.0.1 "$port" >/dev/null 2>&1 && break; sleep 0.25; done
  sleep 1
  if ! nc -z -G 1 127.0.0.1 "$port" >/dev/null 2>&1; then
    echo "[$((i+1))/${#NODES[@]}] $name → ⚠️ 临时 mihomo 启动失败（见 $dir/mihomo.log）"
    continue
  fi
  ip=""
  for _ in 1 2 3; do
    ip=$(curl -s -m 10 -4 -x "http://127.0.0.1:$port" https://api.ipify.org 2>/dev/null)
    [ -n "$ip" ] && break
    sleep 1
  done
  out=$(HTTPS_PROXY="http://127.0.0.1:$port" HTTP_PROXY="http://127.0.0.1:$port" \
        "$AGY" -p "Reply with exactly: PONG" --print-timeout 90s 2>&1)
  if echo "$out" | grep -q "User location is not supported"; then
    echo "[$((i+1))/${#NODES[@]}] $name → ❌ 地区拒绝  出口 ${ip:-?}"
    fail=$((fail+1))
  elif echo "$out" | grep -q "PONG"; then
    echo "[$((i+1))/${#NODES[@]}] $name → ✅ 可用      出口 ${ip:-?}"
    pass=$((pass+1))
  else
    reason=$(echo "$out" | tail -1 | cut -c1-90)
    echo "[$((i+1))/${#NODES[@]}] $name → ⚠️ 其他失败  出口 ${ip:-?}  ($reason)"
  fi
done

echo
echo "结果：可用 $pass 个，地区拒绝 $fail 个"
[ "$pass" -gt 0 ] && exit 0 || exit 1
