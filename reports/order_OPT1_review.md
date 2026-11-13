# OPT1 · 龙门客栈（奶龙工坊）轮询性能优化

- 日期：2026-11-13
- 目标文件：`D:\tmp\xiaozhu_live.ps1`（桌面「龙门客栈」→ `launch_app.vbs` → 本脚本）
- 改前镜像：`mirror\20261113_OPT1_before.ps1`（SHA256 `72b68640…e277c7217c25a8`）
- 改后镜像：`mirror\20261113_OPT1_after.ps1`（SHA256 `466c642d…e33ab1e7a8073970d7c6ee0`）
- 现役脚本与 after 镜像逐字节一致

## 一、问题

脚本末尾的 `DispatcherTimer` 每 2 秒在 **UI 线程**上同步执行：

```
Refresh-Feed → Read-MergedFeed → Read-Feed + Read-BusJsonl("board.jsonl")
Refresh-Collab                 → Read-BusJsonl("board.jsonl")   ← 同一文件第二遍
```

`board.jsonl` 此时 589 行 / 572,349 字节。旧实现每轮把整份文件读两遍、逐行 `ConvertFrom-Json`，且用 `$items +=` 拼接 PowerShell 数组（每次复制全数组，O(n²)）；`Convert-FeedTime` 和 board 循环里还逐条调用 `Get-Date`。即使一条新消息都没有，这些工作也照做不误。

基线实测：单遍 `Read-BusJsonl` 中位 136 ms；一轮 `Read-MergedFeed` 346~349 ms；合上一轮 tick 约 **491 ms 被压在 UI 线程上**，即每 2 秒卡顿约 0.5 秒，且随留言板增长持续恶化。

## 二、改动（全部在主脚本内，5 处）

| 位置 | 改动 |
| --- | --- |
| 新增 `Get-FileStamp` + `$script:FileStamp` / `$script:FileCache` | 以「文件长度 + LastWriteTimeUtc.Ticks」为指纹；与 26 号 `OutSig` / `JobSig` / `cbKey` 同一套路 |
| `Read-Feed` | `@()` + `+=` → `ArrayList.Add`；命中指纹直接复用解析结果 |
| `Read-BusJsonl` | 同上，按 `bus:<文件名>` 分键缓存 |
| `Convert-FeedTime` | 新增 `[datetime]$now` 入参，去掉逐条 `Get-Date` |
| `Read-MergedFeed` | 双源文件签名缓存（跳过每轮 690 条对象重建 + 排序）；board 循环里 `$w` 复用 `$now` |

调用点安全性已逐一核对：`Read-Feed`(1 处)、`Read-BusJsonl`(3 处)、`Read-MergedFeed`(1 处) 全是只读遍历或 `@()` 复制，无一处回写元素，故缓存共享引用安全。

## 三、验证

**1. 数据层函数级对比**（把新旧两版真实函数代码分别载入独立 scriptblock 跑）

| 指标 | 改前 | 改后 |
| --- | --- | --- |
| `Read-MergedFeed` 冷首次 | 513 ms | 262 ms |
| `Read-MergedFeed` 第 2 / 3 次 | 349 / 346 ms | 2 / 1 ms |
| `Read-BusJsonl` 单遍 | 142 ms | 0 ms（命中） |
| 合并结果 | 690 条，首 `DSH-Qwen`、尾 `Dave 16:14:20` | **完全一致** |

**2. 缓存失效（防漏消息）**：临时 feed 追加一条后再次合并，条数 582 → 583，新消息可见。追加必然改变文件长度，故指纹一定变化。

**3. 真实启动**：两次启动均成功，`app.log` 追加 `start entries=690`，无 `dispatcher-unhandled`；`live3_ok.txt` 正常。PS 5.1 `Parser::ParseFile` **0 错误**，UTF-8 BOM 保留（AGENTS.md 铁律）。

**4. 稳态 CPU 采样**（启动后静置 8 秒 ≈ 4 个轮询周期，取 `TotalProcessorTime` 增量）

| 版本 | 8 秒 CPU 时间 |
| --- | --- |
| 改前镜像 | 781.2 ms |
| 改后 | **93.8 ms**（降约 88%） |

## 四、回滚

```
copy /Y "D:\tmp\nailong\mirror\20261113_OPT1_before.ps1" "D:\tmp\xiaozhu_live.ps1"
```

## 五、本次未动、但值得排期的发现

1. **冷启动仍要 4.7~6.0 秒**。本次实测 `boot-window-parsed 1135ms`、`boot-loaded-enter 3832ms`、`boot-feed-ready 4688ms`（热）/ 6004ms（冷）。大头是启动时 `Add-Type` 现场编译三段 C#（`GlassFx` / `WinIcon` / `TaskbarId`）与 XAML 解析，不是数据层。可预编译成 DLL 复用。
2. **健康检查在刷屏**：自 2026-11-08 18:12 起，`HC` 每 5 分钟往 `board.jsonl` 写一条**内容完全相同**的 `[HC] tailscale status 异常，已重启服务：service=Running status-json-fail restart=ok recovered=no`，累计 **67 条**（HC 帖共 97 条）。即服务反复重启却 `recovered=no`，同时这是留言板体积增长的主因。应查 `health\hc_tailscale.ps1` 的 status-json 判定，并加去重/静默窗口。**涉及另一模块与远程链路，本次未擅自改动。**
3. `activity.jsonl` 自 51 号单停写，协作台「📜 动作日志」页签恒为空——要么撤页签，要么换数据源。
4. 主脚本已 2782 行单文件，可考虑按「数据层 / 气泡渲染 / 视频工坊 / 协作台」拆模块（改动面大，需单独排期）。

## 六、规约遵守

- 改动前后各留一份 mirror，不覆盖旧版 ✓
- `.ps1` 保留 UTF-8 BOM ✓
- 51 号单起 `claim` / `log` 均为 no-op，claims 目录为空，故未发总线帖；本单以台账 + 本报告留痕 ✓
