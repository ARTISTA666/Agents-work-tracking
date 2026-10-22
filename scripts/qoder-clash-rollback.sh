#!/usr/bin/env bash
# 回滚：移除 Clash 配置里前置的三条 qoder DIRECT 规则并热重载。
# 若要整体还原到修改前，用同目录 backup/clash-*/config.yaml.bak 覆盖后再重载。
# 用法：bash qoder-clash-rollback.sh
set -u

CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"
SECRET=$(grep -E '^secret:' "$CFG" | head -1 | sed -E 's/.*secret:[ ]*"?([^"]+)".*/\1/')

TS=$(date +%Y%m%d-%H%M%S)
cp "$CFG" "$HOME/Library/Application Support/com.follow.clash/config.yaml.bak-$TS"

grep -vE 'DOMAIN-SUFFIX,qoder\.(sh|com|ai),DIRECT' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
echo "已移除 qoder DIRECT 规则"

curl -sS --noproxy '*' --max-time 8 -X PUT \
  -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$CFG\",\"force\":true}" "$CTRL/configs" -o /dev/null -w "重载 HTTP %{http_code}\n"
