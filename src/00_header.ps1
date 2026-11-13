param(
    [string]$FeedFile  = "D:\tmp\muse_feed.json",
    [string]$StateFile = "D:\tmp\live_state.json",
    [switch]$NoMutex,
    [switch]$DebugFeed
)
# 57 号：字体令牌区（唯一来源；其余处只引用令牌，不写字面量）
$script:FontFamilyName = "Microsoft YaHei UI, Segoe UI"
$script:FsCaption = 10.5   # 说明/角标
$script:FsMeta = 11.5      # 元信息/时间/名字/胶囊
$script:FsBody = 13        # 正文
$script:FsTitle = 14.5     # 标题
$script:FwRegular = "Normal"
$script:FwSemiBold = "SemiBold"
# 57-补：XAML 侧用的四个 Double 令牌（与上面同值）

# 53 号 boot-log v5.3：分段计时（写入 health\ui.log）
$script:_t0 = [Diagnostics.Stopwatch]::StartNew()
function Log-Boot([string]$tag) {
    try {
        $d = "D:\tmp\nailong\health"
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
        [IO.File]::AppendAllText((Join-Path $d "ui.log"), ((Get-Date -Format "HH:mm:ss.fff") + " | boot-" + $tag + " " + $script:_t0.ElapsedMilliseconds + "ms" + "`r`n"))
    } catch { }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 17 号④：崩溃/退出留痕（06:53 无日志消失那次，事后零线索）
function Write-AppLog([string]$msg) {
    try {
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' | v5.2 pid=' + $PID + ' | ' + $msg
        $dir = 'D:\tmp\nailong\health'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -LiteralPath (Join-Path $dir 'app.log') -Value $line -Encoding UTF8
    } catch { }
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GlassFx {
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WCA_DATA data);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    [StructLayout(LayoutKind.Sequential)]
    public struct ACCENT_POLICY { public int AccentState; public int AccentFlags; public int GradientColor; public int AnimationId; }
    [StructLayout(LayoutKind.Sequential)]
    public struct WCA_DATA { public int Attribute; public IntPtr Data; public int SizeOfData; }
    public static void EnableAcrylic(IntPtr hwnd, bool dark) {
        var accent = new ACCENT_POLICY();
        accent.AccentState = 4;
        accent.AccentFlags = 2;
        accent.GradientColor = dark ? unchecked((int)0xE61B2836) : unchecked((int)0xC2FFF8F2);
        int size = Marshal.SizeOf(accent);
        IntPtr ptr = Marshal.AllocHGlobal(size);
        Marshal.StructureToPtr(accent, ptr, false);
        var data = new WCA_DATA();
        data.Attribute = 19;
        data.Data = ptr;
        data.SizeOfData = size;
        SetWindowCompositionAttribute(hwnd, ref data);
        Marshal.FreeHGlobal(ptr);
        int corner = 2;
        DwmSetWindowAttribute(hwnd, 33, ref corner, sizeof(int));
    }
}
'@

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinIcon {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
'@

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TaskbarId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@

# ICON-01：给本进程一个独立 AppUserModelID。任务栏按钮是按进程 AUMID 归类取图标的，
# 不改这一条，WM_SETICON 设上去也仍然显示 powershell.exe 的蓝色图标。
try { [void][TaskbarId]::SetCurrentProcessExplicitAppUserModelID("Nailong.Workshop.Live") } catch { }

$Utf8 = New-Object Text.UTF8Encoding $false

