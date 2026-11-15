# UI-01｜全局外观统一 · 实施交付

- 日期：2026-11-15 14:22
- 触发：用户「可以，有些外观全局要统一才好看」
- 产物：`D:\tmp\xiaozhu_live.ps1` SHA `F5E3FBE3F1EB83FFF1268467D5F4DA7E3BC1AE44F8900A94CD3CF15D70824D28`（3166 行 / 163455 B）
- 方案依据：`reports\UI-01_proposal.md`（上一轮调研、9 项来源、合理性判断）

---

## 1. 为什么不是照方案 U0 直接做

方案写的 U0 是「XAML 交互态改 `DynamicResource` + 运行时换资源键」。**四个探针把它推翻了**，实测结论：

| 探针 | 结果 | 结论 |
| --- | --- | --- |
| 1 · 模板内 `DynamicResource` 替换字典项 | `Setter.Value` 保持 `DynamicResourceExtension`，但模板内 `Border.Background` 变 `null` | 运行时换资源不可靠 |
| 2 · 共享画刷 + 改 `Color` | `ReferenceEquals=True` 三处全部共享，但资源画刷 `IsFrozen=True`，改 Color 抛「只读」 | 不能就地改色 |
| 3 · `po:Freeze="False"` / 重写 Setter | 仍被 Freeze；`SetterBase` 密封后 `Value` 不可写 | 两条退路都堵死 |
| 4 · 控件级 `DynamicResource` / 换 Style | 替换字典项时 `Foreground` 抛「不是有效值」；独立 Parse 的 Style 里 `StaticResource` 找不到键 | 控件级也不稳 |

另外探针 1 还确认了方案里自查的风险 1：**`local_overrides_resource = YES`**，即 `Apply-Theme` 设的 local value 会压过模板 Trigger——只换资源键会白改一轮。

微软《XAML resources overview》虽允许 `Style Setter` 内使用 `DynamicResource`，但原文同时警告「并非所有属性都保证实时更新」。实测与这条警告一致。

## 2. 实际采用的机制（绕开上面所有坑）

1. **单一色板**：`src\00_header.ps1` 定义 `$script:UiLight` / `$script:UiDark`，36 个语义键（Surface / Card / Ink / Meta / Hint / Stroke / Accent / Focus / 分类色…），`$script:UiTokens` 指向当前主题。
2. **启动期注入**：`30_window.xaml` 的资源字典写 `{{Key}}` 占位符，`$xaml = Resolve-UiXaml $xaml` 在 `XamlReader.Parse` **之前**按当前主题替换。主题在解析前从 `live_theme.txt` 读取，不再「先按浅色解析、再整体改色」。
3. **交互态主题无关**：12 处 hover / pressed 的写死浅色背景改为 `Opacity 0.78 / 0.62` 反馈，深浅一致，彻底消灭「深色下弹 `#E9F0F8` 白块」。关闭按钮的红色 hover 作为危险语义保留。
4. **运行时切换**：`Apply-Theme` 重写为「只换一层」——遍历从 XAML 自动提取的 **78 条**「具名控件 → 属性 → 语义键」映射，值全部 `Tok()` 取自同一色板；不再有深浅两套 hex 分支。气泡由 `Refresh-Feed` 重建。
5. **代码构造的控件统一**：`New-MsgBubble`、`Apply-StudioTheme`、工坊参数区、成品视图、页签按钮等的条件式色值全部改为色板派生；`Pal()` 等遗留色板一并收编；字号也统一由 XAML 令牌解析后同步到 `$script:Fs*`，消除「XAML 12/14、PS 10.5/13」两套并存。

## 3. 全局统一后的量化

| 项 | 改前 | 改后 |
| --- | --- | --- |
| XAML 硬编码颜色 | 93 处 / 39 种 | **7 处**（4×阴影色 `#33507A`、2×半透明白描边、1×关闭红，均为固定语义色） |
| 交互态写死主题色 | 13 处 | **0**（改 Opacity；关闭红保留） |
| `40_app.ps1` 硬编码 hex | 136 处 | **87 处**（全部为分类/角色/优先级/危险语义色，集中在 ChipBg、ChipFg、Get-RoleInfo、优先级映射等少数定义处） |
| 字号来源 | XAML 与 PS 两套 | **一套**（XAML 令牌 12/12/14/14/18，解析后同步脚本变量） |
| 焦点 | `FocusVisualStyle="{x:Null}"` | 全局 `FocusRing`（2px `FocusBrush`） |
| 间距/圆角 | 69 处散值 | 新增 `Space1–4` / `RadiusSm/Md/Lg` 令牌；历史散值**未机械替换**（避免破坏既有布局） |
| 主题分支 | 两套 hex 各写一遍 | 单一色板 + 78 条映射 |

**对比度验收**（`tools\check_ui_contrast.py`，WCAG 相对亮度公式，从色板解析）：**20/20 全 PASS**。主文字 11.8–15:1、次要文字 4.92–6.43:1、提示 4.76–5.49:1、按钮/自己气泡白字 5.91–6.52:1、组件描边 3.39–3.44:1、焦点环 5.95–6.52:1。

## 4. 验收记录

- `build.ps1` → 产物 3166 行 / 163455 B；`check_source_sync.ps1` **OK**（源=产物）
- Parser 语法 **0 错**（23258 tokens）、UTF-8 BOM `EF BB BF`
- Pester **25/0**；`verify_baseline.ps1 -Mirror -Tag UI01F` → **GREEN**（报告 `baseline_20261115_142046.md`、镜像 `20261115_142046_UI01F_verify.ps1`）
- 真实启动（`-NoMutex`）：深色 `boot-feed-ready 4599ms`、浅色 `3385ms`，两次均 `start entries=644`、`live3_err.txt` 为空、无 `dispatcher-unhandled`
- 双主题截图 `reports\ui_UI01_dark.jpg` / `ui_UI01_light.jpg`：深色无刺眼浅色块、导航图标可见、蓝色按钮白字清晰；浅色标题/状态/图标层次正常
- 主题文件 `D:\tmp\live_theme.txt` 测试后已恢复为原值 `True`

## 5. 边界与如实说明

1. **U2 消息分组未做**：本轮按用户「全局统一」聚焦样式层；分组是信息密度改造，会改变「每条都显示头像 + 时间」的既有习惯，留作下一轮单独确认。
2. **运行时切换未做自动化点击验证**：双主题是分别以 `live_theme.txt` 启动实证的；点击 DarkBtn 的即时切换沿用原有 `Apply-Theme + Refresh-Feed` 链路并新增 78 条映射，未做 UI 自动化点击测试。
3. **未具名静态文本**：XAML 里没有 `x:Name` 的少量静态文字（如工坊流程图里的「人物 / 场景」标签）在**运行时**切换主题后保留启动期注入的分类色；重开窗口即完全统一。这是当前架构（`XamlReader.Parse` 单窗口 + 资源被 Freeze）的固有边界，不假装已解决。
4. **分类色保留**：ChipBg / ChipFg、角色色、优先级色、危险红属于有意区分的语义色，集中在少数定义处，未强行压成中性色。
5. **间距**：令牌已建立，但 69 处历史 Margin/Padding 未机械替换为 4px 栅格——逐处语义不同，盲改会破坏布局；这是刻意的渐进策略。
6. **截图局限**：截图为全屏，左侧被 PowerShell 控制台/WorkBuddy 窗口部分遮挡，窗口右半超出缩放后画面边缘；COM 窗口置前被环境安全策略拦截，按规则未绕行，改用正常窗口启动重拍。视频工坊 / 传菜口 / 协作台未逐页目视。
7. **启动耗时**：字号从 10.5/11.5/13/14.5 提升到 12/12/14/14 后，首屏渲染成本略增（本次深色 4599ms、浅色 3385ms；历史基线约 4.1–4.3s）。这是密度与可读性的取舍，用户已同意。

## 6. 文件与回滚

**改动**：`src\00_header.ps1`（色板 + 注入函数 + 字号占位）、`src\30_window.xaml`（语义资源 + 令牌 + Opacity 交互态 + 焦点环）、`src\40_app.ps1`（Apply-Theme 重写、78 条映射、气泡/工坊/成品区色值收编）、`reports\build_map.md`（构建行号映射随之更新）。

**新增工具/证据**：`tools\check_ui_contrast.py`、`reports\UI-01_delivery.md`、`reports\baseline_20261115_142046.md`、`mirror\20261115_142046_UI01F_verify.ps1`、双主题截图。一次性迁移脚本与四个探针留在 `tools\inspect\`（已被 `.gitignore` 排除，供复现）。

**回滚**：`git revert <本次提交号>` 后重跑 `tools\build.ps1`；或 `copy /Y mirror\20261113_215742_S3B_verify.ps1 D:\tmp\xiaozhu_live.ps1`（回到 UI 改动前）。**不要直接编辑现役 `xiaozhu_live.ps1`**。

## 7. 下一轮可选项

- U2 消息分组 + 时间戳 `HH:mm` / 日期分隔（改变信息密度）
- 把 69 处历史间距逐步迁到 `Space1–4` 令牌（需逐处目视）
- 为纯图标按钮补 `AutomationProperties.Name`（低成本可访问性）
- 解决未具名静态文本运行时切换的边界（需视觉树遍历或重新设计资源结构）
