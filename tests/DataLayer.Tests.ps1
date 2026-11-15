# ARCH-01 / S0 · 数据层特征测试（Pester 3.4.0 兼容）
# 目的：在 S1「读侧增量偏移」重构之前，把当前可观察行为锁成黄金基线。
# 方法：不改主程序，从 xiaozhu_live.ps1 提取纯数据层函数并 dot-source 到本作用域。
# 注意：只提取不依赖 WPF / 控件的函数，因此无需加载 PresentationFramework。

$ErrorActionPreference = 'Stop'

$Main     = 'D:\tmp\xiaozhu_live.ps1'
$RealFeed = 'D:\tmp\muse_feed.json'
$RealBus  = 'D:\tmp\nailong\bus'
$Src      = [IO.File]::ReadAllLines($Main, [Text.Encoding]::UTF8)

function Find-LineIndex([string[]]$lines, [string]$pattern) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) { return $i }
    }
    throw "marker not found: $pattern"
}
function Get-Block([string[]]$lines, [string]$startPattern, [string]$endPattern) {
    $a = Find-LineIndex $lines $startPattern
    $b = Find-LineIndex $lines $endPattern
    if ($b -le $a) { throw "bad block: $startPattern -> $endPattern" }
    return ($lines[$a..($b - 1)] -join "`n")
}

# 三段纯数据层代码：缓存基础 + Read-Feed / Read-BusJsonl + Add-BusJsonl / Convert-FeedTime + Read-MergedFeed
$DataCode = (@(
    (Get-Block $Src '^function Get-FileStamp'   '^function Append-Feed'),
    (Get-Block $Src '^function Read-BusJsonl'    '^function Get-RoleInfo'),
    (Get-Block $Src '^function Convert-FeedTime' '^function New-MsgBubble'),
    (Get-Block $Src '^# ==== UI-02 纯函数区'    '^# ==== UI-02 END')
) -join "`n") + "`n" + '$Utf8 = New-Object Text.UTF8Encoding $false'

# 先指向真实数据（只读），供黄金断言使用
$FeedFile = $RealFeed
$BusRoot  = $RealBus
. ([scriptblock]::Create($DataCode))

# 黄金基线以「主脚本函数实际读出来的结果」为准，不独立重解析 JSON：
# board.jsonl 里存在 ConvertFrom-Json 处理不了的行，主脚本逐行 try/catch 会静默跳过，
# 这本身就是需要锁定的当前行为（S1 增量读重构时不得改变跳过语义）。
$rawFeedObjs   = @(Read-Feed)
$rawBoardObjs  = @(Read-BusJsonl 'board.jsonl')
$rawFeedLines  = @([IO.File]::ReadAllLines($RealFeed, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
$rawBoardLines = @([IO.File]::ReadAllLines((Join-Path $RealBus 'board.jsonl'), [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
$mirrorCount    = @($rawBoardObjs | Where-Object { [string]$_.ref -eq 'mirror' }).Count
$expectedMerged = $rawFeedObjs.Count + $rawBoardObjs.Count - $mirrorCount

Describe 'S0 黄金基线 · 真实数据只读' {
    It 'Read-Feed 结果不超过源文件非空行数（损坏行静默跳过）' {
        (@(Read-Feed).Count -le $rawFeedLines.Count) | Should Be $true
    }

    It 'Read-BusJsonl 结果不超过 board 非空行数（损坏行静默跳过）' {
        (@(Read-BusJsonl 'board.jsonl').Count -le $rawBoardLines.Count) | Should Be $true
    }

    It 'Read-MergedFeed 条数 = feed + board - mirror' {
        @(Read-MergedFeed).Count | Should Be $expectedMerged
    }

    It '合并结果字段齐全' {
        $first = @(Read-MergedFeed)[0]
        foreach ($f in @('n','when','ts','sender','kind','text')) {
            ($first.PSObject.Properties.Name -contains $f) | Should Be $true
        }
    }

    It '合并结果按 when 升序（Sort-Object when,n 的行为）' {
        $when = @((Read-MergedFeed) | ForEach-Object { $_.when })
        $outOfOrder = 0
        for ($i = 1; $i -lt $when.Count; $i++) {
            if ($when[$i] -lt $when[$i - 1]) { $outOfOrder++ }
        }
        $outOfOrder | Should Be 0
    }

    It '文件未变时命中缓存，二次调用远快于冷解析' {
        [void](Read-MergedFeed)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        [void](Read-MergedFeed)
        $sw.Stop()
        ($sw.ElapsedMilliseconds -lt 150) | Should Be $true
    }

    It '同一文件指纹下两次结果条数一致' {
        $a = @(Read-MergedFeed).Count
        $b = @(Read-MergedFeed).Count
        $a | Should Be $b
    }
}

Describe 'S0 Convert-FeedTime · 固定时钟下的确定性规则' {
    $fixedNow = Get-Date '2026-11-13 12:00:00'

    It '带日期的字符串按原日期解析' {
        (Convert-FeedTime '2026-11-01 08:30:00' $fixedNow).ToString('yyyy-MM-dd HH:mm:ss') | Should Be '2026-11-01 08:30:00'
    }

    It '纯 HH:mm:ss 按今天补齐，时分秒不变' {
        (Convert-FeedTime '10:00:00' $fixedNow).ToString('HH:mm:ss') | Should Be '10:00:00'
    }

    It '比当前晚 5 分钟以上的纯时间回退到前一天（跨天修正）' {
        (Convert-FeedTime '23:59:59' $fixedNow).ToString('yyyy-MM-dd') | Should Be '2026-11-12'
    }

    It '非法输入回退为传入的 now' {
        (Convert-FeedTime 'not-a-time' $fixedNow).ToString('yyyy-MM-dd HH:mm:ss') | Should Be '2026-11-13 12:00:00'
    }
}

# ---- 临时沙箱：缓存失效 / 截断重建 / mirror 过滤 / 首行简报 / 写入格式 ----
$Tmp     = Join-Path $env:TEMP ('nailong_s0_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$TmpBus  = Join-Path $Tmp 'bus'
$TmpFeed = Join-Path $Tmp 'feed.json'
[void](New-Item -ItemType Directory -Path $TmpBus -Force)
$Utf8NoBom = New-Object Text.UTF8Encoding($false)

$longText = ('A' * 120)
$seedBoard = @(
    '{"ts":"2026-11-13 10:01:00","from":"X","kind":"note","text":"b1","ref":"","id":"1"}',
    '{"ts":"2026-11-13 10:02:00","from":"Y","kind":"note","text":"mirror-hidden","ref":"mirror","id":"2"}',
    ('{"ts":"2026-11-13 10:03:00","from":"Z","kind":"task","text":"' + $longText + '","ref":"","id":"3"}')
) -join "`n"
$seedFeed = @(
    '{"ts":"2026-11-13 10:00:00","sender":"A","kind":"note","text":"alpha"}',
    '{"ts":"2026-11-13 10:00:30","sender":"B","kind":"note","text":"beta"}'
) -join "`n"

function Reset-Sandbox {
    [IO.File]::WriteAllText((Join-Path $TmpBus 'board.jsonl'), ($seedBoard + "`n"), $Utf8NoBom)
    [IO.File]::WriteAllText($TmpFeed, ($seedFeed + "`n"), $Utf8NoBom)
    $script:FileState    = @{}
    $script:ReadStats    = @{}
    $script:MergedCache  = $null
    $script:MergedSig    = ''
    $script:MergedState  = $null
    $script:FeedFile     = $TmpFeed
    $script:BusRoot      = $TmpBus
}

Reset-Sandbox

Describe 'S0 临时沙箱 · 数据层语义' {
    It 'ref=mirror 的板帖不进入合并时间线' {
        @(Read-MergedFeed).Count | Should Be 4
        $texts = @((Read-MergedFeed) | ForEach-Object { $_.text }) -join '|'
        ($texts -match 'mirror-hidden') | Should Be $false
    }

    It '板上 task/result/decision 长文只显首行简报（≤60 字 + 省略号）' {
        $t = @((Read-MergedFeed) | Where-Object { $_.kind -eq 'task' } | ForEach-Object { $_.text })[0]
        ($t.Length -le 62) | Should Be $true
        ($t.EndsWith(' …')) | Should Be $true
    }

    It '追加一条 feed 后缓存失效，新增消息可见' {
        [void](Read-MergedFeed)
        [IO.File]::AppendAllText($TmpFeed, '{"ts":"2026-11-13 10:04:00","sender":"C","kind":"note","text":"gamma"}' + "`n", $Utf8NoBom)
        $m = @(Read-MergedFeed)
        $m.Count | Should Be 5
        (($m | ForEach-Object { $_.text }) -join '|' -match 'gamma') | Should Be $true
    }

    It '文件被截断（长度变短）时整表重建，不残留旧条目' {
        [IO.File]::WriteAllText($TmpFeed, '{"ts":"2026-11-13 10:00:00","sender":"A","kind":"note","text":"only-one"}' + "`n", $Utf8NoBom)
        $m = @(Read-MergedFeed)
        $m.Count | Should Be 3
        (($m | ForEach-Object { $_.text }) -join '|' -match 'beta') | Should Be $false
    }

    It '文件指纹未变时复用解析结果' {
        [void](Read-MergedFeed)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        [void](Read-MergedFeed)
        $sw.Stop()
        ($sw.ElapsedMilliseconds -lt 150) | Should Be $true
    }

    It 'Add-BusJsonl 追加一行合法 JSON 且字段齐全' {
        $before = @(Read-BusJsonl 'board.jsonl').Count
        Add-BusJsonl 'board.jsonl' ([ordered]@{
            ts = '2026-11-13 10:05:00'; from = 'TEST'; to = 'all'
            kind = 'status'; text = 's0-write-check'; ref = ''; id = 's0test01'
        })
        $lines = @([IO.File]::ReadAllLines((Join-Path $TmpBus 'board.jsonl'), [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
        $lines.Count | Should Be ($before + 1)
        $obj = $lines[-1] | ConvertFrom-Json
        $obj.from | Should Be 'TEST'
        $obj.text | Should Be 's0-write-check'
    }

    It 'S1 文件未变 → Mode=cache / Parsed=0' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        [void](Read-BusJsonl 'board.jsonl')
        $script:ReadStats['bus:board.jsonl'].Mode | Should Be 'cache'
        $script:ReadStats['bus:board.jsonl'].Parsed | Should Be 0
    }

    It 'S1 追加 1 行 → Mode=append / 只解析 1 行' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        [IO.File]::AppendAllText((Join-Path $TmpBus 'board.jsonl'), '{"ts":"2026-11-13 10:06:00","from":"N","kind":"note","text":"s1-append","ref":"","id":"s1a"}' + "`n", $Utf8NoBom)
        [void](Read-BusJsonl 'board.jsonl')
        $script:ReadStats['bus:board.jsonl'].Mode | Should Be 'append'
        $script:ReadStats['bus:board.jsonl'].Parsed | Should Be 1
        @(Read-BusJsonl 'board.jsonl').Count | Should Be 4
    }

    It 'S1 末尾半行留缓冲，补齐换行后只解析 1 行' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        $bp = Join-Path $TmpBus 'board.jsonl'
        [IO.File]::AppendAllText($bp, '{"ts":"2026-11-13 10:07:00","from":"P","kind":"note","text":"half"', $Utf8NoBom)
        @(Read-BusJsonl 'board.jsonl').Count | Should Be 3
        $script:ReadStats['bus:board.jsonl'].Parsed | Should Be 0
        [IO.File]::AppendAllText($bp, ',"ref":"","id":"s1p"}' + "`n", $Utf8NoBom)
        @(Read-BusJsonl 'board.jsonl').Count | Should Be 4
        $script:ReadStats['bus:board.jsonl'].Parsed | Should Be 1
    }

    It 'S1 文件被截断 → Mode=rebuild，不残留旧条目' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        [IO.File]::WriteAllText((Join-Path $TmpBus 'board.jsonl'), '{"ts":"2026-11-13 10:09:00","from":"R","kind":"note","text":"only","ref":"","id":"s1r"}' + "`n", $Utf8NoBom)
        @(Read-BusJsonl 'board.jsonl').Count | Should Be 1
        $script:ReadStats['bus:board.jsonl'].Mode | Should Be 'rebuild'
    }

    It 'S1 Reset-JsonlCache 后强制整表重建' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        Reset-JsonlCache
        [void](Read-BusJsonl 'board.jsonl')
        $script:ReadStats['bus:board.jsonl'].Mode | Should Be 'rebuild'
    }

    It 'S2 增量合并与全量重排逐条一致' {
        Reset-Sandbox
        $before = @(Read-MergedFeed)
        $bp = Join-Path $TmpBus 'board.jsonl'
        [IO.File]::AppendAllText($bp, '{"ts":"2026-11-13 10:10:00","from":"N1","kind":"note","text":"inc1","ref":"","id":"i1"}' + "`n", $Utf8NoBom)
        [IO.File]::AppendAllText($bp, '{"ts":"2026-11-13 10:11:00","from":"N2","kind":"note","text":"inc2","ref":"","id":"i2"}' + "`n", $Utf8NoBom)
        $inc = @(Read-MergedFeed)
        $inc.Count | Should Be ($before.Count + 2)
        # 清掉合并签名与状态，强制走全量重排
        $script:MergedSig = ''; $script:MergedState = $null; $script:MergedCache = $null
        $full = @(Read-MergedFeed)
        $inc.Count | Should Be $full.Count
        $same = $true
        for ($k = 0; $k -lt $inc.Count; $k++) {
            if (([string]$inc[$k].sender -ne [string]$full[$k].sender) -or
                ([string]$inc[$k].kind -ne [string]$full[$k].kind) -or
                ([string]$inc[$k].text -ne [string]$full[$k].text) -or
                ($inc[$k].when -ne $full[$k].when)) { $same = $false; break }
        }
        $same | Should Be $true
    }

    It 'S2 新条目时间早于现有最大值时回退全量重排' {
        Reset-Sandbox
        [void](Read-MergedFeed)
        $bp = Join-Path $TmpBus 'board.jsonl'
        [IO.File]::AppendAllText($bp, '{"ts":"2026-11-13 09:00:00","from":"OLD","kind":"note","text":"early","ref":"","id":"e1"}' + "`n", $Utf8NoBom)
        $m = @(Read-MergedFeed)
        [string]$m[0].text | Should Be 'early'
        $ok = $true
        for ($k = 1; $k -lt $m.Count; $k++) { if ($m[$k].when -lt $m[$k - 1].when) { $ok = $false; break } }
        $ok | Should Be $true
    }

    It 'S3 多点锚点：文件开头被就地编辑且长度增长时回退全量' {
        Reset-Sandbox
        [void](Read-BusJsonl 'board.jsonl')
        $bp = Join-Path $TmpBus 'board.jsonl'
        $text = [IO.File]::ReadAllText($bp, [Text.Encoding]::UTF8)
        # 改写开头行 + 末尾追加一行：旧版单一尾部锚点会误判成 append，多点锚点应察觉
        $edited = $text.Replace('"text":"b1"', '"text":"b1-EDITED"') + '{"ts":"2026-11-13 10:12:00","from":"Q","kind":"note","text":"tail","ref":"","id":"q1"}' + "`n"
        [IO.File]::WriteAllText($bp, $edited, $Utf8NoBom)
        $items = @(Read-BusJsonl 'board.jsonl')
        $script:ReadStats['bus:board.jsonl'].Mode | Should Be 'rebuild'
        $joined = ($items | ForEach-Object { [string]$_.text }) -join '|'
        ($joined -match 'b1-EDITED') | Should Be $true
    }
}

# ==== UI-02：连续消息分组与时间戳统一（纯函数，不需要 WPF）====
Describe 'UI-02 Format-UiTime · 时间戳统一' {
    It 'HH:mm:ss 显示为 HH:mm' { (Format-UiTime '20:36:00') | Should Be '20:36' }
    It '完整日期时间显示为 HH:mm' { (Format-UiTime '2026-11-06 23:28:54') | Should Be '23:28' }
    It '旧连字符写法显示为 HH:mm' { (Format-UiTime '20-50-03') | Should Be '20:50' }
    It '空串原样返回' { (Format-UiTime '') | Should Be '' }
    It '无法识别的字符串原样返回' { (Format-UiTime 'unknown') | Should Be 'unknown' }
    It '真实合并数据所有 ts 均可格式化为 HH:mm' {
        $bad = @(Read-MergedFeed | Where-Object { (Format-UiTime ([string]$_.ts)) -notmatch '^\d{2}:\d{2}$' })
        $bad.Count | Should Be 0
    }
}
Describe 'UI-02 Test-UiGrouping · 分组边界' {
    $t0 = [datetime]'2026-11-15 20:00:00'
    $d0 = '2026-11-15'
    It '同一发送者 30 秒内合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(30) 'note' $d0 '') | Should Be $true
    }
    It '恰好 60 秒仍合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(60) 'note' $d0 '') | Should Be $true
    }
    It '超过 60 秒不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(61) 'note' $d0 '') | Should Be $false
    }
    It '不同发送者不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'B' $t0.AddSeconds(10) 'note' $d0 '') | Should Be $false
    }
    It '系统消息不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(10) 'status' $d0 '') | Should Be $false
    }
    It '搜索态不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(10) 'note' $d0 'abc') | Should Be $false
    }
    It '跨天不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddDays(1) 'note' '2026-11-16' '') | Should Be $false
    }
    It '时间倒退不合并' {
        (Test-UiGrouping 'A' $t0 $d0 'A' $t0.AddSeconds(-5) 'note' $d0 '') | Should Be $false
    }
    It '首条消息（无前序）不合并' {
        (Test-UiGrouping $null ([datetime]::MinValue) '' 'A' $t0 'note' $d0 '') | Should Be $false
    }
}

# 恢复真实数据指向（便于后续单独调试），并清理临时沙箱
$FeedFile = $RealFeed
$BusRoot  = $RealBus
$script:FileState   = @{}
$script:ReadStats   = @{}
$script:MergedCache = $null
$script:MergedSig   = ''
$script:MergedState = $null
Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
