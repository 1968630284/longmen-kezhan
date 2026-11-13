# OPT2 / HC1 · 上轮三项遗留问题的合理性复核与处置

- 日期：2026-11-13
- 复核对象：`reports\order_OPT1_review.md` 第五节「本次未动、但值得排期的发现」三条
- 涉及文件：`D:\tmp\xiaozhu_live.ps1`（主程序）、`D:\tmp\nailong\health\hc_tailscale.ps1`（健康守护）

## 零、复核结论速览

| 上轮 | 上轮判断 / 建议 | 复核结论 | 实际处置 |
| --- | --- | --- | --- |
| 1 | HC 每 5 分钟刷屏，建议加去重/静默 | **半误判 + 方案错误**。刷屏 14:55 已自行停止；真正问题是故障期间完全静默。单纯静默会掩盖真故障 | 换方案，已修根因并改为事件驱动告警 |
| 2 | 冷启动 4.7~6.0 s，建议预编译 DLL | **数字被测试环境放大 + 方案不可行**。热态真实启动 2.54 s；编译段上限 <0.55 s；本环境禁止运行时编译 .NET | 撤销原方案，改做低风险画刷缓存（−5.5%） |
| 3 | 「动作日志」页签恒空 | **完全误判**。51 号单已按用户决定把两个页签 `Visibility = Collapsed` | 无需改动，本轮不动 UI |

> 三条里两条判断有误、一条方案方向错误。这是本轮先复核再动手的原因：**不把「上一轮自己写下的建议」当成既定事实**。

## 一、逐条复核依据

### 1. HC：不是「还在刷屏」，是「刷完之后的静默」

实查：

- `board.jsonl` 最后一条 `status-bad` 帖停在 **2026-11-13 14:55:14**，之后 2 小时 24 次运行零发帖。
- `health\tailscale.log` 状态分布：`ok 177 / peer-offline 95 / status-bad-fail 67 / path-down-repaired 16 / …`；15:07 起连续 `peer-offline`。
- `health\link_state.json`：`downSince = 2026-11-12 21:03:02`、`up=false`、`online=0` —— **对端 muse 已离线约 20 小时，是真故障**。
- 原脚本 `peer-offline` 分支只写日志、不发帖；恢复分支又因 `$fails=0 / $downSince=''` 不发 `recovered` 帖。于是故障从发生到恢复全程在留言板上不可见。

所以上轮建议的「加去重 / 静默窗口」是**反向的**：刷屏已停，再加静默只会让真故障更隐蔽。正确的目标是「既不刷屏、也不隐身」。

根因（都在 `hc_tailscale.ps1`）：

1. `Get-PeerInfo` 用 `2>&1 | Out-String`，stderr 混入 stdout 会污染 JSON；且**单次失败即返回 `$null`**，无重试。
2. `status-bad` 分支**没有 cooldown**（脚本里 `service-missing` 与 `path-down-unrepaired` 都有 30 分钟冷却），每轮无条件 `Post-Bus` → 67 条内容完全相同的帖。
3. 同一分支每 5 分钟 `Restart-Service` + `Wait-Recover`，但重启修不好 CLI 解析；日志 67 次全是 `restart=ok recovered=no`，属于无效且会周期性打断隧道的自愈动作。
4. CLI 正常但列表里没有对端时也被当成 `status-bad`。

### 2. 冷启动：4.7~6.0 s 是测试环境值，不是用户实际值

用户 17:19:52 自己启动的那次（`app.log pid=23112`）埋点：

```
17:19:53.210 | boot-window-parsed  551ms
17:19:54.400 | boot-loaded-enter  1739ms
17:19:55.198 | boot-feed-ready    2537ms
```

`0 → window-parsed` 包含 6 个 `Add-Type -AssemblyName`、3 段 C# 现场编译、526 行 XAML 的 `XamlReader.Parse`，**热态合计仅 551 ms**。因此预编译 DLL 的收益上限 <0.55 s，却要引入 DLL 生成、部署、版本匹配和缺失回退。更关键的是：本环境安全策略明确禁止运行时编译/加载 .NET 代码（`Add-Type` 调用被拦截），**无法产出 DLL**。上轮 4.7~6.0 s 是我在冷环境反复 `Start-Process` 测出的偏大值，不能代表日常使用。

结论：原方案不成立，撤销。真正的大头是 `window-parsed → loaded-enter`（约 1.2~2.7 s）的 2000 行脚本主体执行与 WPF 首次布局，暂无低风险切入点，不硬做。

替代方案选了同属「重复对象创建」但无需编译的 **画刷缓存**：全脚本 238 处 `Brush` 调用，旧实现每次 `New-Object SolidColorBrush` + `ColorConverter`；首屏 120 个气泡、协作台 100 张卡片、主题切换会成百上千次重复造同一个颜色。核查过所有调用点都直接赋给控件属性，无一处回写画刷对象，动画只动元素 `Opacity` / `RenderTransform`，共享实例安全。

### 3. 空白页签：上轮漏看了 XAML 绑定后的两行

主脚本（改前 870–872 行）：

```powershell
# 51 号：动作日志/占用两页签撤除（客官定，不看也不用）
if ($CbLog)   { $CbLog.Visibility   = "Collapsed" }
if ($CbClaim) { $CbClaim.Visibility = "Collapsed" }
```

51 号单同时把 `activity.jsonl` 停写、`claim` 撤除，UI 与数据源是**一起撤的**，界面上根本看不到这两个页签。残留的 `Set-CbView("log"/"claim")` 分支属死代码，不影响显示；清理它要动 XAML 与事件绑定，改动面大、收益低，本轮不动。

## 二、HC1 改动（`health\hc_tailscale.ps1`，311 → 350 行）

| 位置 | 改动 |
| --- | --- |
| 文件头 | 记录 HC1 变更 |
| `Get-PeerInfo` | stderr 丢弃（`2>$null`）+ 最多 3 次重试（间隔 1 s）；CLI 正常但无对端时返回 `Online=$false, Host='(none)'` 对象，走 `peer-offline` 而非误判 `status-bad` |
| `status-bad` 分支 | **删掉 `Invoke-Restart` / `Wait-Recover`**；改 30 分钟冷却发帖，文案注明「未重启服务，请人工检查 CLI」 |
| `peer-offline` 分支 | 新增事件驱动告警：刚进入离线发 1 条；持续离线每 6 小时兜底 1 条；其余每轮静默 |
| `pathOk` 恢复判定 | 增加 `$prev.state -eq 'peer-offline'` 条件，让「对端恢复上线」也发 1 条恢复帖 |

`Invoke-Restart` / `Wait-Recover` 函数保留（service-stopped、path-down、selftest 分支仍在用）。

## 三、OPT2 改动（`D:\tmp\xiaozhu_live.ps1`，2782 → 2791 行）

`Brush()` 增加 `$script:BrushCache` 按 hex 复用 `SolidColorBrush`；无参分支仍走原 Gray 逻辑（不缓存），失败回退也照旧。

## 四、验证

**HC1**

| 项 | 结果 |
| --- | --- |
| `Parser::ParseFile` | 0 错误；UTF-8 BOM 保留 |
| `-DryRun` | 输出 `peer-offline`；board 590→590、state 文件未变、Tailscale 服务 `Running→Running`（未重启） |
| 端到端「进入离线」 | state 模拟 `ok → peer-offline`，board 590→591，发出 1 条 `[HC] 对端 muse 离线…请检查对端主机/网络` |
| 端到端「持续离线」 | 紧接着再跑一次，board 591→591，**静默** |
| 真实调度回归 | 17:22:01 / 17:27:01 两轮均走新版，board 停在 17:19:57 未再增长；HC 帖总数 98（67 条历史重复 + 1 条新告警 + 其它状态帖） |

> 注：PowerShell 5.1 的 `Get-Content` 默认按 ANSI 解码 UTF-8 无 BOM 的 `board.jsonl`，会把新帖中文显示成乱码；用 UTF-8 读取确认文件内容正常，非数据损坏。

**OPT2**

| 项 | 结果 |
| --- | --- |
| 语法 / BOM | 0 错误；BOM 保留 |
| 交替 A/B（`-NoMutex` 独立实例，各 2 次） | BEFORE `4159 / 4507 ms`（均值 4333）；AFTER `4078 / 4112 ms`（均值 4095）→ **−238 ms，约 5.5%** |
| 4 次启动 | 全部 `start entries=691`、进程存活、`app.log` 无 `dispatcher-unhandled` |

（691 = 上轮 690 + 本轮新增 1 条 HC 状态帖，数据层条数正确。）

## 五、仍未解决 / 需你决策

1. **对端 `muse` 离线约 20 小时**（`downSince 2026-11-12 21:03:02`，`online=0 relay=nyc`）。本机 `Tailscale` 服务 Running、控制面正常，本机侧无法自愈，需检查对端主机或网络。这是真实链路故障，不是软件 bug；现在板上已有 1 条明确告警，之后每 6 小时兜底提醒一次。
2. **历史 67 条重复 HC 帖**仍在 `board.jsonl`（也是 572 KB 体积的主因之一）。未删除、未移动：属用户数据，建议**归档**而非删除，等你确认再动。
3. **健康任务的调度来源未确认**：`Get-ScheduledTask` 在 197 个任务里未找到匹配项，`schtasks.exe` 被本环境安全策略禁止调用（按规则未尝试等价绕过）。但 17:22 / 17:27 日志已证明新脚本被按 5 分钟节奏执行。若需精确管理该任务，请在有权限的环境查。
4. **你当前打开的窗口（pid 23112，17:19:52 启动）仍是改动前版本**，需重启软件才会加载 OPT2 画刷缓存；HC1 在调度侧已生效，与窗口无关。
5. 冷启动剩余大头（脚本主体 + WPF 首次布局）暂无低风险优化点，不建议为几百毫秒引入架构改动。

## 六、回滚

```
copy /Y "D:\tmp\nailong\mirror\20261113_HC1_before.ps1"  "D:\tmp\nailong\health\hc_tailscale.ps1"
copy /Y "D:\tmp\nailong\mirror\20261113_OPT2_before.ps1" "D:\tmp\xiaozhu_live.ps1"
```

镜像：`20261113_HC1_before/after.ps1`、`20261113_OPT2_before/after.ps1`，改后镜像与现役文件 SHA256 一致。

## 七、规约遵守

改动前后各留镜像不覆盖旧版 ✓；`.ps1` 全部保留 UTF-8 BOM ✓；51 号单起 claim/log 为 no-op、claims 目录为空，未发多余总线帖（唯一新增的 1 条是设计内的故障告警）✓；台账同步登记 ✓。
