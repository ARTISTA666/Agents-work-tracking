#!/bin/bash
# 作用：把 Qoder 域名加入 macOS Wi-Fi 代理绕过列表（DIRECT，不走 127.0.0.1:7890 代理）
# 原理：Qoder 后端（阿里云海外节点）直连正常，走 FlClash 代理时 TLS 被重置；
#       加入绕过列表后，Electron/Chromium 对这些域名直连，其余流量仍走代理。
# 幂等：重复执行不会重复添加。兼容 macOS 自带 bash 3.2。
# 回滚：运行 qoder-rollback-bypass.sh。

set -euo pipefail
SERVICE="Wi-Fi"

# 读取现有绕过域名（每行一个，去空行）
CURRENT=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  CURRENT+=("$line")
done < <(networksetup -getproxybypassdomains "$SERVICE")

# 需要确保存在的 Qoder 域名（通配子域 + 裸域）
WANT=("*.qoder.sh" "qoder.sh" "*.qoder.com" "qoder.com")

# 组装新列表：先保留原有，再追加缺失项
NEW=("${CURRENT[@]}")
for w in "${WANT[@]}"; do
  found=0
  for c in "${CURRENT[@]}"; do
    if [[ "$c" == "$w" ]]; then found=1; break; fi
  done
  if [[ "$found" -eq 0 ]]; then NEW+=("$w"); fi
done

echo "写入后的绕过列表（共 ${#NEW[@]} 条）："
printf '  %s\n' "${NEW[@]}"

# networksetup 一次性替换整个绕过列表
networksetup -setproxybypassdomains "$SERVICE" "${NEW[@]}"

echo
echo "完成。当前生效绕过列表："
networksetup -getproxybypassdomains "$SERVICE"
