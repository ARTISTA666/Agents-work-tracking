#!/bin/bash
# 回滚：把 Wi-Fi 代理绕过列表恢复为 2026-10-22 修复前的原始 17 条（移除新增的 4 条 qoder 域名）
# 用法：bash qoder-rollback-bypass.sh；兼容 macOS 自带 bash 3.2。

set -euo pipefail
SERVICE="Wi-Fi"

ORIGINAL=(
  "*zhihu.com"
  "*zhimg.com"
  "*jd.com"
  "100ime-iat-api.xfyun.cn"
  "*360buyimg.com"
  "localhost"
  "*.local"
  "127.*"
  "10.*"
  "172.16.*"
  "172.17.*"
  "172.18.*"
  "172.19.*"
  "172.2*"
  "172.30.*"
  "172.31.*"
  "192.168.*"
)

echo "恢复为修复前的原始绕过列表（共 ${#ORIGINAL[@]} 条）："
printf '  %s\n' "${ORIGINAL[@]}"
networksetup -setproxybypassdomains "$SERVICE" "${ORIGINAL[@]}"

echo
echo "回滚完成。当前绕过列表："
networksetup -getproxybypassdomains "$SERVICE"
echo
echo "提示：回滚后退出并重新打开 Qoder，使其重新读取系统代理。"
