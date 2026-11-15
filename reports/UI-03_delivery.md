# UI-03｜观感打磨 · 交付报告

- 日期：2026-11-15 14:58
- 触发：用户「感觉不好看，没有大厂软件的审美」
- 产物：`D:\tmp\xiaozhu_live.ps1` SHA `9D0D0B459F0F2A8AAA315DB069019F7F1C768639F617D141513AE1F9138C2380`
- 性质：**这一轮改的是观感，不是机制**。前两轮（UI-01/02）做的是令牌统一与消息分组，工程上更整齐，但不足以让界面好看。

---

## 1. 先解决「看不见全貌」的问题

此前所有截图都被前景窗口遮挡或窗口右半超出画面，无法做视觉评审。新增 `tools\inspect\capture_ui.ps1`：

- `EnumWindows` 按进程 ID + 标题定位 WPF 窗口（`MainWindowHandle` 在 Hidden 启动时为 0）
- `SetProcessDPIAware()` + `GetWindowRect` 按**真实物理矩形**截图
- `SetWindowPos` 临时置顶，避免被 WorkBuddy / 控制台遮挡
- 支持 `-ScriptPath` 切换对照版本、`-Theme` 切换深浅

**关键自查**：第一版截图工具没声明 DPI 感知，`GetWindowRect` 读到 `860×645`，而窗口真实物理尺寸是 `1290×968`（正好 1.5 倍）。因此最初判断「消息区横向溢出、右侧气泡被裁、输入区消失」是**误判**——实际 `feedW=781 viewportW=781 winW=860 inputVis=Visible`，布局完全正常。诊断日志写进 `ui.log` 后确认。

基于这个误判加的两处改动（`FeedList` 宽度绑定 `ViewportWidth`、`$body.MaxWidth=352`）**保留为防御性约束**：它们不改变当前视觉，但能防止未来长文本把气泡撑出窗口。此处如实记录，不把误判包装成修 bug。

## 2. 基于完整截图的诊断

拿到 `ui_review_before.jpg` / `ui_review_before_light.jpg` 后逐项评审，最影响观感的五点：

1. **每条自己消息都是一块高饱和亮蓝**（`#2563B8`）+ 白字 + 垃圾桶图标，8 条重复「已删除成品」像一排操作按钮，而不是对话。
2. **头像橙棕色** `#8A5A44` 高饱和且每条重复，与冷色界面冲突，抢视觉焦点。
3. **气泡 18px 圆角 + 6px 投影 + 1px 描边**，QQ 风偏重；大厂 IM 多用 8–12px 圆角、无逐条阴影。
4. **导航选中态是整块蓝底方块**，左栏与内容区同色无分层，图标无分组，像调试工具栏。
5. **标题栏把奶龙图标、状态胶囊、裸时间挤在一行**，信息层级扁平；系统消息两行居中与气泡混排，节奏散。

## 3. 实际改造

**色彩克制**（`src\00_header.ps1`）
- 自己气泡：亮蓝白字 → 浅色 `#E8F1FB` + 深字 `#16283C`、深色 `#20334A` + 浅字 `#EAF1F8`，几乎融进背景，靠对齐与头像区分。对比度 13.12:1 / 11.28:1。
- 新增 5 个低饱和角色色 `RoleSelf/RoleHost/RoleGpt/RoleChef/RoleUnknown`（`#4A5A72`…`#5A6B82`），白字对比 5.44–7.13:1，橙色头像消失。
- 所有气泡统一 `10px` 圆角、`1px` 极淡 `Line` 描边、**移除逐条 DropShadowEffect**；内边距、外边距按 4px 栅格重排。

**分组密度**（`src\10_data.ps1` + 测试）
- `Test-UiGrouping` 阈值 60 秒 → **120 秒**。本机消息多为 1 分钟间隔的操作回执，60 秒会把它们逐条拆开；放宽后首屏重复头像与「客官 · 时间」明显减少。Pester 两条边界断言同步改为 120/121 秒。

**导航与层级**（`src\30_window.xaml` + `src\40_app.ps1`）
- `IcoBtn` 模板支持 `BorderBrush`/`BorderThickness` 绑定；`Update-Rail` 选中态由「整块蓝底」改为「淡底 + 左侧 3px 强调条」。
- 左栏 `Rail` 加 `Soft` 底色，与内容区分层。
- 系统消息字号降到 `FsCaption`、最大宽度 470→560，减少两行硬换行。

**自查修复的缺陷**：第一版改完截图发现**所有图标按钮冒出细方框**（模板开始响应默认边框）。立即在 `IcoBtn` Style 补 `BorderBrush=Transparent` / `BorderThickness=0`，重截确认消失。这是本轮唯一一次回归，已闭环。

## 4. 验收

| 项 | 结果 |
| --- | --- |
| 对比度 | `check_ui_contrast.py` **20/20 全 PASS**；5 个角色色白字 5.44–7.13:1；自己气泡 11.28–13.12:1 |
| Pester | **40 / 0**（含 120 秒边界） |
| 一键校验 | **GREEN**，BOM `EF BB BF`、Parser 0 错 / 24097 tokens |
| 一致性守卫 | `[OK]` 源 = 产物 |
| 真实启动 | `start entries=645`、`live3_err` 空、无未捕获异常 |
| 双主题截图 | `ui_review_final_dark.jpg` / `ui_review_final_light.jpg`，完整窗口无裁切 |
| 主题文件 | 测试后恢复 `True` |

**前后对比**：改前 `ui_review_before.jpg`（DPI 修正后可用的是 `ui_review_after_dark.jpg` 之前的版本，完整的是 `ui_review_after2_dark.jpg` 之前的中间态）；最终版 `ui_review_final_*.jpg`。直观变化：高饱和蓝块 → 淡底细描边、橙色头像 → 灰蓝、整块蓝底选中 → 强调条、逐条重复 meta → 成簇合并、圆角 18 → 10、投影消失。

## 5. 边界与如实说明

1. **内容本身不是 UI 能改的**：屏上 8 条「已删除成品 zz_uitest_…」是真实操作回执，UI 层按文本特判属于硬编码业务规则，没有做。已通过降低色块感 + 分组减轻噪音，但它们仍占满首屏。
2. **标题栏未重构**：奶龙图标、状态胶囊、裸时间的层级问题仍在（改动会牵动窗口按钮布局与 57 单历史行为），本轮保留。
3. **间距令牌迁移未做**：69 处历史 Margin 仍是散值，本轮只改了气泡相关的一小部分。
4. **运行时主题切换未做 UI 自动化验证**（UI-01 遗留边界）。
5. 截图脚本用 P/Invoke 置顶窗口，仅用于评审，不进入产物；`tools\inspect\` 下的一次性迁移脚本不入库。
6. Analyzer 告警 178（较 UI-02 无新增类别），仅记录不设门禁。

## 6. 文件与回滚

**改动**：`src\00_header.ps1`（色板 + 角色色）、`src\10_data.ps1`（阈注 + 120 秒）、`src\30_window.xaml`（IcoBtn 边框/FeedList 宽度/Rail 底色）、`src\40_app.ps1`（气泡/头像/导航/系统消息/布局诊断）、`tests\DataLayer.Tests.ps1`、`tools\check_ui_contrast.py`（用例名）、`reports\build_map.md`。

**新增**：`reports\UI-03_delivery.md`、`reports\baseline_20261115_145833.md`、`mirror\20261115_145833_UI03_verify.ps1`、4 张评审截图、`tools\inspect\capture_ui.ps1`。

**回滚**：`git revert <本次提交号>` 后重跑 `build.ps1`；或 `copy /Y mirror\20261115_143508_UI02_verify.ps1 D:\tmp\xiaozhu_live.ps1`。

## 7. 下一轮建议

- 标题栏重构（图标容器化、状态与时间分层、窗口按钮节奏）
- 把操作回执类消息在数据层标成 `system` 语义，渲染层走轻提示（需动数据协议，风险较高）
- 69 处间距迁移到 `Space1–4`
- 97 条空 catch 的静默失败治理
