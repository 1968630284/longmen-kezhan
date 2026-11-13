# 29 号审单 · 美化库可行性 + 帧率下一档（只审不改）

- 审单人：大厨｜时间：2026-11-07 21:15
- 方法：NuGet 下载 → 解包看 TFM → **隔离进程**（`powershell -STA`，不碰现役）逐个试加载程序集、实例化控件、加载主题资源字典。脚本与包都在 `verify\29\libs\`、`verify\29\test_wpf_libs.ps1`。

## 3 项 · 四个 UI 库在 PS 5.1 + .NET Framework 4.8 下能不能用

| 库 | 版本 | 有 net48/net481 | 程序集加载 | 控件实例化 | 主题字典 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| HandyControl | 3.5.1 | ✓（net48） | ✓ | ✓ `Controls.Badge` | ✓ `Themes/Theme.xaml` | **可用** |
| Wpf.Ui（wpf-ui） | 4.3.0 | ✓（net481） | ✓ | ✓ `Controls.Button` | ✓ `Resources/Wpf.Ui.xaml` | **可用**（包 16.8 MB） |
| ModernWpf | 0.9.6 | ✓（net462） | ✓ | ✓ `Controls.ProgressRing`（需同时加载 `ModernWpf.dll` + `ModernWpf.Controls.dll`） | ✓ `ThemeResources/Dark.xaml` | **可用** |
| Panuon.WPF.UI | 1.1.12.1 | ✓（net48） | ✓ | **部分**：`Switch` 能建，`Pagination`/`WindowX` 静态构造直接抛异常 | 未验（控件层已挂） | **部分可用，风险高** |

**一句话**：四个里三个技术上能跑起来，Panuon 有静态构造坑。

**但"能加载"≠"该换"**，三条硬理由：
1. 这三家都是**整套控件替换**（自带 Window/Button/TextBox 模板），一旦合并它们的资源字典，会跟现役 100+ 处自绘样式、`Apply-Theme` 的逐控件赋色**双轨打架**——我们已经踩过 DynamicResource/PSObject 的坑（handoff 坑 8）。
2. 都要在 Application 级挂它们的 ThemeManager/资源字典，与"单文件脚本 + 运行时 FindName"的加载顺序冲突风险高。
3. 体积：三个包合计约 28 MB，存档包会跟着变大。

**推荐：不换皮，走本地实现（方案 B）**——把现有 7 个资源键扩成一套"设计令牌"（颜色/圆角/间距/字号/阴影 5 类，约 30 个键），仍由 `Apply-Theme` 统一赋值，不引入第三方。
成本约 80 行、风险低、零依赖；观感提升主要来自**间距与字号的节奏**，不是换控件库。

## 字体（26 号遗留一并了结）

本机已装可用：`Microsoft YaHei UI` / `Segoe UI` / `Noto Sans SC` / `微软雅黑`。三套候选结论：
- **A（推荐）**：YaHei UI 打底，数字/英文显式写 `Segoe UI`，小字 10.5→11，正文 13.5→14。零下载、零授权风险。
- B：`Noto Sans SC` 打底——更现代但中文略宽，长文换行变多。
- C：只提字号不动字体。与 A 重叠，可并入 A。

## 4 项 · 帧率下一档（在 26 层二 + 虚拟化之上）

| 序 | 措施 | 预期收益 | 成本 | 风险 |
| --- | --- | --- | --- | --- |
| 1 | **应用内计时埋点**（Set-Collab/Set-OutView/Refresh-Feed 进出手表，写 `health\ui.log`） | 先拿到真实毫秒数，后面全部优化才有依据 | ~12 行 | 低 |
| 2 | **时间线窗口化**：只渲染最近 300 条 + 顶部「加载更早」 | 内存 568 MB → 约 400 MB，首屏渲染少一半 | ~25 行 | 低 |
| 3 | **阴影只悬停/选中才有**（当前每卡都有） | 重建时少一批离屏绘制，滚动更顺 | ~15 行 | 低 |
| 4 | **2 秒 tick 分频**（Refresh-Collab/Products 只在对应视图可见时跑） | 空闲时不再白跑 5 件事 | ~10 行 | 极低 |
| 5 | **真虚拟化**（ItemsControl + VirtualizingStackPanel） | 内存降到 ~150 MB，1000 条也不卡 | 60–80 行 | 中：滚动位置、新条目动画、卡片复用都要重验 |

**建议序**：1 → 2 → 4 → 3 → 5。理由：先有数据，再砍体量，最后才动列表控件（风险最高、收益最晚兑现）。

*本文件只审不改，未动现役代码；下载的包与测试脚本都在 verify\29\libs\ 下，可整目录删除。*