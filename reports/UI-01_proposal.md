# UI-01｜UI 优化对标方案与合理性判断

- 日期：2026-11-13 22:14
- 阶段：**方案 + 调研**，本轮**未修改任何程序代码**
- 对象：`D:\tmp\xiaozhu_live.ps1`（现役产物，源在 `src\`，由 `tools\build.ps1` 逐字节构建）
- 现役产物 SHA：`410C07AF7868886AAFF4E3C4FABB834B233A94AB84F4573C03524E307272C8F2`（本轮前后一致）
- 交付形态约束：唯一 `.ps1`、PS 5.1 Desktop / .NET Framework 4.x、`XamlReader.Parse` 单窗口、无 NuGet 还原、无 `Application` 对象

---

## 0. 结论摘要

**建议做 U0（主题令牌化）+ U1（可读性与焦点修正）+ U2（消息分组，缩小范围）**，全部零依赖、只改样式层，走已有 `src → build → check_source_sync → verify_baseline → 真实启动` 链路，每步可 `git revert`。

**否决**：引入第三方 WPF 控件库、重写 UI 框架、UI 虚拟化、全面 WCAG 合规改造、Mica 材质、逐气泡动效。

**判断要点**：这个项目的 UI 问题不是「不够漂亮」，而是**主题机制有结构洞**——深浅主题靠 PowerShell 遍历控件硬改颜色，模板内的交互态改不到；以及**样式值散落**（93 处色值 / 39 种颜色 / 42 处字号 / 69 处 Margin）。对标大厂最该抄的是「语义令牌 + 主题只换一层」，不是抄控件库。

---

## 1. 现状诊断（可复现量化）

### 1.1 结构数据

| 指标 | 实测 | 说明 |
| --- | --- | --- |
| XAML 行数 | 525 | `src\30_window.xaml`，内联 here-string |
| 硬编码颜色 | 93 处 / **39 种不同色值** | 另有 PS 侧 `Brush '#...'` 70 处 |
| `FontSize` | 42 处 | 已有 4 个字号令牌：`FsCaption 10.5` / `FsMeta 11.5` / `FsBody 13` / `FsTitle 14.5` |
| `Margin` / `Padding` | 69 / 19 处 | 全部散值，无 4px 栅格 |
| `CornerRadius` | 29 处 | 4 / 6 / 7 / 9 / 12 / 14 / 18 / 20 等 |
| `ControlTemplate.Trigger` | **15 个，13 处交互态写死浅色** | `#E9F0F8` / `#DCE7F3` / `#4A90E8` / `#2569BC` |
| `VisualState` / `Storyboard` | 0 / 0 | 无统一状态与动效模型 |
| `KeyboardNavigation` / `TabIndex` / `AccessKey` | 0 / 0 / 0 | 焦点顺序未设计 |
| `FocusVisualStyle` | 1 处，且为 `{x:Null}` | 图标按钮**显式关掉**焦点框 |
| `AutomationProperties` | 0（XAML） | 已有 `ToolTip` 20 处可复用 |

**已有优点（不要推翻）**：`UseLayoutRounding` / `SnapsToDevicePixels` / `TextOptions.ClearType` 已开；`Microsoft YaHei UI, Segoe UI` 字体栈；`WindowChrome` 圆角 12 自绘标题栏符合 Win11；`BrushCache` 已做画刷复用；双主题、消息可选中 + 右键复制、20 处 ToolTip、系统消息居中样式都已具备。

### 1.2 三层样式链路的结构洞

1. **XAML 静态层**：525 行内联 XAML，颜色/字号/Margin 大量写死。
2. **`Apply-Theme`（`src\40_app.ps1` 132–185 行）**：深浅主题靠遍历约 40 个具名控件**直接赋 local value**，两套 hex 各写一遍。
3. **`ControlTemplate.Triggers`**：hover / pressed 的 `Setter.Value` 写在模板里，属于模板资源，**遍历控件树够不到**；代码里也确认没有任何 `.Template =` 动态替换。

结果：深色主题下，`IcoBtn` 的 hover 仍会弹浅色块 `#E9F0F8`，主按钮仍用 `#4A90E8`。这是可验证的机制性缺陷，不是审美偏好。

### 1.3 对比度实测（WCAG 相对亮度公式）

| 场景 | 前景 / 背景 | 对比度 | AA 4.5:1 |
| --- | --- | --- | --- |
| 深色·主文字 | `#EAF1F8` / `#172432` | 13.81:1 | PASS |
| 深色·卡片正文 | `#E9F1F9` / `#22303F` | 11.78:1 | PASS |
| 深色·次要/时间戳 | `#93A8BE` / `#172432` | 6.43:1 | PASS |
| 浅色·主文字 | `#16283C` / `#FFFFFF` | 14.97:1 | PASS |
| **深色·输入框提示** | `#6E8299` / `#22303F` | **3.40:1** | FAIL |
| **浅色·次要/时间戳** | `#8496AB` / `#FFFFFF` | **3.03:1** | FAIL |
| **浅色·输入框提示** | `#9FB0C3` / `#FFFFFF` | **2.22:1** | FAIL |
| **深色·边框（非文本 3:1）** | `#3A4E66` / `#22303F` | **1.58:1** | FAIL |
| **深色·导航图标** | `#5A6E85` / `#172432` | **3.00:1** | 临界 |
| **自己气泡白字（浅/深）** | `#FFFFFF` / `#2F7DE1`、`#3B82F6` | **4.08 / 3.68:1** | FAIL（13px 正文） |
| **主按钮白字** | `#FFFFFF` / `#4A90E8` | **3.26:1** | FAIL |

正文与标题其实很健康（11.8–15:1），问题集中在**提示文字、时间戳、边框、图标、蓝色底上的白字**这五类小字/非文本元素。

### 1.4 真实截图观察（`check_ui.jpg`）

- 连续三条「未识别」消息各自重复头像 + `未识别 · 20-50-03` 元信息，视觉上像日志文件而不是对话。
- 时间戳写作 `20-50-03` / `20-54-21`，无日期分隔，跨天消息难以定位。
- 底部 HC 状态行**横向被裁切**（`D:\tmp\nailo...`），长文本没有换行或省略号策略。
- 左侧导航图标偏暗，与深色底几乎融为一体；图标无文字标签，只能靠 ToolTip。
- 未见任何焦点态、选中态或键盘导航提示。

---

## 2. 联网调研（出处、关键值、可信度）

| # | 来源 | 关键结论 / 数值 | 可信度 |
| --- | --- | --- | --- |
| 1 | Microsoft Fluent 2 官方 `fluent2.microsoft.design/design-tokens` | 令牌是「不硬编码像素与 hex」的存储值；**两层结构 global（原始值）→ alias（语义）**；官方明说令牌「原生支持 light / dark / high-contrast 主题，并确保系统级足够对比度」 | 一手·官方 |
| 2 | Microsoft Learn《Typography in Windows》 | 字体 `Segoe UI Variable`；**最小值 12px Regular / 14px Semibold**，更小「在某些语言难以辨认」；type ramp `12/16 · 14/20 · 18/24 · 20/28 · 28/36 · 40/52 · 68/92 epx`；**Bold 与 Italic 不在 ramp 内，用 Semibold**；每行 50–60 字符；截断用省略号 | 一手·官方 |
| 3 | Fluent 2 令牌表（GitHub 社区整理 `TheLobbi/Claude-m` 技能库） | 间距基准 **4px**（2/4/6/8/10/12/16/20/24/32）；圆角 2/4/6/8；字号 10/12/14/16/20/24/28/32/40/68；阴影 `shadow2/4/8/16/28/64`；动效 `50/100/150/200/250/300/400/500ms`，常用 150–200ms | 二手·社区整理，数值与官方页互相印证 |
| 4 | W3C **WCAG 2.2 Recommendation（2024-12-12）** | 1.4.3 正文 ≥ **4.5:1**、大字 ≥ 3:1；1.4.11 非文本组件/状态 ≥ **3:1**；2.4.7 **键盘焦点指示器可见**；2.4.11/2.4.13 为更高层级要求 | 一手·规范原文 |
| 5 | Google Material 3 官方 Spacing | 基准 **8dp** 线性间距梯度（0/2/4/6/8/10/12/16/20/24/32/40/48…）；颜色用 26+ role 自动配对保证对比度；动效也有 token | 一手·官方 |
| 6 | Microsoft Learn《XAML resources overview》 | `DynamicResource` 适用于「**打算在 app 生命周期内调整 ResourceDictionary**」与主题切换；限制条件里明确允许「**引用用于 Style Setter 内的值**」；但官方同时警告「**并非所有以 DynamicResource 赋值的属性都保证实时更新**，取决于属性、类型与逻辑结构」 | 一手·官方 |
| 7 | `lepoco/wpfui` GitHub + NuGet 4.3.0 | MIT；**确实支持 .NET Framework 4.6.2 / 4.7.2 / 4.8.1**（并非只支持 .NET 6+）；但要求 NuGet 引入、在 `App.xaml` 合并 `ThemesDictionary`/`ControlsDictionary`（或 `ApplicationThemeManager.Apply`），并把根元素换成 `ui:FluentWindow` | 一手·官方仓库/包元数据 |
| 8 | Microsoft Learn《Keyboard accessibility》 | 键盘是一等交互；`TabIndex` 控制顺序、`IsTabStop=false` 排除；**F6 在主要区域间跳转**（需自行实现）；区域应设 `AutomationProperties.Name` | 一手·官方 |
| 9 | IM 行业惯例（Interface Lineage / Ethora / Uxcel 等） | 同一发送者约 **60 秒内连续消息合并成一个视觉簇**（一个头像、一个时间戳）；时间以 gutter/日期分隔呈现；系统消息中性居中；**Slack / Discord 在多参与者场景放弃气泡**，改左对齐 + 名字前缀；错误/空态要有明确反馈 | 行业惯例，非规范，可信度中 |

**收敛出的对标原则**（跨平台一致，与本应用强相关）：语义令牌 > 硬编码；4/8px 栅格；12px 起跳的 type ramp；交互态由主题令牌驱动；正文 4.5:1 / 组件 3:1；焦点可见；连续消息分组。

---

## 3. 方案（U0 → U3，自底向上）

### U0 · 主题令牌化（地基，必做）

- 在 `src\30_window.xaml` 的 `Window.Resources` 增加**语义别名层**：
  `SurfaceBrush / CardBrush / InkBrush / MetaBrush / HintBrush / StrokeBrush / HoverBrush / PressedBrush / AccentBrush / AccentInkBrush / FocusBrush`，尺寸令牌 `Space1=4 / Space2=8 / Space3=12 / Space4=16`、`RadiusSm=4 / RadiusMd=8 / RadiusLg=12`。
- 把 13 处 Trigger 内写死的交互态色替换为 `{DynamicResource HoverBrush}` / `PressedBrush` / `AccentBrush`。
- `Apply-Theme` 从「遍历约 40 个控件赋 local value」改为「只更新十来个资源键」；PowerShell 侧 `Brush '#hex'` 集中收进 `$script:UiTokens`（XAML 资源与 PS 代码是两套作用域，不能直接互引，必须双写但只在一处定义）。
- **前置探针（10 行）**：先验证 `XamlReader.Parse` 加载的模板中 `DynamicResource` 是否随 `$win.Resources[...]` 实时刷新。本轮想实测但被工具层拦截（见 §5.1），官方文档只说「允许」不保证「实时」。**探针不通过则退回方案 B**：交互态改用随主题切换的半透明中性叠加层 + 深浅各一套 `ControlTemplate`，不依赖动态资源。
- 验收：深浅主题各截一张图，hover / pressed / focus 三种状态目视；产物 SHA 变化但 `check_source_sync` OK；Pester 25/0 不变。

### U1 · 可读性与焦点修正（必做，零依赖）

色值全部按 WCAG 公式验算过（下表为**第二轮修正值**，首轮候选 `#6B7A8C` 4.39:1、`#5A7089` 2.63:1 不达标，已弃用）：

| 用途 | 现值 | 建议值 | 验算 |
| --- | --- | --- | --- |
| 浅色 hint | `#9FB0C3` 2.22:1 | `#64748B` | **4.76:1** |
| 浅色 meta / 时间戳 | `#8496AB` 3.03:1 | `#5F6E80` | **5.21:1** |
| 深色 hint | `#6E8299` 3.40:1 | `#93A8BE` | **5.49:1** |
| 深色导航图标 | `#5A6E85` 3.00:1 | `#93A8BE` | **6.43:1** |
| 深色边框（非文本） | `#3A4E66` 1.58:1 | `#6B829B` | **3.39:1** |
| 自己气泡 / 主按钮 / 焦点环 | `#2F7DE1`、`#3B82F6`、`#4A90E8` | `#185FA5` | 白字 **6.52:1** |

- 字号 `FsCaption 10.5 → 12`、`FsMeta 11.5 → 12`、`FsBody 13 → 14`、`FsTitle 14.5 → 18`（对齐 12/14/18 ramp）；`FontWeight="Bold"` 改 `SemiBold`。**这一步会改变行高与首屏可见条数，需用户接受密度变化**（见 §6）。
- 焦点：`FocusVisualStyle="{x:Null}"` 换成 2px `FocusBrush` 焦点环；给纯图标按钮补 `AutomationProperties.Name`（复用已有 ToolTip 文案）；显式设定主要区域的 Tab 顺序。
- 长文本：底部状态行改 `TextWrapping="Wrap"` 或 `TextTrimming="CharacterEllipsis"`，消除横向裁切；每行控制在 ~50–60 字符。
- 验收：对比度脚本复算全绿；深浅主题截图；键盘 Tab 走一遍主要控件；Pester 25/0、`verify_baseline` GREEN、真实启动无异常。

### U2 · 消息分组（建议做，范围已收窄）

- 同一发送者、间隔 < 60 秒的连续消息合并：只显示一次头像与名字，后续消息缩进对齐；时间戳统一 `HH:mm`，跨天插入「今天 / 昨天 + 日期」分隔；系统/HC 消息保持现有居中中性样式。
- 只做「分组 + 时间格式 + 日期分隔」这一低风险子集，**不改气泡体系、不换 Slack 式左对齐**（理由见 §4.5）。
- 验收：同一批真实数据渲染前后逐条文本一致（可加 Pester 断言：合并视图文本序列 == 原视图文本序列）；条数上限 120 不变；渲染耗时不高于现有 1.26 s。

### U3 · 动效（可选，默认不做）

- 若要做，仅在视图切换 / 导航切换用 150–200ms 淡入（Fluent 常用档），**禁止逐气泡动画**：S3 已测 120 条气泡渲染增量 1.26 s，500 条 4.18 s，逐条动画会线性放大。
- 不做密度模式切换、不做弹簧物理动效（M3 Expressive）——单人自用工具收益极低。

### 统一验收与回滚

`src\` 改动 → `build.ps1` → `check_source_sync.ps1` → `verify_baseline.ps1`（BOM / Parser / Pester / 镜像）→ 真实启动 `-NoMutex` → 深浅主题各截图 → `git commit`。
回滚：单步 `git revert <commit>` 后重跑 `build.ps1`；或 `copy /Y mirror\<对应 before>.ps1 D:\tmp\xiaozhu_live.ps1`。**禁止直接编辑现役 `xiaozhu_live.ps1`**。

---

## 4. 合理性判断（逐条压力测试）

| 方案项 | 判断 | 理由 |
| --- | --- | --- |
| 引入 `wpfui` / ModernWpf 等控件库 | **否决** | 注意：wpfui 4.3.0 **确实支持 .NET Framework 4.6.2+**，否决理由不是「不兼容」。真实障碍是：需 NuGet 包与 DLL 落地（破坏「唯一 `.ps1`」交付与桌面快捷方式）、需 `App.xaml` 合并资源字典（本应用是 `XamlReader.Parse` 单窗口、无 `Application` 对象）、需把根元素换成 `ui:FluentWindow` 并改写 525 行 XAML 的控件类型。为一个在用的自用工具引入整条依赖链，风险远大于收益。**只借它的 Fluent 规范，不引库。** |
| U0 语义令牌 + 资源字典 | **成立** | 零依赖；Fluent 2 / M3 的核心都是「语义别名 + 主题只换一层」；git 与构建链已就位，可逐步替换、每步可回滚；能顺带消掉 §1.2 的结构洞和大量重复代码。 |
| U1 对比度 / 字号 / 焦点 | **成立，但降级为「可读性改进」而非合规改造** | 这是**个人自用**工具，不是对外产品，不做 WCAG 认证式全量改造：44×44 触控目标（鼠标桌面不适用）、完整屏幕阅读器语义、高对比度模式、200% 缩放全量验收都不排期。只修实测影响阅读的 6 组色值 + 焦点可见 + 长文本裁切，成本低、收益直接。 |
| U2 消息分组 | **成立，但缩小范围** | 60 秒分组 / 时间 gutter 是 IM 通用惯例，截图里重复头像确实降低扫读效率。但本应用是**三方协作日志流 + 57 单历史行为**，不是 1:1 聊天；完全改成 Slack/Discord 无气泡左对齐会推翻既有视觉语言与历史交付，属于「为大厂而对标」。只做分组与时间格式。 |
| UI 虚拟化 | **否决** | S3 已实测：120 条硬上限下渲染增量 1.26 s，500/1000 条才 4.18/5.21 s，正常路径触发不到；改 `ItemsControl` + 数据绑定要重写整套 `New-MsgBubble`。 |
| Mica / 亚克力升级 | **否决** | 已有自绘 `GlassFx.EnableAcrylic` 与 Win11 圆角，再上 Mica 需 DWM/WinAppSDK API，视觉收益小、回归面大。 |
| 全面重做亮/暗双主题 | **否决** | 现有双主题框架可用，缺的是「令牌化」不是「重做」。U0 即可复用。 |
| 逐气泡动效 / 全局动效系统 | **降级** | 只保留视图切换 150–200ms；120 条渲染成本已测，逐条动画是负优化。 |
| 字号提升到 12/14/18 | **成立但有副作用** | 10.5 / 11.5 低于微软 12px 下限；提升后行高增加，120 条首屏可见消息变少。这需要你明确接受，否则保留 11.5 只改色值与字重。 |

### 方案自身的两处风险（自查，必须写进实施前提）

1. **DP 值优先级陷阱**：`Apply-Theme` 现在给控件设的是 **local value**，WPF 中 local value 优先级**高于** Style/Trigger。如果只把 Trigger 里的写死色换成 `DynamicResource`，而不同时移除这些 local 赋值，交互态依旧不生效 —— **会白改一轮**。U0 必须把「换资源键」和「移除 local 颜色赋值」一起做。
2. **`DynamicResource` 实时性未实测**：本轮想用最小 XAML 探针验证「模板内 Setter 的 DynamicResource 随运行时资源更新」，命令被工具层以「运行时加载 .NET 程序集」拦截，按规则未换等价手段绕行。官方文档允许 Setter 内使用，但同时警告「不保证所有属性实时更新」。因此 **U0 第一步必须是这个探针**；不通过就走方案 B（半透明中性叠加层 + 深浅双模板）。此处不假装已验证。

---

## 5. 本轮受阻与诚实记录

- **DynamicResource 探针未跑成**：命令文本含 `Add-Type -AssemblyName PresentationFramework`，被环境安全策略拦截（提示「compiles and loads .NET code at runtime」）。按规则不重试等价手段，改用官方文档与社区资料交叉确认机制，并把「本机实测」列为 U0 前置待办。
- **目视范围**：`check_ui.jpg` 是聊天首屏；视频工坊、传菜口、协作台的视觉状态未逐页检查，方案里未对这三个视图下结论。
- **截图遮挡**：真实截图里窗口左半被另一应用覆盖，因此导航 rail 的完整布局与底部输入区仅依据 XAML 与代码判断，未做像素级目视。

---

## 6. 需要你拍板的 5 件事

1. 是否进入 **U0**（会动 `30_window.xaml` 与 `Apply-Theme`，改动面比前几轮数据层优化大，但仍是纯样式层）。
2. 是否接受**字号提升到 12 / 14 / 18**（首屏密度下降）；不接受则只改色值与字重。
3. 是否要 **U2 消息分组**（会改变「每条都显示头像 + 时间」的现有习惯）。
4. 深色主题是否定为默认（当前由 `D:\tmp\live_theme.txt` 决定；令牌化后切换成本更低）。
5. 是否保留 QQ 风气泡体系（若想换 Slack/Discord 式左对齐，属于另一档工作量，需单独立项）。

在你确认前，**主程序、测试、数据文件一律不动**。本轮只新增本文档与台账一行，并提交到 git。

---

## 7. 参考链接

- Fluent 2 Design tokens：https://fluent2.microsoft.design/design-tokens
- Microsoft Learn · Typography in Windows：https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography
- Microsoft Learn · XAML resources overview：https://learn.microsoft.com/en-us/dotnet/desktop/wpf/systems/xaml-resources-overview
- Microsoft Learn · Keyboard accessibility：https://learn.microsoft.com/en-us/windows/uwp/accessibility/keyboard-accessibility
- W3C · WCAG 2.2 Recommendation：https://www.w3.org/TR/WCAG22/
- Material 3 · Spacing tokens：https://m3.material.io/styles/spacing/tokens
- lepoco/wpfui：https://github.com/lepoco/wpfui ；NuGet 4.3.0 目标框架：https://www.nuget.org/packages/wpf-ui/
- IM 消息分组惯例：https://interfacelineage.com/messaging-speech-bubbles 、https://ethora.com/blog/chat-app-ui-ux-design/
