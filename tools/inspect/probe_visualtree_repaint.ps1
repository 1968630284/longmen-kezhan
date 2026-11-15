# UI-05 探针：验证「遍历视觉树 + 按色板把 SolidColorBrush 换成新主题色」
# 能否覆盖 根级 Border / ControlTemplate 内元素 / Shape.Fill / TextBlock.Foreground。
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="300" Height="160">
  <Window.Resources>
    <SolidColorBrush x:Key="Surf" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Card" Color="#F7FAFD"/>
    <Style x:Key="TplBtn" TargetType="Button">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{StaticResource Card}" CornerRadius="6">
              <TextBlock x:Name="tb" Text="模板内" Foreground="#16283C" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid x:Name="root" Background="{StaticResource Surf}">
    <StackPanel>
      <Border x:Name="outer" Background="{StaticResource Card}" Height="40" Margin="6"/>
      <Button x:Name="btn" Style="{StaticResource TplBtn}" Height="40" Margin="6"/>
      <Rectangle x:Name="rect" Fill="{StaticResource Card}" Stroke="#D7E1EC" Height="20" Margin="6"/>
    </StackPanel>
  </Grid>
</Window>
'@
$w = [Windows.Markup.XamlReader]::Parse($xaml)
$w.Show() | Out-Null
[void]$w.UpdateLayout()
$btn = $w.FindName('btn')
[void]$btn.ApplyTemplate()

function Hex($c) {
    if ($null -eq $c) { return '' }
    $s = $c.ToString().ToUpperInvariant().Replace('#','')
    if ($s.Length -eq 6) { $s = 'FF' + $s }
    return '#' + $s
}
$map = @{ '#FFFFFFFF' = '#FF172432'; '#FFF7FAFD' = '#FF22303F'; '#FF16283C' = '#FFEAF1F8'; '#FFD7E1EC' = '#FF3A4E66' }

function Walk($v, $acc) {
    if ($null -eq $v) { return }
    [void]$acc.Add($v)
    $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($v)
    for ($i = 0; $i -lt $n; $i++) { Walk ([Windows.Media.VisualTreeHelper]::GetChild($v, $i)) $acc }
}
$all = New-Object System.Collections.ArrayList
Walk $w $all
"visual_count = $($all.Count)"

$dps = @(
    [Windows.Controls.Control]::BackgroundProperty,
    [Windows.Controls.Control]::ForegroundProperty,
    [Windows.Controls.Control]::BorderBrushProperty,
    [Windows.Controls.Border]::BackgroundProperty,
    [Windows.Controls.Border]::BorderBrushProperty,
    [Windows.Controls.Panel]::BackgroundProperty,
    [Windows.Controls.TextBlock]::ForegroundProperty,
    [Windows.Shapes.Shape]::FillProperty,
    [Windows.Shapes.Shape]::StrokeProperty
)
$changed = 0; $errors = 0
foreach ($el in $all) {
    foreach ($dp in $dps) {
        try {
            $v = $el.GetValue($dp)
            if ($v -is [Windows.Media.SolidColorBrush]) {
                $h = Hex $v.Color
                if ($map.ContainsKey($h)) {
                    $nb = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($map[$h]))
                    $el.SetValue($dp, $nb)
                    $changed++
                }
            }
        } catch { $errors++ }
    }
}
"changed = $changed  errors = $errors"
"--- after ---"
"root.Background  = " + (Hex $w.FindName('root').Background.Color)
"outer.Background = " + (Hex $w.FindName('outer').Background.Color)
$bd = $btn.Template.FindName('bd', $btn)
$tplTb = $btn.Template.FindName('tb', $btn)
"template_bd.Background    = " + (Hex $bd.Background.Color)
"template_tb.Foreground    = " + (Hex $tplTb.Foreground.Color)
"rect.Fill   = " + (Hex $w.FindName('rect').Fill.Color)
"rect.Stroke = " + (Hex $w.FindName('rect').Stroke.Color)
$ok = ((Hex $w.FindName('root').Background.Color) -eq '#FF172432') -and
      ((Hex $bd.Background.Color) -eq '#FF22303F') -and
      ((Hex $tplTb.Foreground.Color) -eq '#FFEAF1F8') -and
      ((Hex $w.FindName('rect').Fill.Color) -eq '#FF22303F') -and
      ((Hex $w.FindName('rect').Stroke.Color) -eq '#FF3A4E66')
"VISUALTREE_REPAINT_WORKS = $ok"
$w.Close()
