# hc_linkqueue.ps1 - link up/down tracker + resume digest (order 30, item: 备路③)
# Every 5 min: probe the tailnet peer. On down->up transition, write a resume digest listing
# bus entries added while the link was down, so Xiaozhu can pull exactly the gap.
# Logs to health\link.log; writes health\link_state.json and health\resume_<stamp>.md.

param(
    [string]$Peer = 'muse',
    [string]$LogPath = 'D:\tmp\nailong\health\link.log',
    [string]$StatePath = 'D:\tmp\nailong\health\link_state.json',
    [string]$BoardPath = 'D:\tmp\nailong\bus\board.jsonl',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$now = Get-Date
$ts = $now.ToString('yyyy-MM-dd HH:mm:ss')

function Write-Log([string]$line) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ($ts + ' | ' + $line) -Encoding UTF8
}

$exe = 'C:\Program Files\Tailscale\tailscale.exe'
$up = $false
$detail = ''
if (Test-Path -LiteralPath $exe) {
    # 30 号：tailscale ping 在该链路上常超时（走 DERP 中继时被抑制），
    # 改用 status --json 的 peer Online 字段判定，稳且快。
    $raw = & $exe status --json 2>&1 | Out-String
    try {
        $j = $raw | ConvertFrom-Json
        $peers = @($j.Peer.PSObject.Properties | ForEach-Object { $_.Value })
        $hit = @($peers | Where-Object { $_.HostName -eq $Peer })
        if ($hit.Count -eq 0) { $hit = $peers }
        $online = @($hit | Where-Object { $_.Online -eq $true })
        $up = ($online.Count -gt 0)
        $detail = if ($hit.Count -gt 0) { ('peers=' + $hit.Count + ' online=' + $online.Count + ' relay=' + ($hit[0].Relay)) } else { 'no-peers' }
    } catch { $up = $false; $detail = 'status-json-parse-failed' }
}
else { $detail = 'tailscale.exe not found' }

$prev = $null
if (Test-Path -LiteralPath $StatePath) {
    try { $prev = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $prev = $null }
}
$wasUp = if ($prev) { [bool]$prev.up } else { $up }
$downSince = if ($prev -and $prev.downSince) { [string]$prev.downSince } else { '' }

$busCount = 0
if (Test-Path -LiteralPath $BoardPath) { $busCount = (Get-Content -LiteralPath $BoardPath -Encoding UTF8).Count }

$resumeFile = ''
if ($up -and -not $wasUp) {
    # 断线恢复：列出断线期间新增的总线帖，供掌柜整段拉取对账
    $since = $downSince
    $added = @()
    if (Test-Path -LiteralPath $BoardPath) {
        foreach ($line in (Get-Content -LiteralPath $BoardPath -Encoding UTF8)) {
            if (-not $line.Trim()) { continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($since -eq '' -or [string]$o.ts -gt $since) { $added += $o }
        }
    }
    # 首次记录（不知道断线起点）时只列最近 20 条，避免把整份历史当"增量"
    $firstRecord = ($since -eq '')
    if ($firstRecord) { $added = @($added | Select-Object -Last 20) }
    $stamp = $now.ToString('yyyyMMdd_HHmmss')
    $resumeFile = Join-Path (Split-Path -Parent $LogPath) ('resume_' + $stamp + '.md')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# 断线恢复摘要 ' + $ts)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- 断线起点：' + $(if ($since) { $since } elseif ($firstRecord) { '未知（首次记录，仅列最近 20 条）' } else { '未知' }))
    [void]$sb.AppendLine('- 恢复时间：' + $ts)
    [void]$sb.AppendLine('- 断线期间总线新增：' + $added.Count + ' 条（当前 board 共 ' + $busCount + ' 条）')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 断线期间新增的帖子')
    foreach ($a in ($added | Select-Object -Last 50)) {
        [void]$sb.AppendLine('- ' + $a.ts + ' | ' + $a.from + ' | ' + $a.kind + ' | ref=' + $a.ref + ' | id=' + $a.id + ' | ' + (([string]$a.text) -replace "`r?`n", ' ').Substring(0, [Math]::Min(80, (([string]$a.text) -replace "`r?`n", ' ').Length)))
    }
    if (-not $DryRun) {
        [IO.File]::WriteAllText($resumeFile, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
        $bus = 'D:\tmp\nailong\bus\bus.ps1'
        if (Test-Path -LiteralPath $bus) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $bus post -From 'HC' -To all -Kind status -Text ('[HC] 链路已恢复，断线期间新增 ' + $added.Count + ' 条，摘要：' + $resumeFile) | Out-Null
        }
    }
    $downSince = ''
}
elseif (-not $up -and $wasUp) {
    $downSince = $ts   # 刚掉线：记住起点
}

$state = [ordered]@{
    at         = $ts
    up         = $up
    downSince  = $downSince
    peer       = $Peer
    detail     = $detail
    busCount   = $busCount
    resumeFile = $resumeFile
}
if (-not $DryRun) {
    [IO.File]::WriteAllText($StatePath, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

Write-Log (('up=' + $up) + ' | peer=' + $Peer + ' | bus=' + $busCount + $(if ($resumeFile) { ' | resume=' + (Split-Path -Leaf $resumeFile) } else { '' }) + ' | ' + $detail)
if ($up) { 'UP' } else { 'DOWN' }