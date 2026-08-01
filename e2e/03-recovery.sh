#!/usr/bin/env bash
# 03 —— 恢复弹窗。**本目录存在的头号理由。**
#
# 这一条得配脚本，因为草稿造不出来：
#
#   `CounterView` 上挂着 `onDisappear { commit() }`，而 SwiftUI 在 App 被
#   terminate 时也会拆视图树、跑一遍 onDisappear。所以 Maestro 的 `stopApp`
#   **不但留不下草稿，反而把它提交了**（实测：杀完主库里躺着 20，草稿是 0）。
#   真正留得下草稿的只有 SIGKILL / OOM / 崩溃——都不是 flow 里做得到的事。
#
# 所以直接往草稿库里插。**而且要插两份**：`fe8aeb6` 那条 bug（答完第一份
# 第二份不弹，界面照旧锁死）只有两份才现得出原形，而杀进程一次只留得下一份。
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.maestro/bin"

UDID="${WW_SIM_UDID:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1)}"
APP=com.msebilly.wisewalk

# ⚠️ bash 3.2 把中文标点的 UTF-8 高位字节当成变量名的一部分，
#    `$UDID）` 会去找一个叫 `UDID）` 的变量。挨着中文一律写 `${}`。
echo "▶ 03-recovery-alert（模拟器 ${UDID}）"

# 1. 清一遍，立一门念佛。
maestro test flows/subflows/new-count-item.yaml 2>&1 | grep -v '^WARNING' | tail -3
[ "${PIPESTATUS[0]}" != "0" ] && { echo "✘ 建课那步就没过"; exit 1; }

xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
sleep 1

C="$(xcrun simctl get_app_container "$UDID" "$APP" data)"
MAIN="$C/Library/Application Support/WiseWalk.store"
DRAFT="$C/Library/Application Support/LocalOnly/WiseWalkLocal.store"

ITEM_HEX="$(sqlite3 "$MAIN" "select hex(ZID) from ZPRACTICEITEM limit 1;")"
[ -z "$ITEM_HEX" ] && { echo "✘ 库里没有定课，建课那步其实没落库"; exit 1; }

# 2. 插两份草稿。Core Data 的时间戳从 2001 年起算，要 +978307200。
#    `Z_ENT=4` 是 SessionDraft 的实体号；插完必须把 Z_PRIMARYKEY 的水位抬上去，
#    否则 App 下次自己插入时会撞主键。
sqlite3 "$DRAFT" <<SQL
DELETE FROM ZSESSIONDRAFT;
INSERT INTO ZSESSIONDRAFT (Z_PK,Z_ENT,Z_OPT,ZAMOUNT,ZSTARTEDAT,ZUPDATEDAT,ZSOURCERAW,ZITEMID,ZSESSIONID)
VALUES (901, 4, 1, 108, strftime('%s','now')-978307200-600, strftime('%s','now')-978307200-300, 'counter', X'$ITEM_HEX', randomblob(16)),
       (902, 4, 1,  21, strftime('%s','now')-978307200-500, strftime('%s','now')-978307200-200, 'counter', X'$ITEM_HEX', randomblob(16));
UPDATE Z_PRIMARYKEY SET Z_MAX=902 WHERE Z_NAME='SessionDraft';
SQL
n="$(sqlite3 "$DRAFT" "select count(*) from ZSESSIONDRAFT;")"
[ "$n" != "2" ] && { echo "✘ 草稿没插进去（现有 ${n} 份）"; exit 1; }
echo "  已造出 2 份草稿"

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
