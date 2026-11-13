# S3 / S4 交付 · 渲染规模测量与源码分层构建链

- 日期：2026-11-13
- 依据：`reports\ARCH-01_proposal.md` 的 S3/S4；用户「继续」
- **本轮主程序 SHA 未变**（仍为 `5478CAC9…`）——S4 是纯结构拆分，零行为变化

## 一、S3：测量结论是「不做虚拟化」

用副本法把首屏上限临时改为 500 / 1000，真实启动测 `boot-feed-ready − boot-loaded-enter`（含首屏气泡、协作台卡片等 Loaded 后的异步构建）：

| 首屏上限 | feed-ready | loaded-enter | 渲染增量 |
| --- | --- | --- | --- |
| 120（现状） | 6538 ms | 5282 ms | **1256 ms** |
| 500 | 8146 ms | 3970 ms | **4176 ms** |
| 1000 | 9202 ms | 3991 ms | **5211 ms** |

数据证明渲染随气泡数明显线性增长（120 条的 1.26 s 里还含协作台等固定开销）。但**结论是不实施虚拟化**：当前 `feedLimit=120` 是硬上限，且 OPT1 已做增量追加，正常路径根本触发不到 500/1000；而改成 `ItemsControl` + `VirtualizingStackPanel` + 数据绑定要重写整套 `New-MsgBubble` 控件构造，风险远大于收益。这组数据留作「将来放开历史上限」的前置依据。

## 二、S4：源码分层 + 可复现构建（已交付）

### 拆分（按字节切片，不改一个字节）

| `src\` 文件 | 行数 | 职责 |
| --- | --- | --- |
| `00_header.ps1` | 96 | `param`、字体令牌、`Log-Boot`/`Write-AppLog`、三段 C# `Add-Type`、AUMID |
| `10_data.ps1` | 163 | `FileState` / `Read-Jsonl` / `Read-Feed` / `Append-Feed` / `Reset-JsonlCache` |
| `20_ui_helpers.ps1` | 120 | `Brush` / 复制菜单 / 可选中文本 / 窗口状态 / 单实例互斥 |
| `30_window.xaml` | 525 | **纯 XAML**（已兑现 S2 推迟的 XAML 抽取） |
| `40_app.ps1` | 2051 | 窗口解析、主题、气泡、视频工坊、协作台、事件绑定、定时器、`ShowDialog` |

`tools\build.ps1` 按固定顺序按字节拼接，`30_window.xaml` 前后自动补 here-string 包装行（`$xaml = @'` / `'@`），产物开头只加一次 UTF-8 BOM，行尾保持 LF。

### 硬验收：产物与拆分前逐字节一致

```
拆分前 xiaozhu_live.ps1  SHA256 = 5478CAC9130131698D36C357CB84EF3166D9730171EE8B63D57357C987D19403
build.ps1 产物           SHA256 = 5478CAC9130131698D36C357CB84EF3166D9730171EE8B63D57357C987D19403
字节数                          153193 = 153193        IDENTICAL = True
```

这是「纯拆分零行为变化」最强的一条证据：不是"看起来没问题"，是字节级相同。

### 配套

- `tools\check_source_sync.ps1`：重新构建一份并与现役脚本比 SHA；不一致就报 `FAIL` 并提示「回填 src」或「重跑 build」，退出码 1。当前 `guard_exit = 0`。
- `reports\build_map.md`：每个片段在产物中的起止行、行数、字节数，用于把产物报错行号映射回 `src\`。

### 今后的工作方式

1. 改 `src\` 里的文件（**不要直接编辑 `xiaozhu_live.ps1`**）
2. `tools\build.ps1` 生成唯一交付物
3. `tools\check_source_sync.ps1` 确认没分叉
4. `tools\verify_baseline.ps1` 跑回归
5. 重启应用生效

> 项目**没有 git 仓库**（本轮再次确认），所以一致性守卫是防止源/产物分叉的关键。若以后引入版本控制，`src\` 与 `tools\` 应一起纳入。

## 三、`-LibraryOnly`：尝试两次后撤销（诚实记录）

| 尝试 | 做法 | 结果 |
| --- | --- | --- |
| 1 | 早退放在 `40_app.ps1` 开头（XAML 解析前） | `Read-MergedFeed` / `New-MsgBubble` / `Set-View` 等函数**也定义在 40_app 里**，被一起跳过；数据层函数调用报「无法识别」 |
| 2 | 早退放在 `ShowDialog` 之前 | 函数可用（`Read-MergedFeed` 返回 642 条），但仍执行完整 UI 初始化（1.29 s），并把主脚本既有的 `Windows.Thickness(10, 3)` 构造错误全部打印出来 |

根因：`40_app.ps1` 的 2051 行里**函数定义与顶层 UI 语句深度交错**，找不到一个既跳过控件构造、又保留全部函数定义的干净分界点。要真正做无 UI 模式，得把这段拆成「定义区」与「初始化区」，属于独立重构专项；而当前 **没有实际调用方**（S0 的提取函数块测法、归档脚本的字节级处理都不需要它）。为一个无需求的功能引入产物变更和一堆噪音不划算 → **撤销，产物精确回到 `5478CAC9…`**。

**附带发现（未擅自修）**：主脚本有 3 处 `New-Object Windows.Thickness(10, 3)`（产物行 1628 / 1698 / 1721）。WPF `Thickness` 没有两参构造，正常启动时也会静默失败（对应 `Padding` 没设上）。这属于既有 UI 外观问题，修复需单独做视觉验证，本轮只记录。

## 四、验收汇总

| 项 | 结果 |
| --- | --- |
| `build.ps1` 产物 SHA | `5478CAC9…`，与拆分前一致 |
| `check_source_sync.ps1` | `[OK]` 退出码 0 |
| Pester | **24 / 0** |
| 一键校验 | GREEN：BOM `EF BB BF`、Parser 0 错 / 22,405 tokens、24/0、Analyzer 164 条仅记录 |
| 真实启动 | `start entries=642`、`live3_ok.txt` 同步 642、无 `dispatcher-unhandled`、窗口正常 |
| 主程序 | SHA 与 S2 交付一致，**本轮零行为变化** |

## 五、文件与回滚

新增：`src\*`（5）、`tools\build.ps1`、`tools\check_source_sync.ps1`、`reports\build_map.md`、`reports\S3_S4_delivery.md`、`reports\baseline_20261113_212543.md`、镜像 `mirror\20261113_212543_S4_verify.ps1`。

纯结构交付，回滚只需删除 `src\` 与两个工具脚本；`xiaozhu_live.ps1` 从未改变。若以后在产物上直接改动导致分叉，用 `build.ps1` 从 `src\` 重建即可（但会覆盖那次直接改动，先回填）。

## 六、遗留

- **S3 虚拟化**：仅在放开 120 条上限时启动，先按本轮数据评估。
- **`-LibraryOnly`**：挂起，需先做 `40_app.ps1` 的定义区/初始化区拆分。
- **3 处 `Thickness(10,3)`**：既有 UI bug，待单独视觉验证后修。
- **DLL 自缓存**：仍挂在 S2「待测量」（C# 编译占比实验受工具层限制未完成）。
- **无版本控制**：一致性守卫已补上，但长期仍建议把 `src\` / `tools\` / `reports\` 纳入 git。
