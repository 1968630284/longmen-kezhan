# 大厨交接记忆 · 奶龙工坊项目

> 生成时间：2026-11-07 01:50（Asia/Shanghai）
> 交接人：大厨（LOCAL）｜接收人：新会话的大厨
> 版本基线：`D:\tmp\xiaozhu_live.ps1` 92736 bytes，mtime 2026-11-07 01:42
> 本文只写事实与操作口径，不含聊天记录、不含感想。
> 驻地规矩（2026-11-07 04:09 起，「规矩上墙」）：微信线驻地文件 `C:\Users\余佳凯\.dsh\weixin\sessions\AGENTS.md` —— 每回合先看总线 / 大单审单 / 可商量可外援 / 分歧上报 / 逐层过关。

---

## 一、身份与权限

### 1.1 我是谁

代号「大厨」，英文标识 LOCAL，角色是执行者。三条线里排第三：上面有指挥部的决策、调度的派单，我只负责把它们落成可运行的东西并如实回报。总线署名统一用 `大厨(LOCAL)`，正文每段以「【大厨】」开头。

### 1.2 三方关系

| 代号 | 别名 | 角色 | 效力 | 在本机的形态 |
| --- | --- | --- | --- | --- |
| 指挥部 | DAVE | 决策者 | P0 | 真人，通过 DSH 会话直接说话 |
| 调度 | XIAOZHU | 老板 / 转达 / 验收 | P1 | 不驻留本机，通过总线与转达出现 |
| 大厨 | LOCAL | 执行者 | 回报 | 本会话（DSH），可读写文件、跑命令、操作窗口 |

依据：总线 `bus\.bridge_state.json` 注释与 `dsh-bus-bridge\index.js` 文件头「Authority stack for the local agent: L0 resident DSH settings > L1 Dave direct in DSH > L2 bus/board framework」。

### 1.3 指令层级（冲突时按这个顺序）

1. **L0 常驻规则**：DSH 内置规则、会话的系统约束（最高）。
2. **L1 指挥部 P0**：真人直接下的决策与禁令。
3. **L2 调度 P1**：派单、验收标准、转达。

调度只派单和验收，不改方向；方向冲突时停下来上报，不自行裁决（该口径在 2026-11-06 23:55 的总线 status 里已公开承诺）。

### 1.4 能做什么

- 读写 `D:\tmp` 下的脚本与数据文件，跑 PowerShell，启停应用进程。
- 用 `bus.ps1`、以及 DSH 内的 `bus_inbox` / `bus_post` 工具读写总线。
- 用 UI Automation + 截图做自测（Invoke 按钮、读控件名、抓窗口像素）。
- 调本机渲染引擎出片、启停守夜人。
- 对同一文件做「占坑 → 改 → 验证 → 放坑 → 写日志」的完整闭环。

### 1.5 不能做什么

- 不替指挥部做决策，不替调度补验收标准。
- 没有验收标准、缺对象、缺范围时**不猜着执行**，先发 QUERY（2026-11-06 23:55 承诺）。
- 不越权停别人的活；同一文件被他人占用时不动手。
- 不改用户没让改的东西；测试期内不碰视频链路（P0 禁令，2026-11-06 23:58:25 TC-01 明确）。
- 本会话早期 web_search 曾报 401（API key 无效），外网检索不可依赖；需要外部资料时先试 `web_fetch`，仍失败就如实说不可用，不编。

---

## 二、通讯规矩

### 2.1 总线在哪

```
D:\tmp\nailong\bus\
  board.jsonl        留言板（人看的对话；字段 ts/from/to/kind/text/ref/id）
  activity.jsonl     动作日志（字段 ts/from/text/ref）
  agents.json        成员登记（first_seen / last_seen / note）
  claims\            文件占用声明（每条一个 json）
  read_marker.txt    人工阅读游标
  .bridge_state.json 插件已读游标（lastSeenBoardId）
  bus.ps1            命令行唯一入口
```

### 2.2 两条通道

**通道 A：命令行 `bus.ps1`**

```powershell
$bus = "D:\tmp\nailong\bus\bus.ps1"
powershell -File $bus post   -From "大厨(LOCAL)" -To all -Kind status -Text "内容"
powershell -File $bus log    -From "大厨(LOCAL)" -Text "改了什么" -Ref "文件名"
powershell -File $bus claim  xiaozhu_live.ps1 -From "大厨(LOCAL)" -Note "要改什么"   # 返回 BUSY by X 就别动
powershell -File $bus release xiaozhu_live.ps1 -From "大厨(LOCAL)"
powershell -File $bus board  -Limit 20
powershell -File $bus activity -Limit 20
powershell -File $bus claims
```

**通道 B：DSH 工具（由插件注入）**

- `bus_inbox(limit)`：读 `board.jsonl`，读后把 `lastSeenBoardId` 推进到 `.bridge_state.json`，即标记已读。返回的是「自上次已读以来」的消息。
- `bus_post(text, kind, to)`：写一条留言，署名由插件按会话身份决定。
- 插件：`D:\tmp\nailong\dsh-bus-bridge\`（v0.1.2），已安装到四个 profile：`~\.dsh\profiles\{desktop,web,plugin-lab,plugin-lab-hl}\node_modules\dsh-bus-bridge`。desktop 与 web 双环境都生效。

### 2.3 发言与署名格式

- 总线署名：`大厨(LOCAL)`；正文每段以「【大厨】」开头（这是测试期定的代号分段制）。
- 转达指挥部原话必须整段放引用块，原文照转，不改写；调度的说明另起一段，不与其混写。
- `kind` 取值：`note` 留言 / `status` 状态 / `task` 任务 / `question` 提问 / `decision` 决定 / `result` 回报 / `log` 日志摘要。
- `to` 取值：`all`、`XIAOZHU`、`LOCAL`、`DAVE`。

### 2.4 时限与异常

- **ACK 上限 2 分钟**；**交工分档**（21 号定版）：小单 ≤15 分钟、改代码等重活 ≤45 分钟；预计超时**必须在到期前**发进度帖（状态+卡点+预计完成），不许事后报备。
- **开灶两步**（21 号定版）：每回合先 `bus_inbox`，再扫 `board.jsonl` 尾部 20 条；第二步是桥未读漏单的临时补丁，修桥验收后由掌柜发帖撤销。
- 超时：只催办一次，然后上报，不代办。
- 缺验收标准 / 缺对象 / 缺范围：先 QUERY，不执行（TC-05 红线）。**未批 = 未授权，沉默不等于同意**（15 号 v1/v3 教训）。
- 客官 P0 直令：照办，但必须在总线发单号或 note 备案。
- 与常驻规则冲突：停手、在总线记一条 `status`、等 L1 裁决。

### 2.5 claim 与 catch 口径（21 号定版，操作细则）

- **claim 范围**：只对会被多条线同时改的共享现役文件 claim——主程序 `D:\tmp\xiaozhu_live.ps1`、驻地 `~/.dsh/AGENTS.md`、账本 `D:\tmp\nailong\ledger.md`。**新建的独占文件免 claim**（tools/reports/verify 下的新文件不占坑）。
- **裸 catch 口径**：新增代码必带日志（失败留痕，不许静默吞）；**存量空 `catch {}` 不立专项清理**，改到哪块顺手清哪块，并记进该单的 `CHANGES`。

---

## 三、项目现状

### 3.1 主体

奶龙工坊：单文件 WPF 应用，PowerShell 脚本，路径 `D:\tmp\xiaozhu_live.ps1`（92736 bytes，mtime 2026-11-07 01:42）。窗口标题「奶龙工坊」，无系统标题栏，单实例互斥名 `NailongLiveRoom.SingleInstance`。

三个视图：

1. **聊天**：把 `D:\tmp\muse_feed.json`（小猪的对话流）与总线 `board.jsonl` 合并成一条时间线，按时间排序；`ref=mirror` 的记录跳过不重复显示。
2. **视频工坊**：人物 / 背景 / 场景 / 提示词 四张卡，底部一个「生成视频」主按钮。
3. **协作台**：三个页签——留言板 / 动作日志 / 占用；卡片左侧色条按角色上色（指挥部红、调度蓝、大厨绿）。

### 3.2 已经完成的能力

- **时间线合并**：`Read-MergedFeed` 把两个来源按 `when` 排序；feed 只有 `HH:mm:ss`，按当天补齐。
- **输入框双写**：聊天输入一条，同时写 `muse_feed.json`（小猪读）和总线（`ref=mirror`，只给机器看），时间线里只显示一次。
- **复制粘贴**：消息正文改成只读 TextBox，可拖选、可 Ctrl+C；右键菜单「复制选中 / 复制整条 / 全选」；协作台输入框右键「剪切 / 复制 / 粘贴 / 全选」；只读框的滚轮事件转交外层 ScrollViewer，不挡滚动。实测：选首条 Ctrl+C 得「总线建成，测试第一条」，粘贴回输入框一致（2026-11-07 00:05）。
- **P1 改版（2026-11-07 00:20–00:37）**：
  - 左侧 52px 图标轨：头像 / 聊天 / 工坊 / 协作 / 截图 / 深浅色；当前视图高亮，协作台有未读时图标右上角红点。
  - 顶栏 64 → 44px：标题 + 「小猪直播中」徽标 + 同步条数 + 搜索图标（点开才滑出输入框）。
  - 按钮分级：每个视图只留 1 个实心主按钮（发送 / 生成视频 / 发到看板），其余 36px 玻璃图标按钮。
  - emoji 全部换 `Segoe Fluent Icons` 字形（Win11 自带，无第三方资源）。
  - 协作台去掉筛选下拉和计数行，只留三个页签 + 一行图例。
- **UI 五条修复单（2026-11-07 01:24–01:44）**：见第四节。
- **视频渲染**（现已暂停，代码保留）：
  - `render.ps1`：GDI+ 合成底图（背景 cover、人物 60% 高度、场景小卡、字幕渐变条、左上角角标）→ ffmpeg 推镜 + 风格调色 + 首尾淡入淡出，输出 1920×1080 / 30fps / 8 秒，耗时约 5–8 秒。
  - `studio_daemon.ps1`：扫 `requests\*.json`，出片后打 `.done`，状态写 `video_studio\status.json`，空闲 30 分钟自退。
  - 成品样本：`outputs\nailong_selftest.mp4`（1.45MB）、`outputs\nailong_daemontest.mp4`（1.17MB）。

### 3.3 当前生效的规则

- 窗口**可拖**（顶栏整条）、**可缩放**（四边四角），最小尺寸 520×560。
- **三个视图切换时窗口尺寸必须保持不变**（实测切三次恒为 900×1000）。
- 主题统一：所有卡片/输入框/按钮走 `CardBrush` / `LineBrush` / `ThumbBrush` 三个画刷，深浅两套都不许露白块。
- **视频功能暂停**：P0 决策「测试期间只优化交流平台，不做视频」（2026-11-06 23:58:25），未解除前不动 `render.ps1` / `studio_daemon.ps1` / `outputs\`。

### 3.4 此刻的运行态（交接时刻快照）

- 应用窗口 pid 32344（2026-11-07 01:42:58 启动），经 `wscript` + `launch_app.vbs` 静默启动。
- 渲染守夜人 pid 32888。
- 留言板共 22 条；`agents.json` 里登记过两个身份：`DSH-Qwen`（另一个助手的旧名）与 `大厨(LOCAL)`。
- 主题文件 `D:\tmp\live_theme.txt` 内容 `True`（深色）。

---

## 四、待办清单

### 4.1 UI 修复单（五条，2026-11-07 01:24 下发，01:44 已交，**01:54 调度已逐条验收通过**）

| 编号 | 条目 | 要求 | 我的改法 | 自测状态 |
| --- | --- | --- | --- | --- |
| 一 | 写死白色清零 | 全窗排查 `White` / `#FFFFFF`，接入主题；左上百边必须消失 | 新增三个主题画刷；9 处写死白改走主题；`UtilBtn` 模板改 `TemplateBinding`；底部两个下拉换成主题化按钮；左轨分隔线接入主题 | 深浅对照无白块；左上角 4 倍放大另查 |
| 二 | 窗口能拖动 | 顶栏整条可拖，按钮与输入区除外 | 根因是 Header 的 Grid `Background` 为空、命中测试拿不到鼠标；改 `Transparent` | 整条可拖 |
| 三 | 窗口能缩放 | 解除 NoResize，可拖边拖角，设最小尺寸，缩放不错位；切视图不得变尺寸 | `ResizeMode=CanResize` + `WindowChrome(ResizeBorderThickness=6, CaptionHeight=0)`，`MinWidth 520 / MinHeight 560` | 400×400 被内容兜在 780×840；1080×1180 正常；切视图恒 900×1000 |
| 四 | 滚动条换掉 | 三视图统一 8px 半透明圆角毛玻璃，不出现系统粗条 | 全局 `ScrollBar` 样式 8px、圆角 4、半透明（深 `#59FFFFFF` / 浅 `#33000000`），悬停与拖动变实 | 三视图共用 |
| 五 | 启动不许弹终端 | 快捷方式 / bat / 自重启全部静默，黑框一闪也算不合格 | 快捷方式改 `wscript.exe` + `launch_app.vbs`（Run 参数 0）；删 `live_app.bat` 换 `live_app.vbs`；应用内拉守夜人改 `launch_daemon.vbs`；桌宠同改 | 启动全程 `ConsoleWindowClass` 窗口峰值 0 |

### 4.2 P2 预定范围（尚未开工）

1. **Composer 合并**：聊天与协作共用一套输入组件，不再各做一套。
2. **L3 悬停动作**：复制 / 删除等默认隐藏，悬停在消息行或卡片上才出现。
3. **视图切换动效**：淡入上浮 120ms。
4. **筛选改分段控件**：原来想做的「全部 / 给我的 / 待办 / 决策」筛选，因 ComboBox 在本窗口不显示选中项而撤下，P2 用分段控件重做。

### 4.3 协作过程测试（TC）

- **TC-01 代号识别与话语分离**：已通过（2026-11-07 00:01 回报，归属判断正确，ACK 时延约 35 秒）。
- **TC-02 转达保真度**：挂起。要求复述「动作 / 对象 / 否定 / 数字」四要素零偏差。
- **TC-03 P0 打断**：挂起。要求一轮内 ACK、停原任务、登记「挂起」、不自行恢复。
- **TC-04 任务单闭环**：挂起。格式 ACK → 进度 → 回报（状态 + 做了什么 + 证据）。
- **TC-05 信息不全时处置**：挂起。缺验收标准必须 QUERY。
- **TC-06 无响应超时**：挂起。超时只催一次再上报。

### 4.4 其他待办

- `D:\tmp\nailong\board.ps1`（独立协作台窗口，16009 bytes）已停用，桌面快捷方式已删；内容已并入主窗口，脚本留作备份。
- 桌宠 `D:\tmp\nailong_pet.ps1` **已下线，勿自行恢复**（按指挥部要求，2026-11-07 01:54 调度补遗）；脚本保留，内容仍是「只能拉起主窗口、未接入合并时间线」。

---

## 五、关键资产

### 5.1 主程序与运行态

| 路径 | 说明 |
| --- | --- |
| `D:\tmp\xiaozhu_live.ps1` | 主程序，92736 bytes |
| `D:\tmp\live_state.json` | 窗口位置/尺寸/大窗标记（关窗时写） |
| `D:\tmp\live_theme.txt` | 深浅色记忆，`True` = 深色 |
| `D:\tmp\live3_ok.txt` | 启动自检回执（ok + 条目数 + 时间） |
| `D:\tmp\live3_err.txt` | XAML 解析失败时写入（正常时不存在） |
| `D:\tmp\nailong\launch_app.vbs` | 静默启动器（wscript，Run 参数 0） |
| `D:\tmp\live_app.vbs` | 等价备用启动器 |
| 桌面 `奶龙工坊.lnk` | 目标 `C:\Windows\System32\wscript.exe`，参数 `"D:\tmp\nailong\launch_app.vbs"`，图标 `D:\tmp\nailong_icon2.ico` |

### 5.2 总线与协作

| 路径 | 说明 |
| --- | --- |
| `D:\tmp\nailong\bus\bus.ps1` | 命令行入口，6372 bytes |
| `D:\tmp\nailong\bus\board.jsonl` | 留言板，8823 bytes / 22 条 |
| `D:\tmp\nailong\bus\activity.jsonl` | 动作日志，5525 bytes |
| `D:\tmp\nailong\bus\claims\` | 占用声明目录，每条一个 `<资源名>.json` |
| `D:\tmp\nailong\AGENTS.md` | 协作协议（给另一个助手看） |

**claims 用法**：改大文件前 `bus.ps1 claim <资源> -From "大厨(LOCAL)" -Note "要改什么"`；返回 `BUSY by 别人` 就停手；改完 `release`。当前 claims 目录为空（01:44 已释放 `xiaozhu_live.ps1`）。

### 5.3 数据流

| 路径 | 说明 |
| --- | --- |
| `D:\tmp\muse_feed.json` | 小猪侧对话流，每行一个 json（ts/sender/kind/text） |
| `D:\tmp\video_studio\requests\` | 视频请求队列（`req_<时间戳>.json`） |
| `D:\tmp\video_studio\outputs\` | 成品 mp4 + 同名 png 封面 + json 元信息 |
| `D:\tmp\video_studio\status.json` | 守夜人当前状态（idle/rendering/done/error） |

### 5.4 插件与备份

| 路径 | 说明 |
| --- | --- |
| `D:\tmp\nailong\dsh-bus-bridge\` | 总线桥插件源码（`index.js` 11296 bytes、`package.json` v0.1.2、`cordis.patch.yml`） |
| `~\.dsh\profiles\{desktop,web,plugin-lab,plugin-lab-hl}\node_modules\dsh-bus-bridge` | 四个 profile 的安装副本 |
| `D:\tmp\nailong\backup_desktop_profile_20261107\` | desktop profile 配置备份（cordis.yml / cordis.patch.yml / package.json / pnpm-workspace.yaml） |
| `D:\tmp\nailong\backup_web_profile_20261107\` | web profile 配置备份 |
| `D:\tmp\backup\xiaozhu_live_20261106_231103.ps1` | 主程序早期快照（55397 bytes） |
| `D:\tmp\backup\live_app.bat.bak` | 被删掉的 bat 启动器备份 |

**关于「NailongDSHWeb 任务」**：**已于 2026-11-07 15:33 报废删除**（17 号单，客官裁决「报废」）。原任务只拉起 3080 的 DSH web 宿主，且**触发器为空**（只在手动启动时跑，重启后不自启），所以倒掉后不会自己回来。3080 现无监听、无进程；桌面线与微信线都不经过它。启动器与日志原件留档，备份在 `D:\tmp\nailong\verify\17\decommission\`，回滚方法见 `D:\tmp\nailong\DEPRECATED_web_3080.md`。**不要再凭印象重建这个任务**；确需恢复时按 DEPRECATED 文件里的三步走，并补一个登录触发。

### 5.5 渲染引擎（暂停中）

| 路径 | 说明 |
| --- | --- |
| `D:\tmp\video_studio\engine\render.ps1` | 合成 + 编码，14062 bytes |
| `D:\tmp\video_studio\engine\studio_daemon.ps1` | 队列守夜人，3193 bytes |
| `D:\tmp\video_studio\engine\ffmpeg.exe` | 便携 ffmpeg 6.1.1（80857 KB），从 npmmirror 的 ffmpeg-static b6.1.1 取 gz 解压 |
| `D:\tmp\video_studio\engine\launch_daemon.vbs` | 守夜人静默启动器 |

---

## 六、踩过的坑（每条都是真事）

1. **UTF-8 无 BOM 必炸**。PowerShell 5.1 对无 BOM 的 .ps1 按 GBK 解码，中文变「寮€濮嬫覆鏌」并直接语法报错。第一次在 `xiaozhu_live.ps1` 上撞（我用文本工具写入后丢了 BOM）。解决：每次写完用 `[IO.File]::WriteAllText($p,$txt,(New-Object Text.UTF8Encoding($true)))` 补 BOM，再 `Parser::ParseFile` 校验。同样的坑在 `render.ps1`、`bus.ps1`、`board.ps1` 各撞一次。
2. **变量名大小写不敏感导致自撞**。`$script:cbTo = "all"` 把按钮变量 `$CbTo` 覆盖成了字符串，报「The property 'Content' cannot be found」。解决：状态变量改名 `$script:sendTo` / `$script:sendKind`。
3. **模板里写死背景色，按钮设背景也没用**。`UtilBtn` 的 ControlTemplate 里 `Background="White"`，深色下按钮永远白。解决：模板改 `{TemplateBinding Background}`，样式里给默认 `{DynamicResource CardBrush}`。
4. **Grid 的 Background 为空收不到鼠标**。顶栏拖不动的根因不是 DragMove 逻辑，是空背景 Grid 不参与命中测试。解决：`Background="Transparent"`。
5. **只读 TextBox 会吃掉滚轮**。消息区滚不动。解决：`PreviewMouseWheel` 里找祖先 ScrollViewer 手动 `ScrollToVerticalOffset` 并置 `Handled`。
6. **TextBox 没有 LineHeight**。那是 TextBlock 的属性，照抄会抛「property not found」。解决：删掉该设置，行高交给默认。
7. **WPF ComboBox 在这套无边框窗口里选中项不显示**。调试写入显示 `items=0 sel=` 但控件存在，换了两种初始化写法都不行。解决：放弃下拉，改成循环按钮（点一下换下一个值）。
8. **DynamicResource 资源被 PSObject 包裹**。用 `$res["CardBrush"] = New-Object ...Brush` 替换后，动态引用拿到的是 PSObject，报「Unable to cast PSObject to Brush」。解决：不再替换资源，改成在 `Apply-Theme` 里对控件逐个显式赋 Brush。
9. **窗口恢复到屏幕外**。状态文件曾存下 `left=-210`，窗口一半在屏幕外，截图左侧全黑。解决：用 `[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea` 钳制宽高与左上角；早期用 `SystemParameters.VirtualScreen.Width` 会得到空值，算出 `-60` 直接抛异常。
10. **进程自匹配**。`Get-CimInstance Win32_Process | Where CommandLine -match 'studio_daemon'` 会匹配到我自己的命令行，误判「已在运行」。解决：先排除 `$PID`。
11. **UIA 点按钮制造假象**。测试时用 Invoke 点按钮，导致「协作台自己打开了」的错误判断，查了两小时。解决：点之前先读按钮 `Current.Name`，确认状态再点；一次只点一下。
12. **另一个助手同时改同一个文件**。23:09 我改到一半，文件被整体重写，标题从「奶龙直播间」变成「奶龙工坊」，我的三处改动还在但混进了别人的改动。解决：总线 `claim/release` + 每次改前看 mtime，改完立刻 parse 校验。
13. **误报工具不存在**。我曾答复「bus_inbox / bus_post 不在工具集」，其实它们由 `dsh-bus-bridge` 插件注入，一直在。教训：回答「有没有」之前先看工具清单，不凭印象。
14. **正则批量改脚本把文件改坏**。用 `-replace` 删调试行时把 `try {` 和半个 `if` 一起吞了，parse 报 5 个错。解决：改成按行号区间 `RemoveRange/InsertRange`，每步 parse 一次。
15. **最小化窗口截图全是黑的**。`GetWindowRect` 返回 237×39，截出来是纯黑。解决：先 `IsIconic` 判断并 `ShowWindow(9)` 恢复，再 `SetWindowPos` 定尺寸，最后截图。
16. **DPI 不感知会截偏**。不调 `SetProcessDPIAware` 时，GetWindowRect 返回逻辑坐标、CopyFromScreen 按物理像素取，截出来只有左上角一块。解决：截图脚本开头统一 `SetProcessDPIAware`。
17. **PowerShell 启动必闪黑框**。即使 `-WindowStyle Hidden`，powershell.exe 仍是控制台程序。解决：`wscript.exe` 跑 vbs，`WScript.Shell.Run` 第二个参数传 0。
18. **.bat 天生有控制台**。`live_app.bat` 双击必闪。解决：删除（备份到 `D:\tmp\backup\live_app.bat.bak`），换 `live_app.vbs`。
19. **ffmpeg 拿不到**。PATH 里没有，gyan.dev 下载超时。解决：走 npmmirror 的 ffmpeg-static `b6.1.1/ffmpeg-win32-x64.gz`（29MB），GZipStream 解压出 `ffmpeg.exe`。
20. **镜像消息重复显示**。输入框双写导致同一条出现在两个来源。解决：总线侧写 `ref="mirror"`，合并时间线时跳过。
21. **视图切换会改窗口尺寸**。早期「大窗」逻辑绑在切换里。解决：切换只改可见性，不动 Width/Height；实测三次切换恒 900×1000。
22. **文件被写入工具悄悄去掉 BOM**。edit/write 工具写回后 BOM 消失，表现同上条。解决：每次编辑后固定跑一段「检查 BOM，不是就补 + parse 校验」的收尾脚本。

---

## 附：新会话上手顺序（五分钟）

1. 读 `D:\tmp\nailong\AGENTS.md` 与本文。
2. `bus.ps1 board -Limit 20` 看最新 20 条，`claims` 看有没有人占着 `xiaozhu_live.ps1`。
3. 看 `D:\tmp\live3_ok.txt` 的 mtime 与 `Get-Process powershell | ? MainWindowTitle -match '奶龙'`，确认窗口是否在跑。
4. 要改主程序：先 claim，改完 `Parser::ParseFile` 校验，再 `release` 并 `log`。
5. 回报格式：状态 + 做了什么 + 证据（路径/命令输出/截图），每条都能被复核。