# 龙门客栈 v5.2 · 运行时优化方案（只出方案，未改现役脚本）

- 出具：2026-11-08 14:35（Asia/Shanghai）
- 对象：`D:\tmp\xiaozhu_live.ps1`
- 现役快照：SHA256 `E40175C9D77F0EDAAA36F98760077BF139FA0DA3567B41A8205177971FF5CFC7`，141,627 B，2026-11-07 21:57:26
- 运行基线：pid 23604，14:17:06 启动，14:17:14 写入 `live3_ok`，`entries=440`
- 本文所有行号以这份 SHA 为准。**只出方案，没改一行代码、没动配置、没重启应用。**

---

## 0. 一句话结论

这个软件现在不是"功能不够"，而是**一条 2 秒轮询把全量数据解析两次、把 440 条消息全部实例化、每条还带独立右键菜单和阴影**。先做"增量缓存 + 渲染减量 + 搜索去抖"三件事，空闲 CPU 能从 11.2% 降到 3% 以下、启动从 8 秒降到 3.5 秒内；架构拆分和虚拟化放到后面，不要先动。

---

## 1. 基线（2026-11-08 14:17–14:35 实测）

| 指标 | 实测值 | 取法 |
| --- | --- | --- |
| 空闲 CPU | **11.2%**（20 秒采样 2.23s CPU） | `Get-Process` 两次采样 |
| 进程累计 CPU | 111.8s / 17.8 分钟 ≈ 10.5% 平均 | pid 23604 |
| 工作集 | **337 MB**（采样前 327.8，采样后 337.3） | `WorkingSet64` |
| 线程 / 句柄 | 12 / 729 | `Get-Process` |
| 启动耗时 | **约 8 秒**（14:17:06 进程启动 → 14:17:14 `live3_ok`） | 进程 StartTime 对比 `live3_ok` |
| 聊天条目 | 440 条（启动日志） | `live3_ok`、`app.log` |
| 数据量 | feed 75 条 / 13,004 B；board 369 条 / 420,726 B | 现查 |
| 视图切换 | 2–40 ms（`ui.log` 已有埋点，这块没问题） | `health\ui.log` |
| 成品 / 占坑 | 0 个 mp4、32 个孤儿缩略图、3 个 job 目录 | 现查 |

### 1.1 代码级基准（隔离进程实测，未碰现役）

| 操作 | 耗时 |
| --- | --- |
| board 369 行：`ReadAllLines` + 逐行 `ConvertFrom-Json` + `$items +=` | **56.3 ms** |
| 同数据改用 `List.Add` | **22.7 ms** |
| feed 75 行同上 | 4.1 ms |
| board 时间戳解析 + `Sort-Object` | 10.9 ms |
| 100 个 TextBox + 4 项右键菜单 + DropShadowEffect（离树，无布局） | 227.4 ms ≈ **2.27 ms/条** |

**结论：每个 2 秒 tick 光数据层就要 ≈ 56.3×2 + 4.1 + 10.9 ≈ 128 ms**（见 2.1），这一项就解释了约 6.4% 的 CPU；剩下的 4–5% 来自 WPF 渲染、呼吸动画和 GC。

---

## 2. 根因链（代码可查，不靠猜）

### 2.1 每 2 秒把 board 全量解析两次

- 定时器：[xiaozhu_live.ps1](file:///D:/tmp/xiaozhu_live.ps1#L2658-L2661) 每 2 秒跑 `Refresh-Feed; Tick-LiveBadge; Refresh-Collab; Update-CollabBadge; Update-JobStatus`。
- 第一次解析：`Refresh-Feed → Read-MergedFeed → Read-BusJsonl("board.jsonl")`（[L1045-L1068](file:///D:/tmp/xiaozhu_live.ps1#L1045-L1068)、[L2304-L2313](file:///D:/tmp/xiaozhu_live.ps1#L2304-L2313)）。
- 第二次解析：`Refresh-Collab` 在判断签名之前就先 `Read-BusJsonl "board.jsonl"`（[L2452-L2459](file:///D:/tmp/xiaozhu_live.ps1#L2452-L2459)），即使传菜口没打开也照读。
- `Read-BusJsonl` / `Read-Feed` 都是 `$items += ...`（[L82](file:///D:/tmp/xiaozhu_live.ps1#L82)、[L2310](file:///D:/tmp/xiaozhu_live.ps1#L2310)），数组每次追加都整段复制，56.3 ms 里一大半是这个。

### 2.2 聊天 440 条全部实例化，每条一个 TextBox + 独立右键菜单 + 阴影

- `New-EntryView` 每条消息建 Border/StackPanel/多个 TextBlock/一个只读 TextBox，并加 `DropShadowEffect`（[L1070-L1131](file:///D:/tmp/xiaozhu_live.ps1#L1070-L1131)）。
- `Attach-CopyMenu` 每条消息新建一个 ContextMenu，里面 4 个 MenuItem（[L97-L116](file:///D:/tmp/xiaozhu_live.ps1#L97-L116)）。
- 440 条 × 2.27 ms ≈ 1 秒只是对象创建；再加布局、动画、加入可视树，启动 8 秒的主要体量在这里。
- 这是 337 MB 工作集和滚动卡顿的主因。29 号审单已把"时间线窗口化 / 阴影降级 / tick 分频 / 真虚拟化"列为层二，**尚未施工**。

### 2.3 搜索恢复后，每次按键都全量重建

- 32 号把搜索整组恢复（[L380-L386](file:///D:/tmp/xiaozhu_live.ps1#L380-L386)、[L1008-L1013](file:///D:/tmp/xiaozhu_live.ps1#L1008-L1013)、[L2571-L2582](file:///D:/tmp/xiaozhu_live.ps1#L2571-L2582)）。
- `SearchBox.Add_TextChanged` 每次都 `$script:forceRefresh = $true; Refresh-Feed`，而 `forceRefresh` 会 `Clear()` 后重建全部命中条目（[L1140-L1165](file:///D:/tmp/xiaozhu_live.ps1#L1140-L1165)）。清空搜索 = 重建 440 条；按一个常见字 = 重建几百条。按同构条目成本推断是秒级，需先埋点坐实。
- 过滤用 `-notlike ("*" + $script:filter + "*")`（[L1154](file:///D:/tmp/xiaozhu_live.ps1#L1154)）。**已实测**：输入 `[` 时 PowerShell 抛「指定的通配符模式无效: *[*」，这个异常会走 Dispatcher 未处理异常，搜索当场失效。

### 2.4 启动期还预建了暂时看不到的东西

- `Loaded` 里直接 `Refresh-Feed`（440 条）+ `Refresh-Collab`（即使传菜口没开，也会建最近 100 张 CbCard）（[L2610-L2639](file:///D:/tmp/xiaozhu_live.ps1#L2610-L2639)、[L2496-L2504](file:///D:/tmp/xiaozhu_live.ps1#L2496-L2504)）。
- 工坊的参数卡、六槽卡、三视图三格在脚本加载时就全部建好（[L1243-L1490](file:///D:/tmp/xiaozhu_live.ps1#L1243-L1490)），即使用户从不进工坊。

### 2.5 持续渲染与同步阻塞

- 呼吸点 Storyboard 是 `RepeatBehavior.Forever`（[L1795-L1819](file:///D:/tmp/xiaozhu_live.ps1#L1795-L1819)），窗口最小化/失焦时也不停。
- `Ensure-Thumb` 在 UI 线程 `Start-Process ffmpeg ... -Wait`（[L1968-L1981](file:///D:/tmp/xiaozhu_live.ps1#L1968-L1981)），成品页首次打开或刷新时，每个缺缩略图的视频都会冻住界面。
- `Update-JobStatus` 在工坊打开时每 2 秒扫 jobs 目录 + 读 `job.json`（[L1514-L1536](file:///D:/tmp/xiaozhu_live.ps1#L1514-L1536)），没有文件签名缓存。

---

## 3. 施工分单（按性价比排序）

> 建议一批一单，每单独立镜像、独立重启、独立证据包。不要把 A–F 混成一次大改。

### 单 A（P0）数据层增量缓存 + tick 收口

**症状/证据**：空闲 CPU 11.2%，每 tick 数据层约 128 ms，且这 128 ms 跑在 UI 线程上，会顶掉入场动画和滚动。

**改法**
1. 给 feed / board 各建一个缓存对象：`path / length / lastWriteTimeUtc / position / items(List) / timestamps`。每次只读新增的完整行，只解析新行；文件变短或同长但 mtime 变了才全量重载。
2. `Read-MergedFeed` 与 `Refresh-Collab` 共用同一份 board 缓存，删掉第二次 `Read-BusJsonl`。
3. 合并时间线缓存：新条目到达才追加 + 排序一次（10.9 ms），**无变化时 0 解析、0 排序**。
4. tick 拆分：
   - 每 2 秒只做"文件 stat + 缓存更新 + 徽章计数"；
   - `Refresh-Collab` 只在传菜口可见时跑；
   - `Update-JobStatus` 只在工坊可见且 `job.json` 签名变化时跑；
   - `Refresh-Products` 只在成品页可见且文件签名变化时跑（已有签名，保留）。
5. 聊天视图不可见时不重建 UI，只把数据标脏；`Set-View 'chat'` 时再补渲染。

**预期**：tick UI 线程耗时 128 ms → **10 ms 以内**；空闲 CPU 11.2% → **约 3%**；新消息到达延迟不变（仍 2 秒轮询）。

**验收**
- 缓存追加：应用运行中向 board 追加 3 条带 `ref=TESTCACHE` 的测试帖，界面 2 秒内出现且不重复、不丢。
- 截断/换文件：把 board 换成较短副本，应用应全量重载而不是只读尾部。
- 跨天：feed 写一条只有 `HH:mm:ss` 的昨日深夜条目，排序仍正确。
- 空转：窗口静置 60 秒，`ui.log` 里 tick 耗时 p95 ≤ 10 ms；CPU 采样 ≤ 3%。

**风险**：中低。缓存边界（文件被截断、并发写、末尾半行）是唯一容易出错的地方；必须保留"检测异常就全量重载"的兜底。

---

### 单 B（P0）聊天渲染减量

**症状/证据**：440 条全部实例化，337 MB、启动 8 秒、搜索/切主题重建全量。

**改法**
1. **渲染窗口**：数据仍全量保留，界面默认只渲染最近 120 条；顶部加「加载更早（还剩 N 条）」，点一次向前扩 100 条，插入时保持当前滚动位置不跳。
2. **共享右键菜单**：只建 1 个 ContextMenu，所有消息 TextBox 共用；菜单项点击时用 `PlacementTarget` 取当前文本框。先在隔离副本验证共享菜单开合正常，不行就退化为"首次右键再懒创建"。
3. **去掉每条气泡的 DropShadowEffect**（[L1102-L1105](file:///D:/tmp/xiaozhu_live.ps1#L1102-L1105)），改用 1px 弱描边；工坊里 4 处静态阴影保留（不进聊天热路径）。此项是视觉变化，需掌柜点头。
4. **加粗不再递归遍历**：`$script:BoldChat` 直接在 `New-EntryView` 创建时给 body/meta/chip 设 FontWeight，删掉 `Set-AllBold` 的整棵可视树递归（[L1858-L1869](file:///D:/tmp/xiaozhu_live.ps1#L1858-L1869)）。
5. **启动后置**：`Loaded` 里不再预建传菜口 100 张卡；工坊参数卡/六槽卡改成首次 `Set-Studio($true)` 时再建。窗口先显示，再渲染最近 120 条。
6. **切主题不重建全量**：`DarkBtn` 现在 `forceRefresh` 会重建 440 条（[L989-L995](file:///D:/tmp/xiaozhu_live.ps1#L989-L995)）；改成只更新已渲染条目的画刷，或按 120 条窗口重建。

**预期**：启动 ≤ 3.5 秒；工作集 ≤ 200 MB；滚动不再被全量重建顶掉；切主题 ≤ 0.5 秒。

**验收**
- 深浅两套三视图截图，与改前同尺寸（860×645 逻辑）。
- 新消息在底部追加；「加载更早」后滚动位置不跳。
- 搜索、右键复制/全选、消息选中均正常。
- 启动日志增加 `first-paint` 与 `feed-rendered` 两个时间点。

**风险**：中。窗口化会改变"打开就看到最早一条"的现状（32 号刚把自动滚到底撤掉），这是产品口径，必须先拍板；共享菜单需要实测。

---

### 单 C（P0）搜索去抖与正确性

**症状/证据**：每次按键全量重建；`[` 直接抛通配符异常（已实测）。

**改法**
1. `TextChanged` 只重启一个 250 ms 单次计时器；计时器到点才应用过滤并渲染，别在按键里同步重建。
2. 过滤改成 `IndexOf($filter, [StringComparison]::OrdinalIgnoreCase)`，用户输入按字面处理，不再拼通配符。
3. 搜索结果最多渲染 100 条，显示「命中 N 条，显示前 100 条」；清空搜索恢复默认 120 条窗口。
4. 无结果时给空态文案，不要留一片空白。

**验收**：输入 `[`、`*`、`?`、中文、清空，均不报错、不冻结；命中数正确；搜索结果与全量数据一致。

**风险**：低。唯一注意点是 IME 输入法组合期间不要提前触发（计时器天然缓解）。

---

### 单 D（P1）成品 / Job / 缩略图

**症状/证据**
- `Ensure-Thumb` 在 UI 线程 `-Wait` 跑 ffmpeg，缺图多时界面冻住。
- **已实测**：`New-OutCard` 里 `New-Object BitmapImage([Uri]$tp)` 之后再设 `DecodePixelWidth=160`，属性值仍是 0（构造时已 EndInit），这条 26 号优化实际没生效（[L2106-L2108](file:///D:/tmp/xiaozhu_live.ps1#L2106-L2108)）。缩略图文件本身是 300px，影响不大，但写法是错的。
- 32 个缩略图对应 0 个 mp4，孤儿文件没人清。
- `Get-JobPrompt` 每张卡都读一次 `job.json`（[L1983-L1993](file:///D:/tmp/xiaozhu_live.ps1#L1983-L1993)）。

**改法**
1. 缩略图生成挪到后台：优先让守夜人 daemon 在视频完成时生成 `outputs\.thumbs\<id>.jpg`（160px）；UI 只查文件、不跑 ffmpeg。若暂不动 daemon，则 UI 用后台 runspace/进程异步生成 + 占位图"生成中"，完成后 Dispatcher 回填。
2. `Ensure-Thumb` 增加"源 mp4 mtime 比缩略图新就重生成"的判断。
3. `New-OutCard` 用 `BeginInit / UriSource / DecodePixelWidth=160 / CacheOption=OnLoad / EndInit` 的正确顺序，或直接依赖 160px 文件。
4. `Update-JobStatus` 先看 jobs 目录 mtime / 最新 job id，签名没变不读 `job.json`。
5. `Get-JobPrompt` 加一个按 job id 的内存缓存。
6. 孤儿缩略图清理单独做成维护命令（列清单 → 可撤销），不要自动删。

**验收**：成品页有 3 个以上缺缩略图的视频时，打开/刷新不阻塞；缩略图陆续出现；删除成品后缩略图与回执一起清；`DecodePixelWidth` 实测不为 0。

**风险**：中。异步回填要处理"用户已经切走/删除"的竞态；daemon 改动要另立单并同步云端协议。

---

### 单 E（P1）稳定性与一致性

1. **重写 915 行**：现役源文件里是
   `...}）`r`n    try { if ($CbInputBar) ...`，两条语句被字面 `` `r`n `` 黏在一行（[L915](file:///D:/tmp/xiaozhu_live.ps1#L915)）。语法能过但语义不可读，且 `CbInputBar` 的深色描边实际靠 `Set-Collab` 兜底（[L2554](file:///D:/tmp/xiaozhu_live.ps1#L2554)）。改成两条独立 `if`。
2. **总线写入不能静默失败**：`Add-BusJsonl` 重试 10×60 ms 后直接放弃，`Post-Collab` 却无条件清空输入框并刷新（[L2314-L2327](file:///D:/tmp/xiaozhu_live.ps1#L2314-L2327)、[L2515-L2534](file:///D:/tmp/xiaozhu_live.ps1#L2515-L2534)）。改成返回 bool；失败时保留输入、状态条报错、写 `app.log`。写前检查文件末字节是否为换行，防止崩溃留下的半行把下一条黏坏。
3. **统一错误日志**：现在散落在 `theme_err.txt`、`verify\6\job_err.txt`、`verify\9\out_err.txt`、`player_err.txt`、`live_icon_err.txt` 等（这些 `verify` 目录可能被清理）。全部走 `Write-AppLog`，带 tag + `ScriptStackTrace`，只留一份 `health\app.log`。
4. **窗口最大化按钮口径过期**：`BtnMax` 还写着 560×720 / 880×840（[L1202-L1207](file:///D:/tmp/xiaozhu_live.ps1#L1202-L1207)），与定版 860×645 不一致；改成基于 `$script:ViewW/ViewH` 或单独定义 `BigW/BigH`。
5. **启动分段时间**：`t0 / xaml / ui-built / first-paint / feed-rendered` 写进 `app.log`，后续优化才有对照。

**验收**：模拟总线写失败（临时只读锁）时输入框不清空且能看到报错；主题切换、最大化、窗口关闭均正常；`app.log` 一条链路可追。

**风险**：低。总线锁若要与 `bus.ps1` 共用命名互斥量，需同时改 `bus.ps1`，另立单协调，别只改应用一半。

---

### 单 F（P2）可维护性（性能稳定后再做）

1. **删死代码**：`Add-FlowLine`、`Add-Port`、`New-GridBrush`、`$VsSurface`、`$VsCanvas`、`NodeGen`、`OutLabel/OutPanel`、`Confirm-Dialog` 均已无调用方（已核对引用数；`VsCanvas` 只剩死函数内部引用）。
2. **配置外置**：路径、渲染窗口、tick 间隔、版本号收进 `app_settings.json`；现在 `D:\tmp` 硬编码散落几十处，移动目录就散架。
3. **主题令牌**：按 29 号审单的 30 键方案，把颜色/圆角/间距/字号/阴影集中；`Apply-Theme` 改成按注册表批量赋值，专治"漏一个控件就出白线"（915 行就是例子）。
4. **可选拆文件**：先提 `lib\data.ps1`（feed/board 缓存 + 锁）和 `lib\theme.ps1`，入口仍是单文件 `xiaozhu_live.ps1`，保持 BOM 与存档/镜像流程。拆出数据层后可以用临时 JSONL 做无 UI 单测，不必每次重启整应用。
5. **版本/哈希入日志**：`Write-AppLog` 的 `v5.2` 改成常量 + 现役 SHA 前 8 位。

**验收**：`parse` 0 错、BOM 在、启动与四视图截图与改前一致；删除的死函数不影响任何行为。

**风险**：低到中。拆文件会影响存档工具与镜像约定，必须单独批。

---

## 4. 验收矩阵

| 指标 | 基线 | 目标 | 测量方式 |
| --- | --- | --- | --- |
| 启动到 `live3_ok` | 约 8 s | ≤ 3.5 s | 进程 StartTime ↔ `live3_ok` 内容时间 |
| 空闲 CPU（窗口可见静置 60 s） | 11.2% | ≤ 3% | `Get-Process` 两次采样 |
| 工作集 | 337 MB | ≤ 200 MB | `WorkingSet64` |
| tick UI 线程 | ≈128 ms（数据层基准推算） | p95 ≤ 10 ms | 新埋点 `health\ui.log` |
| 搜索输入到结果 | 未埋点，推断秒级 | ≤ 100 ms（250 ms 去抖后） | 新埋点 + 手工输入 `[` |
| 视图切换 | 2–40 ms（已达标） | 保持 ≤ 60 ms | 现有 `ui.log` |
| 新消息出现 | ≤ 2 s | ≤ 2 s | 追加测试帖 |
| 数据正确性 | — | 不丢、不重、跨天不乱序 | 追加/截断/跨天用例 |

**注意**：启动 8 秒、CPU 11.2%、工作集 337 MB、board 解析 56.3 ms、`DecodePixelWidth=0`、`[` 抛异常，均为本次实测；搜索重建耗时、tick 128 ms 是代码结构 + 隔离基准推算，施工前先用埋点坐实。

---

## 5. 施工规约（给接单 agent）

1. 先 `claim xiaozhu_live.ps1`，`BUSY` 就停手发帖问；改完 `release` 并写 `log`。
2. `.ps1` 必须 **UTF-8 with BOM**；每次新版另存 `mirror\<日期>_<单号>.ps1`，不覆盖旧版。
3. 每单独立证据包 `verify\<单号>\`：深浅两套截图（1150 宽 JPG）、SELFTEST、CHANGES、前后哈希。
4. 行为口径保持 32 号现状：**搜索保留**、**不自动滚到底**、**聊天正文加粗**、**窗口 860×645**。不要借优化把 32 号刚撤的东西加回来。
5. 一次只做一单；A/B 涉及 UI 与数据层，必须分开验收。
6. 不引第三方 UI 库（29 号已否：HandyControl/Wpf.Ui/ModernWpf/Panuon 会与现役自绘样式双轨打架，且增大存档）。
7. 不删 `board.jsonl` / `muse_feed.json` 任何一条；清理走 `feed_retention_proposal.md` 的单独流程。
8. 不把 PowerShell 7 或 C# 重写作为本方案的前置条件；现有证据不支持先迁移（见 `ps_efficiency_diagnosis.md`）。

---

## 6. 需要掌柜/客官拍板的四件事

1. **聊天首屏窗口化**：默认只渲染最近 120 条 + 「加载更早」，还是保持 440 条全渲染？前者启动/内存收益最大，但首屏不再从最早一条开始（32 号刚取消自动滚到底）。
2. **气泡阴影**：去掉每条消息的 DropShadowEffect、改 1px 弱描边，是否接受这个视觉变化？
3. **搜索结果上限**：命中最多显示 100 条，可接受吗？
4. **缩略图生成位置**：挪到守夜人 daemon（更彻底，但要改视频链），还是只在 UI 侧异步（改动小、保留 ffmpeg 依赖）？

---

## 7. 不做 / 暂缓

- **不换 UI 框架**：29 号已实测四个库，三个能加载但会与 100+ 处自绘样式双轨冲突，28 MB 体积也不划算。
- **不先上真虚拟化**：`ItemsControl + VirtualizingStackPanel` 是 60–80 行、滚动位置/入场动画/复用都要重验；先用窗口化 + 缓存拿数据，再决定。
- **不碰 PMv2 DPI**：单屏 150% 下收益小，需 manifest/API，风险大于收益。
- **不删总线档案**：board 是唯一正式档案，清理另走提案。
- **不整体迁移 C#/PS7**：先看本方案落地后开发反馈是否仍被 PowerShell 动态类型拖住，再按 `ps_efficiency_diagnosis.md` 的触发判据评估。

---

## 8. 复测命令（施工 agent 可直接用）

```powershell
# 空闲 CPU / 内存（窗口可见，静置 60 秒）
$p = Get-Process -Id <pid>; $c1=$p.CPU
Start-Sleep 60; $p2=Get-Process -Id <pid>
"CPU%=" + [math]::Round((($p2.CPU-$c1)/60)*100,1)
"WS_MB=" + [math]::Round($p2.WorkingSet64/1MB,1)

# 数据层基准（隔离进程，不碰现役）
$board="D:\tmp\nailong\bus\board.jsonl"
Measure-Command { $items=@(); foreach($l in [IO.File]::ReadAllLines($board,[Text.Encoding]::UTF8)){ if($l.Trim()){ try{$items += ($l|ConvertFrom-Json)}catch{}} } }

# 启动耗时
# 进程 StartTime ↔ D:\tmp\live3_ok.txt 里的 at 时间
```

---

*本文件只出方案，未改现役脚本、未动总线、未重启应用。*
