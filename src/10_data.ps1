# ===== OPT1 / S1（2026-11-13）：数据层文件状态与增量读取 =====
# OPT1 解决「文件没变时重复全量解析」；S1 进一步解决「文件追加一行时仍要全量重解析」。
# 读侧只从上次字节偏移读取新增内容，按 \n 只处理完整行，半行以字节形式留到下一轮，
# 因此 O(N) 变成 O(新增行)。写侧与 board.jsonl / bus.ps1 / Node 桥 / HC 的协议零改动。
# 状态合并为单一 $script:FileState，不再有 FileStamp / FileCache / offset 三套状态。
function Get-FileStamp([string]$path) {
    try {
        if (-not [IO.File]::Exists($path)) { return "" }
        $f = New-Object IO.FileInfo($path)
        $f.Refresh()
        return ($f.Length.ToString() + "|" + $f.LastWriteTimeUtc.Ticks.ToString())
    } catch { return "" }
}

# 单一状态对象：Stamp 指纹 / Items 已解析对象 / Offset 已读入字节位置 /
# Pending 末尾未成行的字节 / LastLength 上次长度 / Anchors 已读区域 9 个采样锚点。
# Anchors 用于识别「文件被重写或中间被就地编辑」：仅靠长度增长无法区分追加与重写。
$script:FileState = @{}
$script:ReadStats = @{}

# 增量读的正确性依赖 append-only 协议（主窗口 / bus.ps1 / Node 桥 / HC 均满足）。
# 9 个采样锚点覆盖已读区域的开头、中部与结尾，能察觉绝大多数就地编辑；
# 但采样点之间的极小范围改动仍可能漏检，人工重写后仍建议调用本函数或重启应用。
function Reset-JsonlCache {
    $script:FileState = @{}
    $script:ReadStats = @{}
}

function Get-JsonlAnchors([string]$path, [long]$offset) {
    if ($offset -le 0) { return "" }
    $parts = New-Object System.Collections.ArrayList
    $positions = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 8; $i++) { [void]$positions.Add([long][Math]::Floor($offset * $i / 8)) }
    [void]$positions.Add([long][Math]::Max(0, $offset - 64))
    try {
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            foreach ($pos in $positions) {
                $n = [int][Math]::Min(64, $offset - $pos)
                if ($n -le 0) { [void]$parts.Add(''); continue }
                [void]$fs.Seek($pos, [IO.SeekOrigin]::Begin)
                $buf = New-Object byte[] $n
                $got = $fs.Read($buf, 0, $n)
                if ($got -le 0) { [void]$parts.Add(''); continue }
                if ($got -lt $n) {
                    $actual = New-Object byte[] $got
                    [Array]::Copy($buf, 0, $actual, 0, $got)
                    [void]$parts.Add([Convert]::ToBase64String($actual))
                } else {
                    [void]$parts.Add([Convert]::ToBase64String($buf))
                }
            }
        } finally { $fs.Dispose() }
    } catch { return $null }
    return ($parts -join '|')
}

# 把一段字节按 \n 切成完整行并逐行解析；无法解析的行静默跳过（S0 基线锁定的行为）。
# 返回 @{ Parsed = 本次解析行数; Pending = 末尾未成行的字节 }
function Split-JsonlBytes([byte[]]$buf, $items) {
    $lastNl = -1
    for ($i = $buf.Length - 1; $i -ge 0; $i--) { if ($buf[$i] -eq 10) { $lastNl = $i; break } }
    $parsed = 0
    if ($lastNl -ge 0) {
        $n = $lastNl + 1
        $complete = New-Object byte[] $n
        [Array]::Copy($buf, 0, $complete, 0, $n)
        $text = [Text.Encoding]::UTF8.GetString($complete)
        foreach ($raw in $text.Split([char]10)) {
            $line = $raw.TrimEnd([char]13)
            if (-not $line.Trim()) { continue }
            $parsed++
            try { [void]$items.Add(($line | ConvertFrom-Json)) } catch { }
        }
        $rest = $buf.Length - $n
    } else {
        $rest = $buf.Length
    }
    $pending = New-Object byte[] $rest
    if ($rest -gt 0) { [Array]::Copy($buf, $buf.Length - $rest, $pending, 0, $rest) }
    return @{ Parsed = $parsed; Pending = $pending }
}

function Read-BytesFrom([string]$path, [long]$start, [long]$end) {
    $n = [int]($end - $start)
    if ($n -le 0) { return ,(New-Object byte[] 0) }
    $buf = New-Object byte[] $n
    $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
        $got = $fs.Read($buf, 0, $n)
        if ($got -lt $n) {
            if ($got -le 0) { return ,(New-Object byte[] 0) }
            $actual = New-Object byte[] $got
            [Array]::Copy($buf, 0, $actual, 0, $got)
            return ,$actual
        }
        return ,$buf
    } finally { $fs.Dispose() }
}

function Read-Jsonl([string]$path, [string]$key) {
    $stamp = Get-FileStamp $path
    if ($stamp -eq "") {
        $script:FileState.Remove($key)
        $script:ReadStats[$key] = @{ Mode = 'missing'; Parsed = 0; Cached = 0 }
        return @()
    }
    $st = $script:FileState[$key]
    if ($st -and $st.Stamp -eq $stamp) {
        $script:ReadStats[$key] = @{ Mode = 'cache'; Parsed = 0; Cached = $st.Items.Count }
        return $st.Items
    }

    $len = [int64]($stamp.Split('|')[0])
    $canAppend = $false
    if ($st -and $st.Offset -le $len -and $st.LastLength -le $len) {
        $curAnchors = Get-JsonlAnchors $path ([long]$st.Offset)
        if ($null -ne $curAnchors -and $curAnchors -eq $st.Anchors) { $canAppend = $true }
    }

    try {
        if ($canAppend) {
            $items = $st.Items
            $start = [long]$st.Offset
            $prev  = $st.Pending
        } else {
            $items = New-Object System.Collections.ArrayList
            $start = 0L
            $prev  = New-Object byte[] 0
        }
        if ($null -eq $prev) { $prev = New-Object byte[] 0 }
        $newBytes = Read-BytesFrom $path $start $len
        $buf = New-Object byte[] ($prev.Length + $newBytes.Length)
        if ($prev.Length -gt 0) { [Array]::Copy($prev, 0, $buf, 0, $prev.Length) }
        if ($newBytes.Length -gt 0) { [Array]::Copy($newBytes, 0, $buf, $prev.Length, $newBytes.Length) }
        $r = Split-JsonlBytes $buf $items
        $newOffset = $start + $newBytes.Length

        $script:FileState[$key] = @{
            Stamp      = $stamp
            Items      = $items
            Offset     = $newOffset
            Pending    = $r.Pending
            LastLength = $len
            Anchors    = (Get-JsonlAnchors $path ([long]$newOffset))
        }
        $script:ReadStats[$key] = @{
            Mode = $(if ($canAppend) { 'append' } else { 'rebuild' })
            Parsed = $r.Parsed
            Cached = $items.Count
        }
        return $items
    } catch {
        # 读失败（例如被独占）时保留上一次可用结果，下一轮指纹不同会再试
        $script:ReadStats[$key] = @{ Mode = 'error'; Parsed = 0; Cached = $(if ($st) { $st.Items.Count } else { 0 }) }
        if ($st) { return $st.Items }
        return @()
    }
}

function Read-Feed {
    return (Read-Jsonl $FeedFile 'feed')
}
function Append-Feed($sender, $kind, $text) {
    $e = [ordered]@{ ts = (Get-Date -Format "HH:mm:ss"); sender = $sender; kind = $kind; text = $text }
    [IO.File]::AppendAllText($FeedFile, (($e | ConvertTo-Json -Compress) + "`n"), $Utf8)
}
# OPT2（2026-11-13）：画刷缓存。全脚本 238 处 Brush 调用，旧实现每次都
# New-Object SolidColorBrush + ColorConverter，而首屏 120 个气泡、协作台 100 张卡片、
# 主题切换都会成百上千次地重复造同一个颜色。核查过：所有调用点都直接赋给控件属性，
# 无一处回写画刷对象；动画只动元素 Opacity / RenderTransform，故共享实例是安全的。
$script:BrushCache = @{}

# ==== UI-02 纯函数区（Pester 可提取，不依赖 WPF）====
# 时间戳统一为 HH:mm。feed 的历史写法有 "20:36:00"，板上帖是完整日期时间，
# 旧数据里还有 "20-50-03" 这类连字符分隔；先按日期解析，失败再按开头时分兜底。
function Format-UiTime([string]$ts) {
    $s = ([string]$ts).Trim()
    if (-not $s) { return '' }
    $dt = [datetime]::MinValue
    try { if ([datetime]::TryParse($s, [ref]$dt)) { return $dt.ToString('HH:mm') } } catch { }
    $m = [regex]::Match($s, '^(\d{1,2})[:.\-](\d{2})')
    if ($m.Success) { return ($m.Groups[1].Value.PadLeft(2, '0') + ':' + $m.Groups[2].Value) }
    return $s
}
# 连续消息分组判定：同一发送者、同一天、间隔 0–60 秒、非系统消息、非搜索态。
# 纯布尔函数，供 Refresh-Feed 与特征测试共用，规则改动只改这一处。
function Test-UiGrouping($prevSender, $prevWhen, $prevDate, $curSender, $curWhen, $curKind, $curDate, $filter) {
    if ($filter) { return $false }
    if ([string]$curKind -eq 'status') { return $false }
    if (-not $prevSender -or [string]$prevSender -ne [string]$curSender) { return $false }
    if ($null -eq $prevWhen -or $prevWhen -eq [datetime]::MinValue) { return $false }
    if ([string]$curDate -ne [string]$prevDate) { return $false }
    $delta = ([datetime]$curWhen - [datetime]$prevWhen).TotalSeconds
    return ($delta -ge 0 -and $delta -le 60)
}
# ==== UI-02 END ====
