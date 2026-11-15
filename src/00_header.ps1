param(
    [string]$FeedFile  = "D:\tmp\muse_feed.json",
    [string]$StateFile = "D:\tmp\live_state.json",
    [switch]$NoMutex,
    [switch]$DebugFeed
)
# 57 号 / UI-01：字体令牌区。这里只是启动期占位，
# 窗口解析后会由 40_app.ps1 从 30_window.xaml 的 <sys:Double> 令牌覆盖，保证两套字号不分叉。
$script:FontFamilyName = "Microsoft YaHei UI, Segoe UI"
$script:FsCaption = 12    # 说明/角标
$script:FsMeta = 12       # 元信息/时间/名字/胶囊
$script:FsBody = 14       # 正文
$script:FsTitle = 14      # 标题（层级靠 Semibold 字重区分）
$script:FsDisplay = 18    # 大标题
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

try { Log-Boot 'assemblies-start' } catch { }

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

try { Log-Boot 'csharp-start' } catch { }

$csGlassFx = @'
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

$csWinIcon = @'
using System;
using System.Runtime.InteropServices;
public static class WinIcon {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
'@

$csTaskbarId = @'
using System;
using System.Runtime.InteropServices;
public static class TaskbarId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@

# S4 / DLL 自缓存：实测三段 C# 现场编译占 0→window-parsed 的 38%（368–402ms），
# 远超 ARCH-01 设定的 15% 门槛。首次启动编译并落盘，后续直接加载 DLL。
# 源码变更会改变哈希 → 自动换一个新 DLL；DLL 损坏或不可写则回退现场编译。
# 三段源码各自带 using，直接拼接会让 using 出现在类型定义之后（C# 不允许）。
# 统一把 using 提到最前，其余按原顺序拼接。
$body = @($csGlassFx, $csWinIcon, $csTaskbarId) | ForEach-Object {
    (($_ -split "`n") | Where-Object { $_ -notmatch '^\s*using\s' }) -join "`n"
}
$allCs = "using System;`nusing System.Runtime.InteropServices;`n" + ($body -join "`n")
$sha = [Security.Cryptography.SHA256]::Create()
$sig = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($allCs))).Replace('-', '').Substring(0, 8)
$cacheDir = 'D:\tmp\nailong\cache'
$dllPath = Join-Path $cacheDir ('NailongNative_' + $sig + '.dll')
$loaded = $false
if (Test-Path -LiteralPath $dllPath) {
    try { Add-Type -Path $dllPath -ErrorAction Stop; $loaded = $true } catch { $loaded = $false }
}
if (-not $loaded) {
    try {
        if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        Add-Type -TypeDefinition $allCs -OutputAssembly $dllPath -ErrorAction Stop
        try { Add-Type -Path $dllPath -ErrorAction Stop } catch { }
    } catch { }
}
# 兜底：无论如何保证三个类型可用（缓存不可写 / DLL 损坏 / 版本冲突）
if (-not ('GlassFx' -as [type])) { Add-Type -TypeDefinition $allCs }
try { Log-Boot 'csharp-done' } catch { }

# ICON-01：给本进程一个独立 AppUserModelID。任务栏按钮是按进程 AUMID 归类取图标的，
# 不改这一条，WM_SETICON 设上去也仍然显示 powershell.exe 的蓝色图标。
try { [void][TaskbarId]::SetCurrentProcessExplicitAppUserModelID("Nailong.Workshop.Live") } catch { }

$Utf8 = New-Object Text.UTF8Encoding $false

# ===== UI-01：全局语义色板（唯一颜色数据源）=====
# 四个探针证实：XamlReader.Parse 场景下，模板内 DynamicResource 换字典项会求值失败、
# 资源画刷会被自动 Freeze、ControlTemplate 的 Setter 密封不可写。因此这里不依赖运行时
# 换资源：XAML 在启动期用 Resolve-UiXaml 注入当前主题色；运行时由 Apply-Theme 遍历
# 具名控件从同一色板取值；交互态统一用主题无关的 Opacity 反馈。
# 所有色值经 WCAG 相对亮度公式验算：正文 >=4.5:1、组件描边 >=3:1。
$script:UiLight = @{
    Surface = '#FFFFFF'; SurfaceStroke = '#D7E1EC'; Card = '#FFFFFF'; Soft = '#F7FAFD'
    Line = '#D7E1EC'; Stroke = '#7A8CA3'; Rail = '#E1E9F1'; Dash = '#B9CBDE'
    Ink = '#16283C'; Ink2 = '#3D4E63'; Meta = '#5F6E80'; Hint = '#64748B'
    Accent = '#185FA5'; AccentInk = '#FFFFFF'; Focus = '#185FA5'
    Hover = '#EAF1F8'; Pressed = '#DCE7F3'; Thumb = '#33000000'
    LiveGreen = '#1E9E4A'; LiveBadgeBg = '#1A35C759'; LiveBadgeLine = '#4D35C759'; LiveDot = '#35C759'
    Danger = '#E5484D'; CloseRed = '#E81123'; Shadow = '#33507A'
    MyBg = '#FFFFFF'; MyLine = '#E2EAF2'; SelfBg = '#E8F1FB'; SelfInk = '#16283C'
    Char = '#1565C0'; CharSoft = '#DCEBFB'
    BgCat = '#2E7D32'; BgSoft = '#DFF2E2'
    Scene = '#7B1FA2'; SceneSoft = '#EEE3F7'
    Prompt = '#C25E10'; PromptSoft = '#FDEBD8'
    RoleSelf = '#4A5A72'; RoleHost = '#2E5A8A'; RoleGpt = '#6B4A8A'; RoleChef = '#2E6B4A'; RoleUnknown = '#5A6B82'
}
$script:UiDark = @{
    Surface = '#F2172432'; SurfaceStroke = '#172432'; Card = '#22303F'; Soft = '#1B2836'
    Line = '#1E2A38'; Stroke = '#6B829B'; Rail = '#1E2A38'; Dash = '#46586E'
    Ink = '#EAF1F8'; Ink2 = '#AFC0D2'; Meta = '#93A8BE'; Hint = '#93A8BE'
    Accent = '#2563B8'; AccentInk = '#FFFFFF'; Focus = '#7FB0EA'
    Hover = '#2A3B4F'; Pressed = '#31465C'; Thumb = '#66FFFFFF'
    LiveGreen = '#4ADE80'; LiveBadgeBg = '#2B35C759'; LiveBadgeLine = '#6635C759'; LiveDot = '#4ADE80'
    Danger = '#E5484D'; CloseRed = '#E81123'; Shadow = '#000000'
    MyBg = '#22303F'; MyLine = '#3A4E66'; SelfBg = '#20334A'; SelfInk = '#EAF1F8'
    Char = '#9CC3EE'; CharSoft = '#1E3A56'
    BgCat = '#9AD3A5'; BgSoft = '#1E4030'
    Scene = '#D3A8EE'; SceneSoft = '#39264D'
    Prompt = '#F2C184'; PromptSoft = '#4D3418'
    RoleSelf = '#4A5A72'; RoleHost = '#2E5A8A'; RoleGpt = '#6B4A8A'; RoleChef = '#2E6B4A'; RoleUnknown = '#5A6B82'
}
function Set-UiTheme([bool]$dark) {
    $script:dark = $dark
    $script:UiTokens = if ($dark) { $script:UiDark } else { $script:UiLight }
}
# 主题在窗口解析前就确定，避免先用浅色 XAML 再整体改色造成闪烁
$script:dark = $false
try { $script:dark = ([IO.File]::ReadAllText("D:\tmp\live_theme.txt", [Text.Encoding]::UTF8).Trim() -eq "True") } catch { }
Set-UiTheme $script:dark

# 供 PowerShell 构造的控件取色（气泡、拖拽区、时间线等）
function Tok([string]$key) {
    $v = $script:UiTokens[$key]
    if (-not $v) { $v = '#888888' }
    return (Brush $v)
}
# 启动期把 XAML 资源字典里的 {{Key}} 占位符替换为当前主题色
function Resolve-UiXaml([string]$x) {
    foreach ($k in @($script:UiTokens.Keys)) {
        $x = $x.Replace('{{' + $k + '}}', [string]$script:UiTokens[$k])
    }
    return $x
}

