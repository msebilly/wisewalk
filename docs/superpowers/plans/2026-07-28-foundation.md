# 慧行 WiseWalk — 地基篇实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭起 WiseWalk 的 Xcode 工程骨架，并实现「记账式 append-only」数据地基——让每一笔修行流水都能在多设备、跨时区、断网、崩溃的情况下不丢不错。

**Architecture:** 三层，自下而上。**Core** 是纯函数（`DayKey` 时区换算、`LedgerMath` 求和），不依赖 SwiftData，因此可以被穷举测试。**Models** 是三个 `@Model` 实体，全部遵守 CloudKit 的四条硬约束，并由一个 Schema 反射测试自动看守。**Store** 是唯一写入口 `DayLedger`，对外只暴露「记一笔 / 撤一笔 / 查一天」，撤销实现为追加负数流水而非删除。本计划不含任何界面，产出物是一个跑得通全套测试的数据层。

**Tech Stack:** Swift 6.0 语言模式 · SwiftUI · SwiftData · Swift Testing · XcodeGen 2.46 · Xcode 26.6 · 部署目标 iOS 17.4

---

## 计划分卷说明

design-spec §2.1 的 v1 范围覆盖多个独立子系统，一卷装不下，按「每卷都能独立产出可测试的软件」拆成六卷。**本文件是第一卷。**

| 卷 | 内容 | 状态 |
|---|---|---|
| **1. 地基** | 工程骨架 · DayKey · 三个实体 · CloudKit 约束守卫 · DayLedger 账本 | **本卷** |
| 2. 计数 | 计数器 / 计时器 / 手动补录界面 · 草稿与崩溃恢复（§4.5） | 待写 |
| 3. 同步 | CloudKit 打开 · 诊断页 · 导出备份 | 待写 |
| 4. 桌面 | App Group 缓存 · 交互式小组件（§4.4 缓存边界在此落地） | 待写 |
| 5. 呈现 | 月历 · 统计 · 隐藏模式 · 隐私锁 · 长辈模式 | 待写 |
| 6. 排班 | 农历规则 · 本地提醒 · 回向 | 待写 |

**为什么地基单独成卷**：工程评审 B1（跨时区 dayKey）、B2（append-only 求和）、B4（幂等写入）三个问题全在这一层。这些错了，上面盖什么都得推倒。

## 前置环境（已实测确认，勿再验证）

- Xcode 26.6 / Swift 6.3.3 / XcodeGen 2.46.0 (`/opt/homebrew/bin/xcodegen`)
- 本机**只有 iOS 26.5 SDK**，但 `IPHONEOS_DEPLOYMENT_TARGET = 17.4` 构建正常
- 可用模拟器只有 iOS 26.5 一档，本计划统一使用 `iPhone 17`
- 测试期间控制台会打印 CoreData `addPersistentStore` 相关错误日志，**这是噪声**，测试仍会通过，不要去追
- 提交后推送需 `env -u GIT_CONFIG_PARAMETERS git push`（Copilot CLI 注入的凭据变量会让推送认证成错误账号）

## 文件结构

```
wisewalk/
├── project.yml                          XcodeGen 工程定义（唯一的工程真相来源）
├── Makefile                             gen / build / test 三个入口
├── Sources/
│   ├── App/
│   │   └── WiseWalkApp.swift            @main，装配 ModelContainer
│   ├── Core/
│   │   ├── DayKey.swift                 绝对时刻 → yyyyMMdd。纯函数，无依赖
│   │   ├── DomainEnums.swift            MeasureType / SessionSource / ScheduleRule
│   │   ├── LedgerMath.swift             流水求和、显示 clamp、圆满判定。纯函数
│   │   └── DeviceIdentity.swift         流水的 deviceName 来源
│   ├── Models/
│   │   ├── PracticeItem.swift           定课项
│   │   ├── PracticeSession.swift        修行流水（append-only）
│   │   └── DaySnapshot.swift            当日应做清单快照
│   ├── Store/
│   │   ├── ModelContainerFactory.swift  Schema 与容器装配
│   │   └── DayLedger.swift              唯一写入口
│   └── UI/
│       └── RootView.swift               占位根视图（第 5 卷替换）
└── Tests/
    ├── SmokeTests.swift
    ├── DayKeyTests.swift
    ├── DomainEnumsTests.swift
    ├── ModelPersistenceTests.swift
    ├── CloudKitConstraintTests.swift    Schema 反射，自动看守 §4.6 四条约束
    ├── LedgerMathTests.swift
    ├── DeviceIdentityTests.swift
    ├── DayLedgerTests.swift
    └── FulfillmentTests.swift
```

**拆分依据**：`Core/` 全是纯函数，可以脱离 SwiftData 穷举测试——时区这类地方，能穷举就必须穷举。`Store/` 收口所有写操作，是「只增不改不删」这条纪律唯一需要看守的地方；散落各处就守不住了。

---

### Task 1: 工程骨架

**Files:**
- Create: `project.yml`
- Create: `Makefile`
- Create: `Sources/App/WiseWalkApp.swift`
- Create: `Sources/UI/RootView.swift`
- Modify: `.gitignore`
- Test: `Tests/SmokeTests.swift`

- [ ] **Step 1: 写工程定义**

`project.yml`：

```yaml
name: WiseWalk

options:
  bundleIdPrefix: com.msebilly
  deploymentTarget:
    iOS: "17.4"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES

targets:
  WiseWalk:
    type: application
    platform: iOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.msebilly.wisewalk
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: 慧行
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
        CODE_SIGN_STYLE: Automatic
        CODE_SIGNING_ALLOWED: NO
        TARGETED_DEVICE_FAMILY: "1"

  WiseWalkTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: WiseWalk
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.msebilly.wisewalk.tests
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGNING_ALLOWED: NO

schemes:
  WiseWalk:
    build:
      targets:
        WiseWalk: all
    test:
      targets:
        - WiseWalkTests
    run:
      config: Debug
```

> `CODE_SIGNING_ALLOWED: NO` 让模拟器构建与测试完全不需要开发者账号。第 3 卷打开 CloudKit 时才需要真实 Team ID 和 entitlements。
>
> 中文名只放在 `CFBundleDisplayName`（用户在桌面上看到「慧行」），**不要动 `PRODUCT_NAME`**——
> 那是二进制文件名，用中文会带来一串路径与工具链上的麻烦。

- [ ] **Step 2: 写 Makefile**

`Makefile`：

```makefile
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
```

> 最后那行 `grep -q` 是这道门的关键：`xcodebuild` 即使测试失败也可能返回 0，
> 光看退出码会得到永远是绿的假绿灯。已实测：测试失败时 `make test` 退出码为 2。

- [ ] **Step 3: 写 App 入口与占位视图**

`Sources/App/WiseWalkApp.swift`：

```swift
import SwiftUI

@main
struct WiseWalkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`Sources/UI/RootView.swift`：

```swift
import SwiftUI

/// 占位根视图。第 5 卷「呈现」替换为真正的今日页。
struct RootView: View {
    var body: some View {
        Text("慧行")
            .font(.largeTitle)
    }
}
```

- [ ] **Step 4: 写冒烟测试**

`Tests/SmokeTests.swift`：

```swift
import Testing
@testable import WiseWalk

@Test func 工程可以构建并运行测试() {
    #expect(Bool(true))
}
```

- [ ] **Step 5: 更新 .gitignore**

在 `.gitignore` 末尾追加：

```gitignore

# XcodeGen 生成物——project.yml 才是工程的唯一真相来源
*.xcodeproj
DerivedData/
```

- [ ] **Step 6: 生成工程并跑测试**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 输出含 `✔ Test 工程可以构建并运行测试() passed` 与 `** TEST SUCCEEDED **`，命令退出码 0

- [ ] **Step 7: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add project.yml Makefile Sources Tests .gitignore
git commit -m "chore: XcodeGen 工程骨架与测试管线"
```

---

### Task 2: DayKey —— 跨时区的日期归属

评审 B1：从 UTC 时间戳反推「那天是几号」，必须知道记录产生时的本地时区。出国的师兄如果记录整批偏一天，这个 App 就失去了存在意义。

**Files:**
- Create: `Sources/Core/DayKey.swift`
- Test: `Tests/DayKeyTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/DayKeyTests.swift`：

```swift
import Testing
import Foundation
@testable import WiseWalk

/// 由「本地墙上时间 + 时区偏移」构造一个绝对时刻，让测试意图一目了然。
private func instant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, tzMinutes: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: tzMinutes * 60)!
    return cal.date(from: c)!
}

@Test func 北京时间正午归当日() {
    let t = instant(2026, 7, 28, 12, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
}

@Test func 同一时刻在不同时区属于不同日期() {
    // 北京 7月28日 08:00 == 温哥华 7月27日 17:00
    let t = instant(2026, 7, 28, 8, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
    #expect(DayKey.make(from: t, tzOffsetMinutes: -420) == 20260727)
}

@Test func 一日起始设为凌晨三点时两点半算前一天() {
    let t = instant(2026, 7, 28, 2, 30, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260727)
}

@Test func 一日起始设为凌晨三点时三点整算当天() {
    let t = instant(2026, 7, 28, 3, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260728)
}

@Test func 一日起始为零点时凌晨两点半算当天() {
    let t = instant(2026, 7, 28, 2, 30, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
}

@Test func 跨月回退() {
    let t = instant(2026, 7, 1, 1, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260630)
}

@Test func 跨年回退() {
    let t = instant(2026, 1, 1, 1, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20251231)
}

@Test func 闰日() {
    let t = instant(2028, 2, 29, 10, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20280229)
}

@Test func 半小时时区() {
    // 印度 +330。当地 7月28日 00:15 == UTC 7月27日 18:45
    let t = instant(2026, 7, 28, 0, 15, tzMinutes: 330)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 330) == 20260728)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 0) == 20260727)
}

@Test func 反解出年月日() {
    let p = DayKey.decompose(20260728)
    #expect(p.year == 2026)
    #expect(p.month == 7)
    #expect(p.day == 28)
}

@Test func 取当前时区偏移() {
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    #expect(DayKey.currentOffsetMinutes(at: Date(), timeZone: tz) == 480)
}

@Test func 今日键使用指定时区与时刻() {
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    let t = instant(2026, 7, 28, 23, 59, tzMinutes: 480)
    #expect(DayKey.today(now: t, timeZone: tz) == 20260728)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'DayKey' in scope`

- [ ] **Step 3: 实现**

`Sources/Core/DayKey.swift`：

```swift
import Foundation

/// 日期键：yyyyMMdd 的整数表示。2026-07-28 → 20260728。
///
/// **为什么不直接存 Date**：CloudKit 同步来的记录可能出自任何时区的设备，
/// 从 UTC 时间戳反推「那天是几号」必须知道记录产生**当时**的本地偏移。
/// 所以每笔流水都随身携带 tzOffsetMinutes，而 dayKey 一旦写入就永不重算——
/// 用户从北京飞到温哥华，昨天的功课不该跳到前天去。
enum DayKey {
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// 由绝对时刻计算日期键。
    /// - Parameters:
    ///   - date: 绝对时刻
    ///   - tzOffsetMinutes: 该时刻的本地时区偏移，东八区为 480，西七区为 -420
    ///   - dayStartHour: 一日起始小时。设为 3 则凌晨 2:59 仍算前一天
    static func make(from date: Date, tzOffsetMinutes: Int, dayStartHour: Int = 0) -> Int {
        let shifted = date.timeIntervalSince1970
            + Double(tzOffsetMinutes * 60)
            - Double(dayStartHour * 3600)
        let c = utcCalendar.dateComponents(
            [.year, .month, .day],
            from: Date(timeIntervalSince1970: shifted)
        )
        // 公历日历请求年月日必定返回三者，此处不可能为 nil。
        return c.year! * 10000 + c.month! * 100 + c.day!
    }

    /// 按指定时区计算「今天」。
    static func today(
        dayStartHour: Int = 0,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Int {
        make(
            from: now,
            tzOffsetMinutes: currentOffsetMinutes(at: now, timeZone: timeZone),
            dayStartHour: dayStartHour
        )
    }

    /// 写入流水时随身记录的时区偏移（分钟）。
    static func currentOffsetMinutes(at date: Date = Date(), timeZone: TimeZone = .current) -> Int {
        timeZone.secondsFromGMT(for: date) / 60
    }

    /// 反解为年月日，供月历与显示使用。
    static func decompose(_ key: Int) -> (year: Int, month: Int, day: Int) {
        (key / 10000, (key / 100) % 100, key % 100)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 13 个测试全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Core/DayKey.swift Tests/DayKeyTests.swift
git commit -m "feat: DayKey 跨时区日期归属"
```

---

### Task 3: 领域枚举

**Files:**
- Create: `Sources/Core/DomainEnums.swift`
- Test: `Tests/DomainEnumsTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/DomainEnumsTests.swift`：

```swift
import Testing
@testable import WiseWalk

@Test func 计量方式原始值稳定() {
    #expect(MeasureType.count.rawValue == "count")
    #expect(MeasureType.duration.rawValue == "duration")
    #expect(MeasureType.check.rawValue == "check")
    #expect(MeasureType.allCases.count == 3)
}

@Test func 流水来源原始值稳定() {
    #expect(SessionSource.counter.rawValue == "counter")
    #expect(SessionSource.timer.rawValue == "timer")
    #expect(SessionSource.manual.rawValue == "manual")
    #expect(SessionSource.adjustment.rawValue == "adjustment")
    #expect(SessionSource.allCases.count == 4)
}

@Test func 排班规则往返() {
    let cases: [ScheduleRule] = [
        .daily,
        .weekdays([1, 3, 5]),
        .lunarDays([1, 15]),
        .lunarSixZhai,
        .lunarTenZhai,
        .lunarBuddhaDays
    ]
    for rule in cases {
        #expect(ScheduleRule(rawValue: rule.rawValue) == rule, "往返失败：\(rule.rawValue)")
    }
}

@Test func 排班规则原始值格式固定() {
    #expect(ScheduleRule.daily.rawValue == "daily")
    #expect(ScheduleRule.weekdays([5, 1, 3]).rawValue == "weekdays:1,3,5")
    #expect(ScheduleRule.lunarDays([15, 1]).rawValue == "lunar:1,15")
    #expect(ScheduleRule.lunarSixZhai.rawValue == "lunar:sixzhai")
    #expect(ScheduleRule.lunarTenZhai.rawValue == "lunar:tenzhai")
    #expect(ScheduleRule.lunarBuddhaDays.rawValue == "lunar:buddhaDays")
}

@Test func 无法识别的排班退化为每日() {
    #expect(ScheduleRule(rawValue: "") == .daily)
    #expect(ScheduleRule(rawValue: "未来版本的新规则") == .daily)
    #expect(ScheduleRule(rawValue: "weekdays:") == .daily)
    #expect(ScheduleRule(rawValue: "lunar:") == .daily)
    #expect(ScheduleRule(rawValue: "weekdays:abc") == .daily)
}

@Test func 计量方式非法值解析为空() {
    // 退化为 .count 发生在 PracticeItem.measureType 的读取门面上，不在这里
    #expect(MeasureType(rawValue: "unknown") == nil)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'MeasureType' in scope`

- [ ] **Step 3: 实现**

`Sources/Core/DomainEnums.swift`：

```swift
import Foundation

/// 计量方式。
/// **rawValue 会写进数据库，已发布的字符串永远不许改。**
enum MeasureType: String, Codable, CaseIterable, Sendable {
    /// 计数：念佛、持咒、拜佛
    case count
    /// 计时：打坐、诵经。数值一律存**秒**
    case duration
    /// 打勾：早晚课、放生、布施
    case check
}

/// 流水来源。用于诊断页回答「这笔账是怎么来的」。
enum SessionSource: String, Codable, CaseIterable, Sendable {
    /// 计数器点击
    case counter
    /// 计时器结束
    case timer
    /// 手动补录
    case manual
    /// 修正。**只有这一种可以为负**——撤销就是追加一笔负数 adjustment
    case adjustment
}

/// 排班规则。存为字符串，形式见 rawValue。
enum ScheduleRule: Equatable, Hashable, Sendable {
    case daily
    /// 公历星期，1 = 周日 … 7 = 周六，与 `Calendar.component(.weekday)` 一致
    case weekdays(Set<Int>)
    /// 指定农历日，如初一十五
    case lunarDays(Set<Int>)
    /// 六斋日
    case lunarSixZhai
    /// 十斋日
    case lunarTenZhai
    /// 诸佛菩萨圣诞日
    case lunarBuddhaDays
}

extension ScheduleRule {
    var rawValue: String {
        switch self {
        case .daily:
            return "daily"
        case .weekdays(let days):
            return "weekdays:" + Self.encode(days)
        case .lunarDays(let days):
            return "lunar:" + Self.encode(days)
        case .lunarSixZhai:
            return "lunar:sixzhai"
        case .lunarTenZhai:
            return "lunar:tenzhai"
        case .lunarBuddhaDays:
            return "lunar:buddhaDays"
        }
    }

    /// 无法识别一律退化为 `.daily`。
    /// 宁可让用户多看见一次提醒，也不能因为解析失败让功课从清单上消失。
    init(rawValue: String) {
        switch rawValue {
        case "lunar:sixzhai":
            self = .lunarSixZhai
        case "lunar:tenzhai":
            self = .lunarTenZhai
        case "lunar:buddhaDays":
            self = .lunarBuddhaDays
        default:
            if let body = Self.body(of: rawValue, prefix: "weekdays:") {
                let days = Self.decode(body)
                self = days.isEmpty ? .daily : .weekdays(days)
            } else if let body = Self.body(of: rawValue, prefix: "lunar:") {
                let days = Self.decode(body)
                self = days.isEmpty ? .daily : .lunarDays(days)
            } else {
                self = .daily
            }
        }
    }

    private static func encode(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    private static func decode(_ body: String) -> Set<Int> {
        Set(body.split(separator: ",").compactMap { Int($0) })
    }

    private static func body(of raw: String, prefix: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 全部 `passed`，`** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Core/DomainEnums.swift Tests/DomainEnumsTests.swift
git commit -m "feat: 领域枚举与排班规则编解码"
```

---

### Task 4: PracticeSession 与 PracticeItem —— 互相引用的一对

这两个实体**必须同时落地**：`PracticeSession.item` 指向 `PracticeItem`，
而 `PracticeItem.sessions` 又用 `@Relationship(inverse: \PracticeSession.item)` 指回来。
双向关系拆不开，单独提交任何一个都编译不过。

**Files:**
- Create: `Sources/Models/PracticeSession.swift`
- Create: `Sources/Models/PracticeItem.swift`
- Test: 本任务只需编译通过，行为测试在 Task 6 建好容器后一并进行

- [ ] **Step 1: 实现 PracticeSession**

`Sources/Models/PracticeSession.swift`：

```swift
import Foundation
import SwiftData

/// 一笔修行流水。**只增不改不删。**
///
/// 撤销的做法是追加一笔等额负数的 `.adjustment`，绝不删除原记录。
/// 理由见 design-spec §4.2：CloudKit 的冲突解决是**整记录级** LWW，
/// 一旦把「今日总数」这类可变字段存进去，iPhone 记的 800 声
/// 会被 iPad 上那条较晚写入的 500 声整条盖掉，凭空少 300 声。
/// 改成流水后每笔都是独立记录，两台设备各写各的，合并即求和——
/// 本质上是 CRDT 里的 PN-Counter。
///
/// 写入粒度是**一次修行结束记一笔**，不是每念一句记一笔。
/// 重度用户五年也只有几万条。
@Model
final class PracticeSession {
    var id: UUID = UUID()

    /// 所属定课项。CloudKit 要求关系必须可选。
    /// 为 nil 表示定课项已被清理，但这笔流水依然作数。
    var item: PracticeItem?

    /// yyyyMMdd。**写入后永不重算。**
    var dayKey: Int = 0

    /// 写入当时的本地时区偏移（分钟）。东八区 480。
    /// 有了它才能在任何设备上还原「这笔是哪天记的」。
    var tzOffsetMinutes: Int = 0

    /// 计数类为遍数，计时类为**秒**，打勾类恒为 1。
    /// `.adjustment` 可为负。**不设上限**——闭关的师兄一天几万声很正常。
    var amount: Int = 0

    var startedAt: Date = Date.distantPast
    var endedAt: Date?

    /// `SessionSource` 的原始值。SwiftData + CloudKit 要求枚举以字符串落库。
    var sourceRaw: String = SessionSource.manual.rawValue

    var deviceName: String = ""
    var note: String?
    var createdAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        item: PracticeItem? = nil,
        dayKey: Int,
        tzOffsetMinutes: Int,
        amount: Int,
        startedAt: Date,
        endedAt: Date? = nil,
        source: SessionSource,
        deviceName: String,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.item = item
        self.dayKey = dayKey
        self.tzOffsetMinutes = tzOffsetMinutes
        self.amount = amount
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceRaw = source.rawValue
        self.deviceName = deviceName
        self.note = note
        self.createdAt = createdAt
    }

    /// 计算属性不会被 SwiftData 持久化，仅作类型安全的读写门面。
    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
```

> `Date.distantPast` 作默认值是刻意的：它是个一眼就知道不对的哨兵值。
> 若用 `Date()`，默认值会在 Schema 构建时定格成某个看起来很合理的时刻，
> 真出了「没赋值」的 bug 反而看不出来。

- [ ] **Step 2: 实现 PracticeItem**

`Sources/Models/PracticeItem.swift`：

```swift
import Foundation
import SwiftData

/// 一项定课。念佛、持咒、诵经、拜佛、打坐、抄经、放生、布施……
///
/// **只归档不真删**：真删会让历史流水变成孤儿，
/// 用户三年前的功课不该因为今天不做了就消失。
@Model
final class PracticeItem {
    var id: UUID = UUID()
    var name: String = ""

    /// SF Symbols 名称
    var iconName: String = "circle"
    /// 形如 "#5C7652"
    var colorHex: String = "#5C7652"

    /// `MeasureType` 的原始值
    var measureTypeRaw: String = MeasureType.count.rawValue

    /// 单位量词：遍 / 声 / 拜 / 部 / 卷。计时类与打勾类为空串。
    var unit: String = ""

    /// 每日目标。**nil 表示不设目标。**
    /// 调研过的九款同类应用无一预设数字，且预设数字与「随分随力」相违。
    /// 计时类存**秒**。
    var dailyGoal: Int?

    /// `ScheduleRule` 的原始值
    var scheduleRuleRaw: String = ScheduleRule.daily.rawValue

    /// 提醒时刻，存「当日零点起的分钟数」。6:00 → 360，21:30 → 1290。
    /// 存分钟数而非 Date，是因为提醒的语义是「每天这个钟点」，与具体哪天无关。
    var reminderTimes: [Int] = []

    var sortOrder: Int = 0
    var isArchived: Bool = false

    /// 内置模板标识，用户自建的定课为 nil。
    var templateKey: String?

    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    /// CloudKit 要求：关系必须可选，且必须有反向关系。
    /// `.nullify` 保证即便定课项被清理，流水也只是失去归属而不会被连带删除。
    @Relationship(deleteRule: .nullify, inverse: \PracticeSession.item)
    var sessions: [PracticeSession]? = []

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "circle",
        colorHex: String = "#5C7652",
        measureType: MeasureType = .count,
        unit: String = "",
        dailyGoal: Int? = nil,
        scheduleRule: ScheduleRule = .daily,
        reminderTimes: [Int] = [],
        sortOrder: Int = 0,
        isArchived: Bool = false,
        templateKey: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.measureTypeRaw = measureType.rawValue
        self.unit = unit
        self.dailyGoal = dailyGoal
        self.scheduleRuleRaw = scheduleRule.rawValue
        self.reminderTimes = reminderTimes
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.templateKey = templateKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = []
    }

    var measureType: MeasureType {
        get { MeasureType(rawValue: measureTypeRaw) ?? .count }
        set { measureTypeRaw = newValue.rawValue }
    }

    var scheduleRule: ScheduleRule {
        get { ScheduleRule(rawValue: scheduleRuleRaw) }
        set { scheduleRuleRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 3: 确认编译通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make build`
Expected: 无 error，命令退出码 0

- [ ] **Step 4: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Models/PracticeSession.swift Sources/Models/PracticeItem.swift
git commit -m "feat: PracticeSession 与 PracticeItem 实体"
```

---

### Task 5: DaySnapshot —— 当日应做清单快照

**Files:**
- Create: `Sources/Models/DaySnapshot.swift`

- [ ] **Step 1: 实现**

`Sources/Models/DaySnapshot.swift`：

```swift
import Foundation
import SwiftData

/// 某一天「应该做哪些功课、各自目标多少」的定格快照。
///
/// 圆满判定**一律读快照，永不按当前设置实时重算**。
/// 用户今天把念佛目标从 1000 改成 3000，上个月那些标着「圆满」的日子
/// 不能因此变回「未完成」——那等于告诉他过去三十天白做了。
///
/// 注意此处**没有** `@Attribute(.unique)`：CloudKit 不支持唯一约束。
/// 同一 dayKey 出现多条快照的去重责任在 `DayLedger.snapshot(for:activeItems:)`。
@Model
final class DaySnapshot {
    var id: UUID = UUID()
    var dayKey: Int = 0

    /// 当日应做的定课项 id
    var requiredItemIDs: [UUID] = []

    /// key 为 `PracticeItem.id.uuidString`，value 为当日目标（计时类为秒）。
    /// **未设目标的项不出现在此字典中**，与 `dailyGoal == nil` 对应。
    var goals: [String: Int] = [:]

    var createdAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        dayKey: Int,
        requiredItemIDs: [UUID],
        goals: [String: Int],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dayKey = dayKey
        self.requiredItemIDs = requiredItemIDs
        self.goals = goals
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: 确认编译通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make build`
Expected: 无 error，命令退出码 0

- [ ] **Step 3: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Models/DaySnapshot.swift
git commit -m "feat: DaySnapshot 当日清单快照实体"
```

---

### Task 6: 容器装配与 CloudKit 约束守卫

design-spec §4.6 列了四条 CloudKit 硬约束。写进文档里靠人眼盯是守不住的——半年后加个字段谁还记得。这个任务把四条约束变成会失败的测试。

**Files:**
- Create: `Sources/Store/ModelContainerFactory.swift`
- Test: `Tests/CloudKitConstraintTests.swift`
- Test: `Tests/ModelPersistenceTests.swift`

- [ ] **Step 1: 写失败测试（约束守卫）**

`Tests/CloudKitConstraintTests.swift`：

```swift
import Testing
import SwiftData
@testable import WiseWalk

/// design-spec §4.6：SwiftData + CloudKit 的四条硬约束。
/// 违反其中任何一条，同步会在真机上静默失效或直接崩溃，
/// 而模拟器上的本地存储照跑不误——所以必须在这里拦住。

@Test func 没有任何实体使用唯一约束() {
    for entity in ModelContainerFactory.schema.entities {
        #expect(
            entity.uniquenessConstraints.isEmpty,
            "\(entity.name) 使用了 @Attribute(.unique)，CloudKit 不支持"
        )
    }
}

@Test func 所有属性要么可选要么有默认值() {
    for entity in ModelContainerFactory.schema.entities {
        for attr in entity.attributes where !attr.isTransient {
            #expect(
                attr.isOptional || attr.defaultValue != nil,
                "\(entity.name).\(attr.name) 既非可选也无默认值，CloudKit 无法同步"
            )
        }
    }
}

@Test func 所有关系均可选() {
    for entity in ModelContainerFactory.schema.entities {
        for rel in entity.relationships {
            #expect(
                rel.isOptional,
                "\(entity.name).\(rel.name) 关系不可选，CloudKit 要求关系必须可选"
            )
        }
    }
}

@Test func 所有关系都有反向关系() {
    for entity in ModelContainerFactory.schema.entities {
        for rel in entity.relationships {
            #expect(
                rel.inverseName != nil,
                "\(entity.name).\(rel.name) 缺少反向关系，CloudKit 要求关系必须成对"
            )
        }
    }
}

@Test func 模型清单完整() {
    let names = Set(ModelContainerFactory.schema.entities.map(\.name))
    #expect(names == ["PracticeItem", "PracticeSession", "DaySnapshot"])
}

@Test func 今日总数不得成为建模属性() {
    // design-spec §4.4：今日总数缓存**绝对不能**进 CloudKit，
    // 否则又变回「存总数」的老路，多设备必然互相覆盖。
    // 缓存的正确去处是 App Group UserDefaults（第 4 卷）。
    let forbidden = ["todayTotal", "cachedTotal", "total", "todayCount"]
    for entity in ModelContainerFactory.schema.entities {
        for attr in entity.attributes {
            #expect(
                !forbidden.contains(attr.name),
                "\(entity.name).\(attr.name) 是缓存字段，不可建模持久化"
            )
        }
    }
}
```

- [ ] **Step 2: 写失败测试（持久化往返）**

`Tests/ModelPersistenceTests.swift`：

```swift
import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@Test func 定课项与流水可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)

    let item = PracticeItem(
        name: "念佛",
        iconName: "circle.hexagonpath",
        measureType: .count,
        unit: "声",
        dailyGoal: 1000,
        scheduleRule: .daily,
        reminderTimes: [360, 1290],
        templateKey: "nianfo"
    )
    ctx.insert(item)

    let session = PracticeSession(
        item: item,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: 108,
        startedAt: Date(timeIntervalSince1970: 1_785_000_000),
        endedAt: Date(timeIntervalSince1970: 1_785_000_600),
        source: .counter,
        deviceName: "iPhone·A1"
    )
    ctx.insert(session)
    try ctx.save()

    let items = try ctx.fetch(FetchDescriptor<PracticeItem>())
    #expect(items.count == 1)
    #expect(items[0].name == "念佛")
    #expect(items[0].measureType == .count)
    #expect(items[0].scheduleRule == .daily)
    #expect(items[0].reminderTimes == [360, 1290])
    #expect(items[0].dailyGoal == 1000)
    #expect(items[0].sessions?.count == 1)

    let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())
    #expect(sessions.count == 1)
    #expect(sessions[0].amount == 108)
    #expect(sessions[0].source == .counter)
    #expect(sessions[0].tzOffsetMinutes == 480)
    #expect(sessions[0].item?.id == item.id)
}

@Test func 不设目标的定课项可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: nil)
    ctx.insert(item)
    try ctx.save()

    let got = try ctx.fetch(FetchDescriptor<PracticeItem>())
    #expect(got[0].dailyGoal == nil)
    #expect(got[0].measureType == .duration)
}

@Test func 快照可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let a = UUID(), b = UUID()
    let snap = DaySnapshot(
        dayKey: 20260728,
        requiredItemIDs: [a, b],
        goals: [a.uuidString: 1000]
    )
    ctx.insert(snap)
    try ctx.save()

    let got = try ctx.fetch(FetchDescriptor<DaySnapshot>())
    #expect(got.count == 1)
    #expect(Set(got[0].requiredItemIDs) == [a, b])
    #expect(got[0].goals[a.uuidString] == 1000)
    #expect(got[0].goals[b.uuidString] == nil)
}

@Test func 清理定课项后流水仍然保留() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "持咒")
    ctx.insert(item)
    let s = PracticeSession(
        item: item, dayKey: 20260728, tzOffsetMinutes: 480, amount: 21,
        startedAt: Date(), source: .counter, deviceName: "t"
    )
    ctx.insert(s)
    try ctx.save()

    ctx.delete(item)
    try ctx.save()

    let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())
    #expect(sessions.count == 1, "deleteRule .nullify 必须保住流水")
    #expect(sessions[0].amount == 21)
    #expect(sessions[0].item == nil)
}
```

> **这四条守卫已实测确认能咬人**，不是摆设。分别往模型里塞过
> `@Attribute(.unique)`、无默认值的非可选属性、名为 `todayTotal` 的字段，
> 三条守卫都如期变红并指名道姓。
>
> 唯一需要说明的是反向关系那条：**把 `inverse:` 从 `@Relationship` 里删掉，测试照样通过**——
> 因为 SwiftData 会在候选唯一时自动推断反向关系，CloudKit 也就满意了，这不算违规。
> 它真正拦的是压根无从推断的情形（比如 `DaySnapshot` 单向指向 `PracticeItem`
> 而对方没有任何回指），实测此时 `inverseName` 为 nil，守卫立刻变红。
> 后来人若发现删 `inverse:` 不报错，别急着断言守卫失灵。

- [ ] **Step 3: 跑测试确认失败**
Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'ModelContainerFactory' in scope`

- [ ] **Step 4: 实现**

`Sources/Store/ModelContainerFactory.swift`：

```swift
import Foundation
import SwiftData

/// Schema 与容器的唯一装配处。
///
/// 新增实体只需改这里一处，`CloudKitConstraintTests` 会自动把新实体
/// 一并纳入 §4.6 四条约束的检查范围。
enum ModelContainerFactory {
    static let schema = Schema([
        PracticeItem.self,
        PracticeSession.self,
        DaySnapshot.self
    ])

    /// 测试用：内存容器，不落盘、不同步。
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// 生产用：本地落盘。
    /// 第 3 卷「同步」会在此处补上 `cloudKitDatabase: .automatic` 与 entitlements。
    static func onDisk() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        )
    }
}
```

- [ ] **Step 5: 把容器接进 App**

`Sources/App/WiseWalkApp.swift` 全文替换为：

```swift
import SwiftUI
import SwiftData

@main
struct WiseWalkApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainerFactory.onDisk()
        } catch {
            // 数据库打不开意味着用户看不到自己的功课。
            // 此处不做静默降级——降级会让人以为记录丢了，比崩溃更伤。
            fatalError("无法打开数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 6: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 全部 `passed`，其中包含 `没有任何实体使用唯一约束`、`所有关系都有反向关系`、`清理定课项后流水仍然保留`

- [ ] **Step 7: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Store/ModelContainerFactory.swift Sources/App/WiseWalkApp.swift \
        Tests/CloudKitConstraintTests.swift Tests/ModelPersistenceTests.swift
git commit -m "feat: 容器装配与 CloudKit 约束守卫测试"
```

---

### Task 7: LedgerMath —— 求和与圆满判定

**Files:**
- Create: `Sources/Core/LedgerMath.swift`
- Test: `Tests/LedgerMathTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/LedgerMathTests.swift`：

```swift
import Testing
import Foundation
@testable import WiseWalk

@Test func 空账本求和为零() {
    // 必须写明 [Int]()：rawTotal 有 [Int] 与 [PracticeSession] 两个重载，
    // 空数组字面量会让类型推断无法决断。
    #expect(LedgerMath.rawTotal([Int]()) == 0)
    #expect(LedgerMath.displayTotal([Int]()) == 0)
}

@Test func 多笔流水求和() {
    #expect(LedgerMath.rawTotal([108, 500, 21]) == 629)
}

@Test func 负数修正抵扣() {
    #expect(LedgerMath.rawTotal([500, -200]) == 300)
}

@Test func 撤销过头时账本可为负而显示归零() {
    #expect(LedgerMath.rawTotal([100, -300]) == -200)
    #expect(LedgerMath.displayTotal([100, -300]) == 0, "账本保留原值，只有显示层归零")
}

@Test func 设了目标时达标才算圆满() {
    #expect(LedgerMath.isFulfilled(total: 999, goal: 1000) == false)
    #expect(LedgerMath.isFulfilled(total: 1000, goal: 1000) == true)
    #expect(LedgerMath.isFulfilled(total: 3000, goal: 1000) == true)
}

@Test func 未设目标时做了就算圆满() {
    // 九款竞品无一预设目标数字，「随分随力」是这款 App 的立场。
    #expect(LedgerMath.isFulfilled(total: 0, goal: nil) == false)
    #expect(LedgerMath.isFulfilled(total: 1, goal: nil) == true)
    #expect(LedgerMath.isFulfilled(total: 108, goal: nil) == true)
}

@Test func 目标为零等同未设目标() {
    #expect(LedgerMath.isFulfilled(total: 0, goal: 0) == false)
    #expect(LedgerMath.isFulfilled(total: 1, goal: 0) == true)
}

@Test func 撤销归零后不算圆满() {
    let total = LedgerMath.displayTotal([1000, -1000])
    #expect(total == 0)
    #expect(LedgerMath.isFulfilled(total: total, goal: 1000) == false)
    #expect(LedgerMath.isFulfilled(total: total, goal: nil) == false)
}

@Test func 大数值不溢出() {
    // 闭关的师兄一天几万声，五年下来累计上千万，必须扛得住。
    let big = Array(repeating: 100_000, count: 10_000)
    #expect(LedgerMath.rawTotal(big) == 1_000_000_000)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'LedgerMath' in scope`

- [ ] **Step 3: 实现**

`Sources/Core/LedgerMath.swift`：

```swift
import Foundation

/// 账本算术。纯函数，不碰 SwiftData，因此可以被穷举测试。
enum LedgerMath {
    /// 账本原值求和。**撤销过多时可以为负**——这是账本的真实状态，不要在这里掩盖。
    static func rawTotal(_ amounts: [Int]) -> Int {
        amounts.reduce(0, +)
    }

    /// 显示用总数。负数 clamp 到 0，**账本本身纹丝不动**。
    static func displayTotal(_ amounts: [Int]) -> Int {
        max(0, rawTotal(amounts))
    }

    /// 是否圆满。
    /// - Parameter goal: nil 或 0 表示未设目标，此时「做了就算圆满」。
    static func isFulfilled(total: Int, goal: Int?) -> Bool {
        guard let goal, goal > 0 else { return total > 0 }
        return total >= goal
    }
}

extension LedgerMath {
    static func rawTotal(_ sessions: [PracticeSession]) -> Int {
        rawTotal(sessions.map(\.amount))
    }

    static func displayTotal(_ sessions: [PracticeSession]) -> Int {
        displayTotal(sessions.map(\.amount))
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 9 个 LedgerMath 测试全部 `passed`

- [ ] **Step 5: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Core/LedgerMath.swift Tests/LedgerMathTests.swift
git commit -m "feat: LedgerMath 账本求和与圆满判定"
```

---

### Task 8: DeviceIdentity —— 流水的落款

诊断页要回答「这笔账是哪台设备记的」。iOS 16 起 `UIDevice.current.name` 不再返回用户起的名字（无特殊 entitlement 时只给通用名），所以用「机型 + 本机短码」拼一个稳定标识。

**Files:**
- Create: `Sources/Core/DeviceIdentity.swift`
- Test: `Tests/DeviceIdentityTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/DeviceIdentityTests.swift`：

```swift
import Testing
import Foundation
@testable import WiseWalk

@Test func 短码稳定不变() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let first = DeviceIdentity.shortCode(defaults: defaults)
    let second = DeviceIdentity.shortCode(defaults: defaults)
    #expect(first == second, "同一台设备的短码必须稳定，否则诊断页会把一台设备算成两台")
    #expect(first.count == 4)
}

@Test func 不同存储生成不同短码() {
    let a = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let b = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    #expect(DeviceIdentity.shortCode(defaults: a) != DeviceIdentity.shortCode(defaults: b))
}

@Test func 短码只含大写字母与数字() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let code = DeviceIdentity.shortCode(defaults: defaults)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    #expect(code.allSatisfy { allowed.contains($0) })
}

@Test func 显示名包含机型与短码() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let name = DeviceIdentity.displayName(defaults: defaults)
    #expect(name.contains("·"))
    let parts = name.split(separator: "·")
    #expect(parts.count == 2)
    #expect(parts[1].count == 4)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'DeviceIdentity' in scope`

- [ ] **Step 3: 实现**

`Sources/Core/DeviceIdentity.swift`：

```swift
import Foundation
import UIKit

/// 流水的落款。诊断页据此回答「这笔账是哪台设备记的」。
///
/// iOS 16 起 `UIDevice.current.name` 在没有特殊 entitlement 时只返回通用机型名，
/// 所以补一个本机随机短码来区分同型号的多台设备。
/// 短码存在本机 UserDefaults，**不进 CloudKit**——它描述的是设备而不是数据。
enum DeviceIdentity {
    private static let storageKey = "device.shortCode"
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// 本机四位短码，首次调用时生成并持久化。
    static func shortCode(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey), existing.count == 4 {
            return existing
        }
        let code = String((0..<4).map { _ in alphabet.randomElement()! })
        defaults.set(code, forKey: storageKey)
        return code
    }

    /// 形如 `iPhone·A3K9`
    static func displayName(defaults: UserDefaults = .standard) -> String {
        "\(UIDevice.current.model)·\(shortCode(defaults: defaults))"
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 4 个 DeviceIdentity 测试全部 `passed`

- [ ] **Step 5: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Core/DeviceIdentity.swift Tests/DeviceIdentityTests.swift
git commit -m "feat: DeviceIdentity 设备落款"
```

---

### Task 9: DayLedger —— 唯一写入口

「只增不改不删」这条纪律，如果散落在各个界面里就守不住。所有写操作收口到这一个类型。

**Files:**
- Create: `Sources/Store/DayLedger.swift`
- Test: `Tests/DayLedgerTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/DayLedgerTests.swift`：

```swift
import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeLedger() throws -> (DayLedger, ModelContext, PracticeItem) {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "念佛", measureType: .count, unit: "声", dailyGoal: 1000)
    ctx.insert(item)
    try ctx.save()
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx, item)
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 记一笔后可以查到() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 多笔累加() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    for amount in [108, 500, 21] {
        try ledger.record(item: item, amount: amount, source: .counter,
                          startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    }
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 629)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 3)
}

@MainActor
@Test func 撤销是追加负数而非删除() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(original, at: now, timeZone: 北京时间)

    let all = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(all.count == 2, "原记录必须还在，撤销是追加一笔而不是删除")
    #expect(all.contains { $0.id == original.id }, "原记录被删掉了")
    #expect(all.contains { $0.amount == -500 && $0.source == .adjustment })
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 撤销笔记指向原记录() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    let adj = try ledger.revoke(original, at: now, timeZone: 北京时间)
    #expect(adj.note == "revoke:\(original.id.uuidString)")
}

@MainActor
@Test func 撤销过头时显示归零而账本留痕() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let a = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "显示层 clamp 到 0")
    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == -500, "账本保留真实值")
}

@MainActor
@Test func 记录自动带上日期键与时区() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 23, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(s.dayKey == 20260728)
    #expect(s.tzOffsetMinutes == 480)
    #expect(s.deviceName == "iPhone·TEST")
}

@MainActor
@Test func 一日起始为凌晨三点时深夜记录归前一天() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 1, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now,
                              dayStartHour: 3, timeZone: 北京时间)
    #expect(s.dayKey == 20260727)
}

@MainActor
@Test func 不同天的流水互不干扰() throws {
    let (ledger, _, item) = try makeLedger()
    let d27 = 北京(7, 27, 9, 0)
    let d28 = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: d27, endedAt: d27, at: d27, timeZone: 北京时间)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: d28, endedAt: d28, at: d28, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260727, itemID: item.id) == 300)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 不同定课项互不干扰() throws {
    let (ledger, ctx, item) = try makeLedger()
    let other = PracticeItem(name: "持咒", measureType: .count, unit: "遍")
    ctx.insert(other)
    try ctx.save()

    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: other, amount: 21, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try ledger.total(on: 20260728, itemID: other.id) == 21)
}

@MainActor
@Test func 幂等检查能识别已入账的编号() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    #expect(try ledger.exists(sessionID: known) == false)

    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    #expect(try ledger.exists(sessionID: known) == true)
}

@MainActor
@Test func 同一编号重复入账只记一笔() throws {
    // 崩溃恢复场景：草稿携带预生成编号，恢复时若已入账则不可重复写。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)

    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 1)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 计时类流水以秒记账() throws {
    let (ledger, ctx, _) = try makeLedger()
    let sit = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(sit)
    try ctx.save()

    let start = 北京(7, 28, 5, 0)
    let end = 北京(7, 28, 5, 45)
    try ledger.record(item: sit, amount: Int(end.timeIntervalSince(start)),
                      source: .timer, startedAt: start, endedAt: end,
                      at: end, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: sit.id) == 2700)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `cannot find 'DayLedger' in scope`

- [ ] **Step 3: 实现**

`Sources/Store/DayLedger.swift`：

```swift
import Foundation
import SwiftData

/// 账本的**唯一**写入口。
///
/// 「只增不改不删」这条纪律如果散落在各个界面里就守不住，
/// 所以所有写操作收口到这里。界面层不许直接 `context.insert(PracticeSession…)`。
///
/// 标注 `@MainActor` 是因为 `ModelContext` 不是 Sendable，必须固定在一个执行域上。
/// v1 的写入量（一天几十笔）远达不到需要后台上下文的程度。
@MainActor
final class DayLedger {
    private let context: ModelContext
    private let deviceName: String

    init(context: ModelContext, deviceName: String) {
        self.context = context
        self.deviceName = deviceName
    }

    // MARK: - 写

    /// 记一笔。
    ///
    /// - Parameter id: 预生成编号。崩溃恢复时传入草稿里的编号，
    ///   本方法会先查重，已入账则直接返回既有记录，不会重复计数。
    @discardableResult
    func record(
        item: PracticeItem,
        amount: Int,
        source: SessionSource,
        startedAt: Date,
        endedAt: Date? = nil,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current,
        id: UUID = UUID(),
        note: String? = nil
    ) throws -> PracticeSession {
        if let existing = try fetch(sessionID: id) {
            return existing
        }

        let offset = DayKey.currentOffsetMinutes(at: now, timeZone: timeZone)
        let session = PracticeSession(
            id: id,
            item: item,
            dayKey: DayKey.make(from: now, tzOffsetMinutes: offset, dayStartHour: dayStartHour),
            tzOffsetMinutes: offset,
            amount: amount,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            deviceName: deviceName,
            note: note,
            createdAt: now
        )
        context.insert(session)
        try context.save()
        return session
    }

    /// 撤销一笔：追加一笔等额负数的 `.adjustment`。**原记录纹丝不动。**
    ///
    /// 新记录落在**原记录的 dayKey** 上而不是今天——
    /// 撤销昨天的误记，不该让今天的账面莫名少一截。
    @discardableResult
    func revoke(
        _ session: PracticeSession,
        at now: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        let adjustment = PracticeSession(
            item: session.item,
            dayKey: session.dayKey,
            tzOffsetMinutes: session.tzOffsetMinutes,
            amount: -session.amount,
            startedAt: now,
            endedAt: now,
            source: .adjustment,
            deviceName: deviceName,
            note: "revoke:\(session.id.uuidString)",
            createdAt: now
        )
        context.insert(adjustment)
        try context.save()
        return adjustment
    }

    // MARK: - 读

    /// 某天某项的全部流水。
    ///
    /// 先按 dayKey 取库、再在内存里按定课项过滤，是刻意为之：
    /// `#Predicate` 穿透可选关系（`$0.item?.id == x`）在 SwiftData 上行为不稳，
    /// 而一天的流水至多几十条，内存过滤的代价可以忽略。
    func sessions(on dayKey: Int, itemID: UUID) throws -> [PracticeSession] {
        let key = dayKey
        let sameDay = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.dayKey == key })
        )
        return sameDay.filter { $0.item?.id == itemID }
    }

    /// 某天某项的显示总数（负数已 clamp 到 0）。
    func total(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.displayTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 某天某项的账本原值（可能为负）。诊断与导出使用。
    func rawTotal(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.rawTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 该编号是否已入账。崩溃恢复前必查。
    func exists(sessionID: UUID) throws -> Bool {
        try fetch(sessionID: sessionID) != nil
    }

    private func fetch(sessionID: UUID) throws -> PracticeSession? {
        let target = sessionID
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 13 个 DayLedger 测试全部 `passed`，特别确认 `撤销是追加负数而非删除` 与 `同一编号重复入账只记一笔`

- [ ] **Step 5: 提交**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Store/DayLedger.swift Tests/DayLedgerTests.swift
git commit -m "feat: DayLedger 账本唯一写入口"
```

---

### Task 10: 快照与圆满判定

**Files:**
- Modify: `Sources/Store/DayLedger.swift`（在 `// MARK: - 读` 之后追加新的 `// MARK: - 快照与圆满` 区段）
- Create: `Sources/Core/FulfillmentState.swift`
- Test: `Tests/FulfillmentTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/FulfillmentTests.swift`：

```swift
import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeEnv() throws -> (DayLedger, ModelContext) {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx)
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 首次取快照会依当前定课生成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    let b = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: nil)
    ctx.insert(a); ctx.insert(b)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a, b])
    #expect(Set(snap.requiredItemIDs) == [a.id, b.id])
    #expect(snap.goals[a.id.uuidString] == 1000)
    #expect(snap.goals[b.id.uuidString] == nil, "未设目标的项不进 goals 字典")
}

@MainActor
@Test func 快照生成后不因定课变更而改写() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()

    _ = try ledger.snapshot(for: 20260728, activeItems: [a])

    a.dailyGoal = 3000
    try ctx.save()

    let again = try ledger.snapshot(for: 20260728, activeItems: [a])
    #expect(again.goals[a.id.uuidString] == 1000, "过去的日子不许被今天的设置改写")
}

@MainActor
@Test func 重复快照按最早一条为准() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    // CloudKit 不支持唯一约束，两台设备可能各生成一条同日快照。
    let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                            goals: [a.id.uuidString: 1000],
                            createdAt: Date(timeIntervalSince1970: 1000))
    let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                           goals: [a.id.uuidString: 9999],
                           createdAt: Date(timeIntervalSince1970: 2000))
    ctx.insert(late); ctx.insert(early)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])
    #expect(snap.goals[a.id.uuidString] == 1000, "去重必须确定性地取最早那条")
}

@MainActor
@Test func 排除已归档的定课项() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let old = PracticeItem(name: "旧功课", isArchived: true)
    ctx.insert(a); ctx.insert(old)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a, old])
    #expect(snap.requiredItemIDs == [a.id])
}

@MainActor
@Test func 未达目标为待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 500, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)
}

@MainActor
@Test func 达到目标为圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1000, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)
}

@MainActor
@Test func 未设目标时做了就圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "放生", measureType: .check, dailyGoal: nil)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1, source: .manual,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)
}

@MainActor
@Test func 当日不需做的项为无需完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let b = PracticeItem(name: "诵经")
    ctx.insert(a); ctx.insert(b)
    try ctx.save()
    // 只把 a 列入当日清单
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    #expect(try ledger.fulfillment(of: b.id, on: 20260728, snapshot: snap) == .notRequired)
}

@MainActor
@Test func 撤销后从圆满退回待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    let s = try ledger.record(item: a, amount: 1000, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)

    try ledger.revoke(s, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 编译失败，报 `value of type 'DayLedger' has no member 'snapshot'`

- [ ] **Step 3: 实现状态类型**

`Sources/Core/FulfillmentState.swift`：

```swift
import Foundation

/// 某项定课在某一天的完成状态。
///
/// 刻意区分 `.notRequired` 与 `.fulfilled`：
/// 月历上「今天本来就不用做」和「做完了」必须是两种颜色，
/// 把二者混为一谈会让用户以为自己做了实际没做的功课。
enum FulfillmentState: Equatable, Sendable {
    /// 当日清单里没有这一项
    case notRequired
    /// 在清单里，尚未达成
    case pending
    /// 在清单里，已达成
    case fulfilled
}
```

- [ ] **Step 4: 给 DayLedger 追加快照与判定**

在 `Sources/Store/DayLedger.swift` 的 `private func fetch(sessionID:)` 之前，插入以下区段：

```swift
    // MARK: - 快照与圆满

    /// 取某天的应做清单快照；不存在则依 `activeItems` 生成并落库。
    ///
    /// **已存在的快照绝不改写。** 用户今天把目标从 1000 调到 3000，
    /// 上个月那些标着圆满的日子不能因此变回未完成——
    /// 那等于告诉他过去三十天白做了。
    ///
    /// `DaySnapshot` 没有唯一约束（CloudKit 不支持），
    /// 两台设备可能各生成一条同日快照，故按 `(createdAt, id)` 确定性地取最早一条。
    func snapshot(for dayKey: Int, activeItems: [PracticeItem]) throws -> DaySnapshot {
        let key = dayKey
        let existing = try context.fetch(
            FetchDescriptor<DaySnapshot>(predicate: #Predicate { $0.dayKey == key })
        )
        if let earliest = existing.min(by: {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }) {
            return earliest
        }

        let required = activeItems.filter { !$0.isArchived }
        var goals: [String: Int] = [:]
        for item in required {
            if let goal = item.dailyGoal, goal > 0 {
                goals[item.id.uuidString] = goal
            }
        }

        let snapshot = DaySnapshot(
            dayKey: dayKey,
            requiredItemIDs: required.map(\.id),
            goals: goals
        )
        context.insert(snapshot)
        try context.save()
        return snapshot
    }

    /// 依快照判定完成状态。**永不按当前设置实时重算。**
    func fulfillment(
        of itemID: UUID,
        on dayKey: Int,
        snapshot: DaySnapshot
    ) throws -> FulfillmentState {
        guard snapshot.requiredItemIDs.contains(itemID) else { return .notRequired }
        let total = try total(on: dayKey, itemID: itemID)
        return LedgerMath.isFulfilled(total: total, goal: snapshot.goals[itemID.uuidString])
            ? .fulfilled
            : .pending
    }

```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make test`
Expected: 9 个 Fulfillment 测试全部 `passed`，全项目 `** TEST SUCCEEDED **`

- [ ] **Step 6: 全量回归**

Run: `cd /Users/bill/Documents/GitHub/wisewalk && make clean && make test`
Expected: 从零生成工程并跑完全部约 60 个测试，`** TEST SUCCEEDED **`

- [ ] **Step 7: 提交并推送**

```bash
cd /Users/bill/Documents/GitHub/wisewalk
git add Sources/Core/FulfillmentState.swift Sources/Store/DayLedger.swift Tests/FulfillmentTests.swift
git commit -m "feat: 当日快照与圆满判定"
env -u GIT_CONFIG_PARAMETERS git push
```

---

## 本卷验收标准

全部满足才算地基打好：

- [ ] `make clean && make test` 从零通过，无 error
- [ ] 跨时区测试证明同一时刻在北京与温哥华归属不同日期（B1）
- [ ] 撤销测试证明原记录仍在库中，总数靠求和得出（B2）
- [ ] 同编号重复入账测试证明只记一笔（B4）
- [ ] Schema 约束守卫测试覆盖 §4.6 全部四条
- [ ] 无任何实体持有「今日总数」类缓存字段（§4.4）
- [ ] 所有提交已推送到 `msebilly/wisewalk`

## 交给下一卷的东西

- `DayLedger.record(id:)` 的幂等入口 —— 第 2 卷草稿恢复直接用
- `ModelContainerFactory.onDisk()` —— 第 3 卷在此加 `cloudKitDatabase: .automatic`
- `FulfillmentState` 三态 —— 第 5 卷月历的三种颜色
- `PracticeItem.scheduleRule` —— 第 6 卷农历排班的输入

## 本卷刻意不做

- **界面**。除占位根视图外无任何 UI，全部留给第 2、5 卷
- **CloudKit 真实同步**。需要 Team ID 与 entitlements，且无法在模拟器上验证，留给第 3 卷
- **App Group 缓存**。§4.4 的缓存边界要连着小组件一起做才说得清，留给第 4 卷
- **农历**。`ScheduleRule` 只做了编解码，真正的农历换算留给第 6 卷
- **内置模板**。`templateKey` 字段已备好，八类模板的具体内容留给第 2 卷
