# ARCH-01 · 龙门客栈底层优化方案与合理性评估

- 日期：2026-11-13
- 性质：**方案与评估，本轮不改动任何程序代码**
- 对象：`D:\tmp\xiaozhu_live.ps1`（2791 行）、`D:\tmp\nailong\bus\board.jsonl`、`bus.ps1`、`dsh-bus-bridge`、`health\*.ps1`
- 前置结论：前两轮 OPT1（轮询缓存）与 OPT2（画刷缓存）都属于**表层缓存补丁**，没有改变结构；本轮从 L0 数据层往上重新设计。

---

## 一、底层诊断基线（实测，非推断）

| 维度 | 实测值 | 含义 |
| --- | --- | --- |
| 主脚本 | 2791 行 / 146,683 B / 61 函数 | 单文件，无模块边界 |
| 内联 XAML | 527 行 here-string | 视图与逻辑同文件，`XamlReader.Parse` |
| 全局状态 | 87 个 `$script:` 变量 | 隐式共享，无法独立测试 |
| UI 构建 | 221 次 `New-Object`、58 处事件绑定 | 全部同步执行在单个 STA UI 线程 |
| 文件 IO | 26 处裸 `ReadAllLines` / `AppendAllText` / `FileStream`、12 处 JSON 转换 | 无数据访问层，散落在各视图函数里 |
| 消息存储 | `board.jsonl` 591 行 / 572,563 B（≈969 B/行）、`muse_feed.json` 110 行 | append-only 文本，无索引、无事务、无归档 |
| 写入者 | 主窗口、`bus.ps1`、Node 桥、`HC` 守护，共 4 个进程 | 靠 `FileStream Append + FileShare.ReadWrite` 重试，桥侧另有 `.lock` 文件 |
| 读取模型 | `Read-MergedFeed` 全量读两文件 → 逐行 `ConvertFrom-Json` → `Sort-Object` | 复杂度 O(N)；OPT1 只在「文件完全没变」时免除，一旦追加一行仍全量重解析 |
| 列表渲染 | `$FeedList.Children.Add($view)` 直接往 `StackPanel` 塞控件 | 无 UI 虚拟化（微软文档明确列为禁用虚拟化的条件） |
| 刷新机制 | `DispatcherTimer` 2 秒轮询 | 事件与 IO、渲染全在同一线程 |
| 测试 / 构建 | 0 个 Pester 测试、无 `.csproj` / `.sln`、无构建脚本 | 57 单历史行为只靠 `verify\*` 截图证据包人工验收 |
| 本机工具链 | PS 5.1.26100.9818 Desktop；**Pester 3.4.0 已装**；PSScriptAnalyzer / ModuleBuilder / PSSQLite / mySQLite / ThreadJob **均未装**；无 `System.Data.SQLite.dll`；PowerShell Gallery HTTP 200 可达 | 决定哪些方案零成本、哪些要引入依赖 |

### 为什么现在就该动 L0（数据量外推）

当前 591 行，OPT1 缓存后稳态 8 秒 CPU 仅 93.8 ms，**现在完全不卡**。但按每天约 100 条、平均 500 B 估算：

- 1 年 ≈ 18 MB / 36,000 行
- 全量解析耗时线性外推 ≈ 136 ms × (36,000 / 589) ≈ **8 秒/次**

即「每追加一行就全量重解析」是一颗随时间引爆的 O(N) 定时炸弹。所以 L0 要做的是**把读侧从 O(N) 变成 O(新增行)**，而不是现在就换数据库。

---

## 二、开源项目与官方资料调研（均已核实来源）

| # | 项目 / 资料 | 出处 | 可借鉴的具体做法 | 可信度 |
| --- | --- | --- | --- | --- |
| 1 | **PoshCode/ModuleBuilder** | https://github.com/PoshCode/ModuleBuilder | 源码按 `Public`/`Private`/`Classes` 分文件、每文件一函数，**构建时合并成单个大 `.psm1`**；主张「单文件交付」是因为性能、天然 script 作用域、classes/`using` 支持、签名开销；提供 `ConvertTo-SourceLineNumber` / `ConvertFrom-SourceLineNumber` / `Convert-CodeCoverage` 做构建产物与源码的行号映射 | 官方仓库，已抓取 README 核实 |
| 2 | **PowerShell/PSScriptAnalyzer** | https://github.com/PowerShell/PSScriptAnalyzer | 静态规则检查（未初始化变量、`Invoke-Expression` 等），`Invoke-ScriptAnalyzer -Severity` 可作 CI 门禁；支持 Windows PowerShell 5.1 | 微软官方仓库 |
| 3 | **Pester** | https://pester.dev/ · https://github.com/pester/Pester | PowerShell 行为测试事实标准；`Describe/It/Should`、`Mock`、代码覆盖率。本机已有 3.4.0，S0 零安装成本 | 官方 |
| 4 | **Axium-Labs/AX · Storage** | https://github.com/Axium-Labs/AX/blob/main/docs/storage.md | **JSONL 是不可变权威事件流，SQLite 只是可重建索引**；索引表存 `event_offset` / `event_length` 字节指针，读时 `seek` 精确字节；`sync_session_locked` 在每次读写前比对文件大小并重建缺失索引；WAL + `IMMEDIATE` 事务处理多进程写；声明「1000 条 / 500 KB 只加载最新 50 条，≈95% 减少读取」 | 已抓取文档核实；Rust 项目，思想可移植 |
| 5 | **Microsoft Learn · 优化控件性能 / 对象行为** | https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-controls · https://learn.microsoft.com/zh-cn/dotnet/desktop/wpf/advanced/optimizing-performance-object-behavior | 明确列出「**直接向 ItemsControl 添加项容器会禁用 UI 虚拟化**」；`VirtualizingStackPanel` + `VirtualizationMode=Recycling`；实测 5000 个 TextBlock：StackPanel **3210 ms** vs 虚拟化 **46 ms**；区分 UI 虚拟化与数据虚拟化 | 微软官方文档 |
| 6 | **Martin Fowler · Strangler Fig** | https://martinfowler.com/bliki/StranglerFigApplication.html | 大爆炸式重写「大多数时候以失败告终」；应找接缝（seams）、逐块迁移、每步可回滚、新旧共存；先明确目标、再切分、再逐块交付 | 原文已核实 |
| 7 | **PowerShell 应用架构指南** | https://rottenwifi.com/building-powershell-applications-a-step-by-step-guide · https://www.techbloat.com/using-powershell-and-wpf-to-create-advanced-guis.html | 「不要把应用逻辑写进按钮处理器」；推荐 `GUI/CLI → 公共模块命令 → 私有业务逻辑 → 外部系统`；长耗时工作用 runspace / thread job 并 marshal 回 UI；Pester + PSScriptAnalyzer 组合 | 社区指南，与微软文档一致 |
| 8 | **单文件分发 + 源码分模块的实例** | https://papanda925.com/?lang=zh&p=17848 | 源码按 `header/start/functions/core/functions/ui/xaml/native/config` 拆分，由 `Compile.ps1` 合并成**单一脚本**分发；提供 `-LibraryOnly` 开关，让后端逻辑不启 UI、可被 CI 直接调用 | 社区实例，思路参考 |
| 9 | **append-only 日志 tail 实践** | https://startdebugging.net/2026/10/how-to-tail-a-log-file-in-csharp-while-another-process-is-still-writing-to-it/ · https://stackoverflow.com/q/50970952 | **反直觉但关键**：`FileSystemWatcher` 不适合做追加日志的增量读（网络盘失效、缓冲区溢出丢事件、Changed 被合并延迟）；正确做法是**维护字节偏移 + 短周期轮询 + 只取完整行 + 处理截断/轮转 + `FileShare.Delete`** | 社区实测，与 .NET 语义一致 |
| 10 | **PSSQLite / mySQLite / AdoSQLiteModule** | https://www.powershellgallery.com/packages/mySQLite/1.0.0 · https://www.powershellgallery.com/packages/AdoSQLiteModule/1.0.1.4/Content/AdoSQLiteModule.psm1 | PS 5.1 上 SQLite 需 `System.Data.SQLite.dll`，PS7 用 `Microsoft.Data.Sqlite`；`Invoke-MySQLiteQuery` / `Invoke-SqliteQuery` 封装；批量插入必须包事务 | Gallery 已核实，但本机均未安装 |
| 11 | JSONL vs SQLite WAL 基准 | https://github.com/digoal/blog/raw/refs/heads/master/202609/20260909_08.md | 崩溃安全逐条写：SQLite WAL FULL 比 JSONL+fsync 快约 2.1× | 个人博客，**仅作方向参考，不作为决策依据** |

---

## 三、方案（自底向上，S0 → S4）

**总原则**：交付物仍是单个 `.ps1`（桌面快捷方式、`launch_app.vbs` 不变）；外部协议零改动（`board.jsonl` 行格式、`bus.ps1`、Node 桥、HC 守护全部照旧）；每一步都有 mirror 与一键回滚。这来自 #1 单文件交付主张 + #6 Strangler Fig。

### S0 · 安全网（必须先做，否则后面不敢动）

- 用本机已有的 **Pester 3.4.0** 写「特征测试 / characterization tests」，锁定当前可观察行为：`Read-Feed` / `Read-BusJsonl` / `Read-MergedFeed` / `Convert-FeedTime` / `Add-BusJsonl` 的黄金用例（含跨天时间补全、`ref=mirror` 过滤、首行 ≤60 字简报、排序稳定性）。
- 基线断言：合并后 691 条（含本轮新增 HC 帖）、首尾消息、排序结果逐条一致。
- 把项目已有规约脚本化：一键 `parse（0 错）→ BOM（EF BB BF）→ Pester → mirror → 回滚`。
- **不装新依赖**。PSScriptAnalyzer 可选（Gallery 可达），但先只记录基线、不设门禁，避免一上来被几百条历史告警淹没。

### S1 · L0 数据接缝（第一个真正的底层改造，**只改读侧**）

借鉴 #4 的字节指针思想 + #9 的 tail 实践，但**不引入 SQLite**：

- 抽出 `Nailong.Data`（源码分文件阶段先以 dot-source 片段形式存在），把所有 JSONL 读写收口到一处，对外暴露 `Read-Board` / `Read-Feed` / `Append-*`。
- 状态统一为一组 `(fileStamp, lastByteOffset, cachedItems)`，**与 OPT1 的 `FileStamp`/`FileCache` 合并成一套**，不允许两套缓存并存。
- 文件增长时：从 `lastByteOffset` 只读新增字节 → 按 `\n` 切完整行 → 只 `ConvertFrom-Json` 新增行 → 追加进缓存数组；**未以 `\n` 结尾的半行留在缓冲区**，等下次。
- 防御：`offset > 文件长度`（文件被截断/归档重建）→ 整表重建；`fileStamp` 不变 → 直接命中缓存；UTF-8 多字节跨界由「只处理完整行」天然规避。
- **写侧一行不改**，四个外部进程的协议完全不动。
- 归档策略（可选、独立排期）：`board.jsonl` 按月切分到 `archive\board-YYYYMM.jsonl`，读侧按文件列表顺序拼接；历史 67 条重复 HC 帖按用户确认后再处理。

### S2 · L1 运行时接缝

- 轮询语义从「每 2 秒全量比对」改成「偏移驱动 + 2 秒兜底」：保留 2 秒定时器作为**保底**（#9 明确警告不能只依赖 watcher），但真正触发刷新的是「指纹/长度变化」。
- 借鉴 #8 增加 `-LibraryOnly`：加载数据层与领域层但不 `ShowDialog()`，让 Pester / CI 直接调用，不必启动窗口。
- XAML 从 here-string 抽成独立 `.xaml`，**构建时内联回单文件**（#1 思路），便于编辑与静态检查。
- `Add-Type` 产物自缓存（见第四节「待测量项」）：软件首次启动把 3~4 段 C# 编译结果落到固定目录的 DLL，之后加载 DLL，避免每次现场编译；**先量化再决定是否排期**。

### S3 · L2 渲染接缝（按需，暂不实施）

- 若将来放开 `feedLimit=120` 的历史上限，再按 #5 把 `$FeedList.Children.Add` 改为 `ItemsControl` + `VirtualizingStackPanel` + `VirtualizationMode=Recycling` + 数据绑定。
- 前置条件：先测 500 / 1000 条的渲染耗时，证明收益 > 重写气泡渲染的风险。

### S4 · 工程化收口

- `src/` 按 `data / domain / view / xaml / native` 分文件，`build.ps1` 合并产出**唯一的** `xiaozhu_live.ps1`（借鉴 #1、#8），并生成源码行号 ↔ 产物行号映射表，便于排错。
- 本地一键链：`build → parse → BOM → Pester → 生成 mirror → 报告`。
- 可选引入 PSScriptAnalyzer，先只对新拆出的 `src/data/*` 启用门禁。

---

## 四、合理性判断（逐条压力测试）

| 方案项 | 依据 | 本机约束 / 反证 | 结论 |
| --- | --- | --- | --- |
| 全量重写成 C# / Tauri / Electron | #6：大爆炸重写「多数失败」；57 单历史行为无规格文档、0 自动化测试、软件正在被使用、4 个外部进程依赖固定文件格式 | 完全命中「不该重写」的全部条件；且用户窗口正在运行 | **否决** |
| 立刻上 SQLite 作为主存储 | #4 混合架构、#10 驱动可用、#11 基准 | 数据量仅 591 行 / 572 KB，OPT1 后稳态 CPU 93.8 ms/8 s；本机无 `System.Data.SQLite.dll`、无 PSSQLite/mySQLite，需从 Gallery 装并引入 x64 原生依赖；更要命的是**必须改动 4 个写入者**，破坏三方协作协议 | **否决（过度工程）**；只吸收「字节偏移 + 可重建索引」思想，落地为无依赖的增量读 |
| 用 `FileSystemWatcher` 取代 2 秒轮询 | 直觉上更「事件驱动」 | #9 实测警告：网络盘/容器挂载失效、内部缓冲溢出丢事件、追加写入的 `Changed` 被 OS 合并与延迟；正确做法恰是「偏移 + 短轮询」 | **否决**；保留 2 秒兜底 |
| 现在就做 UI 虚拟化 | #5：直接加子项禁用虚拟化，5000 项 3210 ms → 46 ms | 当前首屏硬限 120 条，且 OPT1 已做增量追加；改成 ItemsControl + 数据绑定要重写 `New-MsgBubble` 整套控件构造，风险远大于收益 | **降级为 S3 预案**，先测量再决定 |
| 直接引入 ModuleBuilder | #1 主张源码分文件、构建合并单文件，且有行号映射 | 它面向 **`.psm1` 脚本模块**，我们是带内联 XAML + `ShowDialog()` 的**应用脚本**，不是模块；本机未安装，引入后还带来 Earthly/Invoke-Build/Pester 5 等一整套构建依赖 | **借鉴思路，不引入工具**；自建一个约 50 行的合并脚本即可 |
| 立刻装 PSScriptAnalyzer 并设 CI 门禁 | #2 官方规则 | 2791 行历史脚本会一次报出大量告警，门禁必然全红，先治理告警再谈门禁；且本机未装 | **降级为可选**，S0 先用已装的 Pester 3.4.0 |
| 把 IO 移到 runspace / ThreadJob | #7「长任务不阻塞 UI」 | 本机 `ThreadJob` 未安装；PS 5.1 + WPF 跨 runspace 共享控件对象易出错；OPT1 后 IO 已基本命中缓存，收益很小 | **暂缓**，等 S1 完成后再评估 |
| 增量偏移读取（S1 核心） | #4 的 `event_offset` 思想 + #9 的 tail 实践 | 纯读侧改动、零新依赖、外部协议不变；能把 O(N) 变成 O(新增行)，且解决长期增长 | **采纳，第一步** |
| 先建 Pester 特征测试（S0） | #3、#6、#7 都强调重构必须由自动化测试兜底 | Pester 3.4.0 **本机已装**，零安装成本；不改主程序 | **采纳，且必须最先做** |
| src 分文件 + build 合并单文件 | #1、#8 双来源印证，且保持现有快捷方式/启动器不变 | 需自建合并脚本、确保 UTF-8 BOM 与行号映射；可控 | **采纳，放在 S4** |

### 方案自身的两个隐患（自我检查）

1. **缓存叠加风险**：OPT1 已有 `FileStamp`/`FileCache`，S1 再加 `lastByteOffset` 会形成两套状态，极易出现「指纹命中但偏移没推进」或反之。**必须合并成单一状态对象**，并在 Pester 里加一条「文件追加 1 行 → 只解析 1 行」的断言。
2. **`-LibraryOnly` 的作用域**：主脚本有大量顶层执行语句（XAML Parse、事件绑定、定时器启动），仅靠参数跳过 `ShowDialog()` 不够，需要在 S2 拆分时把这些显式收进 `Initialize-Ui` 函数，否则「无 UI 模式」仍会构建整棵控件树。

### 对上一轮两处判断的更正

- **「环境禁止运行时编译 .NET，故预编译 DLL 不可行」是错的**：我混淆了**工具沙箱限制**与**软件运行时限制**。软件每次启动都在执行 3~4 段 `Add-Type -TypeDefinition`（`GlassFx` / `WinIcon` / `TaskbarId`，以及单实例分支的 `WinAct`），说明运行时编译完全可用；被限制的只是我通过工具调用 `Add-Type`。因此正确做法是**软件首次启动自行编译并把 DLL 缓存到固定目录、后续加载**，不需要我预生成。但热态 `0 → window-parsed` 全程仅 551 ms，C# 编译占比尚未量化，**未量化前不排期**（列为 S2 待测量项）。
- **「冷启动 4.7~6.0 秒」是冷环境测试值**：用户真实启动为 2537 ms（`window-parsed 551 / loaded-enter 1739 / feed-ready 2537`）。底层方案不应以那个偏大值作为立项依据。

---

## 五、验收口径与回滚

| 步骤 | 可量化验收 |
| --- | --- |
| S0 | `Invoke-Pester` 全绿；黄金断言：合并条数、排序、首行简报、`ref=mirror` 过滤与改造前逐条一致；`Parser::ParseFile` 0 错；BOM = `EF BB BF` |
| S1 | 追加 1 行后，埋点证明**新增解析行数 = 1**、耗时不再随总行数增长；`board.jsonl` 字节格式与 4 个写入者代码均未改动；Pester 黄金用例仍全绿 |
| S2 | `-LibraryOnly` 可在无窗口下调用数据层；启动后控件数、`start entries` 与改造前一致；DLL 缓存仅在实测收益 ≥15% 时启用 |
| S4 | `build.ps1` 可重复产出同一 SHA 的单文件；行号映射表可把产物异常行定位回 `src/` 具体文件 |

回滚沿用项目规约：每步改前 `mirror\<日期>_<单号>_before.ps1`，改后 `_after.ps1`，一句 `copy /Y ... D:\tmp\xiaozhu_live.ps1` 即可退回。

---

## 六、待你确认

1. 是否进入 **S0**（只新增 Pester 测试与一键校验脚本，不动主程序）？
2. 是否允许从 PowerShell Gallery 安装 PSScriptAnalyzer（可选，S0 不需要）？
3. `board.jsonl` 里 67 条历史重复 HC 帖与按月归档策略，是否授权处理（只归档、不删除）？
4. 是否接受「软件首次启动自行生成 DLL 缓存」这一运行时行为变化（S2 待测量项）？

**本轮未修改任何程序文件**，仅新增本文档与台账登记。
