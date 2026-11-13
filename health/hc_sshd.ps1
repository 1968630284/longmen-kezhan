# hc_sshd.ps1 - sshd watchdog (order 17, item 1)
# Runs every 5 minutes via scheduled task HcSshd.
# Checks: service exists -> running -> port listening. Recreates service if missing.
# Logs one line per run to D:\tmp\nailong\health\sshd.log (ASCII only, on purpose).
# Posts to bus ONLY on abnormal (avoid noise).

param(
    [string]$ServiceName = 'sshd',
    [int]$Port = 22,
    [string]$LogPath = 'D:\tmp\nailong\health\sshd.log',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$sshdExe = 'C:\Program Files\OpenSSH\sshd.exe'
$actions = @()
$state = 'ok'

function Write-Log([string]$line) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ($now + ' | ' + $line) -Encoding UTF8
}

# 1) service exists?
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    $state = 'repair-service-missing'
    $actions += 'service-missing'
    if (-not (Test-Path -LiteralPath $sshdExe)) {
        $state = 'fail-exe-missing'
        $actions += 'sshd.exe-not-found'
    }
    elseif (-not $DryRun) {
        $out = & sc.exe create $ServiceName binPath= ('"' + $sshdExe + '"') start= auto obj= LocalSystem 2>&1
        $actions += ('sc-create=' + (($out | Out-String).Trim()))
        Start-Sleep -Seconds 2
        $out2 = & sc.exe start $ServiceName 2>&1
        $actions += ('sc-start=' + (($out2 | Out-String).Trim()))
    }
    else { $actions += 'dry-run: would sc create + start' }
}
else {
    # 2) running?
    if ($svc.Status -ne 'Running') {
        $state = 'repair-service-stopped'
        $actions += ('was=' + $svc.Status)
        if (-not $DryRun) {
            try { Start-Service -Name $ServiceName -ErrorAction Stop; $actions += 'start-service=ok' }
            catch { $actions += ('start-service-err=' + $_.Exception.Message) }
        }
        else { $actions += 'dry-run: would Start-Service' }
    }
    else { $actions += 'service=running' }
}

# 3) port listening?
Start-Sleep -Milliseconds 300
$listen = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($listen.Count -eq 0) {
    if ($state -eq 'ok') { $state = 'warn-port-not-listening' }
    $actions += 'port-not-listening'
}
else { $actions += ('port-listening pid=' + ($listen[0].OwningProcess)) }

Write-Log ($state + ' | ' + ($actions -join ' '))

# 4) bus post only when abnormal
if ($state -notin @('ok') -and -not $DryRun) {
    $bus = 'D:\tmp\nailong\bus\bus.ps1'
    if (Test-Path -LiteralPath $bus) {
        $msg = '[HC] sshd abnormal: ' + $state + ' | ' + ($actions -join ' ')
        & powershell -NoProfile -ExecutionPolicy Bypass -File $bus post -From 'HC' -To all -Kind status -Text $msg | Out-Null
    }
}

$state