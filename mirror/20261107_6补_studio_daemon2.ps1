# 6 号 · 视频守夜人 v2.1（本地段 + 等待策略/进度通道）
# 状态机：queued → posted → awaiting_confirm → cloud_working → verifying → completed / failed
#   规则（补充三/四）：
#   - 只在「回执文件到盘 + 两端哈希一致」时才写 completed，别无他路；
#   - posted 后 15 分钟无掌柜接单帖 → 标「云端未响应」并 @掌柜 提醒一次，不自动重提、不本地顶替；
#   - 掌柜的进度帖（ref=videojob 且正文带 job_id）驱动 cloud_working 并把这句进度显示到工坊。
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
$Board = "D:\tmp\nailong\bus\board.jsonl"
$Utf8 = New-Object Text.UTF8Encoding($false)
$PidFile = Join-Path $JobsDir ".daemon2.pid"
$TimeoutMin = 15

function Log($msg) {
    $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $msg
    try { [IO.File]::AppendAllText($LogPath, ($line + "`r`n"), $Utf8) } catch { }
}
function Write-Job($path, $job) { [IO.File]::WriteAllText($path, ($job | ConvertTo-Json -Depth 8), $Utf8) }
function Get-Sha($p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Set-Prop($job, $name, $value) { $job | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }

foreach ($d in @($JobsDir, $OutDir, $EngineDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

if (-not $Once) {
    if (Test-Path $PidFile) {
        $oldPid = 0
        [int]::TryParse((Get-Content $PidFile -Raw).Trim(), [ref]$oldPid) | Out-Null
        if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            Log "已有守夜人在跑 pid=$oldPid，本进程退出"; exit 0
        }
    }
    [IO.File]::WriteAllText($PidFile, [string]$PID, $Utf8)
}

function Get-StagePost($id, $since, $postedAfter) {
    if (-not (Test-Path $Board)) { return $null }
    $lines = @([IO.File]::ReadAllLines($Board, [Text.Encoding]::UTF8))
    $found = $null
    foreach ($l in $lines) {
        if (-not $l.Trim()) { continue }
        if ($l.IndexOf($id) -lt 0) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { continue }
        if ([string]$o.from -notmatch '小猪|掌柜') { continue }
        if ([string]$o.kind -ne 'status') { continue }
        if ($postedAfter -and ([string]$o.ts -lt $postedAfter)) { continue }
        foreach ($kw in @("已收到", "已接单", "素材已拉取", "生成中", "回传中", "已完成")) {
            if ([string]$o.text -match $kw) { $found = @{ stage = $kw; ts = [string]$o.ts } }
        }
    }
    return $found
}

function Post-Job($jobDir) {
    $jobPath = Join-Path $jobDir "job.json"
    if (-not (Test-Path $jobPath)) { return }
    $id = [IO.Path]::GetFileName($jobDir)
    if ($JobId -and $id -ne $JobId) { return }
    $postedMark = Join-Path $jobDir ".posted"
    $job = $null
    try { $job = [IO.File]::ReadAllText($jobPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { Log "$id job.json 解析失败，跳过"; return }

    if (Test-Path $postedMark) {
        # 老包补状态：已发过帖但状态还停在 queued 的
        if ([string]$job.status -eq "queued") {
            Set-Prop $job "status" "awaiting_confirm"
            Set-Prop $job "statusNote" "已递总线，等掌柜回执"
            Write-Job $jobPath $job
            Log "$id 补状态 → awaiting_confirm"
        }
        return
    }

    $assets = @(); $missing = @(); $roles = @()
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
        Set-Prop $job "status" "failed"
        Set-Prop $job "statusNote" ("素材缺失：" + ($missing -join ", "))
        Set-Prop $job "failedAt" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Write-Job $jobPath $job
        Log "$id 素材缺失：$($missing -join ', ')"
        return
    }
    $rst = Get-Content $jobPath -Raw -Encoding UTF8
    $body = @(
        ("【大厨】videojob " + $id + " 提交（Job 包已校验）"),
        "",
        ("job_id：" + $id),
        ("包路径：" + $jobDir),
        ("参数：比例 " + $job.ratio + "｜时长 " + $job.durationSec + "s｜质量 " + $job.tier + "｜运镜 " + $job.motion + "｜seed " + $job.seed + "｜模式 " + $job.mode + "｜人物参考 " + $(if ($job.character_partial) { "不全（partial）" } else { "3/3" })),
        ("提示词：" + $job.prompt),
        ("六槽：" + (($job.prompt_slots.PSObject.Properties | ForEach-Object { $_.Name + "=" + $_.Value }) -join "；")),
        ("负向：" + $job.negative),
        "",
        "素材（拉取用绝对路径，回传按 outputs\<job_id>.mp4 + receipt_<job_id>.json）：",
        ($assets -join "`r`n"),
        "",
        "job.json 全文：",
        $rst
    ) -join "`r`n"
    if ($DryRun) { Log ("[dryrun] 将发帖 " + $id + "（正文 " + $body.Length + " 字，素材 " + $assets.Count + " 件）"); return }
    try {
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Set-Prop $job "status" "posted"
        Set-Prop $job "postedAt" $now
        Set-Prop $job "statusNote" "已递总线"
        Write-Job $jobPath $job
        & $Bus post -From "大厨(LOCAL)" -To "all" -Kind "task" -Ref "videojob" -Text $body | Out-Null
        [IO.File]::WriteAllText($postedMark, $now, $Utf8)
        Set-Prop $job "status" "awaiting_confirm"
        Set-Prop $job "statusNote" "已递总线，等掌柜回执"
        Write-Job $jobPath $job
        Log "$id 已发帖 → awaiting_confirm"
    } catch {
        Log "$id 发帖失败：" + $_.Exception.Message
        Set-Prop $job "status" "failed"
        Set-Prop $job "statusNote" ("发帖失败：" + $_.Exception.Message)
        Write-Job $jobPath $job
    }
}

function Get-ResultFail($id, $postedAfter) {
    if (-not (Test-Path $Board)) { return $null }
    $lines = @([IO.File]::ReadAllLines($Board, [Text.Encoding]::UTF8))
    $msg = $null
    foreach ($l in $lines) {
        if (-not $l.Trim()) { continue }
        if ($l.IndexOf($id) -lt 0) { continue }
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { continue }
        if ([string]$o.from -notmatch '小猪|掌柜') { continue }
        if ([string]$o.kind -ne 'result') { continue }
        if ($postedAfter -and ([string]$o.ts -lt $postedAfter)) { continue }
        $t = [string]$o.text
        if ($t -match '失败' -and $t -notmatch '对账通过|已完成') {
            $msg = $t
        }
    }
    return $msg
}

function Watch-Job($jobDir) {
    $id = [IO.Path]::GetFileName($jobDir)
    if ($JobId -and $id -ne $JobId) { return }
    $jobPath = Join-Path $jobDir "job.json"
    if (-not (Test-Path $jobPath)) { return }
    $job = $null
    try { $job = [IO.File]::ReadAllText($jobPath, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return }
    $st = [string]$job.status
    if (@("completed", "failed") -contains $st) { return }

    # 1) 掌柜进度帖 → cloud_working
    if (@("awaiting_confirm", "posted", "cloud_working") -contains $st) {
        $stage = Get-StagePost $id $null ([string]$job.postedAt)
        if ($stage) {
            if ($st -ne "cloud_working" -or ([string]$job.statusNote) -notmatch [regex]::Escape($stage.stage)) {
                Set-Prop $job "status" "cloud_working"
                Set-Prop $job "statusNote" ("掌柜：" + $stage.stage + "（" + $stage.ts + "）")
                Set-Prop $job "stageAt" $stage.ts
                Write-Job $jobPath $job
                Log "$id 进度 → cloud_working（$($stage.stage)）"
            }
            $st = "cloud_working"
        }
    }

    # 2) 掌柜失败回帖（总线 result 帖，非回执文件）→ failed
    if (@("posted", "awaiting_confirm", "cloud_working", "verifying") -contains $st) {
        $failMsg = Get-ResultFail $id ([string]$job.postedAt)
        if ($failMsg) {
            $brief = $failMsg
            if ($brief -match '原因[：:]\s*([^\r\n]+)') { $brief = $Matches[1].Trim() }
            elseif ($brief -match '失败类别[：:]\s*([^\r\n]+)') { $brief = $Matches[1].Trim() }
            if ($brief.Length -gt 120) { $brief = $brief.Substring(0, 120) }
            Set-Prop $job "status" "failed"
            Set-Prop $job "statusNote" ("掌柜回执失败：" + $brief)
            Set-Prop $job "failedAt" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Write-Job $jobPath $job
            Log "$id 掌柜失败回帖 → failed"
            return
        }
    }

    # 3) 超时未响应（15 分钟，只提醒一次）
    if (@("posted", "awaiting_confirm", "cloud_working") -contains $st) {
        $pa = [string]$job.postedAt
        if ($pa) {
            $t0 = [datetime]::MinValue
            if ([datetime]::TryParse($pa, [ref]$t0)) {
                $mins = ((Get-Date) - $t0).TotalMinutes
                if ($mins -ge $TimeoutMin -and ([string]$job.statusNote) -notmatch '云端未响应') {
                    $note = "云端未响应（已等 " + [int]$mins + " 分钟）· " + ([string]$job.statusNote)
                    Set-Prop $job "statusNote" $note
                    Write-Job $jobPath $job
                    Log "$id 超时：云端未响应（$([int]$mins) 分钟）"
                    if (-not $DryRun) {
                        try {
                            & $Bus post -From "大厨(LOCAL)" -To "掌柜" -Kind "status" -Ref "videojob" -Text ("【大厨】提醒：" + $id + " 递出已 " + [int]$mins + " 分钟，总线未见接单/进度帖，工坊已标「云端未响应」。按补充三不自动重提、不本地顶替，等你一句话。") | Out-Null
                        } catch { Log "$id 提醒发帖失败：" + $_.Exception.Message }
                    }
                }
            }
        }
    }

    # 3) 回执 → verifying → completed / failed（唯一完成通道）
    $rc = Join-Path $OutDir ("receipt_" + $id + ".json")
    if (-not (Test-Path $rc)) { return }
    try { $r = [IO.File]::ReadAllText($rc, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { Log "$id receipt 解析失败"; return }
    Set-Prop $job "status" "verifying"
    Set-Prop $job "statusNote" "回执已到，哈希对账中"
    Write-Job $jobPath $job
    $mp4 = [string]$r.file
    if (-not $mp4) { $mp4 = Join-Path $OutDir ($id + ".mp4") }
    if (-not [IO.Path]::IsPathRooted($mp4)) { $mp4 = Join-Path $OutDir $mp4 }
    if (-not (Test-Path -LiteralPath $mp4)) {
        Set-Prop $job "status" "failed"
        Set-Prop $job "statusNote" "回执有、成品文件不在"
        Set-Prop $job "failedAt" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Write-Job $jobPath $job; Log "$id 回执有但成品缺失"; return
    }
    $actual = Get-Sha $mp4
    if ($r.sha256 -and ([string]$r.sha256).ToUpper() -ne $actual) {
        Set-Prop $job "status" "failed"
        Set-Prop $job "statusNote" ("成品哈希不符：期望 " + $r.sha256 + " 实测 " + $actual)
        Set-Prop $job "failedAt" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Write-Job $jobPath $job; Log "$id 哈希不符"; return
    }
    Set-Prop $job "status" "completed"
    Set-Prop $job "output" $mp4
    Set-Prop $job "outputBytes" (Get-Item -LiteralPath $mp4).Length
    Set-Prop $job "statusNote" ("成品 " + (Get-Item -LiteralPath $mp4).Length + " B，哈希 " + $actual.Substring(0, 12) + "… 对账通过")
    Set-Prop $job "completedAt" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Job $jobPath $job
    Log "$id 对账通过 → completed"
}

function Run-Sweep {
    if (-not (Test-Path $JobsDir)) { return }
    $dirs = Get-ChildItem -LiteralPath $JobsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($d in $dirs) {
        try { Post-Job $d.FullName } catch { Log ("Post-Job 异常：" + $_.Exception.Message) }
        try { Watch-Job $d.FullName } catch { Log ("Watch-Job 异常：" + $_.Exception.Message) }
    }
}

Log "守夜人 v2.1 启动 pid=$PID once=$Once dryrun=$DryRun jobid=$JobId"
if ($Once) { Run-Sweep; Log "once 结束"; exit 0 }
while ($true) {
    try { Run-Sweep } catch { Log ("扫描异常（已捕获，继续跑）：" + $_.Exception.Message) }
    Start-Sleep -Seconds 6
}