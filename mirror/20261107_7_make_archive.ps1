# 存档打包 v3：全量 + 误点防护 + 保留策略 + 体检 + CHANGES/INDEX + 读档
# 由应用左栏「存档」按钮调用，也可独立运行。
# 不做 exit：被应用内 & 调用时 exit 会带走宿主进程；出错一律 throw。

$ErrorActionPreference = 'Stop'

$root = 'D:\tmp\nailong'
$archive = Join-Path $root 'archive'
$lockPath = Join-Path $archive '.pack.lock'
$bus = Join-Path $root 'bus\bus.ps1'

# ---- 并发锁 ----
if (Test-Path -LiteralPath $lockPath) {
    try {
        $age = (Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime
        if ($age.TotalMinutes -lt 5) { throw '打包进行中（锁文件存在），本次跳过' }
        Remove-Item -LiteralPath $lockPath -Force
    } catch { if ($_.Exception.Message -like '*打包进行中*') { throw } }
}
New-Item -ItemType File -Path $lockPath -Force | Out-Null
try {

$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir = Join-Path $archive $stamp
if (Test-Path -LiteralPath $dir) {
    $i = 2
    while (Test-Path -LiteralPath ($dir + "-$i")) { $i++ }
    $dir = $dir + "-$i"
}
$pkg = [IO.Path]::GetFileName($dir)

# ---- 上一包（最近、有 manifest、非本包） ----
$prev = $null
foreach ($d in (Get-ChildItem -LiteralPath $archive -Directory | Sort-Object LastWriteTime -Descending)) {
    if ($d.Name -eq $pkg) { continue }
    $mp = Join-Path $d.FullName 'manifest.json'
    if (Test-Path -LiteralPath $mp) { $prev = $d; break }
}

# ---- 固定件清单 ----
$items = @(
    @{ src = (Join-Path $archive 'STATE_LOG.md');                    name = 'STATE_LOG.md';        purpose = '状态日志全文：规矩、现状、教训、恢复流程' },
    @{ src = (Join-Path $root 'handoff\gongbing_memory.md');          name = 'gongbing_memory.md';  purpose = '大厨交接记忆：身份、口径、资产、踩坑' },
    @{ src = 'C:\Users\余佳凯\.dsh\AGENTS.md';                        name = 'AGENTS.md';           purpose = '全局驻地规矩（五条，全线路生效）' },
    @{ src = 'C:\Users\余佳凯\.dsh\weixin\sessions\AGENTS.md';        name = 'AGENTS_weixin.md';    purpose = '微信线驻地规矩（工作区级）' },
    @{ src = (Join-Path $root 'ledger.md');                           name = 'ledger.md';           purpose = '单据账本：每单交付与证据索引' },
    @{ src = (Join-Path $root 'bus\board.jsonl');                     name = 'board.jsonl';         purpose = '总线留言板全量档案' },
    @{ src = (Join-Path $root 'bus\activity.jsonl');                  name = 'activity.jsonl';      purpose = '总线动作日志全量' },
    @{ src = (Join-Path $root 'dsh-bus-bridge\cordis.patch.yml');     name = 'cordis.patch.yml';    purpose = '总线桥配置：抬头标记、软唤醒参数' },
    @{ src = (Join-Path $root 'dsh-bus-bridge\package.json');         name = 'bridge_package.json'; purpose = '总线桥插件 package.json：版本与标记' },
    @{ src = (Join-Path $root 'tools\make_archive.ps1');              name = 'make_archive.ps1';    purpose = '打包脚本本体（打自己也要留底）' },
    @{ src = 'D:\tmp\xiaozhu_live.ps1';                               name = 'xiaozhu_live.ps1';    purpose = '应用当前版（WPF 主程序）' },
    @{ src = (Join-Path $root 'launch_app.vbs');                      name = 'launch_app.vbs';      purpose = '应用静默启动器' }
)
$mirror = Join-Path $root 'mirror'
$textExt = @('.ps1', '.js', '.yml', '.md')
$notIncluded = @()
if (Test-Path -LiteralPath $mirror) {
    foreach ($f in (Get-ChildItem -LiteralPath $mirror -File)) {
        if ($textExt -contains $f.Extension.ToLowerInvariant()) {
            $items += @{ src = $f.FullName; name = ('mirror_text\' + $f.Name); purpose = '镜像存档：历史脚本/配置副本' }
        } else {
            $notIncluded += ('mirror\{0}（非文本资产，{1} 字节，SHA256 {2}；按规矩只登记不入包）' -f $f.Name, $f.Length, (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)
        }
    }
}
$notIncluded += '凭据、令牌、登录态（微信登录态、API Key、.credentials 等）——永不入包，是规矩不是缺失'

# ---- 无变化检查：关键件哈希集与上一包 manifest 全同则不建包 ----
$srcFp = @()
$fpExclude = @('board.jsonl', 'activity.jsonl', 'ledger.md')
foreach ($it in $items) { if ($fpExclude -contains $it.name) { continue }; if (Test-Path -LiteralPath $it.src) { $srcFp += ($it.name + '|' + (Get-FileHash -LiteralPath $it.src -Algorithm SHA256).Hash) } }
$srcFp = $srcFp | Sort-Object
if ($prev) {
    $pm = Get-Content -LiteralPath (Join-Path $prev.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $srcNames = @($items | ForEach-Object { $_.name })
    $prevFp = @($pm.files | Where-Object { ($srcNames -contains $_.name) -and ($fpExclude -notcontains $_.name) } | ForEach-Object { $_.name + '|' + $_.sha256 }) | Sort-Object
    if (($srcFp -join "`n") -eq ($prevFp -join "`n")) {
        return ('NOCHANGE:' + $prev.Name)
    }
}

# ---- 建包 ----
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$files = @()
$missing = @()
foreach ($it in $items) {
    if (Test-Path -LiteralPath $it.src) {
        $dst = Join-Path $dir $it.name
        $parent = [IO.Path]::GetDirectoryName($dst)
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $it.src -Destination $dst -Force
        $fi = Get-Item -LiteralPath $dst
        $files += [ordered]@{ name = $it.name; sha256 = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash; bytes = $fi.Length; purpose = $it.purpose }
    } else { $missing += $it.name }
}

# ---- BOOT.md：模板 + 时间/路径 + 第一屏三行 ----
$tplPath = Join-Path $archive 'BOOT_template.md'
if (-not (Test-Path -LiteralPath $tplPath)) { throw 'BOOT_template.md 缺失，先报备掌柜' }
$tpl = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8
$boot = '<!-- 打包时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' -->' + "`r`n" +
        '<!-- 包路径：' + $dir + ' -->' + "`r`n`r`n" +
        '> **本包用途**：龙门客栈全量存档，用于新会话从零恢复。' + "`r`n" +
        '> **读取顺序**：本卡 → STATE_LOG.md → 对应记忆件 → board/ledger 最近记录。' + "`r`n" +
        '> **读完先汇报三件事**：①身份（客官/掌柜/大厨）②待办（open_items + 总线在办单）③上次停在哪（最近交付与未结案）。汇报完等指令。' + "`r`n`r`n" +
        $tpl
$bootPath = Join-Path $dir 'BOOT.md'
[IO.File]::WriteAllText($bootPath, $boot, (New-Object Text.UTF8Encoding($false)))
$bfi = Get-Item -LiteralPath $bootPath
$files = @([ordered]@{ name = 'BOOT.md'; sha256 = (Get-FileHash -LiteralPath $bootPath -Algorithm SHA256).Hash; bytes = $bfi.Length; purpose = '恢复卡：第一读件（模板原样 + 时间/路径 + 三行读法）' }) + $files

# ---- open_items ----
$open = @()
$logPath = Join-Path $archive 'STATE_LOG.md'
if (Test-Path -LiteralPath $logPath) {
    $lines = Get-Content -LiteralPath $logPath -Encoding UTF8
    $inSec = $false
    foreach ($ln in $lines) {
        if ($ln -match '^##\s*7\.') { $inSec = $true; continue }
        if ($inSec -and $ln -match '^##\s*8\.') { break }
        if ($inSec -and $ln.Trim() -match '^(在办|待验|押后)') { $open += $ln.Trim() }
    }
}

# ---- CHANGES.md（与上一包按哈希比对） ----
$chg = @()
if ($prev) {
    $pm = Get-Content -LiteralPath (Join-Path $prev.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $prevMap = @{}
    foreach ($pf in $pm.files) { $prevMap[$pf.name] = $pf.sha256 }
    $curMap = @{}
    foreach ($cf in $files) { $curMap[$cf.name] = $cf.sha256 }
    $added = @($curMap.Keys | Where-Object { -not $prevMap.ContainsKey($_) }) | Sort-Object
    $removed = @($prevMap.Keys | Where-Object { -not $curMap.ContainsKey($_) }) | Sort-Object
    $changed = @($curMap.Keys | Where-Object { $prevMap.ContainsKey($_) -and $prevMap[$_] -ne $curMap[$_] }) | Sort-Object
    $chg += ('# CHANGES — ' + $pkg + '（对比 ' + $prev.Name + '）') + "`r`n"
    $chg += '## 新增' + "`r`n"; if ($added.Count) { foreach ($a in $added) { $chg += ('- ' + $a) } } else { $chg += '- （无）' }
    $chg += "`r`n## 变更" + "`r`n"; if ($changed.Count) { foreach ($c in $changed) { $chg += ('- ' + $c) } } else { $chg += '- （无）' }
    $chg += "`r`n## 删除" + "`r`n"; if ($removed.Count) { foreach ($r in $removed) { $chg += ('- ' + $r) } } else { $chg += '- （无）' }
} else {
    $chg = @(('# CHANGES — ' + $pkg), '无上一包可比对（首包）。')
}
[IO.File]::WriteAllText((Join-Path $dir 'CHANGES.md'), ($chg -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
$cfi = Get-Item -LiteralPath (Join-Path $dir 'CHANGES.md')
$files += [ordered]@{ name = 'CHANGES.md'; sha256 = (Get-FileHash -LiteralPath (Join-Path $dir 'CHANGES.md') -Algorithm SHA256).Hash; bytes = $cfi.Length; purpose = '与上一包的变化清单（新增/变更/删除）' }

# ---- manifest.json ----
$manifest = [ordered]@{
    created      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    package      = $pkg
    prev         = $(if ($prev) { $prev.Name } else { '' })
    files        = $files
    open_items   = $open
    not_included = $notIncluded
}
$manPath = Join-Path $dir 'manifest.json'
[IO.File]::WriteAllText($manPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

# ---- drill_result.txt：包内只读自检 ----
$drill = @()
$okCount = 0; $badCount = 0
$man2 = Get-Content -LiteralPath $manPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($f in $man2.files) {
    $fp = Join-Path $dir $f.name
    if (Test-Path -LiteralPath $fp) {
        if ((Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash -eq $f.sha256) { $okCount++ } else { $badCount++; $drill += ('哈希不符 ' + $f.name) }
    } else { $badCount++; $drill += ('缺文件 ' + $f.name) }
}
$cloud = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -like 'xiaozhu_*' }).Count
$drill += ('manifest 可解析：是（' + $man2.files.Count + ' 件）')
$drill += ('哈希对账：通过 ' + $okCount + ' / 异常 ' + $badCount)
$drill += ('BOOT 第一读件：' + $(if (Test-Path (Join-Path $dir 'BOOT.md')) { '在' } else { '缺' }))
$drill += ('云端份：' + $(if ($cloud -gt 0) { '已有 ' + $cloud + ' 件' } else { '待掌柜补' }))
$drill += ('open_items：' + $open.Count + ' 条')
$drillText = ('# 自检 ' + $pkg + ' · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) + "`r`n" + ($drill -join "`r`n")
[IO.File]::WriteAllText((Join-Path $dir 'drill_result.txt'), $drillText, (New-Object Text.UTF8Encoding($false)))
$dres = if ($badCount -eq 0) { '通过' } else { ('异常 ' + $badCount + ' 件') }

# ---- 里程碑 + 保留清理（最近 5 个非里程碑） ----
$msPath = Join-Path $archive 'milestones.txt'
if (-not (Test-Path -LiteralPath $msPath)) {
    [IO.File]::WriteAllText($msPath, "20261107_0450`r`n20261107_0520`r`n", (New-Object Text.UTF8Encoding($false)))
}
$milestones = @(Get-Content -LiteralPath $msPath -Encoding UTF8 | Where-Object { $_.Trim() })
$allPkgs = @(Get-ChildItem -LiteralPath $archive -Directory | Sort-Object LastWriteTime -Descending)
$nonMs = @($allPkgs | Where-Object { $milestones -notcontains $_.Name })
$pruned = @()
if ($nonMs.Count -gt 5) {
    foreach ($old in ($nonMs | Select-Object -Skip 5)) {
        $sz = (Get-ChildItem -LiteralPath $old.FullName -Recurse -File | Measure-Object Length -Sum).Sum
        Remove-Item -LiteralPath $old.FullName -Recurse -Force
        $pruned += ($old.Name + '（' + $sz + ' B）')
    }
}

# ---- INDEX.md ----
$idx = @('# 存档索引 · 龙门客栈', '', ('更新时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), '',
         '| 包名 | 时间 | 件数 | open_items | 云端份 | 里程碑 | 自检 |',
         '| --- | --- | --- | --- | --- | --- | --- |')
foreach ($d in (Get-ChildItem -LiteralPath $archive -Directory | Sort-Object Name -Descending)) {
    $mp = Join-Path $d.FullName 'manifest.json'
    $cnt = 0; $oc = 0; $dt = ''
    if (Test-Path -LiteralPath $mp) {
        try { $mj = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json; $cnt = $mj.files.Count; $oc = $mj.open_items.Count; $dt = $mj.created } catch { }
    }
    $cloudN = @(Get-ChildItem -LiteralPath $d.FullName -File | Where-Object { $_.Name -like 'xiaozhu_*' }).Count
    $isMs = if ($milestones -contains $d.Name) { '★' } else { '' }
    $dr = ''
    $drp = Join-Path $d.FullName 'drill_result.txt'
    if (Test-Path -LiteralPath $drp) { $dr = if ((Get-Content -LiteralPath $drp -Raw -Encoding UTF8) -match '异常 0') { '通过' } else { '有异常' } }
    $idx += ('| ' + $d.Name + ' | ' + $dt + ' | ' + $cnt + ' | ' + $oc + ' | ' + $(if ($cloudN -gt 0) { '齐' } else { '待补' }) + ' | ' + $isMs + ' | ' + $dr + ' |')
}
[IO.File]::WriteAllText((Join-Path $archive 'INDEX.md'), ($idx -join "`r`n"), (New-Object Text.UTF8Encoding($false)))

# ---- 发帖（仅真建包） ----
$text = '存档请求：新包 ' + $dir + '（全量：BOOT.md + manifest.json + ' + $files.Count + ' 件；open_items ' + $open.Count + ' 条；自检 ' + $dres + '）'
if ($missing.Count -gt 0) { $text += '；缺：' + ($missing -join ', ') }
$posted = & $bus post -From '存档' -To 'all' -Kind 'task' -Ref '存档请求' -Text $text
if ($pruned.Count -gt 0) {
    & $bus post -From '存档' -To 'all' -Kind 'status' -Ref '存档保留' -Text ('自动清理旧包：' + ($pruned -join '、')) | Out-Null
}
if (-not ($posted -match 'posted')) { throw ('bus 发帖失败：' + ($posted -join ' ')) }

Set-Content -LiteralPath (Join-Path $archive 'last_archive.txt') -Value $dir -Encoding UTF8

if ($missing.Count -gt 0) { throw ('存档已建但缺少：' + ($missing -join ', ')) }
return $dir

} finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}