# 6 号 · 视频守夜人 v2（本地段）
# 职责：扫 jobs\ 新包 → 校验 job.json 与素材 → 状态置 queued → 总线发帖（job.json 全文 + 每件素材路径/SHA256/字节）
#        → 轮询 outputs\receipt_<job_id>.json → 成品 SHA 对账 → 状态 completed / failed
# 常驻：不自退。单实例：jobs\.daemon2.pid
param(
    [switch]$Once,
    [switch]$DryRun,
    [string]$JobId = ""
)
$ErrorActionPreference = "Stop"
$Root = "D:\tmp\video_studio"
$JobsDir = Join-Path $Root "jobs"
$OutDir = Join-Path $Root "outputs"
$EngineDir = Join-Path $Root "engine"
$LogPath = Join-Path $EngineDir "daemon2.log"
$Bus = "D:\tmp\nailong\bus\bus.ps1"
$Utf8 = New-Object Text.UTF8Encoding($false)
$PidFile = Join-Path $JobsDir ".daemon2.pid"

function Log($msg) {
    $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $msg
    try { [IO.File]::AppendAllText($LogPath, ($line + "`r`n"), $Utf8) } catch { }
}
function Write-Job($path, $job) {
    [IO.File]::WriteAllText($path, ($job | ConvertTo-Json -Depth 8), $Utf8)
}
function Get-Sha($p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

foreach ($d in @($JobsDir, $OutDir, $EngineDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# ---- 单实例 ----
if (-not $Once) {
    if (Test-Path $PidFile) {
        $oldPid = 0
        [int]::TryParse((Get-Content $PidFile -Raw).Trim(), [ref]$oldPid) | Out-Null
        if ($oldPid -gt 0) {
            $alive = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($alive) { Log "已有守夜人在跑 pid=$oldPid，本进程退出"; exit 0 }
        }
    }
    [IO.File]::WriteAllText($PidFile, [string]$PID, $Utf8)
}

function Post-Job($jobDir) {
    $jobPath = Join-Path $jobDir "job.json"
    if (-not (Test-Path $jobPath)) { return }
    $id = [IO.Path]::GetFileName($jobDir)
    if ($JobId -and $id -ne $JobId) { return }
    $postedMark = Join-Path $jobDir ".posted"
    if (Test-Path $postedMark) { return }
    $job = $null
    try { $job = [IO.File]::ReadAllText($jobPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch {
        Log "$id job.json 解析失败，跳过"; return
    }
    # 素材校验 + 哈希
    $assets = @()
    $missing = @()
    $roles = @()
    if ($job.inputs.character.front) { $roles += @("character.front", $job.inputs.character.front) }
    if ($job.inputs.character.side) { $roles += @("character.side", $job.inputs.character.side) }
    if ($job.inputs.character.back) { $roles += @("character.back", $job.inputs.character.back) }
    if ($job.inputs.background) { $roles += @("background", $job.inputs.background) }
    if ($job.inputs.scene) { $roles += @("scene", $job.inputs.scene) }
    for ($i = 0; $i -lt $roles.Count; $i += 2) {
        $rel = [string]$roles[$i + 1]
        $abs = Join-Path $jobDir ($rel -replace "/", "\")
        if (-not (Test-Path -LiteralPath $abs)) { $missing += $rel; continue }
        $fi = Get-Item -LiteralPath $abs
        $assets += ("- " + $roles[$i] + " · " + $abs + " · " + $fi.Length + " B · SHA256 " + (Get-Sha $abs))
    }
    if ($missing.Count -gt 0) {
        $job.status = "failed"
        $job | Add-Member -NotePropertyName statusNote -NotePropertyValue ("素材缺失：" + ($missing -join ", ")) -Force
        Write-Job $jobPath $job
        Log "$id 素材缺失：$($missing -join ', ')"
        return
    }
    $job.status = "queued"
    $job | Add-Member -NotePropertyName statusNote -NotePropertyValue "已发帖，等掌柜接单" -Force
    $job | Add-Member -NotePropertyName postedAt -NotePropertyValue (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Force
    $rst = Get-Content $jobPath -Raw -Encoding UTF8
    $body = @(
        ("【大厨】videojob " + $id + " 提交（Job 包已校验）"),
        "",
        ("job_id：" + $id),
        ("包路径：" + $jobDir),
        ("参数：比例 " + $job.ratio + "｜时长 " + $job.durationSec + "s｜质量 " + $job.tier + "｜运镜 " + $job.motion + "｜seed " + $job.seed + "｜模式 " + $job.mode + "｜人物参考 " + $(if ($job.character_partial) { "不全（partial）" } else { "3/3" })),
        ("提示词：" + $job.prompt),
        ("六槽：" + ($job.prompt_slots.PSObject.Properties | ForEach-Object { $_.Name + "=" + $_.Value }) -join "；"),
        ("负向：" + $job.negative),
        "",
        "素材（拉取用绝对路径，回传按 outputs\<job_id>.mp4 + receipt_<job_id>.json）：",
        ($assets -join "`r`n"),
        "",
        "job.json 全文：",
        $rst
    ) -join "`r`n"
    if ($DryRun) {
        Log ("[dryrun] 将发帖 " + $id + "（正文 " + $body.Length + " 字，素材 " + $assets.Count + " 件）")
        return
    }
    try {
        & $Bus post -From "大厨(LOCAL)" -To "all" -Kind "task" -Ref "videojob" -Text $body | Out-Null
        [IO.File]::WriteAllText($postedMark, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Utf8)
        Write-Job $jobPath $job
        Log "$id 已发帖"
    } catch {
        Log "$id 发帖失败：" + $_.Exception.Message
        $job.status = "failed"
        $job | Add-Member -NotePropertyName statusNote -NotePropertyValue ("发帖失败：" + $_.Exception.Message) -Force
        Write-Job $jobPath $job
    }
}

function Check-Receipt($jobDir) {
    $id = [IO.Path]::GetFileName($jobDir)
    if ($JobId -and $id -ne $JobId) { return }
    $jobPath = Join-Path $jobDir "job.json"
    if (-not (Test-Path $jobPath)) { return }
    $job = [IO.File]::ReadAllText($jobPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (@("completed", "failed") -contains [string]$job.status) { return }
    $rc = Join-Path $OutDir ("receipt_" + $id + ".json")
    if (-not (Test-Path $rc)) { return }
    try { $r = [IO.File]::ReadAllText($rc, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { Log "$id receipt 解析失败"; return }
    $mp4 = [string]$r.file
    if (-not $mp4) { $mp4 = Join-Path $OutDir ($id + ".mp4") }
    if (-not (Test-Path -LiteralPath $mp4)) {
        $job.status = "failed"
        $job | Add-Member -NotePropertyName statusNote -NotePropertyValue "回执有、成品文件不在" -Force
        Write-Job $jobPath $job; Log "$id 回执有但成品缺失"; return
    }
    $actual = Get-Sha $mp4
    if ($r.sha256 -and ([string]$r.sha256).ToUpper() -ne $actual) {
        $job.status = "failed"
        $job | Add-Member -NotePropertyName statusNote -NotePropertyValue ("成品哈希不符：期望 " + $r.sha256 + " 实测 " + $actual) -Force
        Write-Job $jobPath $job; Log "$id 哈希不符"; return
    }
    $job.status = "completed"
    $job | Add-Member -NotePropertyName output -NotePropertyValue $mp4 -Force
    $job | Add-Member -NotePropertyName statusNote -NotePropertyValue ("成品 " + (Get-Item -LiteralPath $mp4).Length + " B，哈希 " + $actual.Substring(0, 12) + "… 对账通过") -Force
    Write-Job $jobPath $job
    Log "$id 对账通过 → completed"
}

function Run-Sweep {
    if (-not (Test-Path $JobsDir)) { return }
    $dirs = Get-ChildItem -LiteralPath $JobsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($d in $dirs) {
        try { Post-Job $d.FullName } catch { Log ("Post-Job 异常：" + $_.Exception.Message) }
        try { Check-Receipt $d.FullName } catch { Log ("Check-Receipt 异常：" + $_.Exception.Message) }
    }
}

Log "守夜人 v2 启动 pid=$PID once=$Once dryrun=$DryRun jobid=$JobId"
if ($Once) {
    Run-Sweep
    Log "once 结束"
    exit 0
}
while ($true) {
    try { Run-Sweep } catch { Log ("扫描异常（已捕获，继续跑）：" + $_.Exception.Message) }
    Start-Sleep -Seconds 6
}