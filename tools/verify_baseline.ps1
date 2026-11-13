# ARCH-01 / S0 · 一键基线校验（不动主程序）
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\tmp\nailong\tools\verify_baseline.ps1
#   ... -Mirror            额外生成一份主脚本镜像
# 退出码：0 = 关键项全绿；1 = 有关键项失败（PSScriptAnalyzer 缺失只记录、不算失败）

param(
    [switch]$Mirror,
    [string]$Tag = 'S0'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Main  = 'D:\tmp\xiaozhu_live.ps1'
$Tests = 'D:\tmp\nailong\tests\DataLayer.Tests.ps1'
$Root  = 'D:\tmp\nailong'
$Stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$rows  = New-Object System.Collections.ArrayList

function Add-Row([string]$name, [string]$status, [string]$detail, [bool]$critical) {
    [void]$rows.Add([pscustomobject]@{ Item = $name; Status = $status; Detail = $detail; Critical = $critical })
}

# 1) UTF-8 BOM（AGENTS.md 铁律：PS 5.1 无 BOM 会把中文读成乱码并语法报错）
try {
    $b = [IO.File]::ReadAllBytes($Main)
    $bomOk = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    Add-Row 'UTF-8 BOM' $(if ($bomOk) { 'PASS' } else { 'FAIL' }) ('前 3 字节 = ' + (($b[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' ')) $true
} catch { Add-Row 'UTF-8 BOM' 'FAIL' $_.Exception.Message $true }

# 2) PowerShell 语法（Parser，不执行脚本）
$parseErrors = @()
try {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Main, [ref]$toks, [ref]$errs)
    $parseErrors = @($errs)
    Add-Row 'Parser 语法' $(if ($parseErrors.Count -eq 0) { 'PASS' } else { 'FAIL' }) ("错误数 = " + $parseErrors.Count + " / tokens = " + @($toks).Count) $true
} catch { Add-Row 'Parser 语法' 'FAIL' $_.Exception.Message $true }

# 3) Pester 特征测试（本机 3.4.0；-Quiet 仅在支持时启用）
$pesterPassed = 0; $pesterFailed = -1
try {
    Import-Module Pester -Force -ErrorAction Stop
    $p = @{ Path = $Tests; PassThru = $true }
    if ((Get-Command Invoke-Pester).Parameters.ContainsKey('Quiet')) { $p['Quiet'] = $true }
    # Pester 3.4.0 的进度条走 Write-Progress，-Quiet 与流重定向均无法抑制，属版本固有噪音；
    # 结果对象（PassedCount / FailedCount / TestResult）仍可靠返回。
    $r = Invoke-Pester @p
    $pesterPassed = [int]$r.PassedCount
    $pesterFailed = [int]$r.FailedCount
    Add-Row 'Pester 特征测试' $(if ($pesterFailed -eq 0 -and $pesterPassed -gt 0) { 'PASS' } else { 'FAIL' }) ("通过 = $pesterPassed / 失败 = $pesterFailed") $true
    if ($pesterFailed -gt 0) {
        foreach ($t in @($r.TestResult | Where-Object { -not $_.Passed })) {
            Add-Row ('  └ 失败用例: ' + $t.Name) 'FAIL' $t.FailureMessage $false
        }
    }
} catch { Add-Row 'Pester 特征测试' 'FAIL' $_.Exception.Message $true }

# 4) PSScriptAnalyzer（可降级：本机 NuGet provider 缺失时跳过，不设为门禁）
try {
    $an = Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1
    if ($an) {
        Import-Module PSScriptAnalyzer -Force
        $diags = @(Invoke-ScriptAnalyzer -Path $Main -Severity Error,Warning -ErrorAction Stop)
        Add-Row 'PSScriptAnalyzer' 'INFO' ("版本 " + $an.Version.ToString() + " / Error+Warning = " + $diags.Count + "（仅记录，不设门禁）") $false
        $top = @($diags | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 5)
        foreach ($g in $top) { Add-Row ('  └ 规则 ' + $g.Name) 'INFO' ('' + $g.Count + ' 条') $false }
    } else {
        Add-Row 'PSScriptAnalyzer' 'SKIPPED' '模块未安装：本机缺 NuGet provider，非交互 shell 下 Install-Module 触发 ShouldContinue 失败。S0 不依赖此工具。' $false
    }
} catch { Add-Row 'PSScriptAnalyzer' 'SKIPPED' $_.Exception.Message $false }

# 5) 主脚本指纹（用于确认本轮未改动程序文件）
try {
    $sha = (Get-FileHash -LiteralPath $Main -Algorithm SHA256).Hash
    Add-Row '主脚本 SHA256' 'INFO' $sha $false
} catch { Add-Row '主脚本 SHA256' 'INFO' '读取失败' $false }

# 6) 可选镜像
if ($Mirror) {
    try {
        $dst = Join-Path $Root ("mirror\" + $Stamp + "_" + $Tag + "_verify.ps1")
        Copy-Item -LiteralPath $Main -Destination $dst -Force
        Add-Row '镜像' 'PASS' $dst $false
    } catch { Add-Row '镜像' 'FAIL' $_.Exception.Message $false }
}

$criticalFail = @($rows | Where-Object { $_.Critical -and $_.Status -eq 'FAIL' }).Count
$overall = if ($criticalFail -eq 0) { 'GREEN' } else { 'RED' }

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('# S0 基线校验报告 · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$lines.Add('')
[void]$lines.Add('- 结论：**' + $overall + '**（关键项失败 ' + $criticalFail + '）')
[void]$lines.Add('- 主程序：`D:\tmp\xiaozhu_live.ps1`（本脚本只读，不修改）')
[void]$lines.Add('- 测试：`tests\DataLayer.Tests.ps1`')
[void]$lines.Add('')
[void]$lines.Add('| 检查项 | 状态 | 明细 |')
[void]$lines.Add('| --- | --- | --- |')
foreach ($row in $rows) {
    $d = ([string]$row.Detail).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
    [void]$lines.Add('| ' + $row.Item + ' | ' + $row.Status + ' | ' + $d + ' |')
}
[void]$lines.Add('')
[void]$lines.Add('## 回滚')
[void]$lines.Add('')
[void]$lines.Add('```')
[void]$lines.Add('copy /Y "D:\tmp\nailong\mirror\<改前镜像>.ps1" "D:\tmp\xiaozhu_live.ps1"')
[void]$lines.Add('```')
[void]$lines.Add('')
[void]$lines.Add('## 备注')
[void]$lines.Add('')
[void]$lines.Add('- PSScriptAnalyzer 为可降级项：缺失或告警均不影响退出码。')
[void]$lines.Add('- Pester 采用 3.4.0 语法（Should Be），升级到 5.x 前需先迁移测试文件。')
[void]$lines.Add('- 特征基线包含「board.jsonl 中无法解析的行被静默跳过」这一当前行为，S1 重构不得改变。')

$report = Join-Path $Root ("reports\baseline_" + $Stamp + ".md")
[IO.File]::WriteAllText($report, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))

foreach ($row in $rows) { ('[{0,-7}] {1,-24} {2}' -f $row.Status, $row.Item, $row.Detail) }
'---'
'overall = ' + $overall + ' ; report = ' + $report
if ($criticalFail -gt 0) { exit 1 }
exit 0
