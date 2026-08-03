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
