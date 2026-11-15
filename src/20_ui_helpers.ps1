# UI-06：共享事件委托。此前每条消息都新建 3 个菜单回调 + 1 个滚轮转发闭包，
# 首屏 72 个只读 TextBox 会产生 288 个闭包/委托；改为脚本级单例，行为完全不变。
$script:UiCopySelectedHandler = { param($s, $ev)
    try { if ($s.Tag.SelectedText) { [Windows.Clipboard]::SetText($s.Tag.SelectedText) } } catch { } }
$script:UiCopyAllHandler = { param($s, $ev)
    try { [Windows.Clipboard]::SetText([string]$s.Tag.Text) } catch { } }
$script:UiSelectAllHandler = { param($s, $ev)
    try { $s.Tag.Focus() | Out-Null; $s.Tag.SelectAll() } catch { } }
# UI-06：右键菜单延迟到首次使用时构造。主题切换会重建 120 条气泡，
# 预先给每条挂 ContextMenu 是重建路径里最没必要的对象开销。
$script:UiContextMenuHandler = { param($s, $ev)
    try { if ($null -eq $s.ContextMenu) { Attach-CopyMenu $s } } catch { } }
$script:UiWheelHandler = { param($s, $ev)
    try {
        $parent = [Windows.Media.VisualTreeHelper]::GetParent($s)
        while ($parent -and -not ($parent -is [Windows.Controls.ScrollViewer])) {
            $parent = [Windows.Media.VisualTreeHelper]::GetParent($parent)
        }
        if ($parent) {
            $parent.ScrollToVerticalOffset($parent.VerticalOffset - ($ev.Delta / 3))
            $ev.Handled = $true
        }
    } catch { } }

function Brush($hex) {
    if (-not $hex) { return (New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::Gray)) }
    $key = [string]$hex
    if ($script:BrushCache.ContainsKey($key)) { return $script:BrushCache[$key] }
    try { $b = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($key)) }
    catch { $b = New-Object Windows.Media.SolidColorBrush([Windows.Media.Colors]::Gray) }
    $script:BrushCache[$key] = $b
    return $b
}

# 消息文字可选中 + 右键复制菜单（留言板 / 聊天流共用）
function Attach-CopyMenu($box) {
    $cm = New-Object Windows.Controls.ContextMenu
    $m1 = New-Object Windows.Controls.MenuItem
    $m1.Header = "复制选中"
    $m1.Tag = $box
    $m1.Add_Click($script:UiCopySelectedHandler)
    $m2 = New-Object Windows.Controls.MenuItem
    $m2.Header = "复制整条"
    $m2.Tag = $box
    $m2.Add_Click($script:UiCopyAllHandler)
    $m3 = New-Object Windows.Controls.MenuItem
    $m3.Header = "全选"
    $m3.Tag = $box
    $m3.Add_Click($script:UiSelectAllHandler)
    $cm.Items.Add($m1) | Out-Null
    $cm.Items.Add($m2) | Out-Null
    $cm.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
    $cm.Items.Add($m3) | Out-Null
    $box.ContextMenu = $cm
}
function New-SelectableText([string]$text, $size, $fore, $lineH, $bg) {
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $text
    $tb.FontSize = $size
    $tb.Foreground = $fore
    $tb.TextWrapping = "Wrap"
    $tb.Margin = New-Object Windows.Thickness(0, 5, 0, 0)
    $tb.IsReadOnly = $true
    $tb.IsReadOnlyCaretVisible = $false
    $tb.IsTabStop = $false
    # UI-06：只读展示不需要撤销栈、拼写检查、拖放与非活动选区高亮
    $tb.IsUndoEnabled = $false
    $tb.AllowDrop = $false
    try { $tb.IsInactiveSelectionHighlightEnabled = $false } catch { }
    try { [Windows.Controls.SpellCheck]::SetIsEnabled($tb, $false) } catch { }
    $tb.BorderThickness = New-Object Windows.Thickness(0)
    # 57 号：可选中正文改不透明底（透明底会让 ClearType 退化成灰度抗锯齿＝字发虚）
if ($bg -and $bg -ne "Transparent") { $tb.Background = Brush $bg } else { $tb.Background = [Windows.Media.Brushes]::Transparent }
try { [Windows.Media.TextOptions]::SetTextFormattingMode($tb, [Windows.Media.TextFormattingMode]::Display) } catch { }
    $tb.Padding = New-Object Windows.Thickness(0)
    $tb.Cursor = [Windows.Input.Cursors]::IBeam
    $tb.VerticalScrollBarVisibility = "Disabled"
    $tb.HorizontalScrollBarVisibility = "Disabled"
    # 只读文本框会吃掉滚轮，转交给外层 ScrollViewer，保证聊天流照样能滚
    $tb.Add_PreviewMouseWheel($script:UiWheelHandler)
    $tb.Add_ContextMenuOpening($script:UiContextMenuHandler)
    return $tb
}

function Read-WindowState {
    $s = @{ left = $null; top = $null; width = 560.0; height = 720.0; big = $false }
    try {
        if (Test-Path $StateFile) {
            $j = [IO.File]::ReadAllText($StateFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($k in @("left", "top", "width", "height")) { if ($null -ne $j.$k) { $s[$k] = [double]$j.$k } }
            if ($null -ne $j.big) { $s["big"] = [bool]$j.big }
        }
    } catch { }
    return $s
}
function Save-WindowState {
    try {
        $rb = $win.RestoreBounds
        $w = if ($rb.Width -ge 420) { $rb.Width } else { $win.Width }
        $h = if ($rb.Height -ge 520) { $rb.Height } else { $win.Height }
        if ($w -lt 420 -or $h -lt 520) { return }
        $j = [ordered]@{
            left   = [double]$rb.X
            top    = [double]$rb.Y
            width  = [double]$w
            height = [double]$h
            big    = [bool]$script:big
        }
        [IO.File]::WriteAllText($StateFile, ($j | ConvertTo-Json), $Utf8)
    } catch { }
}

# ---- 单实例：如果已经开着一个奶龙工坊，就把它叫到前面，不再开第二个 ----
if (-not $NoMutex) {
    $script:MutexNew = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, "NailongLiveRoom.SingleInstance", [ref]$script:MutexNew)
    if (-not $script:MutexNew) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinAct {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    public static bool Activate(string title) {
        IntPtr h = FindWindow(null, title);
        if (h == IntPtr.Zero) return false;
        ShowWindow(h, IsIconic(h) ? 9 : 5);
        return SetForegroundWindow(h);
    }
}
'@
        } catch { }
        try { [WinAct]::Activate("龙门客栈") | Out-Null } catch { }
        exit 0
    }
}

