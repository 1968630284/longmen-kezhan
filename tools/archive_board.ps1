# ARCH-01 / S2 · 留言板归档（默认只预览，-Apply 才写盘）
# 设计要点：
#  1) 字节级过滤：按 0x0A 切段，只丢弃命中行，其余行原样字节保留，不重编码、不改行尾。
#  2) 写盘前先备份整份 board.jsonl，再写临时文件后原子替换。
#  3) board.jsonl 是 append-only 存储，重写后运行中的应用需重启，或调用 Reset-JsonlCache 才能看到新内容。
#  4) 只移除由 -Match 命中的重复状态帖；result/task/decision 等参与桥回放的帖子不受影响。

param(
    [string]$Board = 'D:\tmp\nailong\bus\board.jsonl',
    [string]$Archive = 'D:\tmp\nailong\archive\board_archived_20261113.jsonl',
    [string]$Match = 'tailscale status 异常',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Board)) { throw "board 不存在: $Board" }
$bytes = [IO.File]::ReadAllBytes($Board)
if ($bytes.Length -eq 0) { throw "board 为空: $Board" }

# 按 0x0A 切成「行 + 分隔符」的字节段，末尾不足一行的也保留
$segs = New-Object System.Collections.ArrayList
$start = 0
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10) {
        $len = $i - $start + 1
        $seg = New-Object byte[] $len
        [Array]::Copy($bytes, $start, $seg, 0, $len)
        [void]$segs.Add($seg)
        $start = $i + 1
    }
}
if ($start -lt $bytes.Length) {
    $len = $bytes.Length - $start
    $seg = New-Object byte[] $len
    [Array]::Copy($bytes, $start, $seg, 0, $len)
    [void]$segs.Add($seg)
}

$kept = New-Object System.Collections.ArrayList
$removed = New-Object System.Collections.ArrayList
foreach ($seg in $segs) {
    $text = [Text.Encoding]::UTF8.GetString($seg)
    if ($text -match [regex]::Escape($Match)) { [void]$removed.Add($seg) } else { [void]$kept.Add($seg) }
}

"board            : $Board"
"bytes            : $($bytes.Length)"
"segments         : $($segs.Count)"
"to_remove        : $($removed.Count)"
"to_keep          : $($kept.Count)"
"match            : $Match"

if ($removed.Count -eq 0) { "nothing to do"; exit 0 }

if (-not $Apply) {
    ""
    "[preview] 未写盘。确认无误后加 -Apply 执行："
    "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Apply"
    exit 0
}

# 1) 备份整份原文件
$bak = $Board + '.bak-' + (Get-Date -Format 'yyyyMMdd_HHmmss')
Copy-Item -LiteralPath $Board -Destination $bak -Force
$bakLen = (Get-Item -LiteralPath $bak).Length
if ($bakLen -ne $bytes.Length) { throw "备份校验失败: $bakLen != $($bytes.Length)" }
"backup           : $bak ($bakLen B, 校验通过)"

# 2) 归档被移除的行（原样字节，便于事后核对/恢复）
$adir = Split-Path -Parent $Archive
if (-not (Test-Path -LiteralPath $adir)) { New-Item -ItemType Directory -Force -Path $adir | Out-Null }
$ams = New-Object IO.MemoryStream
foreach ($seg in $removed) { $ams.Write($seg, 0, $seg.Length) }
[IO.File]::WriteAllBytes($Archive, $ams.ToArray())
"archived         : $Archive ($((Get-Item -LiteralPath $Archive).Length) B, $($removed.Count) 行)"

# 3) 写临时文件后原子替换
$tmp = $Board + '.tmp'
$ms = New-Object IO.MemoryStream
foreach ($seg in $kept) { $ms.Write($seg, 0, $seg.Length) }
[IO.File]::WriteAllBytes($tmp, $ms.ToArray())
Move-Item -LiteralPath $tmp -Destination $Board -Force

$after = [IO.File]::ReadAllBytes($Board)
"after_bytes      : $($after.Length)"
"after_lines      : $(([Text.Encoding]::UTF8.GetString($after).Split([char]10) | Where-Object { $_.Trim() }).Count)"
""
"注意：board.jsonl 已被重写。正在运行的龙门客栈需重启，或调用 Reset-JsonlCache，才能看到归档后的内容。"
