# ARCH-01 / S4 · 源 / 产物一致性守卫
# 重新从 src\ 构建一份，与现役 xiaozhu_live.ps1 比对 SHA256。
# 不一致 = 有人直接改了产物却没回填 src\，或改了 src\ 却没跑 build.ps1。
# 退出码 0 = 同步；1 = 分叉（应停止继续在产物上直接改动）。

$ErrorActionPreference = 'Stop'
$live  = 'D:\tmp\xiaozhu_live.ps1'
$build = 'D:\tmp\nailong\tools\build.ps1'
$tmp   = Join-Path $env:TEMP ('nailong_sync_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')

try {
    & $build -Output $tmp -NoMap | Out-Null
    $a = (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash
    $b = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    if ($a -ne $b) {
        '[FAIL] 现役脚本与 src\ 构建产物不一致，源码与产物已分叉。'
        "  live    = $a"
        "  rebuilt = $b"
        '  处理：若改的是产物，请把改动回填 src\；若改的是 src\，请运行 tools\build.ps1。'
        exit 1
    }
    "[OK] 现役脚本 = src\ 构建产物  SHA256 $a"
    exit 0
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
