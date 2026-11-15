# UI-05 探针：直接改 Window.Resources 中画刷的 Color，
# 验证所有 StaticResource 引用者（含模板内）是否同步换色，且不抛 Freeze 异常。
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="260" Height="120">
  <Window.Resources>
    <SolidColorBrush x:Key="SurfaceBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="CardBrush" Color="#F7FAFD"/>
    <Style x:Key="TplBtn" TargetType="Button">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{StaticResource CardBrush}" Height="40"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid x:Name="root" Background="{StaticResource SurfaceBrush}">
    <StackPanel>
      <Border x:Name="outer" Background="{StaticResource CardBrush}" Height="30"/>
      <Button x:Name="btn" Style="{StaticResource TplBtn}"/>
    </StackPanel>
  </Grid>
</Window>
'@
$w = [Windows.Markup.XamlReader]::Parse($xaml)
$w.Show() | Out-Null
[void]$w.UpdateLayout()
$btn = $w.FindName('btn'); [void]$btn.ApplyTemplate()
$bd = $btn.Template.FindName('bd', $btn)

$errs = @()
foreach ($pair in @(@('SurfaceBrush','#FF172432'), @('CardBrush','#FF22303F'))) {
    try {
        $b = $w.Resources[$pair[0]]
        "before $($pair[0]): frozen=$($b.IsFrozen) color=$($b.Color)"
        $b.Color = [Windows.Media.ColorConverter]::ConvertFromString($pair[1])
        "after  $($pair[0]): color=$($b.Color)"
    } catch { $errs += "$($pair[0]): " + $_.Exception.Message }
}
"errors = $($errs.Count) $($errs -join ' | ')"
"root.Background  = " + $w.FindName('root').Background.Color
"outer.Background = " + $w.FindName('outer').Background.Color
"template bd      = " + $bd.Background.Color
$ok = ($errs.Count -eq 0) -and
      ($w.FindName('root').Background.Color.ToString() -eq '#FF172432') -and
      ($w.FindName('outer').Background.Color.ToString() -eq '#FF22303F') -and
      ($bd.Background.Color.ToString() -eq '#FF22303F')
"RESOURCE_RECOLOR_WORKS = $ok"
$w.Close()
