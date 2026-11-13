param(
    [string]$FeedFile  = "D:\tmp\muse_feed.json",
    [string]$StateFile = "D:\tmp\live_state.json",
    [switch]$NoMutex,
    [switch]$DebugFeed
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

function Read-Feed {
    if (-not (Test-Path $FeedFile)) { return @() }
    $items = @()
    foreach ($line in [IO.File]::ReadAllLines($FeedFile, [Text.Encoding]::UTF8)) {
        if ($line.Trim()) { try { $items += ($line | ConvertFrom-Json) } catch {} }
    }
    return $items
}
function Append-Feed($sender, $kind, $text) {
    $e = [ordered]@{ ts = (Get-Date -Format "HH:mm:ss"); sender = $sender; kind = $kind; text = $text }
    [IO.File]::AppendAllText($FeedFile, (($e | ConvertTo-Json -Compress) + "`n"), $Utf8)
}
function Brush($hex) { return (New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($hex))) }

# 消息文字可选中 + 右键复制菜单（留言板 / 聊天流共用）
function Attach-CopyMenu($box) {
    $cm = New-Object Windows.Controls.ContextMenu
    $m1 = New-Object Windows.Controls.MenuItem
    $m1.Header = "复制选中"
    $m1.Tag = $box
    $m1.Add_Click({ param($s, $ev) try { $tb = $s.Tag; if ($tb.SelectedText) { [Windows.Clipboard]::SetText($tb.SelectedText) } } catch { } })
    $m2 = New-Object Windows.Controls.MenuItem
    $m2.Header = "复制整条"
    $m2.Tag = $box
    $m2.Add_Click({ param($s, $ev) try { [Windows.Clipboard]::SetText([string]$s.Tag.Text) } catch { } })
    $m3 = New-Object Windows.Controls.MenuItem
    $m3.Header = "全选"
    $m3.Tag = $box
    $m3.Add_Click({ param($s, $ev) try { $s.Tag.Focus() | Out-Null; $s.Tag.SelectAll() } catch { } })
    $cm.Items.Add($m1) | Out-Null
    $cm.Items.Add($m2) | Out-Null
    $cm.Items.Add((New-Object Windows.Controls.Separator)) | Out-Null
    $cm.Items.Add($m3) | Out-Null
    $box.ContextMenu = $cm
}
function New-SelectableText([string]$text, $size, $fore, $lineH) {
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $text
    $tb.FontSize = $size
    $tb.Foreground = $fore
    $tb.TextWrapping = "Wrap"
    $tb.Margin = New-Object Windows.Thickness(0, 5, 0, 0)
    $tb.IsReadOnly = $true
    $tb.IsReadOnlyCaretVisible = $false
    $tb.IsTabStop = $false
    $tb.BorderThickness = New-Object Windows.Thickness(0)
    $tb.Background = [Windows.Media.Brushes]::Transparent
    $tb.Padding = New-Object Windows.Thickness(0)
    $tb.Cursor = [Windows.Input.Cursors]::IBeam
    $tb.VerticalScrollBarVisibility = "Disabled"
    $tb.HorizontalScrollBarVisibility = "Disabled"
    # 只读文本框会吃掉滚轮，转交给外层 ScrollViewer，保证聊天流照样能滚
    $tb.Add_PreviewMouseWheel({ param($s, $ev)
            try {
                $parent = [Windows.Media.VisualTreeHelper]::GetParent($s)
                while ($parent -and -not ($parent -is [Windows.Controls.ScrollViewer])) { $parent = [Windows.Media.VisualTreeHelper]::GetParent($parent) }
                if ($parent) {
                    $parent.ScrollToVerticalOffset($parent.VerticalOffset - ($ev.Delta / 3))
                    $ev.Handled = $true
                }
            } catch { }
        })
    Attach-CopyMenu $tb
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

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="龙门客栈" Width="620" Height="740" MinWidth="520" MinHeight="560"
        WindowStyle="None" ResizeMode="CanResize" ShowInTaskbar="True"
        WindowStartupLocation="CenterScreen" Background="Transparent"
        FontFamily="Microsoft YaHei UI, Segoe UI" TextOptions.TextFormattingMode="Display">
  <shell:WindowChrome.WindowChrome>
    <shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="12" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="CardBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="LineBrush" Color="#DCE4EE"/>
    <SolidColorBrush x:Key="ThumbBrush" Color="#33000000"/>
    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="#3D4E63"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#14000000"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#26000000"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CloseBtn" TargetType="Button" BasedOn="{StaticResource WinBtn}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E81123"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="tb" CornerRadius="4" Background="{DynamicResource ThumbBrush}" Opacity="0.45" Margin="1,0"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="tb" Property="Opacity" Value="1"/>
                          </Trigger>
                          <Trigger Property="IsDragging" Value="True">
                            <Setter TargetName="tb" Property="Opacity" Value="1"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  <Style x:Key="UtilBtn" TargetType="Button">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="#3D4E63"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="14" Padding="11,5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1A000000"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2A000000"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  <Style x:Key="IcoBtn" TargetType="Button">
      <Setter Property="Width" Value="36"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="Foreground" Value="#5A6E85"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="9">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E9F0F8"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#DCE7F3"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="RootBorder" CornerRadius="12" Background="#F2F7FB" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="52"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="44"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
<Grid x:Name="Header" Grid.Row="0" Grid.Column="1" Margin="8,0,0,0" Background="Transparent">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="TitleText" Text="龙门客栈" FontSize="14.5" FontWeight="SemiBold" Foreground="#16283C" VerticalAlignment="Center"/>
          <Border x:Name="LiveBadge" CornerRadius="9" Background="#1A35C759" BorderBrush="#4D35C759" BorderThickness="1" Padding="7,2" Margin="8,0,0,0" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <Ellipse x:Name="LiveDot" Width="6" Height="6" Fill="#35C759" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
                <Ellipse.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Ellipse.RenderTransform>
              </Ellipse>
              <TextBlock x:Name="LiveBadgeText" Text="营业中" FontSize="10.5" FontWeight="SemiBold" Foreground="#1E9E4A" Margin="4,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <TextBlock x:Name="StatusText" Text="已同步 0 条" FontSize="10.5" Foreground="#7A8CA3" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <Border x:Name="SearchBorder" Grid.Column="1" Width="0" CornerRadius="13" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,6,0" VerticalAlignment="Center" Visibility="Collapsed">
          <Grid>
            <TextBox x:Name="SearchBox" BorderThickness="0" Background="Transparent" FontSize="12" Foreground="#16283C" Padding="10,4" VerticalContentAlignment="Center"/>
            <TextBlock x:Name="SearchHint" Text="搜索历史…" FontSize="12" Foreground="#9FB0C3" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          </Grid>
        </Border>
        <Button x:Name="SearchBtn" Grid.Column="2" Style="{StaticResource IcoBtn}" Content="&#xE721;" FontSize="15" Width="32" Height="32" Margin="0,0,4,0" ToolTip="搜索历史"/>
        <Button x:Name="BtnMin" Grid.Column="3" Style="{StaticResource WinBtn}" VerticalAlignment="Center" Margin="0,0,2,0" ToolTip="最小化">
          <Path Data="M 0,5 L 10,5" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.2"/>
        </Button>
        <Button x:Name="BtnMax" Grid.Column="4" Style="{StaticResource WinBtn}" VerticalAlignment="Center" Margin="0,0,2,0" ToolTip="放大 / 还原">
          <Path Data="M 1,1 L 9,1 L 9,9 L 1,9 Z" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.2" Fill="Transparent"/>
        </Button>
        <Button x:Name="BtnClose" Grid.Column="5" Style="{StaticResource CloseBtn}" VerticalAlignment="Center" Margin="0,0,8,0" ToolTip="关闭">
          <Path Data="M 0,0 L 10,10 M 10,0 L 0,10" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.2"/>
        </Button>
        <Border x:Name="HeaderLine" Grid.ColumnSpan="6" VerticalAlignment="Bottom" Height="1" Background="#E1E9F1"/>
      </Grid>
      <Grid x:Name="Rail" Grid.Column="0" Grid.RowSpan="3" Background="Transparent">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Width="34" Height="34" CornerRadius="17" Background="Transparent" Margin="0,6,0,6" HorizontalAlignment="Center">
          <Border.Clip>
            <EllipseGeometry Center="17,17" RadiusX="17" RadiusY="17"/>
          </Border.Clip>
          <Image x:Name="AvatarImg" Stretch="UniformToFill" Width="34" Height="34"/>
        </Border>
        <StackPanel Grid.Row="1">
          <Button x:Name="BtnChat" Style="{StaticResource IcoBtn}" Content="&#xE8BD;" ToolTip="聊天" Margin="0,2" HorizontalAlignment="Center"/>
          <Button x:Name="StudioBtn" Style="{StaticResource IcoBtn}" Content="&#xE714;" ToolTip="视频工坊" Margin="0,2" HorizontalAlignment="Center"/>
          <Grid Width="36" Height="36" Margin="0,2" HorizontalAlignment="Center">
            <Button x:Name="CollabBtn" Style="{StaticResource IcoBtn}" Content="&#xE716;" ToolTip="传菜口（留言板 / 日志 / 占用）"/>
            <Ellipse x:Name="CollabDot" Width="8" Height="8" Fill="#E5484D" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,4,4,0" Visibility="Collapsed"/>
          </Grid>
          <Button x:Name="ArchiveBtn" Style="{StaticResource IcoBtn}" Content="&#xE74E;" ToolTip="存档（打包状态日志与记忆）" Margin="0,2" HorizontalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Margin="0,0,0,8">
          <Button x:Name="ShotBtn" Style="{StaticResource IcoBtn}" Content="&#xE722;" ToolTip="给大厨看屏幕" Margin="0,2" HorizontalAlignment="Center"/>
          <Button x:Name="DarkBtn" Style="{StaticResource IcoBtn}" Content="&#xE706;" ToolTip="深浅色" Margin="0,2" HorizontalAlignment="Center"/>
        </StackPanel>
        <Border x:Name="RailLine" HorizontalAlignment="Right" Width="1" Background="{DynamicResource LineBrush}"/>
      </Grid>
      <ScrollViewer x:Name="FeedScroll" Grid.Row="1" Grid.Column="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="6,6,2,6">
        <StackPanel x:Name="FeedList"/>
      </ScrollViewer>
      <Border x:Name="InputBar" Grid.Row="2" Grid.Column="1" BorderBrush="#E1E9F1" BorderThickness="0,1,0,0" Padding="14,12,14,14">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border x:Name="InputBorder" Grid.Column="0" CornerRadius="20" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,10,0">
            <Grid>
              <TextBox x:Name="InputBox" BorderThickness="0" Background="Transparent" FontSize="13.5" Foreground="#16283C"
                       Padding="13,9" VerticalContentAlignment="Center" MaxLength="500"/>
              <TextBlock x:Name="InputHint" Text="跟掌柜说句话…" FontSize="13.5" Foreground="#9FB0C3" Margin="14,0,0,0"
                         VerticalAlignment="Center" IsHitTestVisible="False"/>
            </Grid>
          </Border>
          <Button x:Name="SendBtn" Grid.Column="1" Width="42" Height="42" Cursor="Hand" ToolTip="发给掌柜" VerticalAlignment="Center">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="bd" Background="#2F7DE1" CornerRadius="21" BorderBrush="#66FFFFFF" BorderThickness="1">
                  <TextBlock Text="↑" FontSize="19" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="bd" Property="Background" Value="#4A90E8"/>
                  </Trigger>
                  <Trigger Property="IsPressed" Value="True">
                    <Setter TargetName="bd" Property="Background" Value="#2569BC"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </Grid>
      </Border>

      <Grid x:Name="StudioView" Grid.Row="1" Grid.RowSpan="2" Grid.Column="1" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="6,4,2,4">
          <StackPanel Margin="10,4,10,6">
            <Border x:Name="FlowBar" CornerRadius="12" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Padding="10,8" Margin="0,0,0,12">
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                <Ellipse x:Name="FlowDotChar" Width="8" Height="8" Fill="#C3D2E2" VerticalAlignment="Center"/>
                <TextBlock Text="人物" FontSize="12" FontWeight="SemiBold" Foreground="#1565C0" Margin="5,0,0,0" VerticalAlignment="Center"/>
                <TextBlock Text="→" FontSize="12" Foreground="#8496AB" Margin="7,0,7,0" VerticalAlignment="Center"/>
                <Ellipse x:Name="FlowDotScene" Width="8" Height="8" Fill="#C3D2E2" VerticalAlignment="Center"/>
                <TextBlock Text="场景" FontSize="12" FontWeight="SemiBold" Foreground="#7B1FA2" Margin="5,0,0,0" VerticalAlignment="Center"/>
                <TextBlock Text="←" FontSize="12" Foreground="#8496AB" Margin="7,0,7,0" VerticalAlignment="Center"/>
                <Ellipse x:Name="FlowDotBg" Width="8" Height="8" Fill="#C3D2E2" VerticalAlignment="Center"/>
                <TextBlock Text="背景" FontSize="12" FontWeight="SemiBold" Foreground="#2E7D32" Margin="5,0,0,0" VerticalAlignment="Center"/>
                <TextBlock Text="·" FontSize="12" Foreground="#8496AB" Margin="7,0,7,0" VerticalAlignment="Center"/>
                <Ellipse x:Name="FlowDotPrompt" Width="8" Height="8" Fill="#C3D2E2" VerticalAlignment="Center"/>
                <TextBlock Text="提示词" FontSize="12" FontWeight="SemiBold" Foreground="#C25E10" Margin="5,0,0,0" VerticalAlignment="Center"/>
                <TextBlock Text="→" FontSize="12" Foreground="#8496AB" Margin="7,0,7,0" VerticalAlignment="Center"/>
                <TextBlock Text="生成" FontSize="12" FontWeight="SemiBold" Foreground="#2F7DE1" VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
            <Border x:Name="NodeChar" CornerRadius="14" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,0,12" RenderTransformOrigin="0.5,0.5">
              <Border.Effect>
                <DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.08" Color="#33507A"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="30"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border x:Name="BarChar" Grid.Row="0" Background="#DCEBFB" CornerRadius="14,14,0,0">
                  <TextBlock x:Name="BarCharT" Text="人物 · 图片" FontSize="12.5" FontWeight="SemiBold" Foreground="#1565C0" Margin="12,0,0,0" VerticalAlignment="Center"/>
                </Border>
                <Grid Grid.Row="1" Margin="10,8,10,10">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <Border x:Name="DropChar" Grid.Row="0" Height="118" CornerRadius="10" Background="#F7FAFD" BorderBrush="#C3D2E2" BorderThickness="1" AllowDrop="True" Tag="char" Cursor="Hand">
                    <Grid>
                      <Rectangle x:Name="DashChar" Margin="4" RadiusX="7" RadiusY="7" Stroke="#B9CBDE" StrokeThickness="1.1" StrokeDashArray="4,3"/>
                      <TextBlock x:Name="HintChar" Text="把人物图片拖到这里，或点击选择" FontSize="12" Foreground="#8496AB" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      <Image x:Name="ImgChar" Stretch="Uniform" Margin="2" Visibility="Collapsed" AllowDrop="True" Tag="char"/>
                    </Grid>
                  </Border>
                  <TextBlock x:Name="NameChar" Grid.Row="1" FontSize="11" Foreground="#8496AB" Margin="2,5,0,0" TextTrimming="CharacterEllipsis"/>
                </Grid>
              </Grid>
            </Border>
            <Border x:Name="NodeBg" CornerRadius="14" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,0,12" RenderTransformOrigin="0.5,0.5">
              <Border.Effect>
                <DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.08" Color="#33507A"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="30"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border x:Name="BarBg" Grid.Row="0" Background="#DFF2E2" CornerRadius="14,14,0,0">
                  <TextBlock x:Name="BarBgT" Text="背景 · 图片" FontSize="12.5" FontWeight="SemiBold" Foreground="#2E7D32" Margin="12,0,0,0" VerticalAlignment="Center"/>
                </Border>
                <Grid Grid.Row="1" Margin="10,8,10,10">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <Border x:Name="DropBg" Grid.Row="0" Height="118" CornerRadius="10" Background="#F7FAFD" BorderBrush="#C3D2E2" BorderThickness="1" AllowDrop="True" Tag="bg" Cursor="Hand">
                    <Grid>
                      <Rectangle x:Name="DashBg" Margin="4" RadiusX="7" RadiusY="7" Stroke="#B9CBDE" StrokeThickness="1.1" StrokeDashArray="4,3"/>
                      <TextBlock x:Name="HintBg" Text="把背景图片拖到这里，或点击选择" FontSize="12" Foreground="#8496AB" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      <Image x:Name="ImgBg" Stretch="Uniform" Margin="2" Visibility="Collapsed" AllowDrop="True" Tag="bg"/>
                    </Grid>
                  </Border>
                  <TextBlock x:Name="NameBg" Grid.Row="1" FontSize="11" Foreground="#8496AB" Margin="2,5,0,0" TextTrimming="CharacterEllipsis"/>
                </Grid>
              </Grid>
            </Border>
            <Border x:Name="NodeScene" CornerRadius="14" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,0,12" RenderTransformOrigin="0.5,0.5">
              <Border.Effect>
                <DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.08" Color="#33507A"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="30"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border x:Name="BarScene" Grid.Row="0" Background="#EEE3F7" CornerRadius="14,14,0,0">
                  <TextBlock x:Name="BarSceneT" Text="场景 · 合成" FontSize="12.5" FontWeight="SemiBold" Foreground="#7B1FA2" Margin="12,0,0,0" VerticalAlignment="Center"/>
                </Border>
                <Grid Grid.Row="1" Margin="10,8,10,10">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <Border x:Name="DropScene" Grid.Row="0" Height="92" CornerRadius="10" Background="#F7FAFD" BorderBrush="#C3D2E2" BorderThickness="1" AllowDrop="True" Tag="scene" Cursor="Hand">
                    <Grid>
                      <Rectangle x:Name="DashScene" Margin="4" RadiusX="7" RadiusY="7" Stroke="#B9CBDE" StrokeThickness="1.1" StrokeDashArray="4,3"/>
                      <TextBlock x:Name="HintScene" Text="把场景图片拖到这里（可空），或点击选择" FontSize="12" Foreground="#8496AB" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      <Image x:Name="ImgScene" Stretch="Uniform" Margin="2" Visibility="Collapsed" AllowDrop="True" Tag="scene"/>
                    </Grid>
                  </Border>
                  <TextBlock x:Name="NameScene" Grid.Row="1" FontSize="11" Foreground="#8496AB" Margin="2,5,0,0" TextTrimming="CharacterEllipsis"/>
                  <Border Grid.Row="2" x:Name="SceneTextBorder" CornerRadius="7" Background="#F7FAFD" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,6,0,0">
                    <Grid>
                      <TextBox x:Name="SceneText" BorderThickness="0" Background="Transparent" FontSize="12" Foreground="#16283C" Padding="8,6" MaxLength="120"/>
                      <TextBlock x:Name="SceneTextHint" Text="补充说明（可空）" FontSize="12" Foreground="#9FB0C3" Margin="9,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
                    </Grid>
                  </Border>
                </Grid>
              </Grid>
            </Border>
            <Border x:Name="NodePrompt" CornerRadius="14" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,0,12" RenderTransformOrigin="0.5,0.5">
              <Border.Effect>
                <DropShadowEffect BlurRadius="12" ShadowDepth="2" Opacity="0.08" Color="#33507A"/>
              </Border.Effect>
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="30"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border x:Name="BarPrompt" Grid.Row="0" Background="#FDEBD8" CornerRadius="14,14,0,0">
                  <TextBlock x:Name="BarPromptT" Text="提示词 · 文字" FontSize="12.5" FontWeight="SemiBold" Foreground="#C25E10" Margin="12,0,0,0" VerticalAlignment="Center"/>
                </Border>
                <Grid Grid.Row="1" Margin="10,8,10,10">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <ComboBox x:Name="StyleBox" Grid.Row="0" Height="30" FontSize="12.5" IsEditable="True" VerticalContentAlignment="Center" Padding="6,0" Background="#F7FAFD" Foreground="#16283C"/>
                  <Border x:Name="PromptBorder" Grid.Row="1" Height="88" CornerRadius="7" Background="#F7FAFD" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,8,0,0">
                    <Grid>
                      <TextBox x:Name="PromptText" BorderThickness="0" Background="Transparent" FontSize="12.5" Foreground="#16283C" Padding="8,6" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                      <TextBlock x:Name="PromptHint" Text="写动作 / 剧情，比如：奶龙在茶园小路上奔跑，脚下一滑，闭眼摔出画面…" FontSize="12" Foreground="#9FB0C3" Margin="9,7,6,0" TextWrapping="Wrap" IsHitTestVisible="False"/>
                    </Grid>
                  </Border>
                </Grid>
              </Grid>
            </Border>
            <TextBlock x:Name="OutLabel" Text="成品 · 双击打开播放" FontSize="11.5" Foreground="#8496AB" Margin="2,2,0,5"/>
            <WrapPanel x:Name="OutPanel"/>
          </StackPanel>
        </ScrollViewer>
        <Border x:Name="VsStatusBar" Grid.Row="1" BorderBrush="#E1E9F1" BorderThickness="0,1,0,0" Padding="14,9,14,7">
          <TextBlock x:Name="VsStatus" Text="等待素材 · 还差人物、背景" FontSize="12" Foreground="#8496AB" TextWrapping="Wrap"/>
        </Border>
        <Border Grid.Row="2" Padding="14,2,14,14">
          <Button x:Name="GenBtn" Content="生成视频" FontSize="14.5" FontWeight="SemiBold" Foreground="White" Height="46" Cursor="Hand">
            <Button.Template>
              <ControlTemplate TargetType="Button">
                <Border x:Name="bd" Background="#2F7DE1" CornerRadius="14" BorderBrush="#66FFFFFF" BorderThickness="1">
                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="bd" Property="Background" Value="#4A90E8"/>
                  </Trigger>
                  <Trigger Property="IsPressed" Value="True">
                    <Setter TargetName="bd" Property="Background" Value="#2569BC"/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </Button.Template>
          </Button>
        </Border>
      </Grid>
      <Grid x:Name="CollabView" Grid.Row="1" Grid.RowSpan="2" Grid.Column="1" Visibility="Collapsed">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="14,8,14,6">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Button x:Name="CbBoard" Grid.Column="0" Style="{StaticResource UtilBtn}" Content="留言板"/>
          <Button x:Name="CbLog" Grid.Column="1" Style="{StaticResource UtilBtn}" Content="动作日志" Margin="8,0,0,0"/>
          <Button x:Name="CbClaim" Grid.Column="2" Style="{StaticResource UtilBtn}" Content="占用" Margin="8,0,0,0"/>
          <TextBlock x:Name="CbCount" Grid.Column="4" FontSize="11.5" Foreground="#8496AB" VerticalAlignment="Center"/>
        </Grid>
        <Grid Grid.Row="1" Margin="14,0,14,8">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
            <Ellipse Width="7" Height="7" Fill="#D9534F" VerticalAlignment="Center"/>
            <TextBlock Text="决策P0" FontSize="10.5" Foreground="#8496AB" Margin="4,0,9,0" VerticalAlignment="Center"/>
            <Ellipse Width="7" Height="7" Fill="#2F7DE1" VerticalAlignment="Center"/>
            <TextBlock Text="转达P1" FontSize="10.5" Foreground="#8496AB" Margin="4,0,9,0" VerticalAlignment="Center"/>
            <Ellipse Width="7" Height="7" Fill="#2E9E5B" VerticalAlignment="Center"/>
            <TextBlock Text="执行" FontSize="10.5" Foreground="#8496AB" Margin="4,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
        </Grid>
        <ScrollViewer x:Name="CbScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8,0,4,8">
          <StackPanel x:Name="CbList"/>
        </ScrollViewer>
        <Border x:Name="CbInputBar" Grid.Row="3" BorderBrush="#E1E9F1" BorderThickness="0,1,0,0" Padding="14,10,14,12">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="CbInputBorder" Grid.Column="0" CornerRadius="18" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Margin="0,0,8,0">
              <Grid>
                <TextBox x:Name="CbInput" BorderThickness="0" Background="Transparent" FontSize="13" Foreground="#16283C" Padding="12,8" MaxLength="1000">
                  <TextBox.ContextMenu>
                    <ContextMenu>
                      <MenuItem Header="剪切" Command="ApplicationCommands.Cut"/>
                      <MenuItem Header="复制" Command="ApplicationCommands.Copy"/>
                      <MenuItem Header="粘贴" Command="ApplicationCommands.Paste"/>
                      <Separator/>
                      <MenuItem Header="全选" Command="ApplicationCommands.SelectAll"/>
                    </ContextMenu>
                  </TextBox.ContextMenu>
                </TextBox>
                <TextBlock x:Name="CbHint" Text="发到留言板，两个助手下一轮都会看到" FontSize="13" Foreground="#9FB0C3" Margin="13,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
              </Grid>
            </Border>
            <Button x:Name="CbTo" Grid.Column="1" Style="{StaticResource UtilBtn}" Content="发给：全员" ToolTip="点击切换收件人：全员 / 掌柜 / 大厨 / 客官" Margin="0,0,6,0"/>
            <Button x:Name="CbKind" Grid.Column="2" Style="{StaticResource UtilBtn}" Content="类型：留言" ToolTip="点击切换类型：留言 / 状态 / 任务 / 提问 / 决定" Margin="0,0,8,0"/>
            <Button x:Name="CbSend" Grid.Column="3" Content="发到看板" FontSize="13" FontWeight="SemiBold" Foreground="White" Padding="16,7" Cursor="Hand">
              <Button.Template>
                <ControlTemplate TargetType="Button">
                  <Border x:Name="bd" Background="#2F7DE1" CornerRadius="17">
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="bd" Property="Background" Value="#4A90E8"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                      <Setter TargetName="bd" Property="Background" Value="#2569BC"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Button.Template>
            </Button>
          </Grid>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

try {
    $win = [Windows.Markup.XamlReader]::Parse($xaml)
} catch {
    [IO.File]::WriteAllText("D:\tmp\live3_err.txt", $_.Exception.ToString(), [Text.Encoding]::UTF8)
    exit 1
}

$FeedList   = $win.FindName("FeedList")
$FeedScroll = $win.FindName("FeedScroll")
$InputBox   = $win.FindName("InputBox")
$InputHint  = $win.FindName("InputHint")
$StatusText = $win.FindName("StatusText")
$LiveBadge = $win.FindName("LiveBadge")
$LiveDot = $win.FindName("LiveDot")
$LiveBadgeText = $win.FindName("LiveBadgeText")
$ArchiveBtn = $win.FindName("ArchiveBtn")
if ($ArchiveBtn) {
    $ArchiveBtn.Add_Click({
        try {
            $d = & 'D:\tmp\nailong\tools\make_archive.ps1'
            Append-Feed "系统" "note" ("已存档 " + (Get-Date -Format "HH:mm") + " · 包 " + (Split-Path $d -Leaf))
        } catch {
            Append-Feed "系统" "status" ("存档失败：" + $_.Exception.Message)
        }
    })
}
$Header     = $win.FindName("Header")
$RootBorder = $win.FindName("RootBorder")
$DarkBtn = $win.FindName("DarkBtn")
$ShotBtn = $win.FindName("ShotBtn")
$SearchBox = $win.FindName("SearchBox")
$SearchHint = $win.FindName("SearchHint")
$TitleText = $win.FindName("TitleText")
$InputBorder = $win.FindName("InputBorder")
$SearchBorder = $win.FindName("SearchBorder")
$HeaderLine = $win.FindName("HeaderLine")
$RailLine = $win.FindName("RailLine")
$InputBar = $win.FindName("InputBar")
$StudioBtn = $win.FindName("StudioBtn")
$CollabBtn = $win.FindName("CollabBtn")
$BtnChat = $win.FindName("BtnChat")
$SearchBtn = $win.FindName("SearchBtn")
$CollabDot = $win.FindName("CollabDot")
$CollabView = $win.FindName("CollabView")
$CbBoard = $win.FindName("CbBoard")
$CbLog = $win.FindName("CbLog")
$CbClaim = $win.FindName("CbClaim")
$CbCount = $win.FindName("CbCount")
$CbScroll = $win.FindName("CbScroll")
$CbList = $win.FindName("CbList")
$CbInput = $win.FindName("CbInput")
$CbHint = $win.FindName("CbHint")
$CbKind = $win.FindName("CbKind")
$CbSend = $win.FindName("CbSend")
$CbInputBorder = $win.FindName("CbInputBorder")
$CbInputBar = $win.FindName("CbInputBar")
$CbTo = $win.FindName("CbTo")
$StudioView = $win.FindName("StudioView")
$VsSurface = $win.FindName("VsSurface")
$VsCanvas = $win.FindName("VsCanvas")
$NodeChar = $win.FindName("NodeChar"); $BarChar = $win.FindName("BarChar"); $BarCharT = $win.FindName("BarCharT")
$DropChar = $win.FindName("DropChar"); $DashChar = $win.FindName("DashChar"); $HintChar = $win.FindName("HintChar"); $ImgChar = $win.FindName("ImgChar"); $NameChar = $win.FindName("NameChar")
$NodeBg = $win.FindName("NodeBg"); $BarBg = $win.FindName("BarBg"); $BarBgT = $win.FindName("BarBgT")
$DropBg = $win.FindName("DropBg"); $DashBg = $win.FindName("DashBg"); $HintBg = $win.FindName("HintBg"); $ImgBg = $win.FindName("ImgBg"); $NameBg = $win.FindName("NameBg")
$NodeScene = $win.FindName("NodeScene"); $BarScene = $win.FindName("BarScene"); $BarSceneT = $win.FindName("BarSceneT")
$DropScene = $win.FindName("DropScene"); $DashScene = $win.FindName("DashScene"); $HintScene = $win.FindName("HintScene"); $ImgScene = $win.FindName("ImgScene"); $NameScene = $win.FindName("NameScene")
$SceneTextBorder = $win.FindName("SceneTextBorder"); $SceneText = $win.FindName("SceneText"); $SceneTextHint = $win.FindName("SceneTextHint")
$NodePrompt = $win.FindName("NodePrompt"); $BarPrompt = $win.FindName("BarPrompt"); $BarPromptT = $win.FindName("BarPromptT")
$StyleBox = $win.FindName("StyleBox"); $PromptBorder = $win.FindName("PromptBorder"); $PromptText = $win.FindName("PromptText"); $PromptHint = $win.FindName("PromptHint")
$NodeGen = $win.FindName("NodeGen"); $BarGen = $win.FindName("BarGen"); $BarGenT = $win.FindName("BarGenT")
$GenBtn = $win.FindName("GenBtn"); $VsStatus = $win.FindName("VsStatus")
$OutLabel = $win.FindName("OutLabel"); $OutPanel = $win.FindName("OutPanel")
$FlowBar = $win.FindName("FlowBar"); $VsStatusBar = $win.FindName("VsStatusBar")
$FlowDotChar = $win.FindName("FlowDotChar"); $FlowDotBg = $win.FindName("FlowDotBg")
$FlowDotScene = $win.FindName("FlowDotScene"); $FlowDotPrompt = $win.FindName("FlowDotPrompt")
function Apply-Theme {
    if ($script:dark) {
        $RootBorder.Background = Brush "#F2172432"
        $RootBorder.BorderBrush = Brush "#1E2A38"
        try { $hh = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; if ($hh -ne [IntPtr]::Zero) { [GlassFx]::EnableAcrylic($hh, $true) } } catch { }
        $HeaderLine.Background = Brush "#1E2A38"
        $InputBar.BorderBrush = Brush "#1E2A38"
        $TitleText.Foreground = Brush "#EAF1F8"
        $StatusText.Foreground = Brush "#93A8BE"
        $LiveBadge.Background = Brush "#2B35C759"
        $LiveBadge.BorderBrush = Brush "#6635C759"
        $LiveBadgeText.Foreground = Brush "#4ADE80"
        $InputBox.Foreground = Brush "#EAF1F8"
        $InputHint.Foreground = Brush "#6E8299"
        $InputBorder.Background = Brush "#22303F"
        $InputBorder.BorderBrush = Brush "#3A4E66"
        $SearchBorder.Background = Brush "#22303F"
        $SearchBorder.BorderBrush = Brush "#3A4E66"
        $SearchBox.Foreground = Brush "#EAF1F8"
        $SearchHint.Foreground = Brush "#6E8299"
        $DarkBtn.ToolTip = "切到浅色"
    } else {
        $RootBorder.Background = Brush "#D9F4F9FF"
        $RootBorder.BorderBrush = Brush "#D7E1EC"
        try { $hh = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; if ($hh -ne [IntPtr]::Zero) { [GlassFx]::EnableAcrylic($hh, $false) } } catch { }
        $HeaderLine.Background = Brush "#E1E9F1"
        $InputBar.BorderBrush = Brush "#E1E9F1"
        $TitleText.Foreground = Brush "#16283C"
        $StatusText.Foreground = Brush "#7A8CA3"
        $LiveBadge.Background = Brush "#1A35C759"
        $LiveBadge.BorderBrush = Brush "#4D35C759"
        $LiveBadgeText.Foreground = Brush "#1E9E4A"
        $InputBox.Foreground = Brush "#16283C"
        $InputHint.Foreground = Brush "#9FB0C3"
        $InputBorder.Background = Brush "#FFFFFF"
        $InputBorder.BorderBrush = Brush "#D7E1EC"
        $SearchBorder.Background = Brush "#FFFFFF"
        $SearchBorder.BorderBrush = Brush "#D7E1EC"
        $SearchBox.Foreground = Brush "#16283C"
        $SearchHint.Foreground = Brush "#9FB0C3"
        $DarkBtn.ToolTip = "切到深色"
    }
    $cardBg = if ($script:dark) { "#22303F" } else { "#FFFFFF" }
    $lineC = if ($script:dark) { "#3A4E66" } else { "#DCE4EE" }
    $ink = if ($script:dark) { "#AFC0D2" } else { "#3D4E63" }
    foreach ($el in @($InputBorder, $SearchBorder, $CbInputBorder)) { if ($el) { $el.Background = Brush $cardBg; $el.BorderBrush = Brush $lineC } }
    foreach ($el in @($FlowBar, $NodeChar, $NodeBg, $NodeScene, $NodePrompt)) { if ($el) { $el.Background = Brush $cardBg } }
    foreach ($el in @($CbTo, $CbKind)) { if ($el) { $el.Background = Brush $cardBg; $el.Foreground = Brush $ink } }
    try { if ($script:cbView) { Set-CbView $script:cbView } } catch { }
    try { if ($RailLine) { $RailLine.Background = Brush $(if ($script:dark) { "#1E2A38" } else { "#E1E9F1" })`r`n    try { if ($CbInputBar) { $CbInputBar.BorderBrush = Brush $(if ($script:dark) { "#1E2A38" } else { "#E1E9F1" }) } } catch { } } } catch { }
    Update-Rail
    Apply-StudioTheme
}
function New-GridBrush($dotHex) {
    $brush = New-Object Windows.Media.DrawingBrush
    $brush.TileMode = "Tile"
    $brush.Viewport = New-Object Windows.Rect(0, 0, 22, 22)
    $brush.ViewportUnits = "Absolute"
    $geo = New-Object Windows.Media.EllipseGeometry
    $geo.Center = New-Object Windows.Point(1.6, 1.6)
    $geo.RadiusX = 1.6
    $geo.RadiusY = 1.6
    $gd = New-Object Windows.Media.GeometryDrawing
    $gd.Brush = Brush $dotHex
    $gd.Geometry = $geo
    $brush.Drawing = $gd
    return $brush
}
function Apply-StudioTheme {
    if (-not $NodeChar) { return }
    $script:VsCardBg = if ($script:dark) { "#22303F" } else { "#FFFFFF" }
    $script:VsCardLine = if ($script:dark) { "#3A4E66" } else { "#DCE4EE" }
    $script:VsInk = if ($script:dark) { "#EAF1F8" } else { "#16283C" }
    $script:VsMeta = if ($script:dark) { "#93A8BE" } else { "#8496AB" }
    $dropBg = if ($script:dark) { "#1B2836" } else { "#F7FAFD" }
    $dashC = if ($script:dark) { "#46586E" } else { "#B9CBDE" }
    $pal = @{
        char = @("#DCEBFB", "#1565C0", "#1E3A56", "#9CC3EE")
        bg = @("#DFF2E2", "#2E7D32", "#1E4030", "#9AD3A5")
        scene = @("#EEE3F7", "#7B1FA2", "#39264D", "#D3A8EE")
        prompt = @("#FDEBD8", "#C25E10", "#4D3418", "#F2C184")
    }
    $bars = @{ char = @($BarChar, $BarCharT); bg = @($BarBg, $BarBgT); scene = @($BarScene, $BarSceneT); prompt = @($BarPrompt, $BarPromptT) }
    foreach ($k in $pal.Keys) {
        $c = $pal[$k]
        if ($script:dark) { $bars[$k][0].Background = Brush $c[2]; $bars[$k][1].Foreground = Brush $c[3] }
        else { $bars[$k][0].Background = Brush $c[0]; $bars[$k][1].Foreground = Brush $c[1] }
    }
    foreach ($k in @("char", "bg", "scene")) {
        $n = $script:VsNodes[$k]
        if ($n) {
            $n.Node.Background = Brush $script:VsCardBg
            $n.Node.BorderBrush = Brush $script:VsCardLine
            $n.Drop.Background = Brush $dropBg
            $n.Dash.Stroke = Brush $dashC
            $n.Name.Foreground = Brush $script:VsMeta
            $n.Hint.Foreground = Brush $script:VsMeta
        }
    }
    $NodePrompt.Background = Brush $script:VsCardBg
    $NodePrompt.BorderBrush = Brush $script:VsCardLine
    $SceneTextBorder.Background = Brush $dropBg
    $SceneTextBorder.BorderBrush = Brush $script:VsCardLine
    $SceneText.Foreground = Brush $script:VsInk
    $SceneTextHint.Foreground = Brush $script:VsMeta
    $PromptBorder.Background = Brush $dropBg
    $PromptBorder.BorderBrush = Brush $script:VsCardLine
    $PromptText.Foreground = Brush $script:VsInk
    $PromptHint.Foreground = Brush $script:VsMeta
    $StyleBox.Background = Brush $dropBg
    $StyleBox.Foreground = Brush $script:VsInk
    $VsStatus.Foreground = Brush $script:VsMeta
    $FlowBar.Background = Brush $script:VsCardBg
    $FlowBar.BorderBrush = Brush $script:VsCardLine
    $VsStatusBar.BorderBrush = Brush $(if ($script:dark) { "#1E2A38" } else { "#DCE4EE" })
    $OutLabel.Foreground = Brush $script:VsMeta
    $script:lastOutSig = "`0force"
    Refresh-Outputs
}
$DarkBtn.Add_Click({
    $script:dark = -not $script:dark
    try { [IO.File]::WriteAllText("D:\tmp\live_theme.txt", $script:dark.ToString(), [Text.Encoding]::UTF8) } catch { }
    Apply-Theme
    $script:forceRefresh = $true
    Refresh-Feed
})
$ShotBtn.Add_Click({
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save("D:\tmp\screen_for_xiaozhu.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Append-Feed "Dave" "note" "📸 我刚截了一张屏幕图给你看，你下次连接时调出来看"
        Refresh-Feed
    } catch { }
})
$SearchBox.Add_TextChanged({
    $script:filter = $SearchBox.Text.Trim()
    $SearchHint.Visibility = if ($SearchBox.Text) { "Collapsed" } else { "Visible" }
    $script:forceRefresh = $true
    Refresh-Feed
})

$script:KindName = @{ status = "状态"; command = "命令"; result = "结果"; question = "提问"; note = "留言"; task = "任务"; decision = "决定" }
$script:dark = $false
$script:filter = ""
$script:forceRefresh = $false
$script:PalLight = @{ MyBg = "#FFFFFF"; MyLine = "#E2EAF2"; DaveBg = "#D9E9FF"; Ink = "#1B2C42"; Meta = "#8496AB" }
$script:PalDark = @{ MyBg = "#22303F"; MyLine = "#3A4E66"; DaveBg = "#2B4A73"; Ink = "#E9F1F9"; Meta = "#93A8BE" }
function Pal() { if ($script:dark) { return $script:PalDark } else { return $script:PalLight } }
$script:ChipBg   = @{ status = "#E4F2E7"; command = "#E1EEFC"; result = "#F1E4F7"; question = "#FBE7E4"; note = "#E9EEF2"; task = "#E1EEFC"; decision = "#FBE7E4" }
$script:ChipFg   = @{ status = "#1E7D32"; command = "#1565C0"; result = "#7B1FA2"; question = "#C62828"; note = "#546E7A"; task = "#1565C0"; decision = "#C62828" }

function Convert-FeedTime([string]$t) {
    $d = [datetime]::MinValue
    if ([datetime]::TryParseExact($t, "HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) {
        return (Get-Date).Date.Add($d.TimeOfDay)
    }
    return (Get-Date)
}
# 把小猪的聊天流和协作总线的留言合成一条时间线：一个窗口里三个人说话
function Read-MergedFeed {
    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($e in (Read-Feed)) {
        [void]$out.Add([pscustomobject]@{
                n = $i; when = (Convert-FeedTime ([string]$e.ts)); ts = [string]$e.ts
                sender = [string]$e.sender; kind = [string]$e.kind; text = [string]$e.text
            })
        $i++
    }
    try {
        foreach ($m in (Read-BusJsonl "board.jsonl")) {
            if ([string]$m.ref -eq "mirror") { continue }
            $w = Get-Date
            try { $w = [datetime]::Parse([string]$m.ts) } catch { }
            [void]$out.Add([pscustomobject]@{
                    n = $i; when = $w; ts = $w.ToString("HH:mm:ss")
                    sender = [string]$m.from; kind = [string]$m.kind; text = [string]$m.text
                })
            $i++
        }
    } catch { }
    return @($out | Sort-Object when, n)
}

function New-EntryView($e) {
    $s = [string]$e.sender
    $isDave = ($s -eq "Dave" -or $s -eq "余佳凯")
    $isZhu = ($s -eq "assistant" -or $s -eq "小猪" -or -not $s)
    $isAgent = (-not $isDave) -and (-not $isZhu)
    $outer = New-Object Windows.Controls.StackPanel
    $outer.Margin = New-Object Windows.Thickness(10, 5, 10, 5)
    $outer.HorizontalAlignment = if ($isDave) { "Right" } else { "Left" }
    $who = if ($isDave) { "Dave" } elseif ($isZhu) { "小猪" } else { $s }
    $meta = New-Object Windows.Controls.TextBlock
    $role = Get-RoleInfo $s
    $meta.Text = [string]$role.label + " · " + $who + " · " + $e.ts
    $meta.FontSize = 11
    $meta.Foreground = Brush ((Pal)["Meta"])
    $meta.Margin = New-Object Windows.Thickness(4, 0, 4, 3)
    $meta.HorizontalAlignment = if ($isDave) { "Right" } else { "Left" }
    $outer.Children.Add($meta) | Out-Null
    $bubble = New-Object Windows.Controls.Border
    $bubble.MaxWidth = 400
    if ($isDave) {
        $bubble.Background = Brush ((Pal)["DaveBg"])
        $bubble.CornerRadius = New-Object Windows.CornerRadius(16, 16, 4, 16)
    } elseif ($isAgent) {
        $agentBg = if ($s -like "*Qwen*") { if ($script:dark) { "#1E4030" } else { "#DFF2E2" } } else { if ($script:dark) { "#39264D" } else { "#F0E6FA" } }
        $bubble.Background = Brush $agentBg
        $bubble.CornerRadius = New-Object Windows.CornerRadius(16, 16, 16, 4)
    } else {
        $bubble.Background = Brush ((Pal)["MyBg"])
        $bubble.BorderBrush = Brush ((Pal)["MyLine"])
        $bubble.BorderThickness = New-Object Windows.Thickness(1)
        $bubble.CornerRadius = New-Object Windows.CornerRadius(16, 16, 16, 4)
    }
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 10; $shadow.ShadowDepth = 2; $shadow.Opacity = 0.10
    $shadow.Color = [Windows.Media.ColorConverter]::ConvertFromString("#33507A")
    $bubble.Effect = $shadow
    $inner = New-Object Windows.Controls.StackPanel
    $inner.Margin = New-Object Windows.Thickness(13, 9, 13, 10)
    $kind = [string]$e.kind
    $chipRow = New-Object Windows.Controls.StackPanel
    $chipRow.Orientation = "Horizontal"
    $chip = New-Object Windows.Controls.Border
    $chip.CornerRadius = New-Object Windows.CornerRadius(7)
    $chip.Background = Brush $script:ChipBg[$kind]
    if (-not $chip.Background) { $chip.Background = Brush "#E9EEF2" }
    $chip.Padding = New-Object Windows.Thickness(8, 2.5, 8, 2.5)
    $chipText = New-Object Windows.Controls.TextBlock
    $chipText.Text = $script:KindName[$kind]
    if (-not $chipText.Text) { $chipText.Text = "留言" }
    $chipText.FontSize = 11
    $chipText.FontWeight = "SemiBold"
    $chipText.Foreground = Brush $script:ChipFg[$kind]
    if (-not $chipText.Foreground) { $chipText.Foreground = Brush "#546E7A" }
    $chip.Child = $chipText
    $chipRow.Children.Add($chip) | Out-Null
    $inner.Children.Add($chipRow) | Out-Null
    $body = New-SelectableText ([string]$e.text) 13.5 (Brush ((Pal)["Ink"])) 20
    $inner.Children.Add($body) | Out-Null
    $bubble.Child = $inner
    $outer.Children.Add($bubble) | Out-Null
    return $outer
}

$script:lastCount = -1
function Refresh-Feed {
    $items = Read-MergedFeed
    if ($script:forceRefresh -or $items.Count -ne $script:lastCount) {
        $script:forceRefresh = $false
        $nearBottom = $true
        if ($script:lastCount -ge 0) {
            $nearBottom = (($FeedScroll.ScrollableHeight - $FeedScroll.VerticalOffset) -lt 80)
        }
        $oldCount = $script:lastCount
        $FeedList.Children.Clear()
        $idx = 0
        foreach ($e in $items) {
            if ($script:filter) {
                $hay = ([string]$e.text) + " " + ([string]$e.kind) + " " + ([string]$e.sender)
                if ($hay -notlike ("*" + $script:filter + "*")) { continue }
            }
            $view = New-EntryView $e
            if ($idx -ge [Math]::Max(0, $oldCount)) {
                $view.Opacity = 0
                $view.RenderTransformOrigin = New-Object Windows.Point(0.5, 1)
                $tg = New-Object Windows.Media.TransformGroup
                $tr = New-Object Windows.Media.TranslateTransform(0, 12)
                $sc = New-Object Windows.Media.ScaleTransform(0.93, 0.93)
                $tg.Children.Add($tr) | Out-Null
                $tg.Children.Add($sc) | Out-Null
                $view.RenderTransform = $tg
                $ease = New-Object Windows.Media.Animation.BackEase
                $ease.EasingMode = "EaseOut"; $ease.Amplitude = 0.45
                $dur = New-Object Windows.Duration([TimeSpan]::FromMilliseconds(400))
                $a1 = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(240))))
                $view.BeginAnimation([Windows.UIElement]::OpacityProperty, $a1)
                $a2 = New-Object Windows.Media.Animation.DoubleAnimation(12, 0, $dur)
                $a2.EasingFunction = $ease
                $tr.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a2)
                $a3 = New-Object Windows.Media.Animation.DoubleAnimation(0.93, 1, $dur)
                $a3.EasingFunction = $ease
                $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $a3)
                $sc.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $a3)
            }
            $FeedList.Children.Add($view) | Out-Null
            $idx++
        }
        if ($oldCount -ge 0 -and $items.Count -gt $oldCount) { $script:LiveBusyUntil = (Get-Date).AddSeconds(8) }
        $script:lastCount = $items.Count
        $StatusText.Text = "已同步 " + $items.Count + " 条 · " + (Get-Date -Format "HH:mm:ss")
        if ($nearBottom) { $FeedScroll.ScrollToEnd() }
    }
}

$send = {
    $t = $InputBox.Text.Trim()
    if ($t) {
        Append-Feed "Dave" "note" $t
        # 同步一份到协作总线，两个助手下一轮都能看到（ref=mirror 只给机器看，聊天流不重复显示）
        try {
            Add-BusJsonl "board.jsonl" ([ordered]@{
                    ts   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    from = "余佳凯"
                    to   = "all"
                    kind = "note"
                    text = $t
                    ref  = "mirror"
                    id   = [guid]::NewGuid().ToString("N").Substring(0, 8)
                })
        } catch { }
        $InputBox.Text = ""
        $script:forceRefresh = $true
        Refresh-Feed
    }
}
$win.FindName("SendBtn").Add_Click($send)
$InputBox.Add_KeyDown({ if ($_.Key -eq "Enter") { & $send } })
$InputBox.Add_TextChanged({ $InputHint.Visibility = if ($InputBox.Text) { "Collapsed" } else { "Visible" } })
$InputBox.Add_GotFocus({ $InputBorder.BorderBrush = Brush "#2F7DE1" })
$InputBox.Add_LostFocus({ $InputBorder.BorderBrush = Brush $(if ($script:dark) { "#3A4E66" } else { "#D7E1EC" }) })
$win.FindName("BtnClose").Add_Click({ $win.Close() })
$win.FindName("BtnMin").Add_Click({ $win.WindowState = "Minimized" })
$script:big = $false
$win.FindName("BtnMax").Add_Click({
    if ($script:big) { $win.Width = 560; $win.Height = 720; $script:big = $false }
    else { $win.Width = 880; $win.Height = 840; $script:big = $true }
    $win.Left = ([Windows.SystemParameters]::WorkArea.Width - $win.Width) / 2
    $win.Top = ([Windows.SystemParameters]::WorkArea.Height - $win.Height) / 2
})
$Header.Add_MouseLeftButtonDown({
    $src = $_.OriginalSource
    while ($src -and -not ($src -is [Windows.Controls.Button])) { $src = [Windows.Media.VisualTreeHelper]::GetParent($src) }
    if (-not $src) { try { $win.DragMove() } catch {} }
})

# ===== 视频工坊 v5.1：节点画布 =====
$VsRoot = "D:\tmp\video_studio"
$script:VsLines = @()
$script:VsCardBg = "#FFFFFF"
$script:VsCardLine = "#DCE4EE"
$script:VsInk = "#16283C"
$script:VsMeta = "#8496AB"
$script:VsNodes = @{
    char  = @{ Node = $NodeChar;  Drop = $DropChar;  Img = $ImgChar;  Hint = $HintChar;  Dash = $DashChar;  Name = $NameChar;  Accent = "#2F7DE1"; Path = $null }
    bg    = @{ Node = $NodeBg;    Drop = $DropBg;    Img = $ImgBg;    Hint = $HintBg;    Dash = $DashBg;    Name = $NameBg;    Accent = "#43A047"; Path = $null }
    scene = @{ Node = $NodeScene; Drop = $DropScene; Img = $ImgScene; Hint = $HintScene; Dash = $DashScene; Name = $NameScene; Accent = "#8E24AA"; Path = $null }
}
function Add-FlowLine($x1, $y1, $x2, $y2) {
    $dx = [Math]::Max(36, ($x2 - $x1) / 2)
    $fig = New-Object Windows.Media.PathFigure
    $fig.StartPoint = New-Object Windows.Point($x1, $y1)
    $seg = New-Object Windows.Media.BezierSegment
    $seg.Point1 = New-Object Windows.Point(($x1 + $dx), $y1)
    $seg.Point2 = New-Object Windows.Point(($x2 - $dx), $y2)
    $seg.Point3 = New-Object Windows.Point($x2, $y2)
    $fig.Segments.Add($seg) | Out-Null
    $pg = New-Object Windows.Media.PathGeometry
    $pg.Figures.Add($fig) | Out-Null
    $path = New-Object Windows.Shapes.Path
    $path.Data = $pg
    $path.Stroke = Brush "#A9BCD2"
    $path.StrokeThickness = 2
    $VsCanvas.Children.Insert(0, $path) | Out-Null
    $script:VsLines += $path
}
function Add-Port($x, $y) {
    $e = New-Object Windows.Shapes.Ellipse
    $e.Width = 9; $e.Height = 9
    $e.Fill = Brush "#8FA6BC"
    $e.Stroke = Brush "#FFFFFF"
    $e.StrokeThickness = 1.6
    [Windows.Controls.Canvas]::SetLeft($e, $x - 4.5)
    [Windows.Controls.Canvas]::SetTop($e, $y - 4.5)
    $VsCanvas.Children.Add($e) | Out-Null
}
function Set-NodeImage($key, $path) {
    $n = $script:VsNodes[$key]
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if (@(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp") -notcontains $ext) { $n.Name.Text = "⚠ 请选择图片文件"; return }
    try {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = [Uri]::new($path)
        $bi.CacheOption = "OnLoad"
        $bi.DecodePixelWidth = 360
        $bi.EndInit()
        $n.Img.Source = $bi
        $n.Img.Visibility = "Visible"
        $n.Hint.Visibility = "Collapsed"
        $n.Dash.Visibility = "Collapsed"
        $n.Path = $path
        $n.Name.Text = [IO.Path]::GetFileName($path)
        Reset-NodeHi $key
        Refresh-Flow
    } catch { $n.Name.Text = "⚠ 图片读取失败" }
}
function Refresh-Flow {
    try {
        $on = Brush "#35C759"; $off = Brush "#C3D2E2"
        $FlowDotChar.Fill = if ($script:VsNodes["char"].Path) { $on } else { $off }
        $FlowDotBg.Fill = if ($script:VsNodes["bg"].Path) { $on } else { $off }
        $FlowDotScene.Fill = if ($script:VsNodes["scene"].Path -or $SceneText.Text.Trim()) { $on } else { $off }
        $FlowDotPrompt.Fill = if ($PromptText.Text.Trim()) { $on } else { $off }
    } catch { }
}
function Reset-NodeHi($key) {
    $n = $script:VsNodes[$key]
    if (-not $n) { return }
    $n.Node.BorderBrush = Brush $script:VsCardLine
    $n.Node.BorderThickness = New-Object Windows.Thickness(1)
    $n.Node.RenderTransform = $null
}
foreach ($key in @("char", "bg", "scene")) {
    $n = $script:VsNodes[$key]
    foreach ($el in @($n.Drop, $n.Img)) {
        $el.Add_DragOver({ param($s, $e)
            if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {
                $e.Effects = "Copy"
                $e.Handled = $true
                $nd = $script:VsNodes[[string]$s.Tag]
                if ($nd) {
                    $nd.Node.BorderBrush = Brush $nd.Accent
                    $nd.Node.BorderThickness = New-Object Windows.Thickness(1.6)
                    $nd.Node.RenderTransform = New-Object Windows.Media.ScaleTransform(1.03, 1.03)
                }
            }
        })
        $el.Add_DragLeave({ param($s, $e) Reset-NodeHi ([string]$s.Tag) })
        $el.Add_Drop({ param($s, $e)
            $k = [string]$s.Tag
            Reset-NodeHi $k
            $files = $e.Data.GetData([Windows.DataFormats]::FileDrop)
            if ($files -and $files.Length -gt 0) { Set-NodeImage $k ([string]$files[0]) }
            $e.Handled = $true
        })
        $el.Add_MouseLeftButtonUp({ param($s, $e)
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = "图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp"
            $dlg.Title = "选择图片"
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Set-NodeImage ([string]$s.Tag) $dlg.FileName }
        })
    }
}
$SceneText.Add_TextChanged({ $SceneTextHint.Visibility = if ($SceneText.Text) { "Collapsed" } else { "Visible" }; Refresh-Flow })
$PromptText.Add_TextChanged({ $PromptHint.Visibility = if ($PromptText.Text) { "Collapsed" } else { "Visible" }; Refresh-Flow })
foreach ($s in @("电影感", "动漫风", "写实", "黏土定格", "水墨国风", "赛博朋克")) { $StyleBox.Items.Add($s) | Out-Null }
$StyleBox.Text = "电影感"
$script:lastOutSig = ""
function Refresh-Outputs {
    $outDir = Join-Path $VsRoot "outputs"
    $files = @()
    if (Test-Path $outDir) { $files = @(Get-ChildItem -LiteralPath $outDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) }
    $sig = ($files | ForEach-Object { $_.Name }) -join "|"
    if ($sig -eq $script:lastOutSig) { return }
    $script:lastOutSig = $sig
    $OutPanel.Children.Clear()
    if ($files.Count -eq 0) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = "还没有成品，生成的视频会出现在这里"
        $tb.FontSize = 12
        $tb.Foreground = Brush $script:VsMeta
        $tb.VerticalAlignment = "Center"
        $OutPanel.Children.Add($tb) | Out-Null
        return
    }
    foreach ($f in $files) {
        $chip = New-Object Windows.Controls.Border
        $chip.CornerRadius = New-Object Windows.CornerRadius(8)
        $chip.Background = Brush $script:VsCardBg
        $chip.BorderBrush = Brush $script:VsCardLine
        $chip.BorderThickness = New-Object Windows.Thickness(1)
        $chip.Padding = New-Object Windows.Thickness(10, 5, 10, 5)
        $chip.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
        $chip.Cursor = "Hand"
        $chip.Tag = $f.FullName
        $sp = New-Object Windows.Controls.StackPanel
        $t1 = New-Object Windows.Controls.TextBlock
        $t1.Text = "🎬 " + $f.Name
        $t1.FontSize = 12
        $t1.Foreground = Brush $script:VsInk
        $t2 = New-Object Windows.Controls.TextBlock
        $t2.Text = $f.LastWriteTime.ToString("MM-dd HH:mm")
        $t2.FontSize = 10
        $t2.Foreground = Brush $script:VsMeta
        $sp.Children.Add($t1) | Out-Null
        $sp.Children.Add($t2) | Out-Null
        $chip.Child = $sp
        $chip.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ClickCount -eq 2) { try { Start-Process -FilePath ([string]$s.Tag) } catch { } } })
        $OutPanel.Children.Add($chip) | Out-Null
    }
}
$GenBtn.Add_Click({
    $charP = $script:VsNodes["char"].Path
    $bgP = $script:VsNodes["bg"].Path
    $sceneP = $script:VsNodes["scene"].Path
    $sceneText = $SceneText.Text.Trim()
    $style = $StyleBox.Text.Trim()
    $prompt = $PromptText.Text.Trim()
    $missing = @()
    if (-not $charP) { $missing += "人物" }
    if (-not $bgP) { $missing += "背景" }
    if ($missing.Count -gt 0) {
        $VsStatus.Text = "还差" + ($missing -join "、") + "图片，先补上再生成哦"
        foreach ($k in @("char", "bg")) {
            if (-not $script:VsNodes[$k].Path) {
                $script:VsNodes[$k].Node.BorderBrush = Brush "#E53935"
                $script:VsNodes[$k].Node.BorderThickness = New-Object Windows.Thickness(1.6)
            }
        }
        return
    }
    try {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $inDir = Join-Path $VsRoot ("inputs\" + $ts)
        $reqDir = Join-Path $VsRoot "requests"
        $outDir = Join-Path $VsRoot "outputs"
        foreach ($d in @($inDir, $reqDir, $outDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
        $copied = @{}
        foreach ($pair in @(@("character", $charP), @("background", $bgP), @("scene", $sceneP))) {
            if ($pair[1]) {
                $dest = Join-Path $inDir ([IO.Path]::GetFileName($pair[1]))
                Copy-Item -LiteralPath $pair[1] -Destination $dest -Force
                $copied[$pair[0]] = $dest
            } else { $copied[$pair[0]] = $null }
        }
        $req = [ordered]@{
            character = $copied["character"]
            background = $copied["background"]
            scene = $copied["scene"]
            sceneText = $sceneText
            style = $style
            prompt = $prompt
            created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $reqPath = Join-Path $reqDir ("req_" + $ts + ".json")
        [IO.File]::WriteAllText($reqPath, ($req | ConvertTo-Json), $Utf8)
        try { Ensure-StudioEngine } catch { }
        $flags = "人物" + $(if ($charP) { "✓" } else { "✗" }) + " 背景" + $(if ($bgP) { "✓" } else { "✗" }) + " 场景" + $(if ($sceneP) { "✓" } else { "✗" })
        $snip = $prompt
        if ($snip.Length -gt 36) { $snip = $snip.Substring(0, 36) + "…" }
        Append-Feed "Dave" "note" ("🎬 视频工坊提交（" + $flags + "｜风格：" + $style + "｜" + $snip + "），请求在 video_studio\requests\req_" + $ts + ".json，等掌柜生成")
        $VsStatus.Text = "✅ 已提交 " + (Get-Date -Format "HH:mm:ss") + " · req_" + $ts + ".json，成品好了会出现在下方"
        Refresh-Feed
    } catch {
        $VsStatus.Text = "⚠ 提交失败：" + $_.Exception.Message
    }
})
function Add-PressFx($el) {
    try {
        $el.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
        $el.RenderTransform = New-Object Windows.Media.ScaleTransform(1, 1)
        $el.Add_PreviewMouseDown({ param($s, $e) try { $st = $s.RenderTransform; $aa = New-Object Windows.Media.Animation.DoubleAnimation(0.86, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(90)))); $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $aa); $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $aa) } catch { } })
        $el.Add_PreviewMouseUp({ param($s, $e) try { $st = $s.RenderTransform; $ee = New-Object Windows.Media.Animation.BackEase; $ee.EasingMode = "EaseOut"; $ee.Amplitude = 0.55; $aa = New-Object Windows.Media.Animation.DoubleAnimation(1, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(320)))); $aa.EasingFunction = $ee; $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $aa); $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $aa) } catch { } })
    } catch { }
}
Add-PressFx $GenBtn
Add-PressFx ($win.FindName("SendBtn"))
$script:LiveBusyUntil = [DateTime]::MinValue
$script:LiveSb = $null
function Start-LiveBadge {
    try {
        $sb = New-Object Windows.Media.Animation.Storyboard
        foreach ($pp in @("(UIElement.RenderTransform).(ScaleTransform.ScaleX)", "(UIElement.RenderTransform).(ScaleTransform.ScaleY)")) {
            $a = New-Object Windows.Media.Animation.DoubleAnimation
            $a.From = 1.0; $a.To = 1.5
            $a.Duration = New-Object Windows.Duration([TimeSpan]::FromSeconds(0.8))
            $a.AutoReverse = $true
            $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            [Windows.Media.Animation.Storyboard]::SetTarget($a, $LiveDot)
            [Windows.Media.Animation.Storyboard]::SetTargetProperty($a, (New-Object Windows.Media.Animation.PropertyPath($pp)))
            $sb.Children.Add($a) | Out-Null
        }
        $ao = New-Object Windows.Media.Animation.DoubleAnimation
        $ao.From = 1.0; $ao.To = 0.5
        $ao.Duration = New-Object Windows.Duration([TimeSpan]::FromSeconds(0.8))
        $ao.AutoReverse = $true
        $ao.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        [Windows.Media.Animation.Storyboard]::SetTarget($ao, $LiveDot)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($ao, (New-Object Windows.Media.Animation.PropertyPath("Opacity")))
        $sb.Children.Add($ao) | Out-Null
        $script:LiveSb = $sb
        $sb.Begin()
    } catch { }
}
function Tick-LiveBadge {
    try {
        if ($script:LiveSb) {
            $target = if ((Get-Date) -lt $script:LiveBusyUntil) { 2.3 } else { 1.0 }
            if ([Math]::Abs($script:LiveSb.SpeedRatio - $target) -gt 0.01) { $script:LiveSb.SpeedRatio = $target }
        }
    } catch { }
}
$script:studio = $false
function Update-Rail {
    try {
        $active = if ($script:dark) { "#2B4A73" } else { "#DCEBFC" }
        $fg = if ($script:dark) { "#AFC0D2" } else { "#5A6E85" }
        $BtnChat.Background = Brush $(if ((-not $script:studio) -and (-not $script:collab)) { $active } else { "Transparent" })
        $StudioBtn.Background = Brush $(if ($script:studio) { $active } else { "Transparent" })
        $CollabBtn.Background = Brush $(if ($script:collab) { $active } else { "Transparent" })
        foreach ($b in @($BtnChat, $StudioBtn, $CollabBtn, $ArchiveBtn)) { $b.Foreground = Brush $fg }
    } catch { }
}
function Set-Studio($on) {
    $script:studio = $on
    if ($on) {
        if ($script:collab) { Set-Collab $false }
        $FeedScroll.Visibility = "Collapsed"
        $InputBar.Visibility = "Collapsed"
        $StudioView.Visibility = "Visible"
        $StudioBtn.ToolTip = "回到聊天"
        Refresh-Outputs
        Refresh-Flow
    } else {
        $FeedScroll.Visibility = "Visible"
        $InputBar.Visibility = "Visible"
        $StudioView.Visibility = "Collapsed"
        $StudioBtn.ToolTip = "视频工坊"
    }
    Update-Rail
}
$StudioBtn.Add_Click({ Set-Studio (-not $script:studio) })

# ===== 协作台 / 渲染守夜人 =====
function Ensure-StudioEngine {
    $mine = $PID
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $mine -and $_.CommandLine -match 'studio_daemon\.ps1' }
    if (-not $running) {
        $daemon = "D:\tmp\video_studio\engine\studio_daemon.ps1"
        if (Test-Path $daemon) {
            Start-Process wscript.exe -ArgumentList '"D:\tmp\video_studio\engine\launch_daemon.vbs"' -WindowStyle Hidden
        }
    }
}
function Open-Collab {
    if ($script:studio) { Set-Studio $false }
    Set-Collab (-not $script:collab)
}

# ---------- 协作台：留言板 / 动作日志 / 占用 ----------
$script:collab = $false
$script:cbView = "board"
$script:cbFilter = "all"
$script:cbKey = ""
$script:cbSeen = 0
$script:sendTotal = 0
$BusRoot = "D:\tmp\nailong\bus"
$CbKindMap = @{ "留言" = "note"; "状态" = "status"; "任务" = "task"; "提问" = "question"; "决定" = "decision" }
$CbKindName = @{ note = "留言"; status = "状态"; task = "任务"; question = "提问"; decision = "决定"; result = "回报"; log = "日志" }
$CbKindBgL = @{ note = "#E9EEF2"; status = "#E4F2E7"; task = "#E1EEFC"; question = "#FBF0DC"; decision = "#FBE7E4"; result = "#F1E4F7"; log = "#E9EEF2" }
$CbKindFgL = @{ note = "#546E7A"; status = "#1E7D32"; task = "#1565C0"; question = "#B26500"; decision = "#C62828"; result = "#7B1FA2"; log = "#546E7A" }
$CbKindBgD = @{ note = "#2C3E52"; status = "#1E4030"; task = "#1E3A56"; question = "#4D3418"; decision = "#4A2320"; result = "#3B2547"; log = "#2C3E52" }
$CbKindFgD = @{ note = "#AFC0D2"; status = "#8FD6A0"; task = "#9CC3EE"; question = "#F2C184"; decision = "#F2A7A0"; result = "#D3A8EE"; log = "#AFC0D2" }

function Read-BusJsonl([string]$name) {
    $path = Join-Path $BusRoot $name
    $items = @()
    if (-not (Test-Path $path)) { return $items }
    foreach ($l in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
        if (-not $l.Trim()) { continue }
        try { $items += ($l | ConvertFrom-Json) } catch { }
    }
    return $items
}
function Add-BusJsonl([string]$name, $obj) {
    $path = Join-Path $BusRoot $name
    if (-not (Test-Path $BusRoot)) { New-Item -ItemType Directory -Path $BusRoot -Force | Out-Null }
    $line = ($obj | ConvertTo-Json -Compress -Depth 5) + "`n"
    $enc = New-Object Text.UTF8Encoding($false)
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
            $sw = New-Object IO.StreamWriter($fs, $enc)
            $sw.Write($line); $sw.Flush(); $sw.Dispose(); $fs.Dispose()
            return
        } catch { Start-Sleep -Milliseconds 60 }
    }
}
function Get-RoleInfo([string]$from) {
    if ($from -match '指挥部|DAVE|Dave|余佳凯') { return @{ label = "客官"; color = "#D9534F"; bgL = "#FBE7E4"; bgD = "#4A2320" } }
    if ($from -match '调度|XIAOZHU|小猪|assistant') { return @{ label = "掌柜"; color = "#2F7DE1"; bgL = "#E1EEFC"; bgD = "#1E3A56" } }
    if ($from -match '工兵|LOCAL|DSH') { return @{ label = "大厨"; color = "#2E9E5B"; bgL = "#DFF2E2"; bgD = "#1E4030" } }
    return @{ label = "成员"; color = "#8E24AA"; bgL = "#F0E6FA"; bgD = "#39264D" }
}
function New-CbCard($m, [bool]$isLog) {
    $from = [string]$m.from
    $role = Get-RoleInfo $from
    $dark = [bool]$script:dark
    $bg = if ($dark) { "#22303F" } else { "#FFFFFF" }
    $line = if ($dark) { "#3A4E66" } else { "#E4ECF5" }
    $fg = if ($dark) { "#E9F1F9" } else { "#1B2C42" }
    $meta = if ($dark) { "#93A8BE" } else { "#8496AB" }
    $accent = [string]$role.color

    $card = New-Object Windows.Controls.Border
    $card.Background = Brush $bg
    $card.BorderBrush = Brush $line
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.CornerRadius = New-Object Windows.CornerRadius(10)
    $card.Margin = New-Object Windows.Thickness(6, 4, 6, 4)
    $card.Padding = New-Object Windows.Thickness(0)

    $grid = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = "5"
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = "*"
    $grid.ColumnDefinitions.Add($c0) | Out-Null
    $grid.ColumnDefinitions.Add($c1) | Out-Null

    $bar = New-Object Windows.Controls.Border
    $bar.Background = Brush $accent
    $bar.CornerRadius = New-Object Windows.CornerRadius(10, 0, 0, 10)
    [Windows.Controls.Grid]::SetColumn($bar, 0)
    $grid.Children.Add($bar) | Out-Null

    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = New-Object Windows.Thickness(12, 8, 12, 9)
    [Windows.Controls.Grid]::SetColumn($sp, 1)

    $head = New-Object Windows.Controls.StackPanel
    $head.Orientation = "Horizontal"
    $roleChip = New-Object Windows.Controls.Border
    $roleChip.CornerRadius = New-Object Windows.CornerRadius(5)
    $roleChip.Padding = New-Object Windows.Thickness(5, 1, 5, 1)
    $roleChip.Background = Brush $(if ($dark) { $role.bgD } else { $role.bgL })
    $roleT = New-Object Windows.Controls.TextBlock
    $roleT.Text = [string]$role.label
    $roleT.FontSize = 10
    $roleT.FontWeight = "SemiBold"
    $roleT.Foreground = Brush ([string]$role.color)
    $roleChip.Child = $roleT
    $head.Children.Add($roleChip) | Out-Null

    $shortFrom = $from
    if ($from -match 'DSH') { $shortFrom = "后厨" }
    elseif ($from -match '工兵') {
        $shortFrom = ($from -replace '工兵', '' -replace '[\(\)（）]', '').Trim()
        if (-not $shortFrom) { $shortFrom = "LOCAL" }
    }
    $nm = New-Object Windows.Controls.TextBlock
    $nm.Text = $shortFrom
    $nm.FontSize = 12
    $nm.FontWeight = "SemiBold"
    $nm.Foreground = Brush $fg
    $nm.Margin = New-Object Windows.Thickness(6, 0, 0, 0)
    $head.Children.Add($nm) | Out-Null

    if (-not $isLog) {
        $kind = [string]$m.kind
        if (-not $kind) { $kind = "note" }
        $chip = New-Object Windows.Controls.Border
        $chip.CornerRadius = New-Object Windows.CornerRadius(6)
        $chip.Padding = New-Object Windows.Thickness(6, 1, 6, 1)
        $chip.Margin = New-Object Windows.Thickness(8, 0, 0, 0)
        $chip.Background = Brush $(if ($dark) { $CbKindBgD[$kind] } else { $CbKindBgL[$kind] })
        if (-not $chip.Background) { $chip.Background = Brush "#E9EEF2" }
        $ct = New-Object Windows.Controls.TextBlock
        $ct.Text = $(if ($CbKindName[$kind]) { $CbKindName[$kind] } else { "留言" })
        $ct.FontSize = 10.5
        $ct.FontWeight = "SemiBold"
        $ct.Foreground = Brush $(if ($dark) { $CbKindFgD[$kind] } else { $CbKindFgL[$kind] })
        $chip.Child = $ct
        $head.Children.Add($chip) | Out-Null
    }

    $tt = New-Object Windows.Controls.TextBlock
    $tt.Text = [string]$m.ts
    $tt.FontSize = 10.5
    $tt.Foreground = Brush $meta
    $tt.Margin = New-Object Windows.Thickness(8, 0, 0, 0)
    $head.Children.Add($tt) | Out-Null
    $sp.Children.Add($head) | Out-Null

    $body = New-SelectableText ([string]$m.text) 12.8 (Brush $fg) 19
    $sp.Children.Add($body) | Out-Null

    if ($m.ref -and [string]$m.ref -ne "mirror") {
        $rf = New-Object Windows.Controls.TextBlock
        $rf.Text = "↳ " + [string]$m.ref
        $rf.FontSize = 10.5
        $rf.Foreground = Brush $meta
        $rf.Margin = New-Object Windows.Thickness(0, 4, 0, 0)
        $sp.Children.Add($rf) | Out-Null
    }

    $grid.Children.Add($sp) | Out-Null
    $card.Child = $grid
    return $card
}
function Refresh-Collab {
    $items = @()
    $key = $script:cbView + "|" + [string]$script:dark
    switch ($script:cbView) {
        "board" {
            $items = @(Read-BusJsonl "board.jsonl")
            $script:sendTotal = $items.Count
            $key += "|" + $items.Count + "|" + $script:cbFilter
            switch ($script:cbFilter) {
                "me" { $items = @($items | Where-Object { ([string]$_.to) -match '工兵|LOCAL' -or ([string]$_.text) -match '工兵' }) }
                "task" { $items = @($items | Where-Object { [string]$_.kind -eq "task" }) }
                "dec" { $items = @($items | Where-Object { [string]$_.kind -eq "decision" }) }
            }
        }
        "log" {
            $items = @(Read-BusJsonl "activity.jsonl")
            $key += "|" + $items.Count
        }
        "claim" {
            $dir = Join-Path $BusRoot "claims"
            $items = @()
            if (Test-Path $dir) {
                foreach ($f in (Get-ChildItem $dir -Filter "*.json" -ErrorAction SilentlyContinue)) {
                    try { $items += ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { }
                }
            }
            $key += "|" + (($items | ForEach-Object { $_.owner + $_.ts }) -join ",")
        }
    }
    if ($key -eq $script:cbKey) { return }
    $script:cbKey = $key

    $CbList.Children.Clear()
    if ($items.Count -eq 0) {
        $empty = New-Object Windows.Controls.TextBlock
        $empty.Text = $(if ($script:cbView -eq "claim") { "现在没人占坑，两份代码可以并行改" } else { "这里还空着" })
        $empty.FontSize = 12.5
        $empty.Foreground = Brush $(if ($script:dark) { "#6E8299" } else { "#9FB0C3" })
        $empty.Margin = New-Object Windows.Thickness(16, 26, 0, 0)
        $CbList.Children.Add($empty) | Out-Null
        $CbCount.Text = ""
        return
    }

    $shown = @($items | Select-Object -Last 100)
    foreach ($m in $shown) {
        if ($script:cbView -eq "claim") {
            $fake = [pscustomobject]@{ from = [string]$m.owner; ts = [string]$m.ts; kind = "task"; text = ("🔒 " + [string]$m.resource + "  " + [string]$m.note); ref = "" }
            $CbList.Children.Add((New-CbCard $fake $false)) | Out-Null
        } else {
            $CbList.Children.Add((New-CbCard $m ($script:cbView -eq "log"))) | Out-Null
        }
    }
    $CbCount.Text = "共 " + $items.Count + " 条"
    $CbScroll.ScrollToEnd()
    if ($script:collab) { $script:cbSeen = $script:sendTotal }
}
function Update-CollabBadge {
    $unread = $script:sendTotal - $script:cbSeen
    if ($CollabDot) {
        $CollabDot.Visibility = if ((-not $script:collab) -and $unread -gt 0) { "Visible" } else { "Collapsed" }
    }
}
function Post-Collab {
    $t = $CbInput.Text.Trim()
    if (-not $t) { return }
    $kind = $script:sendKind
    if (-not $kind) { $kind = "note" }
    $to = $script:sendTo
    if (-not $to) { $to = "all" }
    Add-BusJsonl "board.jsonl" ([ordered]@{
        ts   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        from = "余佳凯"
        to   = $to
        kind = $kind
        text = $t
        ref  = ""
        id   = [guid]::NewGuid().ToString("N").Substring(0, 8)
    })
    $CbInput.Text = ""
    $script:cbKey = ""
    Refresh-Collab
}
function Set-CbView([string]$v) {
    $script:cbView = $v
    $script:cbKey = ""
    $active = @("#DCEBFC", "#12559E")
    $idle = @("#FFFFFF", "#5A6E85")
    if ($script:dark) { $active = @("#1E3A56", "#9CC3EE"); $idle = @("#22303F", "#AFC0D2") }
    foreach ($pair in @(@("board", $CbBoard), @("log", $CbLog), @("claim", $CbClaim))) {
        $btn = $pair[1]
        $isOn = ($pair[0] -eq $v)
        $btn.Background = Brush $(if ($isOn) { $active[0] } else { $idle[0] })
        $btn.Foreground = Brush $(if ($isOn) { $active[1] } else { $idle[1] })
        $btn.FontWeight = if ($isOn) { "SemiBold" } else { "Normal" }
    }
    Refresh-Collab
}
function Set-Collab([bool]$on) {
    $script:collab = $on
    if ($on) {
        if ($script:studio) { Set-Studio $false }
        $FeedScroll.Visibility = "Collapsed"
        $InputBar.Visibility = "Collapsed"
        $CollabView.Visibility = "Visible"
        $script:cbKey = ""
        Set-CbView $script:cbView
        $script:cbSeen = $script:sendTotal
    } else {
        $FeedScroll.Visibility = "Visible"
        $InputBar.Visibility = "Visible"
        $CollabView.Visibility = "Collapsed"
    }
    Update-CollabBadge
    Update-Rail
}
$CollabBtn.Add_Click({ Open-Collab })
$BtnChat.Add_Click({
    if ($script:studio) { Set-Studio $false }
    if ($script:collab) { Set-Collab $false }
    Update-Rail
})
$script:searchOpen = $false
$SearchBtn.Add_Click({
    $script:searchOpen = -not $script:searchOpen
    if ($script:searchOpen) {
        $SearchBorder.Visibility = "Visible"
        $SearchBorder.Width = 180
        $SearchBox.Focus() | Out-Null
    } else {
        $SearchBorder.Visibility = "Collapsed"
        $SearchBorder.Width = 0
        $SearchBox.Text = ""
    }
})
$KindOrder = @("note", "status", "task", "question", "decision")
$ToOrder = @("all", "XIAOZHU", "LOCAL", "DAVE")
$ToLabel = @{ all = "全员"; XIAOZHU = "掌柜"; LOCAL = "大厨"; DAVE = "客官" }
$script:sendKind = "note"
$script:sendTo = "all"
$CbTo.Content = "发给：" + $ToLabel["all"]
$CbKind.Content = "类型：" + $CbKindName["note"]
$CbTo.Add_Click({
    $i = [Array]::IndexOf($ToOrder, $script:sendTo)
    $script:sendTo = $ToOrder[($i + 1) % $ToOrder.Count]
    $CbTo.Content = "发给：" + $ToLabel[$script:sendTo]
})
$CbKind.Add_Click({
    $i = [Array]::IndexOf($KindOrder, $script:sendKind)
    $script:sendKind = $KindOrder[($i + 1) % $KindOrder.Count]
    $CbKind.Content = "类型：" + $CbKindName[$script:sendKind]
})
$script:cbFilter = "all"
$CbBoard.Add_Click({ Set-CbView "board" })
$CbLog.Add_Click({ Set-CbView "log" })
$CbClaim.Add_Click({ Set-CbView "claim" })
$CbSend.Add_Click({ Post-Collab })
$CbInput.Add_KeyDown({ if ($_.Key -eq "Enter") { Post-Collab } })
$CbInput.Add_TextChanged({ $CbHint.Visibility = if ($CbInput.Text) { "Collapsed" } else { "Visible" } })
Apply-StudioTheme
Refresh-Flow

$win.Add_Loaded({
    try {
        $helper = New-Object Windows.Interop.WindowInteropHelper($win)
        [GlassFx]::EnableAcrylic($helper.Handle, $false)
        $src = [Windows.Interop.HwndSource]::FromHwnd($helper.Handle)
        if ($src) { $src.CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent }
        $RootBorder.Background = Brush "#D9F4F9FF"
        $RootBorder.BorderBrush = Brush "#D7E1EC"
        try { $hh = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; if ($hh -ne [IntPtr]::Zero) { [GlassFx]::EnableAcrylic($hh, $false) } } catch { }
    } catch { }
    # ICON-01：头像与窗口图标拆成两次独立的 try，图标不再搭 PNG 那次的车（原先失败会一起被吞）
    try { $img = New-Object Windows.Media.Imaging.BitmapImage([Uri]::new("file:///D:/tmp/nailong.png")); $win.FindName("AvatarImg").Source = $img } catch { }
    # ICON-01：Loaded 时窗口句柄已就绪，用 WM_SETICON 直接向窗口补发 ICO 大/小图标，兜住任务栏
    try {
        $hiconWnd = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle
        $icoPath = "D:\tmp\nailong_chef_icon.ico"
        if (($hiconWnd -ne [IntPtr]::Zero) -and (Test-Path -LiteralPath $icoPath)) {
            $script:icoBig = New-Object System.Drawing.Icon($icoPath, 32, 32)
            $script:icoSmall = New-Object System.Drawing.Icon($icoPath, 16, 16)
            [WinIcon]::SendMessage($hiconWnd, 0x0080, [IntPtr]1, $script:icoBig.Handle) | Out-Null
            [WinIcon]::SendMessage($hiconWnd, 0x0080, [IntPtr]0, $script:icoSmall.Handle) | Out-Null
        }
    } catch { try { [IO.File]::WriteAllText("D:\tmp\live_icon_err.txt", ("loaded: " + $_.Exception.ToString()), (New-Object Text.UTF8Encoding $false)) } catch { } }
    try { if ([IO.File]::ReadAllText("D:\tmp\live_theme.txt").Trim() -eq "True") { $script:dark = $true; Apply-Theme } } catch { }
    Refresh-Feed
    try { Refresh-Collab; Update-CollabBadge } catch { }
    [IO.File]::WriteAllText("D:\tmp\live3_ok.txt", ("ok v5.2 entries=" + $script:lastCount + " at " + (Get-Date -Format "HH:mm:ss")), [Text.Encoding]::UTF8)
    Start-LiveBadge
    $InputBox.Focus() | Out-Null
})

$win.Add_Closing({ Save-WindowState })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Refresh-Feed; Refresh-Outputs; Tick-LiveBadge; Refresh-Collab; Update-CollabBadge })
$timer.Start()

# 恢复上次的窗口位置和大小
$ws = Read-WindowState
$script:big = [bool]$ws.big
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($ws.width -ge 420 -and $ws.height -ge 520) {
    $win.Width = [Math]::Min([double]$ws.width, $wa.Width - 40)
    $win.Height = [Math]::Min([double]$ws.height, $wa.Height - 60)
}
if ($null -ne $ws.left -and $null -ne $ws.top) {
    $win.WindowStartupLocation = "Manual"
    $win.Left = [Math]::Max($wa.Left + 8, [Math]::Min([double]$ws.left, $wa.Right - $win.Width + 20))
    $win.Top = [Math]::Max($wa.Top + 8, [Math]::Min([double]$ws.top, $wa.Bottom - 120))
}

# ICON-01：ShowDialog 之前就把窗口图标钉成 nailong.ico（IconBitmapDecoder 取最大一帧），独立 try
try {
    $icoPre = "D:\tmp\nailong_chef_icon.ico"
    if (Test-Path -LiteralPath $icoPre) {
        $icoStream = [IO.File]::OpenRead($icoPre)
        try {
            $icoDec = New-Object Windows.Media.Imaging.IconBitmapDecoder($icoStream, [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $bestFrame = $null
            foreach ($fr in $icoDec.Frames) { if (($null -eq $bestFrame) -or ($fr.PixelWidth -gt $bestFrame.PixelWidth)) { $bestFrame = $fr } }
            if ($null -ne $bestFrame) { $win.Icon = $bestFrame }
        } finally { $icoStream.Close() }
    }
} catch { try { [IO.File]::WriteAllText("D:\tmp\live_icon_err.txt", ("pre-show: " + $_.Exception.ToString()), (New-Object Text.UTF8Encoding $false)) } catch { } }

$win.ShowDialog() | Out-Null
