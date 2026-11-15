# ARCH-01 / S4 · 可复现单文件构建
# 源码按职责拆在 src\，但交付物仍是唯一的 D:\tmp\xiaozhu_live.ps1
# （桌面快捷方式与 launch_app.vbs 直接指向它，不能改成多文件）。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1                # 构建到现役路径
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 -Output X -NoMap   # 构建到别处（用于一致性校验）
#
# 约定：
#  * 所有片段按字节拼接，不重新编码，行尾保持 LF，BOM 只加在产物开头一次。
#  * 30_window.xaml 是纯 XAML，前后由本脚本补 here-string 包装行。
#  * 硬验收：产物 SHA256 必须等于拆分前的现役脚本 5478CAC9…（纯拆分零行为变化）。

param(
    [string]$Output = '',
    [switch]$NoMap
)

$ErrorActionPreference = 'Stop'
# 仓库相对：tools\ 的上一级就是仓库根，CI 与本地都能用
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Output) { $Output = Join-Path (Split-Path -Parent $Root) 'xiaozhu_live.ps1' }
$Src  = Join-Path $Root 'src'
$Enc  = New-Object Text.UTF8Encoding($false)

$order = @(
    @{ Name = '00_header.ps1';      Kind = 'file' },
    @{ Name = '10_data.ps1';        Kind = 'file' },
    @{ Name = '20_ui_helpers.ps1';  Kind = 'file' },
    @{ Name = '(XAML open)';        Kind = 'open' },
    @{ Name = '30_window.xaml';     Kind = 'file' },
    @{ Name = '(XAML close)';       Kind = 'close' },
    @{ Name = '40_app.ps1';         Kind = 'file' }
)

$q     = [char]39
$open  = $Enc.GetBytes('$xaml = @' + $q + "`n")
$close = $Enc.GetBytes($q + '@' + "`n")

$ms = New-Object IO.MemoryStream
$bom = [byte[]]@(0xEF, 0xBB, 0xBF)
$ms.Write($bom, 0, 3)

$map = New-Object System.Collections.ArrayList
$lineNo = 1
foreach ($p in $order) {
    switch ($p.Kind) {
        'open'  { $bytes = $open }
        'close' { $bytes = $close }
        default { $bytes = [IO.File]::ReadAllBytes((Join-Path $Src $p.Name)) }
    }
    if ($bytes.Length -eq 0) { throw "空片段: $($p.Name)" }
    $ms.Write($bytes, 0, $bytes.Length)
    $n = ([Text.Encoding]::UTF8.GetString($bytes).Split([char]10)).Count - 1
    [void]$map.Add([pscustomobject]@{
        Part = $p.Name; Start = $lineNo; End = $lineNo + $n - 1
        Lines = $n; Bytes = $bytes.Length
    })
    $lineNo += $n
}

$outBytes = $ms.ToArray()
$ms.Dispose()
[IO.File]::WriteAllBytes($Output, $outBytes)
$sha = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash

"built  = $Output"
"sha256 = $sha"
"lines  = $($lineNo - 1)"
"bytes  = $($outBytes.Length)"

if (-not $NoMap) {
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('# 构建行号映射 · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$lines.Add('')
    [void]$lines.Add('产物：`D:\tmp\xiaozhu_live.ps1` · SHA256 `' + $sha + '`')
    [void]$lines.Add('')
    [void]$lines.Add('| 片段 | 产物起始行 | 结束行 | 行数 | 字节 |')
    [void]$lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($m in $map) {
        [void]$lines.Add('| `' + $m.Part + '` | ' + $m.Start + ' | ' + $m.End + ' | ' + $m.Lines + ' | ' + $m.Bytes + ' |')
    }
    [void]$lines.Add('')
    [void]$lines.Add('排错时用此表把产物报错行号映射回 `src\` 里的具体文件。')
    $report = Join-Path $Root 'reports\build_map.md'
    [IO.File]::WriteAllText($report, (($lines -join "`n") + "`n"), $Enc)
    "map    = $report"
}
