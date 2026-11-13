# 存档打包 v2（全量）：状态日志 + 记忆 + 总线 + 桥 + 应用 + 镜像文本
# 由应用左栏「存档」按钮调用，也可独立运行。
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
$pkg = [IO.Path]::GetFileName($dir)

$files = @()
$missing = @()

# ---- 固定件 ----
$items = @(
    @{ src = (Join-Path $root 'archive\STATE_LOG.md');               name = 'STATE_LOG.md';        purpose = '状态日志全文：规矩、现状、教训、恢复流程' },
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

# ---- 镜像文本件（.ps1/.js/.yml/.md 全量；其余只登记不入包） ----
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

foreach ($it in $items) {
    if (Test-Path -LiteralPath $it.src) {
        $dst = Join-Path $dir $it.name
        $parent = [IO.Path]::GetDirectoryName($dst)
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $it.src -Destination $dst -Force
        $fi = Get-Item -LiteralPath $dst
        $files += [ordered]@{ name = $it.name; sha256 = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash; bytes = $fi.Length; purpose = $it.purpose }
    } else {
        $missing += $it.name
    }
}

# ---- BOOT.md（模板 + 头部两行，原样） ----
$tplPath = Join-Path $root 'archive\BOOT_template.md'
if (-not (Test-Path -LiteralPath $tplPath)) { throw 'BOOT_template.md 缺失，先报备掌柜' }
$tpl = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8
$boot = ('<!-- 打包时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' -->' + "`r`n" + '<!-- 包路径：' + $dir + ' -->' + "`r`n" + $tpl)
$bootPath = Join-Path $dir 'BOOT.md'
[IO.File]::WriteAllText($bootPath, $boot, (New-Object Text.UTF8Encoding($false)))
$bfi = Get-Item -LiteralPath $bootPath
$files = @([ordered]@{ name = 'BOOT.md'; sha256 = (Get-FileHash -LiteralPath $bootPath -Algorithm SHA256).Hash; bytes = $bfi.Length; purpose = '恢复卡：新会话第一读件（模板原样 + 打包时间/路径两行）' }) + $files

# ---- open_items：从 STATE_LOG 第 7 节摘「在办/待验/押后」行 ----
$open = @()
$logPath = Join-Path $root 'archive\STATE_LOG.md'
if (Test-Path -LiteralPath $logPath) {
    $lines = Get-Content -LiteralPath $logPath -Encoding UTF8
    $inSec = $false
    foreach ($ln in $lines) {
        if ($ln -match '^##\s*7\.') { $inSec = $true; continue }
        if ($inSec -and $ln -match '^##\s*8\.') { break }
        if ($inSec -and $ln.Trim() -match '^(在办|待验|押后)') { $open += $ln.Trim() }
    }
}

# ---- manifest.json ----
$manifest = [ordered]@{
    created      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    package      = $pkg
    files        = $files
    open_items   = $open
    not_included = $notIncluded
}
$manPath = Join-Path $dir 'manifest.json'
[IO.File]::WriteAllText($manPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

# ---- 发帖给掌柜 ----
$bus = Join-Path $root 'bus\bus.ps1'
$text = '存档请求：新包 ' + $dir + '（全量：BOOT.md + manifest.json + ' + $files.Count + ' 件；open_items ' + $open.Count + ' 条）'
if ($missing.Count -gt 0) { $text += '；缺：' + ($missing -join ', ') }
$posted = & $bus post -From '存档' -To 'all' -Kind 'task' -Ref '存档请求' -Text $text
if (-not ($posted -match 'posted')) { throw ('bus 发帖失败：' + ($posted -join ' ')) }

Set-Content -LiteralPath (Join-Path $root 'archive\last_archive.txt') -Value $dir -Encoding UTF8

if ($missing.Count -gt 0) { throw ('存档已建但缺少：' + ($missing -join ', ')) }
return $dir