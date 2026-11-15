param([string]$Path = 'D:\tmp\nailong\reports\ui_review_rebuild_light.jpg')
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($Path)
$w = $bmp.Width; $h = $bmp.Height
"image = ${w}x${h}"
$lineRows = @()
$bg = @{}
for ($y = 0; $y -lt [Math]::Min(160, $h); $y++) {
    $cnt = @{}
    for ($x = 0; $x -lt $w; $x += 4) {
        $c = $bmp.GetPixel($x, $y)
        $key = '{0:X2}{1:X2}{2:X2}' -f $c.R, $c.G, $c.B
        if (-not $cnt.ContainsKey($key)) { $cnt[$key] = 0 }
        $cnt[$key]++
    }
    $top = $cnt.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    $total = [Math]::Ceiling($w / 4)
    if ($top.Value -ge $total * 0.6 -and $top.Key -eq 'E1E9F1') { $lineRows += $y }
    if ($y -ge 20 -and $y -le 100) {
        if (-not $bg.ContainsKey($top.Key)) { $bg[$top.Key] = 0 }
        $bg[$top.Key]++
    }
}
"divider_rows_E1E9F1 = " + $(if ($lineRows.Count) { $lineRows -join ',' } else { 'NONE (已移除)' })
"titlebar_bg = " + (($bg.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name)
"pure_white = " + ($bg.ContainsKey('FFFFFF') -and $bg['FFFFFF'] -gt 40)
$bmp.Dispose()
