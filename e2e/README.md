# e2e —— 视图层的回归网

## 为什么有这个目录

单元测试 369 条全绿的那几天里，手点模拟器点出了 **6 条 bug**，
其中 3 条会让**整个 App 点不动，只能杀进程**，1 条是 **3600 倍的丢账**。

**没有一条是单元测试够得着的。**

三条死锁全长在 `.alert` 的 `isPresented` 上——那是 SwiftUI 自己的状态机，
只有真的点下去才知道：

| 写法 | 后果 |
|---|---|
| `.constant(!pending.isEmpty)` 作 `isPresented` | SwiftUI 关窗时写回 `false` 被丢弃 |
| `accept()` 抛错时故意留着 pending | alert 已经拆了，`.disabled` 却还锁着 |
| `showRecovery` 从 `true` 又写成 `true` | 不算状态变化，第二份草稿不弹 |

三条的表征一模一样：**弹窗没了，界面永远解不开锁。**

这个目录不追求覆盖率。它只盯**「一点就废」和「够得着账本」**的那几条路。

## 怎么跑

```bash
brew install maestro          # 或 curl -Ls 'https://get.maestro.mobile.dev' | bash
make install-sim              # 编译并装进当前开着的模拟器
./e2e/run.sh                  # 跑全部
./e2e/run.sh 03               # 只跑 03
```

03 得先把草稿造出来，所以它是个脚本（`03-recovery.sh`）而不是裸 flow，
`run.sh` 会连它一起跑。

**不进 CI** —— 要真模拟器。合并前手动跑一遍，尤其是动过弹窗、输入框、
导航的时候。

## 每条守什么

| flow | 守的 commit | 一句话 |
|---|---|---|
| `01-first-run` | `578d9aa` `2cded4f` | 装上头一天立的第一门课，当天就得能记 |
| `02-counter-exact` | 立身之本 | 点 20 下就是 20 声，一声不多一声不少 |
| `03-recovery-alert` | `95ee7fc` `fe8aeb6` | **弹窗关掉之后界面还点得动**（由 `03-recovery.sh` 驱动，见下）|
| `04-migration-duration` | `6c12439` `08fb0ba` | 计时类的以往累计按时分问，不是问秒 |
| `05-chinese-only` | `35e8117` | 界面里不许冒 `Edit` / `Cancel` |
| `05-chinese-info` | 本机记的那些不必每行都报一遍机器名 | 流水那行小字里不许冒 `iPhone·XXXX` |
| `07-timer` | 走时和今日两个数得分得出哪个是哪个 | 小号自报「今日」，且读屏软件拿得到两个数 |
| `06-postpone-then-manual` | `837ebc1` | 推迟之后他自己补记过，再问时得说出账上已有的数（由 `06-postpone.sh` 驱动）|

## 这张网真咬得住吗

不问「它跑绿了吗」，问「它红得起来吗」——两个变异实测：

| 变异 | 结果 |
|---|---|
| 把 `fe8aeb6` 退回去（`showRecovery = !pending.isEmpty`，从 true 又写成 true）| 03 在**答完第一份之后**红，脚本另报「还剩 1 份草稿没裁决」 |
| 迁移页 `syncDial` 写 `hours*60+minutes`（当成分钟）| 04 红在 `已经记过以往累计 3 小时` |
| `metaText` 去掉 `!= thisDevice`（本机记的也报机器名）| 05-chinese-info 红在 `.*iPhone.*` 竟然可见 |
| 计时页删掉 `.accessibilityValue(...)` | 07-timer 红。**这一口专挑单元测试够不着的那一段**：`subtitleText` 是纯函数、单元测试钉得死，但「视图有没有真去调它」「读屏软件拿不拿得到」只有跑真机才知道 |
| `accept/discard` 不刷新「账上已有的数」| 单元测试红（`这个数得跟着队头的那一份走`）|
| 「那一笔要落的那天」换成「今天」| 单元测试红（`昨晚崩的今早问要摆昨天的账不是今天的`）|

第二条值得多看一眼：变异之后「小时」「分」两个标签**照样在**，
01/02/05 也照样绿——**红的是账上那个数**。
断言挑「3 小时」而不是挑标签，这一步没白挑。

改动这几条 flow 之后，请照样咬一口再信它。

## ⚠️ 造草稿要把 `startedAt` 错开

`RecoveryCoordinator` 按 `(startedAt, id.uuidString)` 排序。两份草稿时间戳一样，
就退化成**按随机 UUID 比大小**——先问哪一份成了掷硬币，
靠「先问 108」立论的断言一半时间红一半时间绿。而它**头一回还会跑绿**。

`lib.sh` 的 `ww_seed_drafts` 已经按序错开了。自己写别的 seed 时别忘了。

## 写 flow 的几条经验

**用文本选择器，别用坐标。**
`tapOn: "记入以往的累计"` 比 `tapOn: {point: "50%,70%"}` 可靠得多，
而且它顺带验了无障碍标签在不在——**Maestro 点不着的东西，读屏软件也念不出来**。
迁移页那两个数字框就是这么发现没有 label 的（`9802c5d`）。

**非要用坐标就用百分比**，`pt` 无效。首屏几个常用的：

| 位置 | 坐标 |
|---|---|
| 右上「定课管理」 | `90%,10%` |
| 左上「补记 / 返回」 | `10%,10%` |
| 计数器点击区 | `50%,45%` |

**⛔ 草稿造不出来，只能往库里插。** 我原先以为 `stopApp` 留得下草稿，**是错的**：
`CounterView` 上挂着 `onDisappear { commit() }`，而 SwiftUI 在 App 被 terminate 时
**也会拆视图树、跑一遍 onDisappear**。实测杀完查库——主库里躺着那 20 声，
草稿是 0：`stopApp` 不但没留下草稿，反而替用户把它提交了。
真留得下草稿的只有 SIGKILL / OOM / 崩溃，都不是 flow 里做得到的事。

所以 `03-recovery.sh` 直接往草稿库插，**而且插两份**——`fe8aeb6` 那条
（答完第一份第二份不弹）只有两份才现得出原形，而就算杀得动进程也只留得下一份。
造法见那个脚本，要点：

- 草稿库和主库是**分开的两个文件**：主库 `Library/Application Support/WiseWalk.store`，
  草稿库 `Library/Application Support/LocalOnly/WiseWalkLocal.store`
- `Z_ENT=4` 是 `SessionDraft` 的实体号
- 插完必须 `UPDATE Z_PRIMARYKEY SET Z_MAX=… WHERE Z_NAME='SessionDraft'`，否则 App 下次撞主键
- Core Data 的时间戳从 2001 年起算，要 **+978307200**
- `ZITEMID` 是 UUID 的 16 字节二进制：`X'$(sqlite3 主库 "select hex(ZID) from ZPRACTICEITEM limit 1;")'`

**这条推论值得单独记一笔**：既然正常「杀 App」会走 commit，
**恢复弹窗在日常使用里根本不弹**，它真正的触发面只有崩溃和 OOM，
比设计时设想的窄得多。那三条死锁修得对（撞上了就是只能杀 App），
但撞上的概率没那么高。

**拿数据库当第二双眼睛。** 屏幕说「3 小时」不等于账上是 10800：

```bash
sqlite3 -header "$C/Library/Application Support/WiseWalk.store" \
  "select ZAMOUNT, ZNOTE from ZPRACTICESESSION where ZNOTE like '%migration%';"
# 查重复记账：
sqlite3 "$C/.../WiseWalk.store" \
  "select count(*), count(distinct ZID) from ZPRACTICESESSION;"
```

**报 COMPLETED 之后要 `sleep 2` 再截图**，不然拍到动画中间态。
`scrollUntilVisible` 不太靠得住，多来几次 `swipe` 更稳。
`maestro hierarchy` 对 SwiftUI 几乎是空的，别指望它。

**一个可见 `Text` 和一个同名 `accessibilityLabel` 撞车时，文本选择器会挑错。**
补记页的数量框就是这样：`Text("数量")` 和框的标签都叫「数量」，
`tapOn: "数量"` 点中的是那个 `Text`，`index: 1` 也不灵，只能落回坐标。
**这是测试的歧义，不是 App 的缺陷**——VoiceOver 读到框时说「数量, 0」，正是要的。

**bash 3.2 的两个坑**（macOS 自带的就是 3.2，改不了）：
中文标识符不认（`模式=x` 报 `command not found`）；
更阴的是 `"$UDID）"` 这种——中文标点的 UTF-8 高位字节会被当成变量名的一部分，
`set -u` 下报 `UDID）: unbound variable`。**挨着中文的变量一律写 `${UDID}`。**

**管道里取 maestro 的退出码要用 `${PIPESTATUS[0]}`**，`| grep` 之后 `$?` 是 grep 的。

**`run.sh` 用 `flows/[0-9]*.yaml` 遍历**，不然会把 `subflows/` 里的当独立 flow 跑。
flow 之间要各自自包含（`runFlow: subflows/…` + `launchApp: {clearState: true}`），
不然前一条留下的草稿会挡住后一条——踩过。

## ⛔ 机器忙的时候跑出来的红绿，一个都不算数

2026-08-03 实测：邻居项目在跑变异循环（load average 22）时连跑两轮，
**红的每轮换一批**——

| 轮次 | 红的 |
|---|---|
| 第一轮 | `05-chinese-only` `07-timer` `06-postpone` |
| 第二轮 | `02-counter-exact` `04-migration` `05-chinese-only` `07-timer` `03-recovery` |

同一份代码，机器闲下来再跑**全绿**。Maestro 的每一步都带超时，
机器一慢就判成「没找着那个元素」。

**红是假的，绿更可疑。** `assertNotVisible` 在页面根本没渲染出来时会**凭空通过**
——而这一套里 `05-chinese-only`（不许有 `Edit`/`Cancel`）、
`05-chinese-info`（不许有 `iPhone`）恰恰都是这个形状。
所以那两条 flow 的 `assertNotVisible` 前面都先钉了一句 `assertVisible`：
先证明页面确实渲染出来了，那句「不许有」才有内容。

`run.sh` 因此**忙就不跑**（不是「等一等再跑」）：

- 等 `xcodebuild` 连着三次不在（变异循环在两次编译之间有空档，查一次会漏）
- 一分钟负载 ≥ 核数就直接 `exit 1`

出一个没人敢信的判决比不出判决更坏。`Makefile` 的 `test` 目标为同一个理由
早就设过同一道闸——`run.sh` 一直缺着。

⚠️ 顺带又踩了一次 bash 3.2：`"负载 $load，太忙"` 里那个**中文逗号**的高位字节
被当成变量名的一部分，`set -u` 报 `load?: unbound variable`。
**挨着中文标点的变量一律写 `${load}`。** 这条 README 里记过，还是又犯了。

### 第三道闸：别的项目在用同一台模拟器

负载闸拦不住这个。实测：邻居项目往同一台 `iPhone 17` 上装
`Horcrux`/`DTest`/`MTest`/`VTest` 跑测试，**把慧行连人带数据一起掀了**
——屏幕停在桌面，图标还是灰的。这时候 8 条 flow 红 6 条，
而机器负载只有 6，前两道闸一道都拦不住。

报「没过」是**说谎**：flow 没问题，代码没问题，是环境被抢了。

所以：跑之前确认 App 在；每条 flow 红了之后**再确认一次它还在**——
不在就整轮作废（`exit 2`），不给任何红绿判决。
「残缺的跑整轮作废，不许从里面挑结论」，与 `Makefile` 那次并发事故同一个结论。

三道闸都验过会拦人（阈值/包名临时改坏，各自报对了话并给出非零退出码）。

想彻底躲开就给慧行单开一台模拟器，用 `WW_SIM_UDID` 指过去。
