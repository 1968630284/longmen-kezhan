# PKG-01 · 绿色免安装包

- 日期：2026-11-15
- 用户指令：「我做的是龙门客栈这个app……你看看怎么打包」，选择「绿色免安装 ZIP / 允许改造路径 / 不含视频工坊」
- 结论：**GREEN**。程序从固定盘符解耦，`dist\龙门客栈_20261115.zip`（140 KB）解压到任意目录可运行，实测窗口正常起来且运行痕迹全部落在包内。

## 一、为什么不能直接打包

改前 `src\00_header.ps1` + `src\40_app.ps1` 共 **36 处硬编码 `D:\tmp\...`**：feed、窗口状态、主题、日志、DLL 缓存、总线、图标、视频工坊全绑死在这个位置。换台机器或换个目录，程序要么读不到数据，要么把日志写到别人的 `D:\tmp` 里。

## 二、改动

### 1. 路径可移植化（唯一的机制性改动）

`src\00_header.ps1` 顶部新增：

```powershell
$script:AppRoot = if ($PSScriptRoot) { $PSScriptRoot }
elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
else { (Get-Location).Path }
$AppRoot = $script:AppRoot
if (-not $FeedFile)  { $FeedFile  = Join-Path $AppRoot 'muse_feed.json' }
if (-not $StateFile) { $StateFile = Join-Path $AppRoot 'live_state.json' }
```

- `-FeedFile` / `-StateFile` 的默认值由写死改为 `$AppRoot` 派生（显式传参行为不变）。
- 其余 34 处按「双引号插值 / 单引号改 `Join-Path`」逐处替换；`Start-Process` 那处原本是单引号包双引号，改为 `('"' + $VsRoot + '\engine\launch_daemon.vbs"')`。
- **旧部署零行为变化**：脚本仍在 `D:\tmp\xiaozhu_live.ps1` 时 `$AppRoot = D:\tmp`，展开后与改前绝对路径逐字相同。

### 2. 存档按钮降级（包内没有开发版存档工具）

```powershell
$tool = Join-Path $AppRoot 'nailong\tools\make_archive.ps1'
if (-not (Test-Path -LiteralPath $tool)) {
    Append-Feed "系统" "note" "此版本未包含存档工具（开发版才有），已跳过"
    return
}
```

`make_archive.ps1` 依赖本机开发资产（`~\.dsh\AGENTS.md`、handoff、mirror、bridge 配置），打进包也只会报「缺件」，因此不入包、入口给明确提示。

### 3. 新增 `tools\package.ps1`

管线：`src\` 现场构建 → 组装目录骨架 → 生成便携启动器 → 压缩。

包结构（7 文件）：

```
龙门客栈\
  xiaozhu_live.ps1        177,014 B（从 src 现场构建，非复制现役产物）
  launch_app.vbs          按自身位置解析脚本，不写死盘符
  nailong_chef_icon.ico   运行期图标
  使用说明.txt
  nailong\health| cache| archive| bus\claims| tools\
  video_studio\engine| outputs\   （空骨架，放 ffmpeg 即启用）
```

## 三、验收

| 项 | 结果 |
| --- | --- |
| `build.ps1` | SHA256 `C21776D525B8AD08…` / 3398 行 / 177,014 B |
| `verify_baseline.ps1` | **GREEN**：BOM `EF BB BF`、Parser 0 错 / 24,306 tokens、Pester **40/0** |
| `check_source_sync.ps1` | `[OK]` 现役脚本 = src 构建产物 |
| 冒烟（`-NoMutex` 实跑包内副本） | 窗口标题「龙门客栈」；`live3_ok.txt` = `ok v5.3 entries=0 at 17:23:03`；`health\ui.log`、`health\app.log`、`cache\NailongNative_A993C56F.dll` 全部生成在**包目录内**；无 `live3_err.txt` |
| 包体积 | 7 文件 / 273,927 B → zip **140 KB** |

冒烟后已重新打包，交付包内不含任何测试运行痕迹。

## 四、未包含 / 已知限制

- **视频工坊**（107 MB，80 文件，含 ffmpeg）：按用户决定不入包。`Ensure-Thumb` 与 `Ensure-StudioEngine` 原本就有 `Test-Path` 守卫，缺失时只降级不报错。
- 包内 `nailong\bus` 是空板；协作台可正常打开但无历史留言（用户数据不入包）。
- 脚本未签名，首次运行可能被 SmartScreen 拦，说明里已写「更多信息 → 仍要运行」。

## 五、复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\tmp\nailong\tools\package.ps1
# 产物：D:\tmp\nailong\dist\龙门客栈\ 与 龙门客栈_<日期>.zip
```

## 六、回滚

```powershell
git -C D:\tmp\nailong checkout -- src\00_header.ps1 src\40_app.ps1 .gitignore
powershell -NoProfile -ExecutionPolicy Bypass -File D:\tmp\nailong\tools\build.ps1
```
