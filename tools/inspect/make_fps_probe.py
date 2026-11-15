# UI-06 帧率诊断：从任意版本产物生成「带埋点的临时副本」，产品代码零改动。
# 用法：python make_fps_probe.py <源ps1> <输出ps1> <标签>
# 埋点：CompositionTarget.Rendering 逐帧记录间隔，采样 3 秒静止 + 3 秒持续滚动，
#       输出滚动阶段的 p50/p95/max 帧间隔与 >33ms 长帧数；并统计视觉树规模。
import io, sys, os

src, out, tag = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(src, 'rb').read().decode('utf-8-sig')
anchor = '$win.ShowDialog() | Out-Null'
assert s.count(anchor) == 1, 'ShowDialog anchor count = %d' % s.count(anchor)

PROBE = r'''
# ===== UI-06 FPS PROBE (instrumented copy only; not in shipped source) =====
try {
    $script:__frames = New-Object System.Collections.ArrayList
    $script:__last = [Environment]::TickCount
    $script:__phase = 'idle'
    $script:__idleN = 0
    $script:__scrollN = 0
    $script:__t0 = [Environment]::TickCount
    $script:__t1 = 0
    $script:__off = 0.0
    $script:__step = 0
    [Windows.Media.CompositionTarget]::add_Rendering([System.EventHandler]{
        $now = [Environment]::TickCount
        $d = $now - $script:__last
        $script:__last = $now
        if ($script:__phase -eq 'scroll') {
            [void]$script:__frames.Add($d)
            $script:__scrollN++
        } else { $script:__idleN++ }
    })
    $script:__vis = 0
    $script:__tb = 0
    $script:__tbl = 0
    function Walk-V($v) {
        if ($null -eq $v) { return }
        $script:__vis++
        try {
            if ($v -is [Windows.Controls.TextBox]) { $script:__tb++ }
            elseif ($v -is [Windows.Controls.TextBlock]) { $script:__tbl++ }
        } catch { }
        try {
            $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($v)
            for ($i = 0; $i -lt $n; $i++) { Walk-V ([Windows.Media.VisualTreeHelper]::GetChild($v, $i)) }
        } catch { }
    }
    $script:__feedChildren = 0
    $__scrollT = New-Object Windows.Threading.DispatcherTimer
    $__scrollT.Interval = [TimeSpan]::FromMilliseconds(16)
    $__scrollT.Add_Tick({
        $script:__off += 4
        if ($script:__off -gt $FeedScroll.ScrollableHeight) { $script:__off = 0 }
        $FeedScroll.ScrollToVerticalOffset($script:__off)
    })
    $__phaseT = New-Object Windows.Threading.DispatcherTimer
    $__phaseT.Interval = [TimeSpan]::FromSeconds(3)
    $__phaseT.Add_Tick({
        $script:__step++
        if ($script:__step -eq 1) {
            $script:__idleMs = [Environment]::TickCount - $script:__t0
            $script:__phase = 'scroll'
            $script:__t1 = [Environment]::TickCount
            $script:__last = [Environment]::TickCount
            $__scrollT.Start()
        } elseif ($script:__step -eq 2) {
            $script:__scrollMs = [Environment]::TickCount - $script:__t1
            $__scrollT.Stop(); $__phaseT.Stop()
            # 窗口已 Loaded、气泡已构建，此时统计才有意义
            $script:__vis = 0; $script:__tb = 0; $script:__tbl = 0
            Walk-V $win
            try { $script:__feedChildren = $FeedList.Children.Count } catch { $script:__feedChildren = -1 }
            # 验证「可选中正文 + 右键复制」在委托共享后仍然可用
            $script:__ctx = -1; $script:__copyOk = $false; $script:__firstTb = $null
            function Find-Tb($v) {
                if ($null -eq $v -or $null -ne $script:__firstTb) { return }
                try { if ($v -is [Windows.Controls.TextBox]) { $script:__firstTb = $v; return } } catch { }
                try {
                    $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($v)
                    for ($i = 0; $i -lt $n; $i++) { Find-Tb ([Windows.Media.VisualTreeHelper]::GetChild($v, $i)) }
                } catch { }
            }
            Find-Tb $FeedList
            if ($null -ne $script:__firstTb) {
                try {
                    if ($null -ne $script:UiContextMenuHandler) {
                        & $script:UiContextMenuHandler $script:__firstTb $null
                    }
                    $cm = $script:__firstTb.ContextMenu
                    if ($cm) {
                        $script:__ctx = $cm.Items.Count
                        if ($null -ne $script:UiCopyAllHandler) {
                            [Windows.Clipboard]::SetText('__fps_probe_reset__')
                            & $script:UiCopyAllHandler $cm.Items[1] $null
                            $script:__copyOk = ([Windows.Clipboard]::GetText() -ne '__fps_probe_reset__')
                        }
                    }
                } catch { }
            }
            # 主题切换的核心工作（Apply-Theme + 全量重建气泡）耗时
            $script:__themeMs = -1
            try {
                $__tt = [Environment]::TickCount
                $script:dark = -not $script:dark
                Apply-Theme
                $script:forceRefresh = $true
                Refresh-Feed
                $script:__themeMs = [Environment]::TickCount - $__tt
            } catch { }
            $sorted = @($script:__frames | Sort-Object)
            $p50 = 0; $p95 = 0; $mx = 0; $jank = 0
            if ($sorted.Count -gt 0) {
                $p50 = $sorted[[Math]::Min($sorted.Count - 1, [int]($sorted.Count * 0.50))]
                $p95 = $sorted[[Math]::Min($sorted.Count - 1, [int]($sorted.Count * 0.95))]
                $mx = $sorted[$sorted.Count - 1]
                $jank = @($sorted | Where-Object { $_ -gt 33 }).Count
            }
            $fi = [Math]::Round(1000.0 * $script:__idleN / [Math]::Max(1, $script:__idleMs), 1)
            $fs = [Math]::Round(1000.0 * $script:__scrollN / [Math]::Max(1, $script:__scrollMs), 1)
            $line = (Get-Date -Format 'HH:mm:ss') + ' | fps-probe tag=__TAG__' +
                    ' idle_fps=' + $fi + ' scroll_fps=' + $fs +
                    ' frames=' + $script:__scrollN + '/' + $script:__scrollMs + 'ms' +
                    ' dt_p50=' + $p50 + ' dt_p95=' + $p95 + ' dt_max=' + $mx +
                    ' jank_gt33ms=' + $jank +
                    ' visuals=' + $script:__vis + ' textboxes=' + $script:__tb +
                    ' textblocks=' + $script:__tbl + ' feed_children=' + $script:__feedChildren +
                    ' ctx_items=' + $script:__ctx + ' copy_handler_ok=' + $script:__copyOk +
                    ' theme_switch_ms=' + $script:__themeMs
            [IO.File]::AppendAllText('D:\tmp\nailong\health\fps.log', $line + "`r`n", [Text.Encoding]::UTF8)
            $win.Close()
        }
    })
    $__phaseT.Start()
} catch {
    try {
        [IO.File]::AppendAllText('D:\tmp\nailong\health\fps.log',
            'probe-error tag=__TAG__ : ' + $_.Exception.Message + "`r`n", [Text.Encoding]::UTF8)
    } catch { }
    $win.Close()
}
# ===== END FPS PROBE =====
'''.replace('__TAG__', tag)

s = s.replace(anchor, PROBE + '\n' + anchor, 1)
io.open(out, 'wb').write(('\ufeff' + s).encode('utf-8'))
print('probe written:', out, '| bytes', os.path.getsize(out))
