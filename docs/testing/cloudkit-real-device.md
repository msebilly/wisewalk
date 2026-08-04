# CloudKit 两台真机验收清单

本清单只验证 development 环境 `iCloud.com.msebilly.wisewalk`。核心不变量是：
**一声都不能丢，也一声都不能多。**

`iCloud 账户可用` 只说明账户查询与路径可用，**不说明任何记录已经传输**。
只有两台设备最终出现逐笔相符的账本，才是数据传输证据。

## 0. HARD STOP GATES

任一项不满足就停止，结论记为 **BLOCKED / UNVERIFIED**，不得继续凑出 PASS：

- [ ] 有有效的付费 Apple Developer Program 会员资格。
- [ ] App ID 已启用 iCloud/CloudKit 与 Push Notifications；development provisioning
      profiles 已重新生成并包含这些 capability。
- [ ] 两台物理设备 A、B 均为 iOS 17.4 或更高，登录**同一个专用、可丢弃的测试
      iCloud 账户**；不得使用用户真实账户或真实账本。
- [ ] CloudKit development container 精确为
      `iCloud.com.msebilly.wisewalk`，不是 production container 或相似名称。
- [ ] 只为本轮真机试验显式打开代码签名。仓库默认的
      `CODE_SIGNING_ALLOWED: NO` 不得被顺手永久改开；Team、App ID、capability 与
      profiles 配好后，仅 provisioned device/archive 配置加入
      `WISEWALK_VERIFIED_CLOUDKIT_DEVICE`。
- [ ] 明白该 flag **只解锁公开的 iCloud 账户查询**；它既不是 entitlement，
      也不是 CloudKit 已传输记录的证明。模拟器或未 provisioned 构建不得配置它。
- [ ] 已归档或提取本轮**实际安装的** `WiseWalk.app`，并检查其真实签名结果，而不是
      `WiseWalk.entitlements` 源文件或 Info.plist：

```bash
APP="/absolute/path/to/archive/Products/Applications/WiseWalk.app"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- "$APP"
```

签名输出必须精确包含：

| key | 必须值 |
|---|---|
| `com.apple.developer.icloud-container-identifiers` | 数组包含且本轮只使用 `iCloud.com.msebilly.wisewalk` |
| `com.apple.developer.icloud-services` | 数组包含 `CloudKit` |
| `aps-environment` | `development` |

缺任一项、值不同、签名校验失败或 factual account state 查不到：**立即停止**。
不得用私有 `SecTask` SPI 在运行时自证 entitlement。

- [ ] A/B 已记录设备标签、机型、OS、时区与各自不同的设备短码；所有定课标签带 case ID。
- [ ] 已记录旧本地构建与本轮 CloudKit 构建的**完整 40 位 Git SHA**，以及归档时间。
- [ ] 已选定观察窗口并写入证据表。窗口只是本轮观察边界，**不是同步 SLA**；窗口内
      未观察到所需事实只能记 BLOCKED / UNVERIFIED，不能记 PASS。

试验数据全部可丢弃。RD-01 作出结论前不得卸载 App、清 store 或“修复”数据。
后续 fresh-device case 可在保全 RD-01 证据后清除 B 的本地 App 数据；不得在 CloudKit
Console 编辑 SwiftData 私有 schema、删改记录或人为重排到达顺序。

## 1. 本轮记录

| 项目 | 实测值 |
|---|---|
| 测试 iCloud 账户代号（不要写真实邮箱） | [ ] |
| 旧本地构建完整 SHA | [ ] |
| CloudKit 构建完整 SHA | [ ] |
| Bundle ID / development container | [ ] |
| A：标签 / 机型 / OS / 时区 / 设备短码 | [ ] |
| B：标签 / 机型 / OS / 时区 / 设备短码 | [ ] |
| 归档时间 / 安装时间 | [ ] |
| 已核验的 signed-entitlements 输出路径 | [ ] |

每个独立重跑使用新的固定后缀（如 `-R2`），并把实际完整标签记入证据；不能复用旧标签
后把旧记录误认成本轮传输。

## 2. 每个 case 的证据表

每个 case/子运行都复制并填写一次：

| 字段 | 记录 |
|---|---|
| Case ID / 重连顺序 / 标签 | [ ] |
| A、B 实际安装的完整 build SHA | [ ] |
| 前置条件与初始逐笔账本 | [ ] |
| A 操作（含断网、终止、重连时刻） | [ ] |
| B 操作（含断网、终止、重连时刻） | [ ] |
| 中间态与首次观察时刻 | [ ] |
| 预先选定的观察窗口（仅证据，不是 SLA） | [ ] |
| 收敛条件与实际收敛时刻 | [ ] |
| 最终逐笔不变量、有效总数、实体计数 | [ ] |
| 截图 / 录屏 / 诊断 / 导出 / 设备日志路径 | [ ] |
| 结论：PASS / FAIL / BLOCKED-UNVERIFIED | [ ] |

判定规则：

- **PASS**：前置、操作、中间态（若该 case 要求）、收敛条件与最终不变量均有证据。
- **FAIL**：观察到丢失、重复、改量、错归属、崩溃、假圆满/假无课或跨账户数据。
- **BLOCKED / UNVERIFIED**：所需状态没出现、无法辨认真正到达顺序、账户/能力不可用、
  iOS 阻止操作，或证据不足。**没看到不是 PASS。**
- 状态栏 `iCloud 账户可用` 只能填“账户路径可用”；必须另填 A→B、B→A 的逐笔传输证据。

## 3. REQUIRED CASES

### RD-01 — 既有本地 store 原地升级（解除 `v3-migrate-safety`）

1. A 安装当前 local-only 构建。确认 build SHA 后，使用 UI 建立三个固定标签：
   `RD01-声-500-37`（目标 37）、`RD01-坐-31m`（目标 31 分钟）、
   `RD01-勾-1`（目标 1 次）。打开今日页形成当天 snapshot。
2. 在 `RD01-声-500-37` 用计数器完成 **+37**，再从补记 UI 手动记 **+500**，
   并在补记/修正 UI 撤销这笔 +500。预期可见流水为 `+37 counter`、
   `+500 manual`、`-500 adjustment`，有效总数精确为 **37**。
3. 从 UI 为 `RD01-坐-31m` 记 **31 分钟**，为 `RD01-勾-1` 完成 **1 次**。
   截取每条流水的量、来源、日期、设备名、撤销关系，以及当日三项集合和目标；
   不能只记三个 entity count。
4. **不卸载、不重装、不清数据**，保持相同 bundle ID，在 A 上覆盖安装已签名
   CloudKit build；这才是同一 store 的 in-place upgrade。
5. 首次启动后立即复核：三项、目标、snapshot、逐笔流水与有效总数必须与步骤 2–3
   完全相同。到观察窗口收敛后再复核一次，仍须完全相同。
6. B 首次安装同一完整 SHA 的 CloudKit build。等待本 case 的收敛条件：
   B 出现同样的三项/目标/snapshot，并逐笔核对量、来源、日期、设备落款、原 +500 与
   撤销笔，以及有效总数 `37 / 31m / 1`；随后 A 再复核一次。

任何记录缺失、重复、改量、改日、错归属或目标变化：**FAIL，禁止发布**。
窗口内不能取得逐笔证据：**BLOCKED / UNVERIFIED**。不得用删除、重建或迁移 store
把失败“修好”。

### RD-02 — 双向、离线与三种重连顺序

分别做三个独立运行：`RD02-AFIRST`、`RD02-BFIRST`、`RD02-SAME`。每次先让一个同名
计数项及其目标在 A/B 都可见，再同时离线：

1. A 离线完成一笔 **41**，B 离线完成一笔 **73**，两边都结束会话。
2. 三次分别按 A 先联网、B 先联网、两边同时联网；记录每次中间态，不把暂时缺记录当失败。
3. 收敛条件：A/B 各自都显示两笔不同设备的正流水，逐笔为 41 与 73，数学和精确为
   **114**；终止重启两边后仍为 114，且没有完成草稿再次弹恢复或生成第三笔流水。

任何顺序最终少一笔、多一笔或不等于 114 为 **FAIL**；仅未观察到收敛为
**BLOCKED / UNVERIFIED**。

### RD-03 — 设备名确由远端记录传来

1. 用 A 在共享项完成一笔 **17**，等它真实出现在 B。
2. B 的该行必须显示 A 的设备名/短码；再由 B 完成 **19**。
3. B 自己的 19 行不显示 B 名，A 上的 19 行显示 B 名；两边最终总数均为 **36**。

`e2e/10-remote-device.sh` 只 seed 模拟器 SQLite，证明持久化字段到 UI 的接线，
**没有证明 CloudKit 传输**，不能替代本 case。

### RD-04 — [§5.6 到达顺序风险（fresh/cleared B）](../design-spec.md#56-已定案2026-07-30同步半到时定格的当日应做集合会残缺)

App/SwiftData 没有受支持的接口强制 CloudKit 记录顺序。每个子项最多做五次独立
fresh-device B 运行：先保存前一轮证据，再清 B 的本地 App 数据并重新安装同一 SHA，
开启屏幕录制，启动后连续记录 UI 与可用的诊断/导出实体计数。CloudKit Console
最多只读观察，绝不编辑私有 SwiftData schema 或记录来制造顺序。

若没有证据证明指定中间态真实发生，子项就是 **BLOCKED / UNVERIFIED**：

**RD-04a snapshot 先于 items**

- 中间态证据必须同时证明 snapshot 已到而对应 `PracticeItem` 尚未齐，并记录
  unresolved 数/实体数；此时不得显示假「圆满」或假「无课」，未解析项仍在分母。
- 收敛后缺项自行出现，A/B 的应做集合、目标与有效账本逐项相同。

**RD-04b items 先到、snapshot/首次打开在后**

- A 预先准备“日开始前已激活”的项目与目标。B 只收到部分项目后首次打开并定格时，
  后到的旧项目必须以追加 snapshot 自愈，最终集合/目标与 A 相同。
- 另记录有意的不对称：非空快照形成后，**当天才激活且随后迟到**的项目不得被
  retroactive append；但无快照的初次定格（以及仍为空的快照路径）会收下当时全部
  在册项目。两种路径的最终集合都按此规则逐项截图，不能把差异当成自动一致。

**RD-04c session 先到、`PracticeSession.item == nil`**

- 中间态证据必须明确显示 session 已存在但关系未解析；仅看到总数偏低不足以证明原因。
- 该窗口内不得崩溃或归到错误项目；per-item 总数只能保守偏低，不能假增。
- 关系解析后，同一 session 必须回到正确项目，A/B 的逐笔账与总数精确一致。
- 五次内没有捕获到真实 nil 窗口，或现有受支持诊断无法辨认 nil：**BLOCKED**，不是 PASS。

### RD-05 — [§5.7 两设备离线撤销同一原记录](../design-spec.md#57-两台设备各撤一次同一笔会扣两次已定案)

分别做 `RD05-AFIRST`、`RD05-BFIRST`、`RD05-SAME`：

1. 先让 A/B 都看到同一原始 **+500** 与一笔对照 **+300**，总数 800。
2. 两边离线，各自从 UI 撤销同一笔原始 +500；再按三种顺序重连。
3. 所有中间态都不得出现负数或双扣；收敛后 A/B 有效总数均精确为 **300**。
   原始 +500 行仍存在，+300 不变，读侧只呈现一次该撤销效果。
4. 保存 append-only 证据。若两条物理 adjustment 被读侧去重，诊断/导出要如实记录
   能确认的物理条数、共同 `revoke:<原记录 id>` 与不同 UUID；若工具未暴露物理层，
   写明“物理条数未知”，不得声称重复记录已被删除。

双扣、负数、原记录消失或任一设备不是 300：**FAIL**。

### RD-06 — 已观察到的半状态下终止与恢复

只对 RD-04 已用证据捕获的 snapshot-half 或 relation-nil 窗口执行；这里的“半状态”必须是**已经真实观察到的部分到达态**，不是人为制造的顺序：

1. 在该窗口内先把 App **送到后台但不终止**，等待并记录此时的 UI / 日志 / 实体计数；再回到前台，确认仍处于同一半状态。
2. 之后分别做 **终止 → 重新启动**，以及 **锁屏 → 解锁**；记录每一步 UI / 日志 / 实体计数，且三组动作必须独立留证，不能把后台/前台切换混同为终止重启，也不能把锁屏/解锁混同为终止重启。
3. 全程不得崩溃、不得显示假圆满/假无课、不得错误归项。
4. 窗口结束后必须逐笔自愈到 A 的精确集合、目标与账本；若未自愈到完全一致，只能记 **BLOCKED / UNVERIFIED**，不得写成 PASS。

这是**观察性验证，不是可诱发保证**。捕获不到窗口就记 **BLOCKED / UNVERIFIED**，
不能把普通重启成功写成 PASS。

### RD-07 — iCloud 账户退出、切换与返回

1. 用专用账户在 A 建 `RD07-ACCOUNT-A` 流水，并先在 B 逐笔确认真实传输。
2. 在 B 退出 iCloud；等待 `.CKAccountChanged` 后，底栏必须刷新为对应的
   “记录目前只在这台设备上”不可用事实，不能仍显示账户可用。
3. 若有第二个可丢弃账户，先清 B 本地 App 数据再切换，确认全新安装看不到
   `RD07-ACCOUNT-A`；在第二账户创建 `RD07-ACCOUNT-B`，原账户的 A 也不得收到它。
4. B 返回原专用账户并重新安装/启动：先单独记录账户状态恢复，再等待
   `RD07-ACCOUNT-A` 逐笔回来；“账户可用”本身不算数据恢复。

iOS/MDM 阻止退出或切换、没有第二个可丢弃账户，受影响子项记 **BLOCKED**。
发现跨账户数据集静默出现为 **FAIL**。

### RD-08 — 草稿只留本机

计数器与计时器各做一次独立运行：

1. A 开始但不结束草稿：计数器停在 **19**；计时器运行后记录 A 当时可见时长。
2. 保持 A 草稿未完成，B 终止并重启。B 不得出现该草稿、恢复提示或账本流水。
3. A 完成草稿，记录最终量/时长与唯一流水；等待 B 出现同一最终流水。
4. 两边终止重启，最终流水仍各只有一笔，量完全相同，B 从未恢复 A 的草稿。

草稿传到 B、B 弹恢复、最终流水缺失或重复均为 **FAIL**。

### RD-09 — 离线写入后先重启、再联网

1. 先让 A/B 都看到共享项原始 **+90**。
2. A 离线：创建新项 `RD09-OFFLINE-30`（目标 30），手动记 **+23**，再用计数器
   完成 **+7**；同时撤销共享项原始 +90。
3. **仍离线**时终止并重启 A。必须本地保留：共享项 `+90/-90 = 0`，
   新项两笔 `23+7 = 30`，且没有恢复已完成草稿或重复流水。
4. A 联网；收敛后 B 必须出现新项、目标与四条相关流水各一次，两个有效总数精确为
   0 与 30。再重启 A/B 复核一次。

离线重启后丢失、联网后重复或归错项目为 **FAIL**。

## 4. RELEASE GATE

| Case | PASS | FAIL | BLOCKED / UNVERIFIED | 证据路径 / 备注 |
|---|:---:|:---:|:---:|---|
| RD-01 migration safety | [ ] | [ ] | [ ] | [ ] |
| RD-02 bidirectional/offline | [ ] | [ ] | [ ] | [ ] |
| RD-03 device name | [ ] | [ ] | [ ] | [ ] |
| RD-04a snapshot before items | [ ] | [ ] | [ ] | [ ] |
| RD-04b items before snapshot/open | [ ] | [ ] | [ ] | [ ] |
| RD-04c unresolved relation | [ ] | [ ] | [ ] | [ ] |
| RD-05 duplicate revoke | [ ] | [ ] | [ ] | [ ] |
| RD-06 partial-state resilience | [ ] | [ ] | [ ] | [ ] |
| RD-07 account change | [ ] | [ ] | [ ] | [ ] |
| RD-08 draft locality | [ ] | [ ] | [ ] | [ ] |
| RD-09 offline/relaunch | [ ] | [ ] | [ ] | [ ] |

- 任一 **FAIL** 都必须调查；RD-01、RD-02、RD-05、RD-08 任一 **FAIL 或 BLOCKED**
  都禁止默认启用 CloudKit。
- RD-04/RD-06 这类到达窗口观察项可以保持 BLOCKED，前提是把未观察事实与残余风险
  明确写入产品/规格并由发布负责人签收；不得改写成 PASS。
- 模拟器、单元测试与 seeded e2e 都必要但不充分，不能代替两台真机逐笔证据。
- **回滚闸门**：RD-01 通过前，绝不发布“既有 store 直接用 CloudKit 打开”；
  失败后不删除、不迁移 store 来伪造修复，先保全 App 版本、store、截图、日志与诊断。
- 不得声称已有本地 JSON 备份。`docs/design-spec.md` §5.3 是规划项，当前未实现，
  不能拿它当本轮回滚或数据保险。
