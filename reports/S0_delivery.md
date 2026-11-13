# S0 交付 · 特征测试安全网与基线校验

- 日期：2026-11-13
- 依据：`reports\ARCH-01_proposal.md` 的 S0；用户对本轮四项确认「可以」
- **本轮未修改任何程序文件**（主脚本 SHA256 前后一致）

## 一、执行边界（按方案的前置条件）

| 用户确认项 | 本轮实际处理 | 理由 |
| --- | --- | --- |
| 进入 S0 | **已完整执行** | 新增测试、校验脚本与报告，不动主程序 |
| 允许装 PSScriptAnalyzer | **已装 1.21.0 / 68 条规则** | `Install-Module` 因本机缺 NuGet provider、非交互 shell 触发 `ShouldContinue` 失败；改用直接取 Gallery nupkg 解到 CurrentUser 模块目录，补齐 `.ps1xml` 后导入成功。PSGallery 策略仍在 `Untrusted`，未留改动 |
| 归档历史 67 条重复 HC 帖 | **只生成归档副本，主文件一行未删** | 黄金基线刚建立，移除会改变 591 行的计数与全部断言；且 55 号单的 `closedRefsFromBoard` / `deliveredIds` 依赖 board 历史回放。等 S1 增量偏移读上线、归档有安全边界后再执行 |
| 接受首启 DLL 自缓存 | **登记方向，不实施** | ARCH-01 明确要求先量化 C# 编译占比 ≥15% 才排期；对照实验被工具层拦截（见下），门槛未验证 |

## 二、交付文件

| 文件 | 用途 |
| --- | --- |
| `tests\DataLayer.Tests.ps1` | 17 项数据层特征测试（UTF-8 BOM） |
| `tools\verify_baseline.ps1` | 一键校验：BOM / Parser / Pester / Analyzer / SHA / 可选镜像（UTF-8 BOM） |
| `reports\baseline_20261113_175719.md` | 首次 GREEN 报告 |
| `archive\board_hc_duplicates_20261113.jsonl` | 67 条重复 HC 帖的**原样副本**（13,936 B） |
| `mirror\20261113_175719_S0_verify.ps1` | 校验时生成的主脚本镜像 |
| `tools\inspect\boot_probe_nocs.ps1` | 未生成成功（见第四节） |

## 三、17 项特征测试（Pester 3.4.0，1.46 s / 17 通过 0 失败）

测试方法：**不改主程序**，从 `xiaozhu_live.ps1` 提取纯数据层函数（`Get-FileStamp` / `Read-Feed` / `Read-BusJsonl` / `Add-BusJsonl` / `Convert-FeedTime` / `Read-MergedFeed`）dot-source 到测试作用域，因此无需加载 WPF。

- **黄金基线（真实数据，只读）**：Read-Feed / Read-BusJsonl 结果不越过源文件非空行数；合并条数 = feed + board − mirror；输出字段齐全；`when` 升序；指纹未变时缓存命中且二次调用 < 150 ms；两次结果条数一致。
- **Convert-FeedTime（固定时钟 2026-11-13 12:00）**：带日期按原日期解析；纯 `HH:mm:ss` 按今天补齐；比现在晚 5 分钟以上回退前一天；非法输入回退传入的 `now`。
- **临时沙箱（`$env:TEMP` 自建目录，测完清理）**：`ref=mirror` 不进时间线；task/result/decision 长文只显 ≤60 字首行简报 + 省略号；追加 1 行后缓存失效且新消息可见；文件截断后整表重建不残留旧条目；指纹未变复用解析结果；`Add-BusJsonl` 追加合法 JSON 且字段齐全。

## 四、一键校验结果（GREEN，退出码 0）

| 检查项 | 结果 |
| --- | --- |
| UTF-8 BOM | PASS（`EF BB BF`） |
| Parser 语法 | PASS（0 错误 / 21,088 tokens） |
| Pester 特征测试 | PASS（17 / 0） |
| PSScriptAnalyzer 1.21.0 | INFO —— Error+Warning **162 条**，仅记录不设门禁 |
| 主脚本 SHA256 | `31D20F036196C9D7019EE317D12E075C8DAC0E9B27EBBE94A51E28B0E8E60D66` |
| 镜像 | PASS |

Analyzer Top 5：`PSAvoidUsingEmptyCatchBlock` **91**、`PSUseShouldProcessForStateChangingFunctions` 25、`PSReviewUnusedParameter` 17、`PSUseApprovedVerbs` 15、`PSUseDeclaredVarsMoreThanAssignments` 11。按 ARCH-01 判断，**先建测试网、暂不设门禁**是正确的：一上来 162 条告警会让门禁全红，反而无法用于回归。

## 五、本轮新发现（均已并入基线）

1. **`board.jsonl` 有 1 行无法解析**：第 400 行、2,197 字符的 result 帖，`ConvertFrom-Json` 报「无效的 JSON 基元」；主脚本逐行 `try/catch` 静默跳过，所以 591 个非空行只读出 590 条——`link.log` 里长期记录的 `bus=590` 由此得到解释。特征测试已锁定这个「静默跳过」语义，**S1 增量偏移读不得改变它**。
2. **91 个空 `catch` 是系统性的静默失败模式**，与第 1 条、以及上一轮 HC `peer-offline` 完全静默同源。S1 收口数据层时应把这些 `catch` 至少改成写诊断日志，但不改变对外的跳过行为。
3. Pester 3.4.0 不支持 `-Show`；它**有** `-Quiet`，但进度条走 `Write-Progress`，`-Quiet` 与 `6>$null` 都压不住（实测捕获流仍拿到正确的 17/0 结果对象）。这是版本固有噪音，不影响退出码，已在校验脚本里注明，未做无效抑制。
4. 本机 PowerShellGet 的 NuGet provider 缺失，`Set-PSRepository` / `Install-Module` 都会因非交互提示失败；离线解包是可行替代，但必须连同 `*.ps1xml` 一起复制，否则 manifest 的 `TypesToProcess` 会报错。

## 六、未完成项与原因

- **C# 编译占比对照实验未做成**：需要用「去掉三段 `Add-Type` 的副本」与现役脚本交替启动计时，但生成该副本的命令文本被工具层安全策略拦截（拦截的是编译类命令文本，不是本轮要执行的动作）。按规则未换工具绕行，也未改主脚本加埋点（S0 边界）。因此 ARCH-01 设定的 ≥15% 门槛**未验证**，DLL 自缓存继续挂在 S2 的「待测量」状态，不实施。
- **67 条重复帖未从 `board.jsonl` 移除**：副本已就绪，理由见第一节。用户若坚持立即清理，需先重跑基线并把断言从 591 行改为 590 行，同时确认桥的回放逻辑不受影响。
- **未引入 SQLite / 未动轮询 / 未做 UI 虚拟化**：均属 ARCH-01 已否决或降级项。

## 七、下一步（S1，需再次确认后开工）

1. 把 OPT1 的 `FileStamp`/`FileCache` 与新增的 `lastByteOffset` **合并成单一状态对象**（ARCH-01 已标为方案自身隐患）。
2. 读侧只解析新增字节、只处理以 `\n` 结尾的完整行、半行留缓冲；`offset > 文件长度` 时整表重建。
3. 写侧与 `bus.ps1` / Node 桥 / HC 守护**零改动**。
4. 验收：追加 1 行时「新增解析行数 = 1」；17 项特征测试全绿；`verify_baseline.ps1` 保持 GREEN。

回滚：本轮只新增文件，无程序改动可回滚；若需撤销，直接删除本页「交付文件」表中新增的文件即可。
