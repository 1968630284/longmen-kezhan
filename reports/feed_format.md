# muse_feed.json 追加规范（24 号交付）

> 给掌柜用：往聊天窗口发「双人汇总汇报」时，按这份格式写即可被龙门客栈聊天视图正常渲染。
> 版本：2026-11-07 17:30，对应当役主程序 SHA `6190D389…2684BF`。

## 一、文件与编码

| 项 | 值 |
| --- | --- |
| 路径 | `D:\tmp\muse_feed.json` |
| 形态 | **JSONL**：一行一条 JSON，行尾 `\n` |
| 编码 | **UTF-8 无 BOM**（带 BOM 会让首行解析失败，应用会静默跳过该行） |
| 读取方式 | 应用 `Read-Feed`：逐行 `ConvertFrom-Json`，**解析失败的行直接跳过**，不报错 |
| 写入方式 | 追加写，**不要重写整个文件**（会丢历史） |

## 二、字段

```json
{"ts":"17:26:10","sender":"小猪","kind":"note","text":"【进度汇总】……"}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ts` | string | 是 | 推荐 `yyyy-MM-dd HH:mm:ss`（带日期最稳）；也兼容老写法 `HH:mm:ss`（按当天补齐，超前 2 小时按前一天算） |
| `sender` | string | 是 | 显示名，决定角色标签：含「小猪/掌柜」→掌柜(蓝)、「DSH/大厨/工兵/存档/HC」→大厨(绿)、「GPT」→GPT(紫)、「Dave/余佳凯/指挥部」→客官(红) |
| `kind` | string | 是 | 决定小标签：`note`留言 / `status`状态 / `result`结果 / `command`指令 / `question`提问 / `task`任务 / `decision`决定 / `discuss`商量 / `log`日志；未知值按 note 渲染 |
| `text` | string | 是 | 正文。可用换行（JSON 里写 `\n`），渲染为同一气泡内多行；建议 ≤500 字，长内容换成总线帖 |

## 三、两种写法

**A. 推荐：走应用同名函数逻辑（等价 shell 写法）**

```powershell
$e = [ordered]@{ ts = (Get-Date -Format 'HH:mm:ss'); sender = '小猪'; kind = 'note'; text = '【进度汇总】……' }
$line = ($e | ConvertTo-Json -Compress) + "`n"
[IO.File]::AppendAllText('D:\tmp\muse_feed.json', $line, (New-Object Text.UTF8Encoding($false)))
```

**B. 纯文本追加**：直接把 `{"ts":"…",…}` 一行加到文件末尾，确保是 UTF-8 无 BOM、行尾换行。

## 四、注意事项（踩过的坑）

1. **别写日期**：`ts` 只认 `HH:mm:ss`。写 `2026-11-07 17:26:10` 会被 `TryParseExact("HH:mm:ss")` 判失败、退回"当前时间"。
2. **跨天排序（24 号已修）**：老写法 `HH:mm:ss` 若补出来的时间比现在晚 2 小时以上，按**前一天**算，昨天 23:45 不会再挤到今天的汇报下面。新写法建议直接带日期（`2026-11-07 17:26:10`），零歧义。
3. **不要写 `ref` 字段**：feed 侧不看它；总线侧 `ref=mirror` 是应用双写时给桥用的标记，别混。
4. **sender 用中文真名**（小猪/大厨/Dave/GPT），不要用内部 id，否则角色标签会落到大厨兜底。
5. 应用每 2 秒轮询一次（`DispatcherTimer`），写完约 2 秒内出现，不需要重启。
6. 应用内发的消息会**双写**：feed 一份 + 总线一份（`ref=mirror`，只给机器看）。掌柜从外部追加时只需写 feed，不用发总线，避免时间线重复。

## 五、验证方法

```powershell
# 追加一条测试行后，看应用是否 ~2 秒内出现；或直接数行数与时间戳
(Get-Content D:\tmp\muse_feed.json -Encoding UTF8 | Select-Object -Last 1)
```

渲染核对：`tools\inspect\Inspect.ps1 -Mode Tree`，在 `tree.tsv` 里搜刚写的 sender 与时间串，能查到即为已渲染。