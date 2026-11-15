param([string]$Path = 'C:\Users\余佳凯\.workbuddy\clipboard-images\clipboard-2026-11-15T07-02-39-794Z-5075e37d.png')
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($Path)
$w = $bmp.Width; $h = $bmp.Height
"size = ${w}x${h}"
$rows = @()
for ($y = 0; $y -lt $h; $y++) {
    $cnt = @{}
    for ($x = 0; $x -lt $w; $x += 3) {
        $c = $bmp.GetPixel($x, $y)
        $key = '{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
        if (-not $cnt.ContainsKey($key)) { $cnt[$key] = 0 }
        $cnt[$key]++
    }
    $top = $cnt.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1
    $rows += [pscustomobject]@{ Y = $y; Hex = '#' + $top.Key; N = $top.Value; Total = [Math]::Ceiling($w / 3) }
}
"--- 每一行主色占比 >= 60% 的行（横贯全宽的线/底色）---"
foreach ($r in $rows) {
    if ($r.N -ge $r.Total * 0.6) {
        '{0,4}  {1}  {2}/{3}' -f $r.Y, $r.Hex, $r.N, $r.Total
    }
}
"--- 关键位置取样 ---"
foreach ($y in @(0, 2, 8, 20, 34, 48, ([Math]::Max(0, $h - 4)), ([Math]::Max(0, $h - 2)), ([Math]::Max(0, $h - 1)))) {
    if ($y -lt $h) {
        $samples = @()
        foreach ($x in @(5, [int]($w * 0.25), [int]($w * 0.5), [int]($w * 0.75), ($w - 5))) {
            $c = $bmp.GetPixel($x, $y)
            $samples += ('#{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B)
        }
        'y={0,3}: {1}' -f $y, ($samples -join '  ')
    }
}
$bmp.Dispose()
