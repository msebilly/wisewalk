#!/usr/bin/env bash
# 06 —— 推迟之后自己补记，再问时要把账上已有的数摆出来。见 flows/06-postpone-then-manual.yaml。
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

echo "▶ 06-postpone-then-manual（模拟器 ${UDID}）"

ww_new_item count || exit 1
ww_seed_drafts 108 || exit 1

maestro test flows/06-postpone-then-manual.yaml 2>&1 | grep -v '^WARNING' | tail -30
code="${PIPESTATUS[0]}"

# 收尾取证：账上必须是 **108**，不是 216。这条 flow 防的就是那个 216。
ww_paths
total="$(sqlite3 "$MAIN" "select coalesce(sum(ZAMOUNT),0) from ZPRACTICESESSION;")"
if [ "$total" != "108" ]; then
  echo "✘ 账上是 ${total}，该是 108——同一笔记了两回"
  code=1
fi

if [ "$code" = "0" ]; then echo "✔ 06-postpone-then-manual 过"; else echo "✘ 06-postpone-then-manual 没过"; fi
exit "$code"
