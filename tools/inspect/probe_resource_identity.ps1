# UI-05 探针：验证「StaticResource 解析后，元素持有的是 Window.Resources 中
# 画刷对象的同一引用」。若成立，运行时切换主题即可按对象引用反查 token，
# 从而精确覆盖全部 XAML 元素（含模板内），不必依赖 x:Name 或颜色猜测。
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
    <SolidColorBrush x:Key="InkBrush" Color="#16283C"/>
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
      <TextBlock x:Name="txt" Text="x" Foreground="{StaticResource InkBrush}"/>
    </StackPanel>
  </Grid>
</Window>
'@
$w = [Windows.Markup.XamlReader]::Parse($xaml)
$w.Show() | Out-Null
[void]$w.UpdateLayout()
$btn = $w.FindName('btn'); [void]$btn.ApplyTemplate()
$bd = $btn.Template.FindName('bd', $btn)

$pairs = @(
    @('root.Background',  $w.FindName('root').Background,  $w.Resources['SurfaceBrush']),
    @('outer.Background', $w.FindName('outer').Background, $w.Resources['CardBrush']),
    @('template bd',      $bd.Background,                  $w.Resources['CardBrush']),
    @('txt.Foreground',   $w.FindName('txt').Foreground,   $w.Resources['InkBrush'])
)
foreach ($p in $pairs) {
    "{0,-22} same_ref={1,-6} frozen={2,-6} expected={3}" -f $p[0], [object]::ReferenceEquals($p[1], $p[2]), $p[1].IsFrozen, $p[2].Color.ToString()
}
# 用 Dictionary[object,string] 做引用查找，验证可行
$d = New-Object 'System.Collections.Generic.Dictionary[object,string]'
foreach ($k in @($w.Resources.Keys)) {
    $b = $w.Resources[$k]
    if ($b -is [Windows.Media.SolidColorBrush]) { $d[$b] = $k }
}
"dict_entries = $($d.Count)"
"lookup root  -> " + $d[$w.FindName('root').Background]
"lookup outer -> " + $d[$w.FindName('outer').Background]
"lookup bd    -> " + $d[$bd.Background]
$ok = ($d[$w.FindName('root').Background] -eq 'SurfaceBrush') -and
      ($d[$w.FindName('outer').Background] -eq 'CardBrush') -and
      ($d[$bd.Background] -eq 'CardBrush') -and
      ($d[$w.FindName('txt').Foreground] -eq 'InkBrush')
"RESOURCE_IDENTITY_LOOKUP_WORKS = $ok"
$w.Close()
