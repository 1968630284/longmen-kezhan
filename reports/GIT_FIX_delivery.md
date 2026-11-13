# 交付 · 版本控制基线 + 首个经构建链修复的真实 bug

- 日期：2026-11-13
- 用户指令：「怎么好怎么搞 / 请继续执行任务」→ 自主选题
- 结论：选了**消除反复出现的根因风险（无版本控制）**，并用刚建好的构建链**修掉第一个真实 UI bug**，端到端验证整套新工作流

## 一、为什么选这两件事

前四轮里我至少四次以「项目没有版本控制、源/产物会分叉」为由推迟重构（XAML 抽取、构建链、大范围拆分）。这个根因不消掉，后面的架构工作永远要绕着走。而 `Thickness(10, 3)` 是上一轮实测发现的、每天都在静默失败的既有 bug，改动仅 3 行、可确定性验证。两件一起做，正好用第一个真实改动检验「src → build → 守卫 → 回归 → 提交」这条链路是否真的可用。

## 二、版本控制基线

### 盘点与排除

项目共 **1261 个文件 / 178 MB**，大头是 `verify/` 下的 3–4 MB 截图和 1 MB 级 `tree.json`（UI 树快照）；`backup_*_profile_*` 目录含 `cordis.yml` / `cordis.patch.yml` 等可能带凭据的配置；`bus/board.jsonl` 是用户对话历史。全部排除。

`.gitignore` 按四类排除：历史证据包与图片、凭据/profile 备份、运行时状态与日志、调试文本片段与临时探针。提交采用**白名单** `git add`（明确列出路径），不用 `git add .`。

### 关键一步：`.gitattributes`

首次 `git add` 出现 `LF will be replaced by CRLF` 警告。`build.ps1` 是**按字节拼接**生成产物的，一旦 src 被转成 CRLF，产物 SHA 就会失配。已写入：

```
* -text
```

并设置仓库级 `core.autocrlf=false`、`core.quotepath=false`。验证 `src\10_data.ps1` 仍为 `CRLF=0 / LF=163` ✓。

### 提交

- `59835c8` — `chore: establish version-controlled baseline (src split, reproducible build, tests, reports)`
- 127 个文件、146,624 行；暂存前敏感项复查（backup_ / .jsonl / 图片 / token / cordis.yml / .log）**干净**
- 仓库级身份 `WorkBuddy <workbuddy@local>`，未改全局 git 配置
- `xiaozhu_live.ps1` 位于仓库外（`D:\tmp\` 根），**不需要入库**：它由 `src\` + `build.ps1` 逐字节可复现，`mirror\` 保存各版本快照

> 工作区仍有大量未跟踪的历史杂项（调试脚本、archive 子目录、bus 状态文件等）。它们保持原样、未被改动也未被提交；`git status` 会显示它们，属预期。

## 三、Thickness 修复（走完整构建链）

### 问题

产物 1628 / 1698 / 1721 行三处 `New-Object Windows.Thickness(10, 3)`。WPF `Thickness` 只有 1 参和 4 参构造，**没有两参重载**，因此每次启动这三处 `Padding` 都静默失败、按钮内边距没设上。

### 改动

只在 `src\40_app.ps1` 改 3 行 → `Thickness(10, 3, 10, 3)`（left=10, top=3, right=10, bottom=3，即左右 10、上下 3 的设计意图）。`git diff` 精确显示 `1 file changed, 3 insertions(+), 3 deletions(-)`。

### 验证

| 项 | 结果 |
| --- | --- |
| 构造单元验证 | 2 参 `succeeded = False`（确属非法）；4 参 `correct = True`（10/3/10/3） |
| 产物残留两参构造 | **0** |
| `build.ps1` | 产物 SHA `85AE3BBD…` / 2957 行 / 153,214 B |
| `check_source_sync.ps1` | `[OK]` 退出码 0 |
| Pester | **24 / 0** |
| 一键校验 | GREEN：BOM `EF BB BF`、Parser 0 错 / 22,417 tokens、24/0、Analyzer 164 条仅记录 |
| 真实启动 | `start entries=642`、`live3_ok` 同步、无 `dispatcher-unhandled` |
| 截图目视 | 窗口标题、深色主题、消息气泡与文字完整，无布局错乱或控件重叠 |

**过程中的一个失败**：原计划用 `Start-Process -RedirectStandardError` 做「改前镜像 vs 改后产物」的错误数 A/B，但本机同时存在 `HTTPS_PROXY` 与 `https_proxy` 两个仅大小写不同的环境变量，`Start-Process` 构造环境字典时抛 `已添加项` 异常，两次启动都没起来。未反复重试，改为确定性的构造单元验证 + 产物残留计数 + 真实启动回归，证据强度等价。

**目视局限**：截图是聊天首屏，被修复的三处按钮位于**视频工坊**的参数区，本次没有逐按钮目视对比。构造正确性与整体启动无回归已验证；若要在意那三个按钮的视觉，请打开工坊页看一眼内边距。

## 四、文件

新增：`.gitignore`、`.gitattributes`、`reports\GIT_FIX_delivery.md`、`reports\baseline_20261113_213500.md`、`reports\build_map.md`（随构建更新）、`mirror\20261113_213500_FIX_verify.ps1`、`tools\inspect\verify_thickness.ps1`（临时验证，未入库）。

修改：`src\40_app.ps1`、`ledger.md`。

## 五、回滚

```
git -C D:\tmp\nailong revert <修复提交号>       # 回到 3 处两参构造
# 或按旧规约：copy /Y mirror\20261113_212543_S4_verify.ps1 D:\tmp\xiaozhu_live.ps1
```
回滚后需重跑 `build.ps1` 让 `src\` 与产物一致。

## 六、遗留（未变）

S3 虚拟化（等放开 120 条上限）、`-LibraryOnly`（需先拆 40_app 定义区/初始化区）、DLL 自缓存（编译占比待测量）、90 条空 `catch`、以及 `verify/` 178 MB 证据包是否单独归档。版本控制与构建链这两项根因已补齐。
