# 交付 · DLL 自缓存与多点采样锚点

- 日期：2026-11-13
- 用户指令：「继续优化」→ 自主选题
- 目标：把前几轮因「测不了」「有局限」而挂起的两件事闭环

## 一、为什么选这两件

前几轮反复挂着的项里，S3 虚拟化和 `-LibraryOnly` 都已被判断为「当前无需求/风险过大」，不该硬做；而剩下两件正好都是**有明确门槛或明确缺陷**：

1. **DLL 自缓存**：ARCH-01 定了「C# 编译占比 ≥15% 才排期」，但一直因为「工具层禁止 Add-Type」没测成。后来意识到那是混淆了工具沙箱与软件运行时——软件每次启动本来就在编译三段 C#，完全可以让**软件自己埋点**测出来。
2. **Tail 只看末尾 64 字节**：S1/S2 报告里我自己标了三次「文件中间就地编辑察觉不到」，是个真实的数据正确性缺口。

## 二、DLL 自缓存（测量 → 决策 → 实施）

### 先量化

在 `src\00_header.ps1` 的 `Add-Type` 前后加 `Log-Boot` 埋点（不改任何功能），构建后真实启动 3 次：

| 段 | 耗时 |
| --- | --- |
| 6 个 `-AssemblyName` | 27–39 ms |
| **3 段 C# 现场编译** | **368–402 ms** |
| XAML 定义 + `XamlReader.Parse` 等 | 364–464 ms |
| `0 → window-parsed` 合计 | 900–1053 ms |

**C# 编译占比中位 38.2%**，远超 15% 门槛 → 方案成立，实施。

### 实施

三段 C# 源码改为先存进变量，合并后按内容 SHA-256 前 8 位命名 DLL（`cache\NailongNative_<sig>.dll`）：

- 存在 → `Add-Type -Path` 直接加载
- 不存在 → `Add-Type -TypeDefinition -OutputAssembly` 编译落盘后再加载
- 缓存不可写 / DLL 损坏 → 回退现场编译
- 最后兜底检查 `GlassFx` 类型是否可用
- 源码变更 → 哈希变 → 自动换 DLL；`cache/` 与 `*.dll` 已加入 `.gitignore`

### 一次失败与修正

首版把三段 here-string 直接拼接，结果**一个 DLL 都没生成**、C# 段仍是 333–398 ms。根因：三段各自带 `using System;`，拼接后 `using` 出现在类型定义之后，C# 不合法；异常被 catch 吞掉，甚至可能让三个 P/Invoke 类型根本没加载（窗口能起只是因为调用处都有 try/catch）。改为**统一把 using 提到最前、去掉后续重复 using** 后正常。

> 顺带印证了「90+ 条空 catch」这个系统性问题的危害：它会把功能退化伪装成正常启动。

### 效果

| | 改前 | 改后 |
| --- | --- | --- |
| C# 段（首次编译） | 368–402 ms | **215 ms** |
| C# 段（命中 DLL） | 368–402 ms | **65 / 67 ms（约 −83%）** |
| `0 → window-parsed` | 900–1053 ms | **643–808 ms**，最终完整启动实测 654 ms |

类型验证：`GlassFx` / `WinIcon` / `TaskbarId` 均可用，`EnableAcrylic` / `SendMessage` / `SetCurrentProcessExplicitAppUserModelID` 三个方法齐全，说明亚克力、图标与任务栏 AUMID 未受影响。

## 三、多点采样锚点

把 `Get-JsonlTail`（只取末尾 64 B）换成 `Get-JsonlAnchors`：在已读区域 `[0, offset)` 上取 **9 个采样点**（8 个按 offset 均匀分布 + 1 个末尾窗口），各读 64 B 拼成校验串。

- 追加写入不改动 `[0, offset)`，正常 append 仍命中 ✓
- 文件**开头 / 中部 / 结尾**被就地编辑时会被察觉 → 回退全量重建
- 成本 9 次 64 B 的 seek+read，追加实测 9–18 ms（S2 为 5–12 ms，多几毫秒，仍是 O(1)）
- 新增断言：「改写开头行 + 末尾追加一行（长度增长）→ `Mode=rebuild`」，旧版单一尾部锚点会误判成 append，现通过

**仍存的局限**：采样点之间的极小范围改动理论上仍可能漏检，正确性依旧依赖 append-only 协议；人工重写后仍建议 `Reset-JsonlCache` 或重启。没有伪称 100% 覆盖。

## 四、验收汇总

| 项 | 结果 |
| --- | --- |
| Pester | **25 / 0**（+1 条多点锚点断言） |
| 一键校验 | GREEN：BOM `EF BB BF`、Parser 0 错 / 22,812 tokens、25/0 |
| 一致性守卫 | `[OK]`，产物 SHA `410C07AF…` / 2999 行 |
| 规模基准 | 1000 / 5000 / 20000 行：重建 374 / 1043 / 4260 ms，**追加 18 / 9 / 11 ms，Parsed=1** |
| DLL 类型 | 3 个类型 + 3 个方法全部可用 |
| 真实启动 | `start entries=642`、Loaded 完成、无未捕获异常、C# 段 62 ms |

## 五、文件与回滚

修改：`src\00_header.ps1`、`src\10_data.ps1`、`tests\DataLayer.Tests.ps1`、`.gitignore`、`reports\build_map.md`、`ledger.md`。
新增：`reports\S3B_delivery.md`、`reports\baseline_20261113_215742.md`、镜像 `mirror\20261113_215742_S3B_verify.ps1`、`tools\inspect\verify_native.ps1`（诊断用，已排除入库）。

回滚：
```
git -C D:\tmp\nailong revert <本次提交号>
# 再运行 tools\build.ps1 让 src\ 与产物一致
```
若只需关掉 DLL 缓存而不回滚代码，删除 `cache\NailongNative_*.dll` 即可回到每次现场编译。

## 六、遗留

S3 虚拟化（等放开 120 条上限）、`-LibraryOnly`（需先拆 `40_app` 定义区/初始化区）、95 条空 `catch`（本轮又新增 5 条空 catch，属于系统性可观测性问题，建议单独做一轮「静默失败治理」）、`verify/` 178 MB 证据包归档、按月归档策略。
