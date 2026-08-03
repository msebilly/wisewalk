# 造草稿的家什。03 和 06 都要用，所以只写一遍。
#
# ⛔ 草稿造不出来，只能往库里插——`stopApp` 不但留不下草稿，反而会替用户提交掉
#    （`CounterView.onDisappear { commit() }` 在 terminate 时也会跑）。详见 README。
export PATH="$PATH:$HOME/.maestro/bin"
APP=com.msebilly.wisewalk

# ⚠️ bash 3.2 会把中文标点的 UTF-8 高位字节当成变量名的一部分，
#    挨着中文的变量一律写 `${UDID}` 而不是 `$UDID`。
UDID="${WW_SIM_UDID:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1)}"

# ⛔ 一律带 `--device`。开着两台模拟器时 maestro 会自己挑一台，
# 而 sqlite 查的是 `${UDID}` 那一台——flow 在 A 上建课、脚本去 B 上查，
# 于是报「库里没有定课，建课那步其实没落库」，而建课明明成功了。
# 实测就是这么被坑的（邻居项目占着 356A…，慧行单开了 07E3…）。
#
# ⚠️ 退出码必须自己接回来。裸写 `maestro | grep` 的话，函数返回的是 **grep** 的
# 退出码——maestro 红了 grep 照样返回 0，于是「没过」变成「过了」。
# 这是本仓库记过的假绿形状（`Makefile` 那次 `|| true` 同源），抽这个函数时又踩了一次。
ww_maestro() {
  local rc
  maestro --device "$UDID" test "$@" 2>&1 | grep -v '^WARNING'
  rc="${PIPESTATUS[0]}"
  return "$rc"
}

ww_paths() {
  local c; c="$(xcrun simctl get_app_container "$UDID" "$APP" data)"
  MAIN="$c/Library/Application Support/WiseWalk.store"
  DRAFT="$c/Library/Application Support/LocalOnly/WiseWalkLocal.store"
}

# ww_seed_drafts 108 [21 ...] —— 给库里第一门定课造出这些量的草稿。
# `Z_ENT=4` 是 SessionDraft 的实体号；插完必须抬 Z_PRIMARYKEY 的水位，否则 App 撞主键。
# Core Data 的时间戳从 2001 年起算，要 +978307200。
ww_seed_drafts() {
  xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
  sleep 1
  ww_paths
  local hex; hex="$(sqlite3 "$MAIN" "select hex(ZID) from ZPRACTICEITEM limit 1;")"
  [ -z "$hex" ] && { echo "✘ 库里没有定课，建课那步其实没落库"; return 1; }
  # ⛔ 每一份的 startedAt 必须**错开**。`RecoveryCoordinator` 按
  # `(startedAt, id.uuidString)` 排序，时间戳一样就退化成按**随机 UUID** 比大小——
  # 先问哪一份成了掷硬币，靠「先问 108」立论的断言就一半时间红一半时间绿。
  # （我抽这个函数时正踩过：两份都写 -600，03 就时好时坏。）
  local pk=901 i=0 sql="DELETE FROM ZSESSIONDRAFT;"
  for amount in "$@"; do
    sql="$sql
INSERT INTO ZSESSIONDRAFT (Z_PK,Z_ENT,Z_OPT,ZAMOUNT,ZSTARTEDAT,ZUPDATEDAT,ZSOURCERAW,ZITEMID,ZSESSIONID)
VALUES ($pk,4,1,$amount,strftime('%s','now')-978307200-$((600 - i * 100)),strftime('%s','now')-978307200-$((300 - i * 100)),'counter',X'$hex',randomblob(16));"
    pk=$((pk + 1)); i=$((i + 1))
  done
  sql="$sql
UPDATE Z_PRIMARYKEY SET Z_MAX=$((pk - 1)) WHERE Z_NAME='SessionDraft';"
  sqlite3 "$DRAFT" "$sql"
  local n; n="$(sqlite3 "$DRAFT" "select count(*) from ZSESSIONDRAFT;")"
  [ "$n" != "$#" ] && { echo "✘ 草稿没插进去（要 $# 份，现有 ${n} 份）"; return 1; }
  echo "  已造出 $# 份草稿"
}

# ww_new_item count|duration —— 清干净，立一门课。
ww_new_item() {
  ww_maestro "flows/subflows/new-$1-item.yaml" | tail -2
  [ "${PIPESTATUS[0]}" != "0" ] && { echo "✘ 建课那步就没过"; return 1; }
  return 0
}
