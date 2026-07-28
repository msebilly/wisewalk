SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

DEST := platform=iOS Simulator,name=iPhone 17
PROJ := WiseWalk.xcodeproj

.PHONY: gen build test clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild build -project $(PROJ) -scheme WiseWalk -destination '$(DEST)' -quiet

test: gen
	@mkdir -p build
	@set -o pipefail; \
	xcodebuild test -project $(PROJ) -scheme WiseWalk -destination '$(DEST)' 2>&1 \
		| tee build/wisewalk-test.log \
		| grep -E "✔|✘|error:|Executed|TEST (SUCCEEDED|FAILED)" || true
	@grep -q "TEST SUCCEEDED" build/wisewalk-test.log

clean:
	rm -rf $(PROJ) build .build DerivedData
