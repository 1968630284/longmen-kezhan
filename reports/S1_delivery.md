# S1 交付 · 读侧增量偏移（第一个底层改造）

- 日期：2026-11-13
- 依据：`reports\ARCH-01_proposal.md` 的 S1；用户确认「可以」
- 性质：**本轮真正修改了主程序**（`D:\tmp\xiaozhu_live.ps1`），但只改读侧

## 一、边界（方案前置条件逐条兑现）

| 约束 | 兑现情况 |
| --- | --- |
| 写侧与 `board.jsonl` 行格式零改动 | `bus.ps1`(11-08 16:46)、Node 桥 `index.js`(11-08 19:19)、`hc_tailscale.ps1`(17:18)、`muse_feed.json`(11-08)、`board.jsonl`(17:19:57) 修改时间全部停在本轮开始之前 |
| 保留「无法解析的行静默跳过」语义 | 全量与增量共用 `Split-JsonlBytes`，坏行依旧 `try/catch` 跳过；591 行仍读出 590 条 |
| 单一状态对象 | OPT1 的 `FileStamp`/`FileCache` 两套哈希 + 新增偏移，**合并为唯一 `FileState`**（`MergedSig`/`MergedCache` 是合并视图缓存，属另一层，保持独立） |
| UTF-8 BOM / 语法 | BOM `EF BB BF`、Parser 0 错误 |
| 可回滚 | `mirror\20261113_S1_before.ps1` / `_after.ps1` 各一份 |

## 二、改动清单（主脚本 +106 行，diff 179 行）

| 新增/替换 | 作用 |
| --- | --- |
| `$script:FileState` | 每文件一条状态：`Stamp`（长度+写入时间）/ `Items`（已解析对象）/ `Offset`（已读入字节位置）/ `Pending`（末尾半行字节）/ `LastLength` / `Tail`（末尾 64 字节锚点） |
| `Get-JsonlTail` | 增量前比对已读区域末尾 64 字节，识别「文件被截断或末尾被重写」 |
| `Split-JsonlBytes` | 按 `\n` 只处理完整行，半行以**字节**留缓冲（避免 UTF-8 多字节跨界），逐行 `ConvertFrom-Json`、坏行静默跳过 |
| `Read-BytesFrom` | `FileStream` + `FileShare.ReadWrite` 从偏移读到当前长度；用 `return ,$buf` 保持 byte[] 不被 PowerShell 展开 |
| `Read-Jsonl` | 统一入口：指纹命中 → `cache`；锚点通过 → `append`（只解析新增行）；否则 → `rebuild`；读失败时回退上次结果 |
| `Read-Feed` / `Read-BusJsonl` | 改为委托 `Read-Jsonl`，删掉两份重复解析逻辑 |
| `Reset-JsonlCache` | 就地编辑/归档重写后显式失效缓存 |
| `$script:ReadStats` | 诊断计数 `Mode / Parsed / Cached`，用于验收与后续观测 |

## 三、验收结果

**1. 特征测试 22 项全绿**（原 17 项断言口径不变 + 5 项 S1 新增）

新增断言：`文件未变 → Mode=cache/Parsed=0`、`追加 1 行 → Mode=append/Parsed=1`、`半行不提前解析且补齐后只解析 1 行`、`截断 → Mode=rebuild 不残留旧条目`、`Reset-JsonlCache → 强制 rebuild`。测试夹具的状态重置变量随实现同步更新，断言口径未放宽。

**2. 一键校验 GREEN（退出码 0）**：BOM `EF BB BF`、Parser 0 错误 / 22,015 tokens、Pester 22/0、PSScriptAnalyzer 1.21.0 报 163 条（仅记录）。主脚本 SHA 由 `31D20F03…` 变为 `0BE340D3…`。报告 `reports\baseline_20261113_180443.md`。

**3. 规模基准（核心证据）**

| 行数 | 全量重建 | 追加 1 行 | 模式 | 本次解析行数 |
| --- | --- | --- | --- | --- |
| 1,000 | 348 ms | 12 ms | append | 1 |
| 5,000 | 1,029 ms | 5 ms | append | 1 |
| 20,000 | 4,248 ms | 7 ms | append | 1 |

重建随 N 线性上涨（符合预期，只在首次启动/文件重写时发生），**追加恒定 5–12 ms 且只解析 1 行**。ARCH-01 外推的「一年后 3.6 万行全量重解析约 8 秒」这一退化路径已被切断。

**4. 真实启动**：`start entries=691`（与 S0 基线一致）、`live3_ok.txt` 正常、`app.log` 无 `dispatcher-unhandled`、稳态 6 秒 CPU 78.1 ms；`boot-feed-ready 4329 ms` 与 OPT2 的 A/B（4078–4112 ms）同量级，未引入启动回退。

## 四、设计判断与已知局限（合理性自检）

- **为什么不是 `FileSystemWatcher`**：ARCH-01 已据 tail 实践否决（丢事件、事件合并、网络盘失效），保留 2 秒兜底轮询；本次只是让「文件变化后」的代价从 O(N) 降到 O(新增行)。
- **为什么加 Tail 锚点**：仅靠 `Length` 增长无法区分「追加」与「重写成更长」，会静默漏读。尾部 64 字节锚点以可忽略的 IO 挡住截断与末尾改写。
- **明确局限**：Tail 只看**末尾** 64 字节，**无法察觉文件中间的就地编辑**。增量正确性依赖 append-only 协议——项目四个写入者都满足；若人工编辑或归档重写，需调用 `Reset-JsonlCache` 或重启应用。这是刻意保留的边界，不伪称全覆盖；S2 做归档时应把该调用串进流程。
- **半行用字节而非字符串**：`board.jsonl` 含中文，若按字符缓存会在 UTF-8 多字节序列中间被切开。字节缓冲 + 拼接后整体解码天然规避。
- **PowerShell 陷阱**：函数直接 `return $buf` 会把 `byte[]` 展开成逐个元素、空数组变成 `$null`，已用一元逗号修掉并在测试里覆盖「追加半行」场景。

## 五、文件与回滚

- 改前镜像 `mirror\20261113_S1_before.ps1`（SHA `31D20F03…`）
- 改后镜像 `mirror\20261113_S1_after.ps1`（SHA `0BE340D3…`），校验时另存 `20261113_180443_S1_verify.ps1`
- 回滚：
  ```
  copy /Y "D:\tmp\nailong\mirror\20261113_S1_before.ps1" "D:\tmp\xiaozhu_live.ps1"
  ```
  回滚后需把 `tests\DataLayer.Tests.ps1` 的 5 项 S1 断言一并退回，否则测试会因缺少 `ReadStats` 而失败。

## 六、仍未做（按 ARCH-01）

- S0 生成的 67 条重复 HC 帖归档副本仍只是副本，`board.jsonl` 一行未删；等 S2 归档流程把 `Reset-JsonlCache` 串进去后再安全移除。
- DLL 自缓存仍挂在 S2「待测量」状态（编译占比实验受工具层限制未完成）。
- UI 虚拟化、SQLite、runspace 异步、全量重写 —— 均为已否决或降级项。

## 七、下一步 S2（需再次确认后开工）

XAML 抽成独立文件并构建时内联、`-LibraryOnly` 无 UI 模式、轮询改为「偏移驱动 + 2 秒兜底」、归档流程接入 `Reset-JsonlCache`。S2 会动到构建与窗口初始化，改动面比 S1 大。
