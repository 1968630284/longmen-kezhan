# UI-05 验收：扫描截图下半部分，找横贯且与主背景不同的实线行。
# 两个取样区：全宽（输入区顶部横线）+ 输入区宽度（输入框上下边框）。
# 用于证明「底部两条线」已清除，并与改前截图做量化对照。
param([string[]]$Path = @('D:\tmp\nailong\reports\ui_UI05_light.jpg'))
Add-Type -AssemblyName System.Drawing

# 用容差排除 JPEG 压缩噪点、主背景与输入区底色，只保留真正的装饰线颜色
function Test-IsRule($hex) {
    if (-not $hex -or $hex.Length -ne 7) { return $false }
    try {
        $r = [Convert]::ToInt32($hex.Substring(1,2),16)
        $g = [Convert]::ToInt32($hex.Substring(3,2),16)
        $b = [Convert]::ToInt32($hex.Substring(5,2),16)
    } catch { return $false }
    if ($r -ge 245 -and $g -ge 245 -and $b -ge 245) { return $false }
    if ($r -le 20 -and $g -le 20 -and $b -le 20) { return $false }
    foreach ($base in @('#F2F6FB','#1C2C3E','#172432','#182430','#22303F','#F7FAFD')) {
        $br = [Convert]::ToInt32($base.Substring(1,2),16)
        $bg = [Convert]::ToInt32($base.Substring(3,2),16)
        $bb = [Convert]::ToInt32($base.Substring(5,2),16)
        if (([Math]::Abs($r-$br) + [Math]::Abs($g-$bg) + [Math]::Abs($b-$bb)) -le 24) { return $false }
    }
    return $true
}

function Scan-Range($bmp, $y, $x0, $x1, $need) {
    $cnt = @{}
    for ($x = $x0; $x -lt $x1; $x += 2) {
        $c = $bmp.GetPixel($x, $y)
        $key = '{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
        if (-not $cnt.ContainsKey($key)) { $cnt[$key] = 0 }
        $cnt[$key]++
    }
    $top = $cnt.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1
    $total = [Math]::Ceiling(($x1 - $x0) / 2)
    if ($top.Value -ge $total * $need) { return ('#' + $top.Key) }
    return ''
}

foreach ($file in $Path) {
    if (-not (Test-Path -LiteralPath $file)) { "MISSING: $file"; continue }
    $bmp = New-Object System.Drawing.Bitmap($file)
    $w = $bmp.Width; $h = $bmp.Height
    $from = [int]($h * 0.70)
    $fullRight = $w - 20
    $lines = @()
    for ($y = $from; $y -lt $h; $y++) {
        $c1 = Scan-Range $bmp $y 20 $fullRight 0.90
        $c2 = Scan-Range $bmp $y 220 900 0.90
        foreach ($hex in @($c1, $c2)) {
            if (Test-IsRule $hex) {
                if (-not ($lines | Where-Object { $_.Y -eq $y -and $_.Hex -eq $hex })) {
                    $lines += [pscustomobject]@{ Y = $y; Hex = $hex }
                }
            }
        }
    }
    "--- $(Split-Path $file -Leaf) (${w}x${h}) ---"
    $lines = @($lines | Sort-Object Y)
    if ($lines.Count -eq 0) {
        "bottom_rule_lines = NONE"
    } else {
        "bottom_rule_lines = $($lines.Count) rows"
        $groups = @()
        $cur = $null
        foreach ($l in $lines) {
            if ($null -eq $cur) { $cur = [pscustomobject]@{ Y0 = $l.Y; Y1 = $l.Y; Hex = $l.Hex } }
            elseif ($l.Y -eq $cur.Y1 + 1 -and $l.Hex -eq $cur.Hex) { $cur.Y1 = $l.Y }
            else { $groups += $cur; $cur = [pscustomobject]@{ Y0 = $l.Y; Y1 = $l.Y; Hex = $l.Hex } }
        }
        if ($cur) { $groups += $cur }
        foreach ($g in $groups) { "  y=$($g.Y0)-$($g.Y1)  $($g.Hex)" }
    }
    $bmp.Dispose()
}
