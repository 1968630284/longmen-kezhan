# hc_tailscale.ps1 - Tailscale watchdog (order 30, item C)
# Runs every 5 minutes via scheduled task HcTailscale.
# Checks: service exists -> running -> `tailscale status` succeeds. Restarts service when broken.
# Logs one line per run to D:\tmp\nailong\health\tailscale.log (ASCII only on purpose).
# Posts to bus ONLY on abnormal.

param(
    [string]$ServiceName = 'Tailscale',
    [string]$LogPath = 'D:\tmp\nailong\health\tailscale.log',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$actions = @()
$state = 'ok'

function Write-Log([string]$line) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ($now + ' | ' + $line) -Encoding UTF8
}

# 1) service
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    $state = 'fail-service-missing'
    $actions += 'service-missing'
}
elseif ($svc.Status -ne 'Running') {
    $state = 'repair-service-stopped'
    $actions += ('was=' + $svc.Status)
    if (-not $DryRun) {
        try { Restart-Service -Name $ServiceName -Force -ErrorAction Stop; $actions += 'restart=ok'; Start-Sleep -Seconds 3 }
        catch { $actions += ('restart-err=' + $_.Exception.Message) }
    }
    else { $actions += 'dry-run: would restart' }
}
else { $actions += 'service=running' }

# 2) tailscale status (only if binary reachable)
$exe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path -LiteralPath $exe) {
    $out = & $exe status 2>&1
    if ($LASTEXITCODE -ne 0 -or ($out -join ' ') -match 'not running|failed') {
        if ($state -eq 'ok') { $state = 'warn-status-bad' }
        $actions += ('status-bad=' + (($out | Select-Object -First 1) -join ''))
        if (-not $DryRun -and $svc -and $svc.Status -eq 'Running') {
            try { Restart-Service -Name $ServiceName -Force -ErrorAction Stop; $actions += 'restart-after-status=ok' }
            catch { $actions += ('restart-after-status-err=' + $_.Exception.Message) }
        }
    }
    else {
        $peer = ($out | Select-Object -First 1)
        $actions += ('status-ok=' + ([string]$peer).Trim())
    }
}
else { $actions += 'tailscale.exe-not-found' }

Write-Log ($state + ' | ' + ($actions -join ' '))

if ($state -notin @('ok') -and -not $DryRun) {
    $bus = 'D:\tmp\nailong\bus\bus.ps1'
    if (Test-Path -LiteralPath $bus) {
        $msg = '[HC] tailscale abnormal: ' + $state + ' | ' + ($actions -join ' ')
        & powershell -NoProfile -ExecutionPolicy Bypass -File $bus post -From 'HC' -To all -Kind status -Text $msg | Out-Null
    }
}

$state