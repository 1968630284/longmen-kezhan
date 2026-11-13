# hc_tailscale.ps1 - Tailscale watchdog + data-plane self-heal (order 40 upgrade)
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
    $raw = & $exe status --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    try { $j = $raw | ConvertFrom-Json } catch { return $null }
    if (-not $j) { return $null }
    $peers = @($j.Peer.PSObject.Properties | ForEach-Object { $_.Value })
    $hit = @($peers | Where-Object { $_.HostName -eq $PeerName })
    if ($hit.Count -eq 0) { $hit = @($peers | Where-Object { $_.Online -eq $true }) }
    if ($hit.Count -eq 0) { return $null }
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
        [void]$actions.Add((Invoke-Restart))
        if (Wait-Recover 3 6) { [void]$actions.Add('recovered=yes'); $state = 'status-bad-ok' }
        else { [void]$actions.Add('recovered=no'); $state = 'status-bad-fail' }
        Post-Bus ('[HC] tailscale status 异常，已重启服务：' + ($actions -join ' '))
        $lastBusAt = $ts
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
    if ($fails -gt 0 -or $downSince) {
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