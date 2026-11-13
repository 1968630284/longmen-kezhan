# hc_tailscale.ps1 - Tailscale watchdog + data-plane self-heal (order 40 upgrade)
# HC1 (2026-11-13): status-read failures no longer trigger Restart-Service, and
#   every abnormal post is state-driven + rate-limited. peer-offline now reports
#   on transition / long silence instead of staying completely invisible.
# Runs every 5 minutes via scheduled task HcTailscale (SYSTEM).
# Order 30 checks: service running + `tailscale status` succeeds.
# Order 40 upgrade: those checks passed during the 2026-11-08 outage while the
#   data plane was dead (control plane still reported peer Online). Add an
#   end-to-end ICMP probe through the tunnel; when peer is Online but probe
#   fails, repair ladder: `tailscale debug rebind` -> Restart-Service.
# Logs one line per run to D:\tmp\nailong\health\tailscale.log.
# Posts to bus on abnormal/recovery (rate-limited on abnormal).
#
# Test hook: create D:\tmp\nailong\health\linkguard_restart_test.flag before a
# run and the run performs a controlled Restart-Service + recovery check.
#
# Parameters:
#   -ProbeOnly : run all checks, write one log line, never repair/post.
#   -DryRun    : same as ProbeOnly plus prints state (no writes unless logging).

param(
    [string]$ServiceName = 'Tailscale',
    [string]$PeerName = 'muse',
    [string]$LogPath = 'D:\tmp\nailong\health\tailscale.log',
    [string]$StatePath = 'D:\tmp\nailong\health\tailscale_state.json',
    [string]$TestFlag = 'D:\tmp\nailong\health\linkguard_restart_test.flag',
    [string]$BusScript = 'D:\tmp\nailong\bus\bus.ps1',
    [switch]$ProbeOnly,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$exe = 'C:\Program Files\Tailscale\tailscale.exe'
$ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$actions = New-Object System.Collections.ArrayList
$state = 'ok'

function Write-Log([string]$line) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Read-State {
    if (Test-Path -LiteralPath $StatePath) {
        try { return (Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
    }
    return $null
}

function Save-State($obj) {
    if ($DryRun) { return }
    try {
        $json = $obj | ConvertTo-Json
        [System.IO.File]::WriteAllText($StatePath, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Post-Bus([string]$text) {
    if ($DryRun -or $ProbeOnly) { return }
    if (-not (Test-Path -LiteralPath $BusScript)) { return }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $BusScript post -From 'HC' -To all -Kind status -Text $text | Out-Null
    } catch { }
}

function Get-PeerInfo {
    # HC1：原先 `2>&1 | Out-String` 会把 stderr 混进 JSON，单次失败即误判「隧道故障」；
    # 下面改为 stderr 丢弃 + 最多 3 次重试（间隔 1s），消除 CLI 偶发抖动。
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $raw = & $exe status --json 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and $raw.Trim()) {
            try {
                $j = $raw | ConvertFrom-Json
                if ($j -and $j.Peer) {
                    $peers = @($j.Peer.PSObject.Properties | ForEach-Object { $_.Value })
                    $hit = @($peers | Where-Object { $_.HostName -eq $PeerName })
                    if ($hit.Count -eq 0) { $hit = @($peers | Where-Object { $_.Online -eq $true }) }
                    if ($hit.Count -eq 0) {
                        # HC1：CLI 正常但列表里没有对端 —— 这是「对端不在线」，不是 status 解析失败，
                        # 交给 peer-offline 分支处理，别再冒充 status-bad 去重启服务。
                        return [pscustomobject]@{
                            Backend = [string]$j.BackendState; Host = '(none)'; Online = $false
                            Relay = ''; IP = ''
                        }
                    }
                    $p = $hit[0]
                    $ip = ''
                    foreach ($a in @($p.TailscaleIPs)) { if ([string]$a -match '^\d+\.') { $ip = [string]$a; break } }
                    return [pscustomobject]@{
                        Backend = [string]$j.BackendState
                        Host    = [string]$p.HostName
                        Online  = [bool]$p.Online
                        Relay   = [string]$p.Relay
                        IP      = $ip
                    }
                }
            } catch { }
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }
    return $null
}

# End-to-end ICMP through the tailnet. Returns number of successful pings.
function Test-TunnelPing([string]$ip, [int]$count, [int]$timeoutMs) {
    if (-not $ip) { return 0 }
    $ok = 0
    for ($i = 0; $i -lt $count; $i++) {
        try {
            $p = New-Object System.Net.NetworkInformation.Ping
            $r = $p.Send($ip, $timeoutMs)
            if ($r -and $r.Status -eq 'Success') { $ok++ }
            $p.Dispose()
        } catch { }
        if ($ok -gt 0) { break }
        Start-Sleep -Milliseconds 300
    }
    return $ok
}

function Invoke-Restart {
    if ($DryRun) { return 'dry-run' }
    try {
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        return 'restart=ok'
    } catch {
        return ('restart-err=' + $_.Exception.Message)
    }
}

function Wait-Recover([int]$tries, [int]$delaySec) {
    for ($i = 1; $i -le $tries; $i++) {
        Start-Sleep -Seconds $delaySec
        $p = Get-PeerInfo
        if (-not $p) { continue }
        if ((Test-TunnelPing $p.IP 1 4000) -gt 0) { return $true }
    }
    return $false
}

$prev = Read-State
$fails = 0
$downSince = ''
$lastBusAt = ''
if ($prev) {
    if ($prev.fails) { $fails = [int]$prev.fails }
    if ($prev.downSince) { $downSince = [string]$prev.downSince }
    if ($prev.lastBusAt) { $lastBusAt = [string]$prev.lastBusAt }
}

$forceTest = $false
if (Test-Path -LiteralPath $TestFlag) {
    $forceTest = $true
    if (-not $DryRun) { Remove-Item -LiteralPath $TestFlag -Force -ErrorAction SilentlyContinue }
    [void]$actions.Add('selftest=flag')
}

# 1) service
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    $state = 'fail-service-missing'
    [void]$actions.Add('service=missing')
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    if (-not $ProbeOnly -and -not $DryRun) {
        $cooldownOk = $true
        if ($lastBusAt) {
            try { if (((Get-Date) - [datetime]$lastBusAt).TotalMinutes -lt 30) { $cooldownOk = $false } } catch { }
        }
        if ($cooldownOk) {
            Post-Bus ('[HC] tailscale 服务不存在（' + $ServiceName + '），看门狗无法自愈')
            $lastBusAt = $ts
        }
    }
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}
[void]$actions.Add('service=' + $svc.Status)

if ($svc.Status -ne 'Running') {
    $state = 'repair-service-stopped'
    [void]$actions.Add('was=' + $svc.Status)
    [void]$actions.Add((Invoke-Restart))
    if (Wait-Recover 4 6) { [void]$actions.Add('recovered=yes'); $state = 'repair-service-stopped-ok' }
    else { [void]$actions.Add('recovered=no'); $state = 'repair-service-stopped-fail' }
    if (-not $ProbeOnly) {
        if ($state -eq 'repair-service-stopped-ok') {
            Post-Bus ('[HC] tailscale 服务停了，看门狗已拉起并恢复：' + ($actions -join ' '))
            $lastBusAt = $ts
        }
    }
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    if (-not $ProbeOnly -and -not $DryRun) { $fails = 0; $downSince = '' }
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}

# 2) status / peer
$peer = Get-PeerInfo
if (-not $peer) {
    $state = 'status-bad'
    [void]$actions.Add('status-json-fail')
    if (-not $ProbeOnly -and -not $DryRun) {
        # HC1：status 读取失败属于本机 CLI / 控制面读取问题，Restart-Service 既修不好，
        # 还会每 5 分钟打断一次本来正常的隧道。这里不做任何修复动作，只按冷却发帖。
        $cooldownOk = $true
        if ($lastBusAt) {
            try { if (((Get-Date) - [datetime]$lastBusAt).TotalMinutes -lt 30) { $cooldownOk = $false } } catch { }
        }
        if ($cooldownOk) {
            Post-Bus ('[HC] tailscale status 读取失败（已重试 3 次），服务仍 Running；未重启服务，请人工检查 CLI：' + ($actions -join ' '))
            $lastBusAt = $ts
        }
    }
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}
[void]$actions.Add('peer=' + $peer.Host + ' online=' + $peer.Online + ' relay=' + $peer.Relay)

if ($peer.Backend -ne 'Running') {
    $state = 'backend-' + $peer.Backend
    [void]$actions.Add('backend=not-running')
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}

if (-not $peer.Online) {
    # Peer (or its control-plane view) is down; nothing PC-side can repair.
    $state = 'peer-offline'
    if (-not $ProbeOnly -and -not $DryRun) {
        # HC1：原实现完全静默 —— 对端断线一整天，留言板上零提示。改为事件驱动：
        # 刚进入离线报一次；持续离线每 6 小时兜底提醒一次；绝不每轮刷屏。
        $enteredOffline = (-not $prev) -or ([string]$prev.state -ne 'peer-offline')
        $remindOk = $true
        if ($lastBusAt) {
            try { if (((Get-Date) - [datetime]$lastBusAt).TotalHours -lt 6) { $remindOk = $false } } catch { }
        }
        if ($enteredOffline -or $remindOk) {
            Post-Bus ('[HC] 对端 ' + $peer.Host + ' 离线（relay=' + $peer.Relay + '，service=Running）；本机侧无法自愈，请检查对端主机/网络')
            $lastBusAt = $ts
        }
    }
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}

# 3) end-to-end data-plane probe
$pingOkCount = Test-TunnelPing $peer.IP 3 4000
$pathOk = ($pingOkCount -gt 0)
[void]$actions.Add('ping=' + $pingOkCount + '/3')

if ($ProbeOnly -or $DryRun) {
    if ($pathOk) { $state = 'probe-ok' } else { $state = 'probe-down' }
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    if ($DryRun) { $actions -join ' ' }
    $state
    return
}

if ($forceTest) {
    $state = 'selftest'
    [void]$actions.Add('step=controlled-restart')
    [void]$actions.Add((Invoke-Restart))
    $rec = Wait-Recover 5 6
    if ($rec) { [void]$actions.Add('recovered=yes'); $state = 'selftest-ok' }
    else { [void]$actions.Add('recovered=no'); $state = 'selftest-fail' }
    Post-Bus ('[HC] linkguard 自测（受控重启 ' + $ServiceName + '）：' + $state + ' | ' + ($actions -join ' '))
    $lastBusAt = $ts
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    $fails = 0
    $downSince = ''
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}

if ($pathOk) {
    # HC1：从 peer-offline 恢复时 $fails/$downSince 都是 0，原条件不成立 → 恢复也静默，补上。
    if ($fails -gt 0 -or $downSince -or ($prev -and [string]$prev.state -eq 'peer-offline')) {
        $state = 'recovered'
        if ($downSince) {
            try { $mins = [int](((Get-Date) - [datetime]$downSince).TotalMinutes) } catch { $mins = -1 }
            [void]$actions.Add('down_since=' + $downSince)
            [void]$actions.Add('down_min=' + $mins)
        }
        Post-Bus ('[HC] 隧道数据面已恢复：' + ($actions -join ' '))
        $lastBusAt = $ts
    }
    $fails = 0
    $downSince = ''
    Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
    Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
    $state
    return
}

# 4) data plane down while control plane says Online -> repair ladder
$state = 'path-down'
$fails = $fails + 1
[void]$actions.Add('fails=' + $fails)
if (-not $downSince) { $downSince = $ts }
[void]$actions.Add('down_since=' + $downSince)

$recoveredBy = ''
# 4a) cheap repair: force magicsock rebind (fixes stale endpoints/NAT mapping)
try {
    & $exe debug rebind 2>&1 | Out-Null
    [void]$actions.Add('rebind=sent')
} catch { [void]$actions.Add('rebind-err') }
Start-Sleep -Seconds 6
$p2 = Get-PeerInfo
if ($p2 -and (Test-TunnelPing $p2.IP 1 4000) -gt 0) { $recoveredBy = 'rebind' }

# 4b) hammer: restart the service (this is what fixed the 15:08 outage by hand)
if (-not $recoveredBy) {
    [void]$actions.Add((Invoke-Restart))
    if (Wait-Recover 5 6) { $recoveredBy = 'restart' }
}

if ($recoveredBy) {
    $state = 'path-down-repaired'
    [void]$actions.Add('recovered_by=' + $recoveredBy)
    try { $mins = [int](((Get-Date) - [datetime]$downSince).TotalMinutes) } catch { $mins = -1 }
    [void]$actions.Add('down_min=' + $mins)
    Post-Bus ('[HC] 隧道数据面掉线已自愈（' + $recoveredBy + '）：' + ($actions -join ' '))
    $lastBusAt = $ts
    $fails = 0
    $downSince = ''
} else {
    $state = 'path-down-unrepaired'
    $cooldownOk = $true
    if ($lastBusAt) {
        try { if (((Get-Date) - [datetime]$lastBusAt).TotalMinutes -lt 30) { $cooldownOk = $false } } catch { }
    }
    if ($cooldownOk) {
        Post-Bus ('[HC] 隧道数据面掉线，rebind+重启服务均未恢复，需人工处理：' + ($actions -join ' '))
        $lastBusAt = $ts
    }
}

Write-Log ($ts + ' | ' + $state + ' | ' + ($actions -join ' '))
Save-State ([pscustomobject]@{ at = $ts; fails = $fails; downSince = $downSince; lastBusAt = $lastBusAt; state = $state })
$state