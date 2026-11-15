# UI-05 交付：底部横线清除 · 视图层大改 · 运行时主题切换根治

日期：2026-11-15　产物：`D:\tmp\xiaozhu_live.ps1`　SHA256 `6794DA6C…`

## 0. 本轮用户诉求

1. 「最下面不是还有两条线吗」——底部仍有可见横线；
2. 「还是不美观，可以大改一下」——授权做较大幅度样式重构；
3. 追加要求：「自己再验证方案的合理性，看看用起来有没有 bug，你看哪个深浅模式变换，有 bug」。

第 3 点优先级最高：**此前四轮都只用「分别启动」验证双主题，从未测过点击切换按钮这条运行时路径**，报告里也一直挂着「运行时主题切换的 UI 自动化验证仍缺」。本轮先补这个洞。

---

## 1. 运行时主题切换 bug：复现、根因、方案合理性

### 1.1 复现（真实点击，不是分别启动）

新增 `tools\inspect\probe_theme_switch.ps1`：按 PID 枚举顶层窗口、DPI 感知、UIAutomation 按 `AutomationId=DarkBtn` 找到按钮并 `Invoke()`，同机位抓切换前后两张完整截图。

**改前实测**：起点浅色，点击 3 秒后内容区变深色，**左侧 156px 侧栏仍为白底**，导航文字变浅灰在白底上几乎不可读，选中态变成突兀的深蓝方块 —— 典型混合主题。用户反映属实。

### 1.2 根因

`src/30_window.xaml` 第 281 行 `Rail` 的背景是 `Background="{StaticResource SoftBrush}"`。UI-01 建立的 `Apply-Theme` 只遍历一张 **78 条具名控件映射表**，其中漏了 `Rail`；同类遗漏还分布在工坊 / 成品 / 协作台的未具名元素上。因此运行时切换只换了一部分控件。启动时不存在此问题，因为色板在 `XamlReader.Parse` **之前**就已注入。

> 顺带排查并排除的两条假嫌疑：主题文件被写成带 BOM 的 UTF-8（`EF BB BF`），但 `[IO.File]::ReadAllText(..., UTF8)` 会自动剥离 BOM，`.Trim() -eq 'True'` 实测为 True；`theme_err.txt` 为空，`Apply-Theme` 未抛异常。BOM 仍改为无 BOM 写入以保持产物干净。

### 1.3 方案比选（先验证再动手，共 3 个探针）

| 候选 | 验证结果 | 结论 |
| --- | --- | --- |
| 补一条 `Rail → Soft` 映射 | 能修侧栏，但工坊/协作台同类遗漏仍在 | **否决**：打补丁 |
| `DynamicResource` + 运行时换字典项 | UI-01 的四个探针已证伪：模板内求值为 null、资源被 Freeze、Setter 密封、控件级替换抛异常 | **否决** |
| 切换时重启进程 | 结果一定正确，但窗口闪退、滚动位置与视图状态丢失 | **否决**：体验倒退 |
| 遍历视觉树按颜色反查替换 | `probe_visualtree_repaint.ps1` 验证可行（12 元素 / 7 处换色 / 0 异常，含模板内与 Shape） | 备选，但色板存在重复 hex（浅色 `Surface`/`Card`/`MyBg` 同为 `#FFFFFF`），反查有歧义 |
| **直接改资源画刷的 Color** | `probe_resource_identity.ps1`：`same_ref=True`、`IsFrozen=False`，含模板内元素；`probe_resource_recolor.ps1`：改 Color 后 root / outer / 模板内 Border 全部同步，**0 异常** | **采纳** |

采纳方案的关键性质：`XamlReader.Parse` 下 `StaticResource` 解析后，所有引用者持有**同一个未冻结画刷对象**。改它的 `Color`，全窗口（含 ControlTemplate 内、未具名元素）自动同步，既不需要 `x:Name`，也不产生 local value、不破坏 TemplateBinding / Trigger。

这与 UI-01 时期「资源画刷被自动 Freeze」的旧结论有冲突；本轮用独立最小 XAML 实测 `IsFrozen=False` 且改色成功，**以实测为准更正旧结论**（旧探针的场景含 `po:Freeze` 等额外条件）。

### 1.4 实施

`Apply-Theme` 在 `Set-UiTheme` 之后遍历 `$win.Resources`，把形如 `XxxBrush` 的键映射回色板 token `Xxx`，未冻结则改 `Color`。37 个资源键全部有色板对应项。`DarkBtn.Add_Click` 写主题文件改用无 BOM 的 `$Utf8`。

另修 `Update-Rail` 的既有遗漏：它只给 7 个导航按钮设前景色，漏了 `ShotBtn` / `DarkBtn`，导致深色下这两项沿用 Style 默认值而发暗。已补入循环。

**复测**：点击后侧栏、标题栏、消息区、输入框、发送按钮全部统一深色，无白底残留，底部两项文字清晰。

---

## 2. 「两条线」：像素定位与清除

`tools\inspect\verify_ui05_lines.ps1` 对改前浅色图 `ui_final_light.jpg` 与改后双主题图做下半部分逐行扫描（全宽 + 输入区宽度两个取样区，容差排除 JPEG 噪点/主背景/输入底色）：

| 图 | 结果 |
| --- | --- |
| 改前 `ui_final_light.jpg` | **y=873-874 `#E5E9EC`/`#E8E9EB`**（输入区顶部 1px 线经 1.5× DPI = 2px）、**y=894 `#365A7C`**（输入框蓝色描边） |
| 改后 `ui_UI05_light.jpg` | `bottom_rule_lines = NONE` |
| 改后 `ui_UI05_dark.jpg` | `bottom_rule_lines = NONE` |

正好对应用户说的「两条线」。清除范围（全部在 `src/30_window.xaml`）：

- `InputBar` / `CbInputBar` / `VsStatusBar` 的 `BorderThickness="0,1,0,0"` → `0`
- `InputBorder` / `CbInputBorder` / `SearchBorder` 的 `BorderThickness="1"` → `0`
- `RootBorder` 窗口外框 `BorderThickness="1"` → `0`
- 侧栏两条 `Rectangle Height=1` 改 `Fill="Transparent"`（只留间距）
- `RailLine` 竖分隔线 `Visibility="Collapsed"`
- `HeaderLine` 保持隐藏

---

## 3. 视图层大改清单

**输入区一体化**：新增色板 token `Input`（浅 `#F2F6FB` / 深 `#1C2C3E`），输入框与搜索框改无边框 + 独立底色 + 圆角 10；发送按钮去白色描边、圆角 10、40×40；内边距按 4px 栅格重排。无边框后仍可辨识，不靠线。

**标题栏精简**：隐藏每 2 秒刷新的裸时钟 `StatusText`（控件名保留，代码仍赋值无副作用）；状态胶囊改全圆角 pill；标题栏只剩「标题 + 状态 + 右侧操作」。

**消息区**：`FeedScroll` 左右留白 6/2 → 18/14；气泡去描边、圆角 10→12、内边距 12×8→14×9、最大宽度 340→360（正文 312→330）。

**侧栏**：去掉分组横线与右边界竖线，靠 `Soft` 底色与分组标题分层。

**字体回退**：根 `FontFamily` 补 `Segoe UI Emoji`。

**合理性判断**：以上全部只在样式层，19 个关键 `x:Name` 未动，数据层 / 四个外部写入者 / 功能逻辑零改动；改动经 `build.ps1` 合并为唯一 `.ps1`，`check_source_sync.ps1` 保证源与产物逐字节一致。

### 明确没做的

- **首屏 8 条「已删除成品」没隐藏**：原始数据是 `sender=Dave, kind=note`，只能按文本前缀 `🗑` 特判，属硬编码业务规则。要根治应在写入侧给这类回执加 `kind='receipt'` 或 `silent` 语义，需动数据协议、得单独确认。
- **emoji 字体回退在本机未见明显改善**：截图中 `🗑` 仍呈黑白方块（只读 `TextBox` 未走该回退列表）。改动零风险，保留为防御性修正，不宣称它解决了观感。
- 69 处历史间距散值、UI 层 0 自动化测试、98 条空 catch 仍未治理。

---

## 4. 验收

| 项 | 结果 |
| --- | --- |
| Parser 语法 | 0 错 / 24209 tokens |
| UTF-8 BOM | `EF BB BF` 保留 |
| 源/产物一致性守卫 | `[OK]` |
| Pester 特征测试 | **40 / 0** |
| 一键校验 | **GREEN**，退出码 0 |
| 对比度（新增输入框 2 组） | **24 / 24 PASS**（浅 Hint/Input 4.80、深 5.80） |
| 真实启动 | `start entries=645`，`live3_err.txt` 为空，无未捕获异常 |
| 真实点击主题切换 | 浅→深全窗口统一，无白底残留，底部导航文字清晰 |
| 底部横线像素扫描 | 改前 2 条 → 改后浅/深均 `NONE` |
| 双主题完整截图 | `ui_UI05_final_light.jpg` / `ui_UI05_final_dark.jpg` 目视通过 |
| 主题文件 | 已恢复用户原值 `True` |

`PSScriptAnalyzer` 告警 179 条（其中空 catch 98 条），按既定策略仅记录、不设门禁。

---

## 5. 交付物与回滚

- 源码：`src/00_header.ps1`、`src/30_window.xaml`、`src/40_app.ps1`、`tools/check_ui_contrast.py`
- 长期验收工具：`tools/inspect/probe_theme_switch.ps1`、`probe_resource_identity.ps1`、`probe_resource_recolor.ps1`、`probe_visualtree_repaint.ps1`、`verify_ui05_lines.ps1`
- 一次性迁移脚本：`apply_theme_fix.py`、`apply_ui_bigpolish.py`（不入库）
- 证据：`reports/ui_switch_before.jpg` / `ui_switch_after.jpg`、`ui_UI05_final_light.jpg` / `ui_UI05_final_dark.jpg`、`baseline_20261115_154306.md`
- 镜像：`mirror/20261115_154306_UI05_verify.ps1`

**回滚**：`git revert <本轮提交>` 后重跑 `tools\build.ps1`；或 `copy /Y mirror\20261115_151710_UI04F_verify.ps1 D:\tmp\xiaozhu_live.ps1`（注意 `src\` 需一并退回，否则一致性守卫会报分叉）。

**注意**：用户当前打开的窗口仍是旧版，重启软件才会加载新样式与主题切换修复。
