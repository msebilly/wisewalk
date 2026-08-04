#!/usr/bin/env bash
# 跑一遍 e2e。要求模拟器已开、App 已装（见 README）。
#
#   ./e2e/run.sh              跑全部
#   ./e2e/run.sh 03           只跑 03 开头的那条
#
# 变量名用英文：macOS 自带的 bash 是 3.2，不认中文标识符。
set -uo pipefail

cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.maestro/bin"

if ! command -v maestro >/dev/null; then
  echo "没装 maestro。装法：curl -Ls 'https://get.maestro.mobile.dev' | bash"
  exit 1
fi

# ⛔ 机器忙的时候跑 e2e，跑出来的红绿都不算数。
#
# 实测：邻居项目在跑变异循环（load average 22）时连跑两轮，红的每轮换一批
# ——第一轮 05/07/06，第二轮 02/04/05/07/03。同一份代码，隔一会儿再跑全绿。
# Maestro 的每一步都带超时，机器一慢就判成「没找着那个元素」。
#
# **红是假的，绿更可疑**：`assertNotVisible` 在页面根本没渲染出来时会凭空通过。
# 所以这里不是「等一等再跑」，是**忙就不跑**——出一个没人敢信的判决
# 比不出判决更坏（`Makefile` 的 `test` 目标为同一个理由设过同一道闸）。
ww_wait_for_quiet() {
  local i=0 clean=0
  while [ "$i" -lt 90 ]; do
    if pgrep -x xcodebuild >/dev/null; then
      clean=0
    else
      clean=$((clean + 1))
      # 连着三次干净才认——变异循环在两次 xcodebuild 之间有空档。
      [ "$clean" -ge 3 ] && return 0
    fi
    [ "$i" = 0 ] && echo "⏳ 有 xcodebuild 在跑，等它收工再开始"
    sleep 10
    i=$((i + 1))
  done
  echo "✘ 等了 15 分钟 xcodebuild 还在跑。这时候跑 e2e 出的红绿都不算数，不跑。"
  return 1
}

ww_wait_for_quiet || exit 1

# ⛔ 第三道，也是唯一挡得住「别的项目在用同一台模拟器」的一道。
#
# 实测：邻居项目往同一台 iPhone 17 上装 `Horcrux`/`DTest`/`MTest`/`VTest` 跑测试，
# 把慧行连人带数据一起掀了——屏幕停在桌面，图标还是灰的。这时候 8 条 flow 红 6 条,
# 而机器负载只有 6，前两道闸一道都拦不住。
#
# 报「没过」是**说谎**：flow 没问题，代码没问题，是环境被抢了。
# 所以跑之前先确认 App 在，每条 flow 红了之后再确认一次它还在——
# 不在就整轮作废（`exit 2`），不给任何红绿判决。
# 「残缺的跑整轮作废，不许从里面挑结论」——同 `Makefile` 那次并发事故的结论。
APP=com.msebilly.wisewalk
UDID="${WW_SIM_UDID:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1)}"
ww_app_present() { xcrun simctl get_app_container "$UDID" "$APP" >/dev/null 2>&1; }

if [ -z "${UDID}" ]; then
  echo "✘ 没有开着的模拟器。先 xcrun simctl boot <UDID>。"
  exit 1
fi
if ! ww_app_present; then
  echo "✘ 模拟器 ${UDID} 上没装慧行。先 make install-sim。"
  exit 1
fi

# 负载是第二道信号：xcodebuild 收工了但机器仍在喘的话照样会假红。
# 阈值按核数取（每核 1.0 就算跑满），不写死一个拍脑袋的数——
# 换台机器那个数就不对了，而不对的闸门比没有闸门更坏。
ncpu="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
load="$(uptime | sed 's/.*load averages*: *//' | awk '{print $1}' | tr -d ',')"
load_int="$(printf '%.0f' "$load" 2>/dev/null || echo 0)"
if [ "$load_int" -ge "$ncpu" ]; then
  echo "✘ 一分钟负载 ${load}（本机 ${ncpu} 核），太忙。这时候跑 e2e 出的红绿都不算数，不跑。"
  echo "   等它闲下来再跑。急的话 ./e2e/run.sh 01 单条跑，但红了别当结论。"
  exit 1
fi

only="${1:-}"
failed=0
# `flows/[0-9]*.yaml` 而不是 `flows/*.yaml`：subflows/ 里的不是独立 flow。
for f in flows/[0-9]*.yaml; do
  name="$(basename "$f")"
  # 03 / 06 得先有草稿，10 得在两次启动之间改落盘字段；都由下面各自的脚本驱动。
  case "$name" in 03-*|06-*|10-*) continue ;; esac
  if [ -n "$only" ]; then
    case "$name" in
      "$only"*) ;;
      *) continue ;;
    esac
  fi
  echo ""
  echo "▶ $name"
  # grep 掉 JVM 的 WARNING 噪声，它每次都刷十几行
  # ⛔ `--device` 不能省。开着两台模拟器时 maestro 自己挑一台，
  # 挑中的未必是装着当前构建的那一台——红了也不是代码的错。
  maestro --device "$UDID" test "$f" 2>&1 | grep -v '^WARNING' | tail -25
  # maestro 的退出码在管道里丢了，用 PIPESTATUS 取
  if [ "${PIPESTATUS[0]}" != "0" ]; then
    if ! ww_app_present; then
      echo ""
      echo "⛔ 跑到一半 App 从模拟器上没了——多半是别的项目在用同一台模拟器。"
      echo "   这一轮**整轮作废**，$name 这个红不算数。等对方收工，make install-sim 之后重跑。"
      exit 2
    fi
    echo "✘ $name 没过"
    failed=1
  fi
done

# 03 要先把草稿造出来（`stopApp` 造不出，见 README），所以它带个脚本。
if [ -z "$only" ] || [ "${only#03}" != "$only" ]; then
  echo ""
  ./03-recovery.sh || failed=1
fi
if [ -z "$only" ] || [ "${only#06}" != "$only" ]; then
  echo ""
  ./06-postpone.sh || failed=1
fi
if [ -z "$only" ] || [ "${only#10}" != "$only" ]; then
  echo ""
  ./10-remote-device.sh || failed=1
fi

echo ""
if [ "$failed" = 0 ]; then echo "✔ e2e 全过"; else echo "✘ e2e 有没过的"; fi
exit "$failed"
