#!/usr/bin/env bash
# Qoder 走 Clash DIRECT 直连（第二轮根因修复）
# 根因：TUN/fake-ip 全局接管下，系统绕过列表只管 7890 入口；
#       qoder 域名被 mihomo 规则送进代理节点，节点在 TLS 握手重置连接。
#       强制 DOMAIN-SUFFIX -> DIRECT 后，直连阿里云后端正常。
# 幂等：已存在 qoder 规则则跳过；每次修改前自动时间戳备份 config.yaml。
# 用法：bash qoder-clash-direct.sh
set -u

CFG="$HOME/Library/Application Support/com.follow.clash/config.yaml"
CTRL="http://127.0.0.1:9090"

if [ ! -f "$CFG" ]; then echo "找不到 $CFG"; exit 1; fi
SECRET=$(grep -E '^secret:' "$CFG" | head -1 | sed -E 's/.*secret:[ ]*"?([^"]+)".*/\1/')

TS=$(date +%Y%m%d-%H%M%S)
BK="$HOME/Library/Application Support/com.follow.clash/config.yaml.bak-$TS"
cp "$CFG" "$BK" && echo "已备份: $BK"

# 幂等：已有 qoder.sh 规则就不再插入
if grep -q 'DOMAIN-SUFFIX,qoder.sh,DIRECT' "$CFG"; then
  echo "qoder DIRECT 规则已存在，无需重复添加"
else
  # 在 rules: 行后插入三条直达规则
  awk 'BEGIN{done=0} /^rules:/{print; if(!done){print "  - \"DOMAIN-SUFFIX,qoder.sh,DIRECT\""; print "  - \"DOMAIN-SUFFIX,qoder.com,DIRECT\""; print "  - \"DOMAIN-SUFFIX,qoder.ai,DIRECT\""; done=1; next}} {print}' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
  echo "已前置 qoder DIRECT 规则"
fi

# 热重载（mihomo external-controller）
curl -sS --noproxy '*' --max-time 8 -X PUT \
  -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$CFG\",\"force\":true}" "$CTRL/configs" -o /dev/null -w "重载 HTTP %{http_code}\n"

echo "完成。验证：curl -x http://127.0.0.1:7890 -I https://openapi.qoder.sh/ 应返回 4xx/2xx 而非 SSL_ERROR_SYSCALL"
