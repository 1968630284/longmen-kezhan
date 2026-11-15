# UI-05 探针：真实点击「切换主题」按钮，抓切换前后同机位窗口截图，
# 用于复现「运行时深浅切换」是否产生混合主题 / 残留旧色。
param(
    [string]$StartTheme = 'False',
    [string]$OutDir = 'D:\tmp\nailong\reports'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ThemeProbe {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
[void][ThemeProbe]::SetProcessDPIAware()

function Save-Shot($bmpPath) {
    $r = New-Object 'ThemeProbe+RECT'
    [void][ThemeProbe]::GetWindowRect($script:h, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    $pad = 10
    $sx = [Math]::Max(0, $r.Left - $pad); $sy = [Math]::Max(0, $r.Top - $pad)
    $sw = $w + $pad * 2; $sh = $ht + $pad * 2
    $bmp = New-Object System.Drawing.Bitmap $sw, $sh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($sx, $sy, 0, 0, (New-Object System.Drawing.Size $sw, $sh))
    $jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $prm = New-Object System.Drawing.Imaging.EncoderParameters 1
    $prm.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 90
    $bmp.Save($bmpPath, $jpg, $prm)
    $g.Dispose(); $bmp.Dispose()
    "shot = $bmpPath (${sw}x${sh})"
}

$themeFile = 'D:\tmp\live_theme.txt'
$enc = New-Object Text.UTF8Encoding($false)
$orig = [IO.File]::ReadAllText($themeFile, [Text.Encoding]::UTF8).Trim()
"theme_before_probe = $orig"
[IO.File]::WriteAllText($themeFile, $StartTheme, $enc)

$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$p = Start-Process -FilePath $ps -ArgumentList @('-STA','-ExecutionPolicy','Bypass','-File','D:\tmp\xiaozhu_live.ps1','-NoMutex') -PassThru
$script:capPid = [uint32]$p.Id
try {
    Start-Sleep -Seconds 6
    $found = New-Object System.Collections.ArrayList
    $cb = [ThemeProbe+EnumWindowsProc]{
        param($hWnd, $lp)
        $wpid = [uint32]0
        [void][ThemeProbe]::GetWindowThreadProcessId($hWnd, [ref]$wpid)
        if ($wpid -eq $script:capPid -and [ThemeProbe]::IsWindowVisible($hWnd)) {
            $sb = New-Object Text.StringBuilder 256
            [void][ThemeProbe]::GetWindowText($hWnd, $sb, 256)
            [void]$found.Add([pscustomobject]@{ H = $hWnd; Title = $sb.ToString() })
        }
        return $true
    }
    [void][ThemeProbe]::EnumWindows($cb, [IntPtr]::Zero)
    $wnd = @($found | Where-Object { $_.Title -match '龙门客栈' })
    if ($wnd.Count -eq 0) { throw '未找到应用窗口' }
    $script:h = $wnd[0].H
    "hwnd = $($script:h) title = $($wnd[0].Title)"
    $r = New-Object 'ThemeProbe+RECT'
    [void][ThemeProbe]::GetWindowRect($script:h, [ref]$r)
    [void][ThemeProbe]::MoveWindow($script:h, 40, 30, ($r.Right-$r.Left), ($r.Bottom-$r.Top), $true)
    [void][ThemeProbe]::SetWindowPos($script:h, [IntPtr](-1), 0, 0, 0, 0, 0x43)
    [void][ThemeProbe]::SetForegroundWindow($script:h)
    Start-Sleep -Milliseconds 1200
    Save-Shot (Join-Path $OutDir 'ui_switch_before.jpg')

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:h)
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'DarkBtn')
    $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($null -eq $btn) {
        "DarkBtn via AutomationId NOT FOUND; listing buttons:"
        $bc = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $bc)
        foreach ($b in $all) { "  id=[$($b.Current.AutomationId)] name=[$($b.Current.Name)]" }
        throw 'DarkBtn not found'
    }
    "DarkBtn found: name=[$($btn.Current.Name)] id=[$($btn.Current.AutomationId)]"
    $ip = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $ip.Invoke()
    "clicked DarkBtn at $(Get-Date -Format 'HH:mm:ss.fff')"
    Start-Sleep -Seconds 3
    Save-Shot (Join-Path $OutDir 'ui_switch_after.jpg')
    "theme_file_after_click = " + [IO.File]::ReadAllText($themeFile, [Text.Encoding]::UTF8).Trim()
    if (Test-Path 'D:\tmp\theme_err.txt') { "--- theme_err tail ---"; Get-Content 'D:\tmp\theme_err.txt' -Tail 8 }
    "alive = $(-not $p.HasExited)"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -Confirm:$false }
    [IO.File]::WriteAllText($themeFile, $orig, $enc)
    "theme_restored = $orig"
}
