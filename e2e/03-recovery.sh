#!/usr/bin/env bash
# 03 —— 恢复弹窗。**本目录存在的头号理由。**
#
# 这一条得配脚本，因为草稿造不出来（见 lib.sh 开头 / README）。
# **而且要插两份**：`fe8aeb6` 那条 bug（答完第一份第二份不弹，界面照旧锁死）
# 只有两份才现得出原形，而杀进程一次只留得下一份。
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

echo "▶ 03-recovery-alert（模拟器 ${UDID}）"

ww_new_item count || exit 1
ww_seed_drafts 108 21 || exit 1

# 3. 验。
maestro test flows/03-recovery-alert.yaml 2>&1 | grep -v '^WARNING' | tail -30
code="${PIPESTATUS[0]}"

# 4. 收尾：两份都答完了，草稿该是空的。答不完就是死锁又回来了。
left="$(sqlite3 "$DRAFT" "select count(*) from ZSESSIONDRAFT;")"
if [ "$left" != "0" ]; then
  echo "✘ 还剩 $left 份草稿没裁决——弹窗没问完就消失了"
  code=1
fi

if [ "$code" = "0" ]; then echo "✔ 03-recovery-alert 过"; else echo "✘ 03-recovery-alert 没过"; fi
exit "$code"
