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
  # 03 / 06 得先有草稿才有意义，裸跑必然失败。它们由下面各自的脚本驱动。
  case "$name" in 03-*|06-*) continue ;; esac
  if [ -n "$only" ]; then
    case "$name" in
      "$only"*) ;;
      *) continue ;;
    esac
  fi
  echo ""
  echo "▶ $name"
  # grep 掉 JVM 的 WARNING 噪声，它每次都刷十几行
  maestro test "$f" 2>&1 | grep -v '^WARNING' | tail -25
  # maestro 的退出码在管道里丢了，用 PIPESTATUS 取
  if [ "${PIPESTATUS[0]}" != "0" ]; then
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

echo ""
if [ "$failed" = 0 ]; then echo "✔ e2e 全过"; else echo "✘ e2e 有没过的"; fi
exit "$failed"
