# 存档打包：状态日志 + 双人记忆 + 总线
# 由应用顶栏「存档」按钮调用，也可独立运行。
# 不做 exit：被应用内 & 调用时 exit 会带走宿主进程；出错一律 throw，由调用方处理。

$ErrorActionPreference = 'Stop'

$root = 'D:\tmp\nailong'
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir = Join-Path $root ("archive\" + $stamp)
if (Test-Path -LiteralPath $dir) {
    $i = 2
    while (Test-Path -LiteralPath ($dir + "-$i")) { $i++ }
    $dir = $dir + "-$i"
}
New-Item -ItemType Directory -Path $dir -Force | Out-Null

$items = @(
    @{ src = (Join-Path $root 'archive\STATE_LOG.md');           name = 'STATE_LOG.md' },
    @{ src = (Join-Path $root 'handoff\gongbing_memory.md');    name = 'gongbing_memory.md' },
    @{ src = 'C:\Users\余佳凯\.dsh\AGENTS.md';                  name = 'AGENTS.md' },
    @{ src = (Join-Path $root 'ledger.md');                     name = 'ledger.md' },
    @{ src = (Join-Path $root 'bus\board.jsonl');               name = 'board.jsonl' }
)

$missing = @()
foreach ($it in $items) {
    if (Test-Path -LiteralPath $it.src) {
        Copy-Item -LiteralPath $it.src -Destination (Join-Path $dir $it.name) -Force
    } else {
        $missing += $it.name
    }
}

$lines = @()
foreach ($f in (Get-ChildItem -LiteralPath $dir -File | Sort-Object Name)) {
    $lines += ("{0}`t{1}`t{2}" -f $f.Name, $f.Length, (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)
}
[IO.File]::WriteAllText((Join-Path $dir '_manifest.txt'), ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))

$bus = Join-Path $root 'bus\bus.ps1'
$text = '存档请求：新包 ' + $dir + '（STATE_LOG.md / gongbing_memory.md / AGENTS.md / ledger.md / board.jsonl）'
if ($missing.Count -gt 0) { $text += '；缺：' + ($missing -join ', ') } else { $text += '；五件齐' }

# 直接以脚本方式调用 bus.ps1（post 分支不 exit；异常会冒泡给调用方）
$posted = & $bus post -From '存档' -To 'all' -Kind 'task' -Ref '存档请求' -Text $text
if (-not ($posted -match 'posted')) { throw ("bus 发帖失败：" + ($posted -join ' ')) }

Set-Content -LiteralPath (Join-Path $root 'archive\last_archive.txt') -Value $dir -Encoding UTF8

if ($missing.Count -gt 0) { throw ("存档已建但缺少：" + ($missing -join ', ')) }
return $dir