# 奶龙协作协议（AGENTS.md）

> 三个人：**余佳凯（用户）**、**DSH-Qwen（助手 A）**、**另一个助手（助手 B，请在这里登记名字）**。
> 界面只有一个：桌面「奶龙工坊」。留言板、动作日志、文件占用都已经长在这个窗口里了。

## 一、在哪说话

打开「奶龙工坊」：

- 主界面就是**三方共同的时间线**：小猪的回复、你的留言、两个助手的留言，按时间排在一起。
- 在底下输入框说话 = 同时写进 `muse_feed.json`（小猪读）和协作总线（两个助手读），不用发两遍。
- 点工具栏 **「🗂 协作台」** 切到看板视图，三页签：
  - 💬 留言板：总线上的全部留言
  - 📜 动作日志：谁改了什么文件、跑过什么命令
  - 🔒 占用：当前哪个文件被谁占着
- 看板底下也有输入框，可以按 `留言/状态/任务/提问/决定` 分类发言。

## 二、总线在哪

```
D:\tmp\nailong\bus\
  board.jsonl      留言板（界面读它）
  activity.jsonl   动作日志
  agents.json      成员登记
  claims\          文件占用声明
  bus.ps1          命令行入口（助手用）
```

## 三、助手怎么用（命令行）

```powershell
$bus = "D:\tmp\nailong\bus\bus.ps1"

# 看板 / 日志 / 占用
powershell -File $bus board
powershell -File $bus activity
powershell -File $bus claims

# 发言（名字就是你的身份，短一点，一直用同一个）
powershell -File $bus post -From "你的名字" -Kind status -Text "在做什么" [-To all]

# 记动作
powershell -File $bus log -From "你的名字" -Text "改了什么" -Ref "文件名"

# 占坑 / 放坑（改 xiaozhu_live.ps1 前必须先占）
powershell -File $bus claim xiaozhu_live.ps1 -From "你的名字" -Note "要改什么"
powershell -File $bus release xiaozhu_live.ps1 -From "你的名字"
```

## 四、四条铁律

1. **动 `D:\tmp\xiaozhu_live.ps1` 前先 `claim`**。返回 `BUSY by 别人` 就别动手，发条留言问。
2. **每次动手后写一条 `log`**，一句话说清改了什么。
3. **要对方配合、有结论、有疑问 → `post`**，别指望对方读心。
4. **`.ps1` 必须存 UTF-8 with BOM**，否则 PowerShell 5.1 会把中文读成「寮€濮嬫覆鏌」并且直接语法报错。

## 五、当前分工（2026-11-06 23:47）

| 模块 | 负责人 | 状态 |
| --- | --- | --- |
| 主窗口 `xiaozhu_live.ps1`（聊天流 + 协作台 + 视频工坊） | DSH-Qwen（占用中） | 已接入总线与渲染 |
| `video_studio\engine\render.ps1` 本地渲染引擎 | DSH-Qwen | 8s / 1080p / 已自测 |
| `video_studio\engine\studio_daemon.ps1` 渲染守夜人 | DSH-Qwen | 常驻，点「生成视频」自动拉起 |
| 桌宠 `nailong_pet.ps1` | 无人 | 可接主线时间线 |

## 六、给用户看的

- 桌面只有「奶龙工坊」一个窗口（单实例：重复启动会把已有窗口叫到前面）。
- 想让我俩停下来讨论，在看板发 `决定` 类型即可，两边下一轮都会看到。