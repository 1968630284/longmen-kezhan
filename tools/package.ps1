# PKG-01 · 绿色免安装包构建
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File D:\tmp\nailong\tools\package.ps1
# 产物：dist\龙门客栈\（解压即用） + dist\龙门客栈_<日期>.zip
#
# 约定：
#  * 包内脚本一律从 src\ 现场构建，不复制可能过期的现役产物 D:\tmp\xiaozhu_live.ps1。
#  * 包内不含视频工坊（107 MB）与开发版存档工具；两者的入口在程序里已有降级处理。
#  * 包内所有运行期数据（feed / 状态 / 主题 / 日志 / 总线）都落在包目录，互不覆盖。

param(
    [string]$Root = 'D:\tmp\nailong',
    [string]$OutDir = '',
    [string]$Version = (Get-Date -Format 'yyyyMMdd')
)

$ErrorActionPreference = 'Stop'
$Name = '龙门客栈'
if (-not $OutDir) { $OutDir = Join-Path $Root 'dist' }
$Stage = Join-Path $OutDir $Name
$Zip = Join-Path $OutDir ($Name + '_' + $Version + '.zip')
$Utf8Bom = New-Object Text.UTF8Encoding($true)
$Utf8 = New-Object Text.UTF8Encoding($false)

# ---- 清场 ----
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage -Force | Out-Null

# ---- 1) 构建主脚本（直接落到包里）----
& (Join-Path $Root 'tools\build.ps1') -Output (Join-Path $Stage 'xiaozhu_live.ps1') -NoMap

# ---- 2) 目录骨架 ----
foreach ($d in @('nailong\health', 'nailong\cache', 'nailong\archive', 'nailong\bus\claims',
                 'video_studio\engine', 'video_studio\outputs')) {
    New-Item -ItemType Directory -Path (Join-Path $Stage $d) -Force | Out-Null
}

# ---- 3) 图标（运行期读 $AppRoot\nailong_chef_icon.ico）----
Copy-Item -LiteralPath (Join-Path $Root 'assets\nailong_chef.ico') -Destination (Join-Path $Stage 'nailong_chef_icon.ico') -Force

# ---- 4) 总线空文件：协作台首次打开就是空列表，而不是缺文件 ----
foreach ($f in @('board.jsonl', 'activity.jsonl')) {
    [IO.File]::WriteAllText((Join-Path $Stage ('nailong\bus\' + $f)), '', $Utf8)
}
[IO.File]::WriteAllText((Join-Path $Stage 'nailong\bus\agents.json'), "{`r`n  `"agents`": []`r`n}`r`n", $Utf8)

# ---- 5) 便携启动器：按自身位置解析脚本，不写死盘符 ----
# 纯 ASCII，避免 WSH 按 ANSI 读中文注释出错
$vbs = @'
' Nailong Workshop launcher (no console window)
Dim fso, sh, base
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & base & "\xiaozhu_live.ps1""", 0, False
'@
[IO.File]::WriteAllText((Join-Path $Stage 'launch_app.vbs'), ($vbs -replace "`r?`n", "`r`n"), $Utf8)

# ---- 6) 使用说明 ----
$readme = @'
龙门客栈（奶龙工坊）· 绿色免安装版
========================================

启动：双击 launch_app.vbs（不弹控制台窗口）。
环境：Windows 10/11 自带的 PowerShell 5.1 即可，无需安装任何运行时或依赖。

数据都写在包目录内，删掉整个文件夹即彻底卸载：
  muse_feed.json     聊天流
  live_state.json    窗口位置与大小
  live_theme.txt     主题（浅色 / 深色）
  nailong\health     启动与运行日志
  nailong\bus        协作台留言板 / 动作日志 / 文件占用

未随包分发：
  · 视频工坊：把 video_studio 目录（含 engine\ffmpeg.exe）放到本目录下即可启用。
  · 存档工具：开发版才有，包里点「存档」会提示已跳过。

首次运行若被 SmartScreen 拦截，选「更多信息 → 仍要运行」（脚本未做代码签名）。
'@
[IO.File]::WriteAllText((Join-Path $Stage '使用说明.txt'), ($readme -replace "`r?`n", "`r`n"), $Utf8Bom)

# ---- 7) 压缩 ----
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip -CompressionLevel Optimal

# ---- 8) 结果 ----
$files = @(Get-ChildItem -LiteralPath $Stage -Recurse -File)
$bytes = ($files | Measure-Object -Property Length -Sum).Sum
"stage = $Stage"
"zip   = $Zip"
"files = $($files.Count)"
"bytes = $bytes (zip {0:N0} KB)" -f ((Get-Item -LiteralPath $Zip).Length / 1KB)
"sha256(script) = " + (Get-FileHash -LiteralPath (Join-Path $Stage 'xiaozhu_live.ps1') -Algorithm SHA256).Hash
"sha256(zip)    = " + (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
