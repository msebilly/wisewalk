SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

DEST := platform=iOS Simulator,name=iPhone 17
PROJ := WiseWalk.xcodeproj

# `guard` 只有在**串行**处理前置目标时才真挡得住：实测 `make -j4 test` 会在
# guard 还没失败退出时就把 gen 跑起来。这一行让并行调用也退回串行。
.NOTPARALLEL:

.PHONY: guard gen build install-sim test clean

# 这道闸必须落在 `gen` **之前**。
#
# 它起初写在 `test` 的 recipe 里、而 `gen` 是 `test` 的前置目标——make 会先把
# `gen` 跑完才进 recipe。两个 `make test` 同时启动时，两边的 `xcodegen generate`
# **都已经把共享的 WiseWalk.xcodeproj 重写过了**，落后那个才在闸前退出；
# 而先跑的那个此刻正拿着被对方刚重写的工程文件在 build。
# 2026-07-30 那次事故里最先坏的就是这一处，闸装在 recipe 里恰好漏掉它。
#
# 残余窗口照实说：从这里检查通过到 xcodegen 真正开跑之间还有约一秒空档，
# 两个 make 恰好同时起跑仍可能双双通过。这道闸挡的是「一个在跑、另一个来了」，
# 挡不住「两个同时来」。真要密闭得上锁，而会僵死的锁比这个窗口更麻烦，
# 所以此处**不声称密闭**——真正的纪律是：同一时刻只许一个人进这棵树。
guard:
	@if pgrep -qx xcodebuild || pgrep -qx xcodegen; then \
		echo "✘ 已经有一个 xcodebuild/xcodegen 在跑。"; \
		echo "  它们抢的是同一份 WiseWalk.xcodeproj、同一个 iPhone 17、"; \
		echo "  同一份 DerivedData，以及同一个 build/wisewalk-test.log。"; \
		echo "  一起跑的结果既可能假绿也可能假红。等它跑完再来。"; \
		exit 1; \
	fi

# `gen` 也要挂 guard：直接跑 `make gen` 会绕过闸门，
# 重新造出 2026-07-30 那次并发重写 WiseWalk.xcodeproj 的条件。
gen: guard
	xcodegen generate --quiet

build: guard gen
	xcodebuild build -project $(PROJ) -scheme WiseWalk -destination '$(DEST)' -quiet

# e2e 每跑一轮都要先把新版装进模拟器（`e2e/README.md`）。
# 手敲那三步（build → 从 build settings 里刨出 .app → install）每次都要查一遍，
# 而漏装的后果是**拿旧版跑出一片绿**——比没跑更坏。
install-sim: build
	@set -e; \
	udid="$${WW_SIM_UDID:-$$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' | head -1)}"; \
	if [ -z "$$udid" ]; then echo "✘ 没有开着的模拟器，先 xcrun simctl boot 'iPhone 17'"; exit 1; fi; \
	xcrun simctl bootstatus "$$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$$udid" >/dev/null 2>&1 || true; \
	app="$$(xcodebuild -project $(PROJ) -scheme WiseWalk -destination '$(DEST)' -showBuildSettings 2>/dev/null \
	        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{d=$$2} / FULL_PRODUCT_NAME =/{n=$$2} END{print d"/"n}')"; \
	if [ ! -d "$$app" ]; then echo "✘ 找不到 $$app"; exit 1; fi; \
	xcrun simctl install "$$udid" "$$app"; \
	echo "✔ 已装进 $$udid"

# 成败以 **xcodebuild 自己的退出码** 为准。
#
# 从前这里是 `... | grep -E "..." || true`，后面再 `grep -q "TEST SUCCEEDED" <日志>`。
# 那个 `|| true` 把退出码整个丢掉，判定只剩下「共享日志文件里有没有那行字」。
# **这件事单人使用时就已经是个假绿发生器**，并发只是让它显形：两个 make test
# 一起跑时，判定读的是对方那一轮写进去的行。
#
# 本仓库真的因此损失过一批变异审查的结论（2026-07-30，Task 13 双审），
# 还凭空造出过一条「机制不明的假红」——查到底，就是另一个 agent 的变异
# 失败行从这个共享日志里串过来的。
test: guard gen
	@mkdir -p build
	@set -o pipefail; \
	xcodebuild test -project $(PROJ) -scheme WiseWalk -destination '$(DEST)' 2>&1 \
		| tee build/wisewalk-test.log \
		| grep -E "✔|✘|error:|Executed|TEST (SUCCEEDED|FAILED)"; \
	rc=$${PIPESTATUS[0]}; \
	if [ $$rc -ne 0 ]; then \
		echo "✘ xcodebuild 退出码 $$rc，详见 build/wisewalk-test.log"; \
		exit $$rc; \
	fi
	@grep -q "TEST SUCCEEDED" build/wisewalk-test.log

clean:
	rm -rf $(PROJ) build .build DerivedData
