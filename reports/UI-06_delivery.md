# UI-06 交付：帧率量化 · 控件轻量化 · 精致度打磨

日期：2026-11-15　产物：`D:\tmp\xiaozhu_live.ps1`　SHA256 `29DEBD70…`

## 0. 用户诉求

「帧率不够高，画面不够精致，继续优化」。两者都不能凭感觉改，本轮先建可复现的测量方法，再决定动什么。

## 1. 测量方法（产品代码零改动）

`tools\inspect\make_fps_probe.py`：把任意版本产物复制成**带埋点的临时副本**，在 `CompositionTarget.Rendering` 上逐帧记录时间戳，采样 3 秒静止 + 3 秒持续程序化滚动，输出：

- 帧间隔 `p50 / p95 / max` 与 `>33ms` 长帧数（平均值会掩盖偶发卡顿，所以看分布）
- 视觉树规模（Visuals / TextBox / TextBlock / FeedList 子项）
- 复制菜单可用性（`ctx_items`、`copy_handler_ok`）
- 主题切换核心工作耗时（`Apply-Theme` + 全量 `Refresh-Feed`）

结果写 `health\fps.log` 后自动关窗，便于交替 A/B，且**现役脚本一行不改**。

## 2. 结论：滚动没掉帧，真正的「卡」在主题切换

| 指标 | UI-05 基线 | UI-06 |
| --- | --- | --- |
| 滚动 fps（4 次交替） | 74.1 / 80.2 / 70.2 | 76.8 / 73.3 / 74.5 / 81.3 |
| 帧间隔 p50 / p95 | 16 / 16 ms | 15–16 / 16 ms |
| `>33ms` 长帧 | 0–1 | 0 |
| 视觉树元素 | 1662（72 TextBox / 229 TextBlock / 126 气泡项） | 1713（胶囊多出 Border，TextBox 仍 72） |
| **主题切换耗时** | **734 / 719 / 734 ms** | **391 / 422 / 422 ms** |

**主题切换 726ms → 412ms（约 −43%）**，这才是「点一下顿一下」的来源：切换时 `forceRefresh` 触发 120 条气泡全量重建。滚动帧率两组在 70–81 fps 完全重叠，**没有显著提升，也不该被包装成提升**。

另一个诚实结论：静止 `idle_fps` 在 15–42 之间大幅波动，它测的是「WPF 空闲时是否需要提交帧」，不是流畅度指标，本轮不用于任何结论。

## 3. 实际改动（`src/20_ui_helpers.ps1`、`src/40_app.ps1`）

### 控件轻量化
- **事件委托共享**：此前每条消息新建 3 个右键菜单回调 + 1 个滚轮转发闭包，首屏 72 个 TextBox 产生 **288 个闭包/委托** → 改为 4 个脚本级单例，行为不变（探针验证 `ctx_items=4 copy_handler_ok=True`）。
- **右键菜单延迟构造**：`ContextMenu + 3 MenuItem + Separator` 推迟到首次右键才创建，主题切换重建路径少造 120 套菜单对象（485 → ~412 ms 的最后一段收益）。
- **关闭只读正文不需要的子系统**：`IsUndoEnabled=false`、`SpellCheck=false`、`AllowDrop=false`、`IsInactiveSelectionHighlightEnabled=false`。
- **紧凑消息不再构造永不加入视觉树的 meta TextBlock**。
- **移除 1 秒 clock 定时器**：顶栏时钟已在 UI-05 隐藏，每秒写 DP 纯属浪费（函数保留便于将来接回）。

### 精致度
- **字体渲染模式统一**：气泡正文被强制 `TextFormattingMode=Ideal`，窗口根是 `Display`，两套并存导致中文发虚且更慢 → 统一 `Display`。
- **入场动效克制化**：4 条 `DoubleAnimation` + `BackEase` 回弹 + `ScaleTransform` → 2 条（Opacity / Y）+ `CubicEase EaseOut`、180ms，更贴近 Fluent 的轻入，也少一半动画时钟。
- **气泡非对称圆角**：靠近头像一侧收小角（自己 12/12/4/12，他人 12/12/12/4），形成对话朝向；内边距从 14×9 回到 4px 栅格 12×8，meta 间距 3→4。
- **系统提示胶囊化**：两行居中裸灰字 → `Input` 淡底、8px 圆角、居中的轻量胶囊，减少对消息流的打断。

### 主动撤销的一项
尝试把聊天滚动条细化成 6px 圆角淡块（局部 `ScrollViewer.Resources`）。截图里滚动条**淡到几乎看不见**，想用像素扫描确认时工具层拦截了运行时程序集加载，按规则未绕行。**可见性未验证 → 整块撤销**，`src/30_window.xaml` 本轮零改动，不留半成品。

## 4. 合理性判断

- **否决「加 UI 虚拟化」**：S3 已测首屏 120 条硬上限，且本轮证明滚动 p95=16ms、零长帧，虚拟化收益为零、风险是重写整套气泡渲染。
- **否决「为提帧率而减少视觉节点」**：数字显示视觉树仍是 1662 量级；真正成本在**重建时的对象创建**（菜单、闭包、TextBox 子系统），所以优化方向是轻量化构造路径而非删控件。
- **否决「把 TextBox 换成 TextBlock」**：会丢掉用户依赖的「可选中 + 右键复制」，收益不足以抵交互回退。
- **保留 412ms 的边界**：再往下压需要让气泡色值全部接入共享资源画刷、切换时不重建气泡，或分帧重建；两者都触及渲染协议，改动面远大于本轮，需单独确认，**没有擅自做**。

## 5. 验收

| 项 | 结果 |
| --- | --- |
| Parser 语法 | 0 错 / 24184 tokens |
| UTF-8 BOM | `EF BB BF` 保留 |
| 源/产物一致性守卫 | `[OK]` |
| Pester 特征测试 | **40 / 0** |
| 一键校验 | **GREEN**，退出码 0 |
| 对比度 | **24 / 24 PASS** |
| 真实启动 | `start entries=645`，`live3_err.txt` 为空，无未捕获异常 |
| 真实点击主题切换 | 通过，全窗口统一深色 |
| 复制菜单 | `ctx_items=4`、`copy_handler_ok=True` |
| 双主题完整截图 | `ui_UI06_deliver_light.jpg` / `ui_UI06_deliver_dark.jpg` 目视通过 |
| 主题文件 | 已恢复用户原值 `True` |

`PSScriptAnalyzer` 告警 183 条（空 catch 101 条），按既定策略仅记录、不设门禁。

## 6. 交付物与回滚

- 源码：`src/20_ui_helpers.ps1`、`src/40_app.ps1`、`reports/build_map.md`
- 长期工具：`tools/inspect/make_fps_probe.py`（可复现 A/B 帧率探针）
- 一次性迁移脚本：`apply_ui06.py` / `apply_ui06b.py` / `apply_ui06c.py`（不入库）
- 证据：`health/fps.log`、`reports/baseline_20261115_161902.md`、双主题截图
- 镜像：`mirror/20261115_161902_UI06F_verify.ps1`

**回滚**：`git revert <本轮提交>` 后重跑 `tools\build.ps1`；或 `copy /Y mirror\20261115_154306_UI05_verify.ps1 D:\tmp\xiaozhu_live.ps1`（`src\` 需同步退回，否则一致性守卫报分叉）。

**仍未解决**：主题切换仍有约 412ms 重建停顿；UI 层自动化测试仍 0；101 条空 catch 未治理；8 条「已删除成品」真实回执仍占首屏。

**用户当前窗口仍是旧版，重启软件才会加载本轮改动。**
