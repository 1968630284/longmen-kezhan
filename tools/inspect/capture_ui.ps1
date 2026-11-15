# UI-03 评审工具：把「龙门客栈」窗口移到固定位置并临时置顶，只截该窗口区域，
# 避免全屏截图里被 WorkBuddy / 控制台遮挡或窗口超出画面。
# 用法：& capture_ui.ps1 -Out <jpg路径> [-Theme True|False]
param(
    [string]$Out = 'D:\tmp\nailong\reports\ui_review.jpg',
    [string]$Theme = '',
    [string]$ScriptPath = 'D:\tmp\xiaozhu_live.ps1'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class UiCap {
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

# 关键：截图进程必须 DPI-aware，否则 GetWindowRect / CopyFromScreen 坐标被虚拟化，
# 截图会只覆盖窗口的一部分，看起来像「内容被右边缘裁切」。
[void][UiCap]::SetProcessDPIAware()

$script:capPid = 0
$script:capFound = New-Object System.Collections.ArrayList

$themeFile = 'D:\tmp\live_theme.txt'
$enc = New-Object Text.UTF8Encoding($false)
$orig = [IO.File]::ReadAllText($themeFile, [Text.Encoding]::UTF8).Trim()
if ($Theme) { [IO.File]::WriteAllText($themeFile, $Theme, $enc) }

$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$p = Start-Process -FilePath $ps -ArgumentList @('-STA','-ExecutionPolicy','Bypass','-File',$ScriptPath,'-NoMutex') -PassThru
$script:capPid = [uint32]$p.Id
try {
    Start-Sleep -Seconds 6
    $cb = [UiCap+EnumWindowsProc]{
        param($hWnd, $lp)
        $wpid = [uint32]0
        [void][UiCap]::GetWindowThreadProcessId($hWnd, [ref]$wpid)
        if ($wpid -eq $script:capPid -and [UiCap]::IsWindowVisible($hWnd)) {
            $sb = New-Object Text.StringBuilder 256
            [void][UiCap]::GetWindowText($hWnd, $sb, 256)
            [void]$script:capFound.Add([pscustomobject]@{ H = $hWnd; Title = $sb.ToString() })
        }
        return $true
    }
    [void][UiCap]::EnumWindows($cb, [IntPtr]::Zero)
    $wnd = @($script:capFound | Where-Object { $_.Title -match '龙门客栈' })
    "windows_found = $(@($script:capFound).Count) | matching = $($wnd.Count)"
    if ($wnd.Count -eq 0) { throw '未找到标题含「龙门客栈」的可见窗口' }
    $h = $wnd[0].H
    "hwnd = $h | title = $($wnd[0].Title)"

    $r = New-Object 'UiCap+RECT'
    [void][UiCap]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    "window_rect = $($r.Left),$($r.Top) ${w}x${ht}"
    # 只移动到左上角，保持窗口原尺寸（WPF 尺寸是逻辑像素，DPI 缩放后物理值更大）
    [void][UiCap]::MoveWindow($h, 40, 30, $w, $ht, $true)
    [void][UiCap]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x43)
    [void][UiCap]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 1100
    [void][UiCap]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    $pad = 10
    $sx = [Math]::Max(0, $r.Left - $pad); $sy = [Math]::Max(0, $r.Top - $pad)
    $sw = $w + $pad * 2; $sh = $ht + $pad * 2
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    if ($sx + $sw -gt $screen.Width)  { $sw = $screen.Width - $sx }
    if ($sy + $sh -gt $screen.Height) { $sh = $screen.Height - $sy }
    "capture_rect = $sx,$sy ${sw}x${sh}"
    $bmp = New-Object System.Drawing.Bitmap $sw, $sh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($sx, $sy, 0, 0, (New-Object System.Drawing.Size $sw, $sh))
    $jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $prm = New-Object System.Drawing.Imaging.EncoderParameters 1
    $prm.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 88
    $bmp.Save($Out, $jpg, $prm)
    $g.Dispose(); $bmp.Dispose()
    "captured = $Out"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -Confirm:$false }
    if ($Theme) { [IO.File]::WriteAllText($themeFile, $orig, $enc) }
    "theme_restored = $orig"
}
