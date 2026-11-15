# UI-04｜修掉那条线、纯白底、视图骨架重构 · 交付报告

- 日期：2026-11-15 15:17
- 触发：用户截图指出「这有个线，不是纯白」，并明确「还是不好看，不行的话就从底层重构」
- 产物：`D:\tmp\xiaozhu_live.ps1` SHA `9A56716AB9C392EB73EF5E64C2B9D3911DF9795399BECA1F478205FA5CE11E27`

---

## 1. 你指出的两个问题：像素级坐实并修掉

视觉工具对那张剪贴板图返回缓存，改用 `tools\inspect\analyze_pixels.ps1` 直接读像素：

| 观察 | 实测 | 处理 |
| --- | --- | --- |
| 「有个线」 | 图片 1128×76，**y=69、70 两行主色 `#E1E9F1`**（1px 逻辑线经 1.5× DPI 变 2px），即 `HeaderLine` | `Visibility="Collapsed"`（保留控件名供 FindName） |
| 「不是纯白」 | 标题栏背景 **`#F4F8FE`** 淡蓝白，来自 `Surface='#D9F4F9FF'` 带 alpha | 浅色 `Surface` 改 **`#FFFFFF`** |
| 状态胶囊 | 1px 描边 + 半透明底 | 去描边、圆角 9→6；时间由 `SemiBold/Meta` 降为 `Normal/FsCaption/Hint` |

修后 `verify_titlebar.ps1` 验证：`divider_rows_E1E9F1 = NONE (已移除)`、`titlebar_bg = FFFFFF`、`pure_white = True`。

## 2. 视图层重构（连续三轮调色无效后的正确动作）

前几轮都在改颜色，你说还是不好看——瓶颈其实在**信息架构**：52px 纯图标工具栏、扁平标题栏、日志式消息流。本轮重做 XAML 骨架：

- **导航 52px 纯图标 → 156px 带中文文字的分组侧栏**：新增 `NavBtn` 样式（图标 + 文字横向项），分组标题「工作区 / 工具」，分隔线，底部「截图 / 切换主题」。全部 9 个按钮 `x:Name` 保留，`Update-Rail` 的选中态改淡蓝卡片 + 左侧 3px 强调条。
- **标题栏分段**：品牌图标与名称、状态（去胶囊描边）、淡化的时间、右侧窗口按钮，层级清楚；**无底部分隔线**，与内容区连续。
- **连续纯白表面**：内容区纯白、侧栏极淡灰分层，不再有带 alpha 的蓝白底。
- **输入区圆角** 20/21 → 8（协作台输入 18 → 8），发送按钮改方形圆角。
- 气泡最大宽度 380 → 340、正文 352 → 312，适配变窄后的内容区。

**约束**：只改 XAML 与两处色值，数据层/功能层零改动；`BtnChat`、`StudioBtn`、`OutBtn`、`CollabBtn`、`CollabDot`、`ArchiveBtn`、`ArchiveUndoBtn`、`BootCopyBtn`、`ShotBtn`、`DarkBtn`、`AvatarImg`、`RailLine`、`HeaderLine`、`LiveBadge`、`StatusText`、`InputBorder`、`SendBtn`、`FeedList`、`InputBar` 等 **19 个关键 x:Name 逐一核对全部保留**，所有事件绑定与 40 项测试不受影响。

## 3. 顺带挖出一个真正的「底层」根因

改完后深色截图出现**混合主题**（侧栏深蓝、内容区纯白、气泡浅色）。加运行时诊断后定位：

- `src\40_app.ps1` 第 339 行有一句历史遗留 **`$script:dark = $false`**，在窗口解析后把主题强行重置为浅色；
- 旧逻辑靠 Loaded 事件里「只有深色时 `$script:dark = $true` + `Apply-Theme`」兜底；上一轮我把那句改成无条件 `Apply-Theme` 并删掉了设回 true 的赋值，于是出现「XAML 注入深色 / Apply-Theme 用浅色」。

**修法**：删掉 339 行重置，主题只在 `00_header.ps1` 解析前读一次；启动末尾无条件 `Apply-Theme`（深浅都跑，顺带修复浅色启动时 `Update-Rail` 从未执行、导航选中态缺失）。诊断实证：

```
file=False -> dark=False surface=#FFFFFF  soft=#F7FAFD
file=True  -> dark=True  surface=#F2172432 soft=#1B2836
```

这算是对「底层」直觉的回应：确实有个状态管理层面的 bug，但它不需要重写整个软件就能修。

## 4. 「从底层重构」是否合理 —— 明确结论

**A. 全量重写 / 换技术栈（C# 重写、Tauri/Electron/WebView、前后端分离）：否决**

1. **功能规格缺失**：57 单历史行为只存在于脚本注释与使用习惯里，没有规格文档；重写必然丢行为。
2. **外部协议耦合**：4 个写入者共写 `board.jsonl` / `muse_feed.json`，append-only、多点锚点、mirror 去重、跨天时间补齐都在数据层；重写会同时破坏读侧与写侧。
3. **交付形态**：唯一 `.ps1` + 桌面快捷方式 + `launch_app.vbs` + 任务栏 AUMID/图标自缓存。换技术栈要引入安装器、DLL、包管理，破坏「单文件即开即用」。
4. **没有安全网**：现有 40 项 Pester **全部是数据层**，UI 层 0 项自动化测试；重写 UI 等于无回归网改全部交互。
5. **软件正在使用**，窗口状态、滚动位置、搜索、主题都在内存里；停机切换代价高。

命中 Strangler Fig 反模式的全部「不该重写」条件，ARCH-01 已论证过一次。

**B. 视图层重构（重做 XAML 骨架，保留数据层/功能层）：成立，本轮已做并验证**

连续三轮调色无效正说明瓶颈在信息架构。本轮就是这条路：改动集中在 `30_window.xaml` 与少量样式值，全部控件名保留、构建链逐字节复现、git 可回滚、双主题截图实证。

**C. 若你仍要做「真·底层重构」**：前置条件是**先补 UI 层特征测试**（当前 0 项）——把视图状态（选中项、可见性、主题一致性、控件树结构）锁成断言，再按 Strangler Fig 逐块替换。没有这一步就重写，等于裸奔。这是可以单独立项的下一阶段，但需要你明确接受成本。

## 5. 验收

| 项 | 结果 |
| --- | --- |
| 标题栏像素 | 横线 `NONE`、背景 `FFFFFF` 纯白 |
| 主题一致性 | 深浅两套运行时诊断分别正确，深色不再混合 |
| Pester | **40 / 0** |
| 一键校验 | **GREEN**（BOM、Parser 0 错 / 24097 tokens） |
| 一致性守卫 | `[OK]` 源 = 产物 |
| 对比度 | `check_ui_contrast.py` **20/20 PASS** |
| 真实启动 | `start entries=645`、`live3_err` 空、无未捕获异常 |
| 双主题截图 | `ui_final_light.jpg` / `ui_final_dark.jpg`，完整窗口无裁切 |
| 主题文件 | 测试后已恢复你原本的浅色 `False` |

## 6. 边界

1. 首屏仍是 8 条「已删除成品」真实操作回执；按文本特判成系统消息属于硬编码业务规则，未做。
2. 69 处历史 Margin 仍是散值；间距令牌只建立了没全量迁移。
3. UI 层自动化测试仍为 0（见 §4C，这是真重构的前置条件）。
4. 97 条空 catch 未治理；本轮又用了一处 `try/catch` 空块做兼容。
5. 侧栏加宽后内容区变窄，长消息换行更早；已在双主题截图确认无溢出。

## 7. 文件与回滚

**改动**：`src\00_header.ps1`（浅色 Surface 纯白）、`src\30_window.xaml`（NavBtn 样式、侧栏 156px 带文字分组、HeaderLine 隐藏、状态胶囊、输入区圆角、红点位置）、`src\40_app.ps1`（删除 339 行 dark 重置、启动末尾无条件 Apply-Theme、Update-Rail 选中色、气泡宽度、渲染诊断）、`reports\build_map.md`。

**新增工具**：`tools\inspect\analyze_pixels.ps1`、`verify_titlebar.ps1`（像素级验证，纳入版本控制）、`apply_ui_rebuild.py`（一次性迁移脚本，未纳入提交）。

**回滚**：`git revert <本次提交号>` 后重跑 `tools\build.ps1`；或 `copy /Y mirror\20261115_145833_UI03_verify.ps1 D:\tmp\xiaozhu_live.ps1`。
