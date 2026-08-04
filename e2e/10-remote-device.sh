#!/usr/bin/env bash
# 10 —— 把一笔由真实 UI 记下的流水改成「来自另一台设备」，再验补记页的显示。
#
# 这里只改已经落盘的 deviceName，不伪造流水。它证明持久化字段到界面的接线，
# 不证明 CloudKit 能把记录从一台设备传到另一台（本地 e2e 没有真实 CloudKit）。
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

fail() {
  echo "✘ 10-remote-device：$1"
  exit 1
}

echo "▶ 10-remote-device（模拟器 ${UDID}）"

[ -n "${UDID}" ] || fail "没有开着的模拟器"
xcrun simctl get_app_container "$UDID" "$APP" data >/dev/null 2>&1 \
  || fail "模拟器 ${UDID} 上没装慧行"

ww_new_item count || fail "建课失败"
ww_maestro flows/subflows/record-one-count.yaml | tail -20
setup_code="${PIPESTATUS[0]}"
[ "$setup_code" = "0" ] || fail "用真实界面记录 1 声失败"

# SQLite 只能在 App 终止时改；否则 Core Data 的内存状态可能把 seed 覆盖回去。
xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
sleep 1
ww_paths
[ -f "$MAIN" ] || fail "找不到主库 $MAIN"

item_count="$(sqlite3 "$MAIN" "select count(*) from ZPRACTICEITEM;")" \
  || fail "读定课失败"
[ "$item_count" = "1" ] || fail "要正好 1 门定课，实际 ${item_count}"

session_count="$(sqlite3 "$MAIN" "select count(*) from ZPRACTICESESSION;")" \
  || fail "读流水失败"
[ "$session_count" = "1" ] || fail "要正好 1 笔流水，实际 ${session_count}"

row="$(sqlite3 -separator '|' -nullvalue '__SQL_NULL__' "$MAIN" "
  select Z_PK,ZAMOUNT,hex(ZSOURCERAW),hex(ZID),
         case when ZDEVICENAME is null then '__SQL_NULL__'
              else 'HEX:' || hex(ZDEVICENAME) end
  from ZPRACTICESESSION;
  ")" \
  || fail "读流水字段失败"
IFS='|' read -r session_pk amount source_hex session_id original_device_token <<EOF
$row
EOF
[ -n "$session_pk" ] || fail "流水没有主键"
[ "$amount" = "1" ] || fail "真实界面记下的量不是 1，而是 ${amount}"
[ "$source_hex" = "636F756E746572" ] \
  || fail "真实界面记下的来源不是 counter，而是 hex:${source_hex}"
[ -n "$session_id" ] || fail "流水没有业务 ID"
case "$original_device_token" in
  __SQL_NULL__) fail "真实界面流水没有本机设备身份（NULL）" ;;
  HEX:) fail "真实界面流水没有本机设备身份（空字符串）" ;;
  HEX:?*) original_device_hex="${original_device_token#HEX:}" ;;
  *) fail "本机设备身份编码无效：${original_device_token}" ;;
esac
remote_device_hex="69506164C2B758375150"
[ "$original_device_hex" != "$remote_device_hex" ] \
  || fail "真实界面流水已经是 iPad·X7QP，seed 会成为 no-op"

# 精确钉住刚才那一笔：主键、数量、来源都得仍与 setup 所见一致，才允许改设备名。
# 原设备身份也进入 WHERE；setup 已在同一补记页证明 marker 当时不可见。
changed="$(sqlite3 "$MAIN" "
BEGIN IMMEDIATE;
UPDATE ZPRACTICESESSION
SET ZDEVICENAME='iPad·X7QP'
WHERE Z_PK=${session_pk} AND ZAMOUNT=1 AND ZSOURCERAW='counter'
      AND hex(ZDEVICENAME)='${original_device_hex}';
SELECT changes();
COMMIT;
")" || fail "写入远端设备名失败"
[ "$changed" = "1" ] || fail "设备名应只改 1 行，实际改了 ${changed} 行"

seeded="$(sqlite3 "$MAIN" \
  "select count(*) from ZPRACTICESESSION where Z_PK=${session_pk} and ZDEVICENAME='iPad·X7QP';")" \
  || fail "回读设备名失败"
[ "$seeded" = "1" ] || fail "设备名没有持久化"

ww_maestro flows/10-remote-device.yaml | tail -25
code="${PIPESTATUS[0]}"

# 一声都不能丢，也一声都不能多：展示这笔远端来源不能新增、复制或改量。
facts="$(sqlite3 -separator '|' "$MAIN" "
select count(*),coalesce(sum(ZAMOUNT),0),count(distinct hex(ZID)),
       sum(case when Z_PK=${session_pk} and ZAMOUNT=1 and ZSOURCERAW='counter'
                     and ZDEVICENAME='iPad·X7QP' then 1 else 0 end)
from ZPRACTICESESSION;
")" || fail "读取 DB 后置条件失败"
IFS='|' read -r final_count final_amount distinct_ids exact_row <<EOF
$facts
EOF
if [ "$final_count" != "1" ] || [ "$final_amount" != "1" ] \
   || [ "$distinct_ids" != "1" ] || [ "$exact_row" != "1" ]; then
  echo "✘ DB 后置条件失败：sessions=${final_count}, amount=${final_amount}, ids=${distinct_ids}, exact=${exact_row}"
  code=1
else
  echo "  DB：sessions=1, amount=1, distinct_ids=1, remote_rows=1"
fi

if [ "$code" = "0" ]; then echo "✔ 10-remote-device 过"; else echo "✘ 10-remote-device 没过"; fi
exit "$code"
