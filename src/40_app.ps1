
try {
    $xaml = Resolve-UiXaml $xaml
    $win = [Windows.Markup.XamlReader]::Parse($xaml)
try { Log-Boot 'window-parsed' } catch { }
} catch {
    [IO.File]::WriteAllText("D:\tmp\live3_err.txt", $_.Exception.ToString(), [Text.Encoding]::UTF8)
    exit 1
}

# UI-01：脚本侧构造的气泡与 XAML 控件共用同一套字号令牌，避免两套数值分叉
foreach ($fsKey in @('FsCaption','FsMeta','FsBody','FsTitle','FsDisplay')) {
    $fsVal = $win.Resources[$fsKey]
    if ($null -ne $fsVal) { Set-Variable -Name $fsKey -Value ([double]$fsVal) -Scope Script }
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
        $ArchiveBtn.IsEnabled = $false
        try {
            $r = & 'D:\tmp\nailong\tools\make_archive.ps1'
            $rs = "$r"
            if ($rs -like 'NOCHANGE*') {
                Append-Feed "系统" "note" ("刚存过，没变化（包 " + ($rs.Split(':')[1]) + "）")
            } else {
                $leaf = [IO.Path]::GetFileName($rs)
                Append-Feed "系统" "note" ("已存档 " + (Get-Date -Format "HH:mm") + " · 包 " + $leaf)
            }
        } catch {
            Append-Feed "系统" "status" ("存档失败：" + $_.Exception.Message)
        } finally {
            $ArchiveBtn.IsEnabled = $true
        }
    })
}
$ArchiveUndoBtn = $win.FindName("ArchiveUndoBtn")
if ($ArchiveUndoBtn) {
    $ArchiveUndoBtn.Add_Click({
        try {
            $lastf = 'D:\tmp\nailong\archive\last_archive.txt'
            if (-not (Test-Path $lastf)) { throw '没有可撤销的存档' }
            $pkgDir = (Get-Content -LiteralPath $lastf -Raw -Encoding UTF8).Trim()
            if (-not (Test-Path $pkgDir)) { throw '存档目录不存在' }
            $age = (Get-Date) - (Get-Item -LiteralPath $pkgDir).LastWriteTime
            if ($age.TotalMinutes -gt 10) { throw ('超出 10 分钟（已 ' + [int]$age.TotalMinutes + ' 分钟），不可撤销') }
            $name = [IO.Path]::GetFileName($pkgDir)
            $ms = @()
            $msp = 'D:\tmp\nailong\archive\milestones.txt'
            if (Test-Path $msp) { $ms = @(Get-Content -LiteralPath $msp -Encoding UTF8 | Where-Object { $_.Trim() }) }
            if ($ms -contains $name) { throw ('里程碑包不可撤销：' + $name) }
            Remove-Item -LiteralPath $pkgDir -Recurse -Force
            $other = Get-ChildItem 'D:\tmp\nailong\archive' -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($other) { Set-Content -LiteralPath $lastf -Value $other.FullName -Encoding UTF8 } else { Remove-Item -LiteralPath $lastf -Force -ErrorAction SilentlyContinue }
            Append-Feed "系统" "note" ("已撤销存档 " + $name)
        } catch {
            Append-Feed "系统" "status" ("撤销失败：" + $_.Exception.Message)
        }
    })
}
$BootCopyBtn = $win.FindName("BootCopyBtn")
if ($BootCopyBtn) {
    $BootCopyBtn.Add_Click({
        try {
            $lastf = 'D:\tmp\nailong\archive\last_archive.txt'
            if (-not (Test-Path $lastf)) { throw '还没有存档包' }
            $pkgDir = (Get-Content -LiteralPath $lastf -Raw -Encoding UTF8).Trim()
            $msg = '读存档 ' + $pkgDir + '，按 BOOT 恢复上下文，恢复完先汇报：身份、待办、上次停在哪，然后等我指令。'
            [Windows.Clipboard]::SetText($msg)
            Append-Feed "系统" "note" ("开局语已复制 · 包 " + [IO.Path]::GetFileName($pkgDir))
        } catch {
            Append-Feed "系统" "status" ("复制开局语失败：" + $_.Exception.Message)
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
# 51 号：动作日志/占用两页签撤除（客官定，不看也不用）
if ($CbLog) { $CbLog.Visibility = "Collapsed" }
if ($CbClaim) { $CbClaim.Visibility = "Collapsed" }
$CbCount = $win.FindName("CbCount")
$CbScroll = $win.FindName("CbScroll")
$CbList = $win.FindName("CbList")
# 50-补3：列表末尾留白，最后一个气泡不贴底
$FeedList.Margin = New-Object Windows.Thickness(0, 0, 0, 18)
$CbList.Margin = New-Object Windows.Thickness(0, 0, 0, 18)
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
    # UI-01：主题只换一层。颜色统一取自 00_header.ps1 的 $script:UiTokens，
    # 不再在深浅两个分支里各写一遍 hex。交互态已改为主题无关的 Opacity 反馈。
    Set-UiTheme $script:dark
    # UI-05：运行时切换只需重置资源字典里画刷的 Color。XamlReader.Parse 场景下
    # StaticResource 解析后，所有引用者（含 ControlTemplate 内、未具名元素）持有
    # 同一个未冻结的画刷对象，改 Color 即全窗口同步换色。这补上了此前「具名控件
    # 映射表」漏掉 Rail / 未具名元素导致深浅切换后侧栏仍是白底的根因。
    # 探针：probe_resource_identity.ps1 / probe_resource_recolor.ps1 已验证。
    try {
        foreach ($rk in @($win.Resources.Keys)) {
            if ($rk -match '^([A-Za-z0-9]+)Brush$') {
                $tk = $matches[1]
                $rb = $win.Resources[$rk]
                if ($script:UiTokens.ContainsKey($tk) -and
                    $rb -is [Windows.Media.SolidColorBrush] -and -not $rb.IsFrozen) {
                    $rb.Color = [Windows.Media.ColorConverter]::ConvertFromString([string]$script:UiTokens[$tk])
                }
            }
        }
    } catch { }
    $uiMap = @(
        ,@('RootBorder',    'Background',  'Surface')
        ,@('RootBorder',    'BorderBrush', 'SurfaceStroke')
        ,@('HeaderLine',    'Background',  'Rail')
        ,@('InputBar',      'BorderBrush', 'Rail')
        ,@('RailLine',      'Background',  'Rail')
        ,@('CbInputBar',    'BorderBrush', 'Rail')
        ,@('TitleText',     'Foreground',  'Ink')
        ,@('StatusText',    'Foreground',  'Meta')
        ,@('LiveBadge',     'Background',  'LiveBadgeBg')
        ,@('LiveBadge',     'BorderBrush', 'LiveBadgeLine')
        ,@('LiveBadgeText', 'Foreground',  'LiveGreen')
        ,@('LiveDot',       'Fill',        'LiveDot')
        ,@('InputBox',      'Foreground',  'Ink')
        ,@('InputHint',     'Foreground',  'Hint')
        ,@('InputBorder',   'Background',  'Input')
        ,@('InputBorder',   'BorderBrush', 'Stroke')
        ,@('SearchBorder',  'Background',  'Input')
        ,@('SearchBorder',  'BorderBrush', 'Stroke')
        ,@('SearchBox',     'Foreground',  'Ink')
        ,@('SearchHint',    'Foreground',  'Hint')
        ,@('CbInputBorder', 'Background',  'Input')
        ,@('CbInputBorder', 'BorderBrush', 'Stroke')
    # UI-01：由 src/30_window.xaml 自动提取，覆盖工坊 / 传菜口 / 协作台等具名控件
        ,@('tb', 'Background', 'Thumb')
        ,@('CollabDot', 'Fill', 'Danger')
        ,@('bd', 'Background', 'Accent')
        ,@('FlowBar', 'Background', 'Card')
        ,@('FlowBar', 'BorderBrush', 'Line')
        ,@('FlowDotChar', 'Fill', 'Dash')
        ,@('FlowDotScene', 'Fill', 'Dash')
        ,@('FlowDotBg', 'Fill', 'Dash')
        ,@('FlowDotPrompt', 'Fill', 'Dash')
        ,@('NodeChar', 'Background', 'Card')
        ,@('NodeChar', 'BorderBrush', 'Line')
        ,@('BarChar', 'Background', 'CharSoft')
        ,@('BarCharT', 'Foreground', 'Char')
        ,@('DropChar', 'Background', 'Soft')
        ,@('DropChar', 'BorderBrush', 'Dash')
        ,@('DashChar', 'Stroke', 'Dash')
        ,@('HintChar', 'Foreground', 'Meta')
        ,@('NameChar', 'Foreground', 'Meta')
        ,@('NodeBg', 'Background', 'Card')
        ,@('NodeBg', 'BorderBrush', 'Line')
        ,@('BarBg', 'Background', 'BgSoft')
        ,@('BarBgT', 'Foreground', 'BgCat')
        ,@('DropBg', 'Background', 'Soft')
        ,@('DropBg', 'BorderBrush', 'Dash')
        ,@('DashBg', 'Stroke', 'Dash')
        ,@('HintBg', 'Foreground', 'Meta')
        ,@('NameBg', 'Foreground', 'Meta')
        ,@('NodeScene', 'Background', 'Card')
        ,@('NodeScene', 'BorderBrush', 'Line')
        ,@('BarScene', 'Background', 'SceneSoft')
        ,@('BarSceneT', 'Foreground', 'Scene')
        ,@('DropScene', 'Background', 'Soft')
        ,@('DropScene', 'BorderBrush', 'Dash')
        ,@('DashScene', 'Stroke', 'Dash')
        ,@('HintScene', 'Foreground', 'Meta')
        ,@('NameScene', 'Foreground', 'Meta')
        ,@('SceneTextBorder', 'Background', 'Soft')
        ,@('SceneTextBorder', 'BorderBrush', 'Line')
        ,@('SceneText', 'Foreground', 'Ink')
        ,@('SceneTextHint', 'Foreground', 'Hint')
        ,@('NodePrompt', 'Background', 'Card')
        ,@('NodePrompt', 'BorderBrush', 'Line')
        ,@('BarPrompt', 'Background', 'PromptSoft')
        ,@('BarPromptT', 'Foreground', 'Prompt')
        ,@('StyleBox', 'Background', 'Soft')
        ,@('StyleBox', 'Foreground', 'Ink')
        ,@('PromptBorder', 'Background', 'Soft')
        ,@('PromptBorder', 'BorderBrush', 'Line')
        ,@('PromptText', 'Foreground', 'Ink')
        ,@('PromptHint', 'Foreground', 'Hint')
        ,@('VsStatusBar', 'BorderBrush', 'Rail')
        ,@('VsStatus', 'Foreground', 'Meta')
        ,@('OutTitle', 'Foreground', 'Ink')
        ,@('CbCount', 'Foreground', 'Meta')
        ,@('CbInput', 'Foreground', 'Ink')
        ,@('CbHint', 'Foreground', 'Hint')
    )
    foreach ($m in $uiMap) {
        try {
            $el = $win.FindName($m[0])
            if ($el) { $el.($m[1]) = Tok $m[2] }
        } catch { }
    }
    $card = Tok 'Card'; $line = Tok 'Stroke'; $ink = Tok 'Ink2'
    foreach ($el in @($FlowBar, $NodeChar, $NodeBg, $NodeScene, $NodePrompt)) { if ($el) { $el.Background = $card } }
    foreach ($el in @($CbTo, $CbKind)) { if ($el) { $el.Background = $card; $el.Foreground = $ink } }
    foreach ($el in @($CbTo, $CbKind, $CbBoard, $CbLog, $CbClaim)) { if ($el) { $el.BorderBrush = $line } }
    try { $hh = (New-Object Windows.Interop.WindowInteropHelper($win)).Handle; if ($hh -ne [IntPtr]::Zero) { [GlassFx]::EnableAcrylic($hh, $script:dark) } } catch { }
    $DarkBtn.ToolTip = if ($script:dark) { "切到浅色" } else { "切到深色" }
    try { if ($script:cbView) { Set-CbView $script:cbView } } catch { }
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
    $t = $script:UiTokens
    $script:VsCardBg = $t.Card
    $script:VsCardLine = $t.Stroke
    $script:VsInk = $t.Ink
    $script:VsMeta = $t.Meta
    $dropBg = $t.Soft
    $dashC = $t.Dash
    $pal = @{
        char   = @($t.CharSoft,   $t.Char)
        bg     = @($t.BgSoft,     $t.BgCat)
        scene  = @($t.SceneSoft,  $t.Scene)
        prompt = @($t.PromptSoft, $t.Prompt)
    }
    $bars = @{ char = @($BarChar, $BarCharT); bg = @($BarBg, $BarBgT); scene = @($BarScene, $BarSceneT); prompt = @($BarPrompt, $BarPromptT) }
    foreach ($k in $pal.Keys) {
        $c = $pal[$k]
        $bars[$k][0].Background = Brush $c[0]
        $bars[$k][1].Foreground = Brush $c[1]
    }
    foreach ($k in @("char", "bg", "scene")) {
        $n = $script:VsNodes[$k]
        if ($n) {
            $n.Node.Background = Brush $script:VsCardBg
            $n.Node.BorderBrush = Brush $script:VsCardLine
            $n.Drop.Background = Brush $dropBg
            $n.Dash.Stroke = Brush $dashC
            $n.Drop.BorderBrush = Brush $dashC
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
    $VsStatusBar.BorderBrush = Tok 'Rail'
    # （9 号：工坊成品区已移除，OutLabel 不再存在）
    $script:lastOutSig = "`0force"

    if ($script:ApplyJobParamsTheme) {
        try { & $script:ApplyJobParamsTheme } catch { try { [IO.File]::AppendAllText("D:\tmp\theme_err.txt", ((Get-Date -Format "HH:mm:ss") + " " + $_.Exception.ToString() + "`r`nSTACK:" + $_.ScriptStackTrace + "`r`n"), [Text.Encoding]::UTF8) } catch { } }
    }
}
$DarkBtn.Add_Click({
    $script:dark = -not $script:dark
    try { [IO.File]::WriteAllText("D:\tmp\live_theme.txt", $script:dark.ToString(), $Utf8) } catch { }
    try { Apply-Theme } catch { try { [IO.File]::AppendAllText("D:\tmp\theme_err.txt", ((Get-Date -Format "HH:mm:ss") + " Apply-Theme 失败：" + $_.Exception.Message + "`r`nSTACK:" + $_.ScriptStackTrace + "`r`n"), [Text.Encoding]::UTF8) } catch { } }
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

$script:KindName = @{ status = "状态"; command = "命令"; result = "结果"; question = "提问"; note = "留言"; task = "任务"; decision = "决定"; discuss = "商量"; log = "日志" }
# UI-04：不再在这里重置 $script:dark。主题由 00_header.ps1 在窗口解析前统一读取，
# 此处重置会造成「XAML 注入深色 / Apply-Theme 用浅色」的混合状态。
$script:filter = ""
$script:forceRefresh = $false
# UI-01：历史遗留的气泡色板改为从单一色板派生（无调用点，保留接口）
function Pal() {
    $t = $script:UiTokens
    return @{ MyBg = $t.Card; MyLine = $t.Stroke; DaveBg = $t.SelfBg; Ink = $t.Ink; Meta = $t.Meta }
}
$script:ChipBg   = @{ status = "#E4F2E7"; command = "#E1EEFC"; result = "#F1E4F7"; question = "#FBE7E4"; note = "#E9EEF2"; task = "#E1EEFC"; decision = "#FBE7E4"; discuss = "#FBF0DC"; log = "#E9EEF2" }
$script:ChipFg   = @{ status = "#1E7D32"; command = "#1565C0"; result = "#7B1FA2"; question = "#C62828"; note = "#546E7A"; task = "#1565C0"; decision = "#C62828"; discuss = "#B26500"; log = "#546E7A" }

function Convert-FeedTime([string]$t, [datetime]$now) {
    # 24 号补：feed 的 ts 允许两种写法——带日期（yyyy-MM-dd HH:mm:ss）优先，
    # 老写法只有 HH:mm:ss 时按"今天"补齐；若补出来的时间比现在还晚 2 小时以上，
    # 说明是昨天深夜写的（跨天），按前一天算，避免旧条目排到新汇报下面。
    # OPT1：$now 由调用方算一次后传入（原先每条消息都 Get-Date，一轮几百次）
    $d = [datetime]::MinValue
    $s = ([string]$t).Trim()
    # 先判"带日期"（TryParse 会把纯时间也按今天补，不能先交给它）
    if ($s -match '^\d{4}-\d{2}-\d{2}') {
        if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    if ([datetime]::TryParseExact($s, "HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) {
        $candidate = $now.Date.Add($d.TimeOfDay)
        if ($candidate -gt $now.AddMinutes(5)) { $candidate = $candidate.AddDays(-1) }
        return $candidate
    }
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $now
}
# 把小猪的聊天流和协作总线的留言合成一条时间线：一个窗口里三个人说话
# S2：把「一条板帖 → 一条时间线条目」的构造抽出来，增量与全量共用，避免两处规则漂移。
function New-BoardEntry($m, [int]$n, [datetime]$now) {
    $w = $now
    try { $w = [datetime]::Parse([string]$m.ts) } catch { }
    $t = [string]$m.text
    # 57 号：聊天视图只显板上全文帖的首行简报（≤60 字），全文去传菜口
    if (([string]$m.kind -in @("task","result","decision")) -and ($t -match "^([^\r\n]{0,60})")) {
        $head = $matches[1]
        $t = $head + $(if ($t.Length -gt $head.Length) { " …" } else { "" })
    }
    return [pscustomobject]@{
        n = $n; when = $w; ts = $w.ToString("HH:mm:ss")
        sender = [string]$m.from; kind = [string]$m.kind; text = $t
    }
}

function Read-MergedFeed {
    # OPT1：两个源文件都没变时复用上次合并结果。
    # S2：board.jsonl 纯追加时只构造新增条目并有序尾插；实测 693 条规模下每次追加
    # 从 ~54ms 降到 ~2ms，且不再随消息数线性增长。feed 变化 / 源被重写 / 时间戳
    # 回退时仍走全量重排，保证结果与旧实现逐条一致。
    $busBoard = Join-Path $BusRoot "board.jsonl"
    $sig = (Get-FileStamp $FeedFile) + "||" + (Get-FileStamp $busBoard)
    if ($null -ne $script:MergedCache -and $script:MergedSig -eq $sig) { return $script:MergedCache }
    $now = Get-Date
    $feed = @(Read-Feed)
    $board = @(Read-BusJsonl "board.jsonl")

    $st = $script:MergedState
    $inc = $false
    if ($null -ne $st -and $feed.Count -eq $st.FeedCount -and $board.Count -ge $st.BoardCount) {
        $bs = $script:ReadStats['bus:board.jsonl']
        if ($null -ne $bs -and ($bs.Mode -eq 'append' -or $bs.Mode -eq 'cache')) { $inc = $true }
    }

    if ($inc) {
        $out = $st.Items
        $i = $st.NextN
        $maxW = $st.MaxWhen
        $tail = $true
        $add = New-Object System.Collections.ArrayList
        for ($k = $st.BoardCount; $k -lt $board.Count; $k++) {
            $m = $board[$k]
            if ([string]$m.ref -eq "mirror") { continue }
            $e = New-BoardEntry $m $i $now
            # 新条目必须不早于已有最大值才能安全尾插，否则回退全量重排
            if ($e.when -lt $st.MaxWhen) { $tail = $false; break }
            [void]$add.Add($e)
            $i++
            if ($e.when -gt $maxW) { $maxW = $e.when }
        }
        if ($tail) {
            foreach ($x in $add) { [void]$out.Add($x) }
            $script:MergedState = @{ FeedCount = $feed.Count; BoardCount = $board.Count; NextN = $i; MaxWhen = $maxW; Items = $out }
            $merged = @($out)
            $script:MergedSig = $sig
            $script:MergedCache = $merged
            return $merged
        }
    }

    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($e in $feed) {
        [void]$out.Add([pscustomobject]@{
                n = $i; when = (Convert-FeedTime ([string]$e.ts) $now); ts = [string]$e.ts
                sender = [string]$e.sender; kind = [string]$e.kind; text = [string]$e.text
            })
        $i++
    }
    try {
        foreach ($m in $board) {
            if ([string]$m.ref -eq "mirror") { continue }
            [void]$out.Add((New-BoardEntry $m $i $now))
            $i++
        }
    } catch { }
    $sorted = New-Object System.Collections.ArrayList
    foreach ($x in ($out | Sort-Object when, n)) { [void]$sorted.Add($x) }
    $merged = @($sorted)
    $script:MergedSig = $sig
    $script:MergedCache = $merged
    $mw = $now
    if ($sorted.Count -gt 0) { $mw = $sorted[$sorted.Count - 1].when }
    $script:MergedState = @{ FeedCount = $feed.Count; BoardCount = $board.Count; NextN = $i; MaxWhen = $mw; Items = $sorted }
    return $merged
}

function New-MsgBubble($From, $Kind, $Text, $Ts, $Prio, [bool]$IsLog, [bool]$Compact = $false) {
    # 50 号：聊天/传菜口共用同一套 QQ 风气泡（形状/配色/头像/头部/阴影）
    $dark = [bool]$script:dark
    $role = Get-RoleInfo ([string]$From)
    if ([string]$From -match 'Dave|余佳凯') { $role = @{ label = '客官'; color = $script:UiTokens.RoleSelf } }
    $isSelf = ([string]$From -match 'Dave|余佳凯')
    $isSystem = ((-not $IsLog) -and ([string]$Kind -eq 'status'))
    $outer = New-Object Windows.Controls.StackPanel
    $outer.Margin = if ($Compact) { New-Object Windows.Thickness(12, 2, 12, 2) } else { New-Object Windows.Thickness(12, 6, 12, 6) }
    if ($isSystem) {
        $outer.HorizontalAlignment = "Center"
        $sys = New-Object Windows.Controls.TextBlock
        $sys.Text = [string]$Text
        $sys.FontSize = $script:FsCaption
        $sys.TextWrapping = "Wrap"
        $sys.MaxWidth = 560
        $sys.TextAlignment = "Center"
        $sys.Foreground = Tok 'Meta'
        $sys.Margin = New-Object Windows.Thickness(24, 10, 24, 10)
        $outer.Children.Add($sys) | Out-Null
        return $outer
    }
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.HorizontalAlignment = $(if ($isSelf) { "Right" } else { "Left" })

    $av = New-Object Windows.Controls.Border
    $av.Width = 32; $av.Height = 32
    $av.CornerRadius = New-Object Windows.CornerRadius(16)
    $av.Background = Brush ([string]$role.color)
    $av.VerticalAlignment = "Top"
    $av.Margin = New-Object Windows.Thickness(0, 16, 0, 0)
    $aT = New-Object Windows.Controls.TextBlock
    $lbl = [string]$role.label
    $aT.Text = $(if ($lbl.Length -gt 0) { $lbl.Substring(0, 1) } else { "?" })
    $aT.FontSize = $script:FsBody
    $aT.FontWeight = "Bold"
    $aT.Foreground = Tok 'AccentInk'
    $aT.HorizontalAlignment = "Center"
    $aT.VerticalAlignment = "Center"
    $av.Child = $aT
    if ($Compact) { $av.Visibility = "Hidden" }

    $content = New-Object Windows.Controls.StackPanel
    $content.Margin = $(if ($isSelf) { New-Object Windows.Thickness(0, 0, 10, 0) } else { New-Object Windows.Thickness(10, 0, 0, 0) })
    $meta = New-Object Windows.Controls.TextBlock
    $meta.Text = [string]$role.label + " · " + (Format-UiTime ([string]$Ts))
    $meta.FontSize = $script:FsMeta
    $meta.Foreground = Tok 'Meta'
    $meta.Margin = New-Object Windows.Thickness(4, 0, 4, 3)
    $meta.HorizontalAlignment = $(if ($isSelf) { "Right" } else { "Left" })
    if (-not $Compact) { $content.Children.Add($meta) | Out-Null }

    $bubble = New-Object Windows.Controls.Border
    $bubble.MaxWidth = 360
    $bubble.Padding = New-Object Windows.Thickness(14, 9, 14, 9)
    $bubble.CornerRadius = New-Object Windows.CornerRadius(12)
    $bgc = if ($isSelf) { $script:UiTokens.SelfBg } else { $script:UiTokens.Card }
    $bubble.Background = Brush $bgc
    $bubble.BorderBrush = Tok 'Line'
    $bubble.BorderThickness = New-Object Windows.Thickness(0)
    # UI-03：移除逐条气泡投影，改由底色层次 + 留白表达分组（对齐 Teams / 飞书的克制做法）

    $inner = New-Object Windows.Controls.StackPanel
    $kind = [string]$Kind
    if ((-not $isSelf) -and (-not $IsLog) -and $kind -and $script:KindName[$kind]) {
        $chipRow = New-Object Windows.Controls.StackPanel
        $chipRow.Orientation = "Horizontal"
        $chip = New-Object Windows.Controls.Border
        $chip.CornerRadius = New-Object Windows.CornerRadius(7)
        $chip.Background = Brush $script:ChipBg[$kind]
        if (-not $chip.Background) { $chip.Background = Tok 'Soft' }
        $chip.Padding = New-Object Windows.Thickness(8, 2.5, 8, 2.5)
        $chipText = New-Object Windows.Controls.TextBlock
        $chipText.Text = $script:KindName[$kind]
        if (-not $chipText.Text) { $chipText.Text = "留言" }
        $chipText.FontSize = $script:FsCaption
        $chipText.FontWeight = "SemiBold"
        $chipText.Foreground = Brush $script:ChipFg[$kind]
        if (-not $chipText.Foreground) { $chipText.Foreground = Tok 'Meta' }
        $chip.Child = $chipText
        $chipRow.Children.Add($chip) | Out-Null
        if ($Prio) {
            $pchip = New-Object Windows.Controls.Border
            $pchip.CornerRadius = New-Object Windows.CornerRadius(999)
            $pchip.Padding = New-Object Windows.Thickness(7, 1, 7, 1)
            $pchip.Margin = New-Object Windows.Thickness(6, 0, 0, 0)
            $pbg = @{ 'P0' = '#FDE8E8'; 'P1' = '#E1EEFC'; 'P2' = '#EEF1F5' }
            $pbgD = @{ 'P0' = '#4A2320'; 'P1' = '#1E3A56'; 'P2' = '#2A3440' }
            $pfc = @{ 'P0' = '#C62828'; 'P1' = '#1565C0'; 'P2' = '#5B6B7C' }
            $pchip.Background = Brush $(if ($dark) { $pbgD[[string]$Prio] } else { $pbg[[string]$Prio] })
            $pt = New-Object Windows.Controls.TextBlock
            $pt.Text = [string]$Prio
            $pt.FontSize = $script:FsCaption
            $pt.FontWeight = "SemiBold"
            $pt.Foreground = Brush ([string]$pfc[[string]$Prio])
            $pchip.Child = $pt
            $chipRow.Children.Add($pchip) | Out-Null
        }
        $inner.Children.Add($chipRow) | Out-Null
    }
    $fg = if ($isSelf) { $script:UiTokens.SelfInk } else { $script:UiTokens.Ink }
    $body = New-SelectableText ([string]$Text) $script:FsBody (Brush $fg) 20 $bgc
    $body.MaxWidth = 330
    $inner.Children.Add($body) | Out-Null
    $bubble.Child = $inner
    $content.Children.Add($bubble) | Out-Null

    if ($isSelf) {
        $row.Children.Add($content) | Out-Null
        $row.Children.Add($av) | Out-Null
    } else {
        $row.Children.Add($av) | Out-Null
        $row.Children.Add($content) | Out-Null
    }
    return $row
}
function New-DayDivider([string]$label) {
    $b = New-Object Windows.Controls.Border
    $b.Margin = New-Object Windows.Thickness(8, 10, 8, 6)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $label
    $tb.FontSize = $script:FsCaption
    $tb.Foreground = Tok 'Meta'
    $tb.HorizontalAlignment = "Center"
    $tb.Opacity = 0.85
    $b.Child = $tb
    return $b
}
function New-EntryView($e, [bool]$Compact = $false) {
    return New-MsgBubble ([string]$e.sender) ([string]$e.kind) ([string]$e.text) ([string]$e.ts) '' $false $Compact
}

$script:lastCount = -1
$script:lastTotal = -1
$script:lastRendered = 0
function Refresh-Feed {
    $items = Read-MergedFeed
    if (-not $script:feedLimit) { $script:feedLimit = 120 }
    $total = $items.Count
    $script:feedTotal = $total
    $trimmed = $false
    if ($total -gt $script:feedLimit) { $items = @($items | Select-Object -Last $script:feedLimit); $trimmed = $true }
    # 53 号：首屏只建最近 N 条；被裁剪时不做增量追加，整块重建（最多 120 条，代价可控）
    $canAppend = (-not $trimmed) -and ($null -eq $script:filter -or $script:filter -eq "") -and
                 (-not $script:forceRefresh) -and
                 ($script:lastTotal -ge 0) -and
                 ($total -gt $script:lastTotal)
    if ($script:forceRefresh -or $total -ne $script:lastTotal) {
        $script:forceRefresh = $false
        $nearBottom = $true
        if ($script:lastTotal -ge 0) {
            $nearBottom = (($FeedScroll.ScrollableHeight - $FeedScroll.VerticalOffset) -lt 80)
        }
        $oldCount = $(if ($canAppend) { $script:lastRendered } else { -1 })
        if (-not $canAppend) {
            $FeedList.Children.Clear()
            $script:UiPrevSender = $null
            $script:UiPrevWhen   = [datetime]::MinValue
            $script:UiPrevDate   = ''
        }
        $today = (Get-Date).Date
        $compactCount = 0
        $dividerCount = 0
        $idx = 0
        foreach ($e in $items) {
            if ($script:filter) {
                $hay = ([string]$e.text) + " " + ([string]$e.kind) + " " + ([string]$e.sender)
                if ($hay -notlike ("*" + $script:filter + "*")) { continue }
            }
            $idx++
            if ($canAppend -and $idx -le $oldCount) { continue }
            $curWhen = [datetime]$e.when
            $curDate = $curWhen.ToString('yyyy-MM-dd')
            # UI-02：跨天插入日期分隔；搜索态不插，避免过滤结果被分隔打断
            if ((-not $script:filter) -and $script:UiPrevDate -and $curDate -ne $script:UiPrevDate) {
                $dayLabel = if ($curWhen.Date -eq $today) { '今天' }
                            elseif ($curWhen.Date -eq $today.AddDays(-1)) { '昨天' }
                            else { $curWhen.ToString('M月d日') }
                $FeedList.Children.Add((New-DayDivider $dayLabel)) | Out-Null
                $dividerCount++
            }
            # UI-02：同一发送者 60 秒内的连续消息合并成簇，后续消息不再重复头像与时间
            $compact = Test-UiGrouping $script:UiPrevSender $script:UiPrevWhen $script:UiPrevDate ([string]$e.sender) $curWhen ([string]$e.kind) $curDate $script:filter
            if ($compact) { $compactCount++ }
            $view = New-EntryView $e $compact
            if ($script:BoldChat) { Set-AllBold $view }
            if ($idx -gt [Math]::Max(0, $oldCount)) {
                Play-PopIn $view
            }
            $FeedList.Children.Add($view) | Out-Null
            if ([string]$e.kind -eq 'status') {
                $script:UiPrevSender = $null
                $script:UiPrevWhen = [datetime]::MinValue
            } else {
                $script:UiPrevSender = [string]$e.sender
                $script:UiPrevWhen = $curWhen
            }
            $script:UiPrevDate = $curDate
        }
        if ($oldCount -ge 0 -and $items.Count -gt $oldCount) { $script:LiveBusyUntil = (Get-Date).AddSeconds(8) }
        $script:lastRendered = $items.Count
        # UI-02 / UI-03：前 3 次渲染记录布局摘要（分组生效 + 实际宽度），之后静默不刷屏
        if ($script:RenderDiagCount -lt 3) {
            $script:RenderDiagCount++
            try {
                [IO.File]::AppendAllText("D:\tmp\nailong\health\ui.log",
                    ((Get-Date -Format "HH:mm:ss.fff") + " | ui-render items=" + $items.Count +
                     " compact=" + $compactCount + " dividers=" + $dividerCount +
                     " feedW=" + [Math]::Round($FeedList.ActualWidth, 0) +
                     " viewportW=" + [Math]::Round($FeedScroll.ViewportWidth, 0) +
                     " winW=" + [Math]::Round($win.ActualWidth, 0) +
                     " winH=" + [Math]::Round($win.ActualHeight, 0) +
                     " inputVis=" + $InputBar.Visibility +
                     " dark=" + $script:dark +
                     " surface=" + $script:UiTokens.Surface +
                     " soft=" + $script:UiTokens.Soft + "`r`n"),
                    [Text.Encoding]::UTF8)
            } catch { }
        }
        $script:lastTotal = $total
        $script:lastCount = $total
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
$InputBox.Add_GotFocus({ $InputBorder.BorderBrush = Tok 'Accent' })
$InputBox.Add_LostFocus({ $InputBorder.BorderBrush = Tok 'Stroke' })
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
$script:VsCardLine = $script:UiTokens.Stroke
$script:VsInk = $script:UiTokens.Ink
$script:VsMeta = $script:UiTokens.Meta
$script:VsNodes = @{
    char  = @{ Node = $NodeChar;  Drop = $DropChar;  Img = $ImgChar;  Hint = $HintChar;  Dash = $DashChar;  Name = $NameChar;  Accent = "#2F7DE1"; Path = $null }
    bg    = @{ Node = $NodeBg;    Drop = $DropBg;    Img = $ImgBg;    Hint = $HintBg;    Dash = $DashBg;    Name = $NameBg;    Accent = "#43A047"; Path = $null }
    scene = @{ Node = $NodeScene; Drop = $DropScene; Img = $ImgScene; Hint = $HintScene; Dash = $DashScene; Name = $NameScene; Accent = "#8E24AA"; Path = $null }
}

# ===== 6 号：Job 包协议 + 工坊参数（三视图三格 / 提示词六槽 / 比例·时长·质量·种子·运镜）=====
$script:JobRoot = Join-Path $VsRoot "jobs"
$script:Job = [ordered]@{ ratio = "16:9"; duration = 5; tier = "draft"; motion = "固定"; seed = [int](Get-Random -Minimum 100000 -Maximum 999999) }
$script:JobMotionTag = 0
$script:JobNegativeDefault = "低分辨率, 模糊, 变形, 多余手指, 水印, 字幕, logo, 过曝, 噪点, 畸变"
$script:JobSlotNames = @("主体", "动作", "场景", "镜头", "光线", "风格")
$script:JobSlotBoxes = @{}
$script:JobSlotLabels = @()
$script:JobLabelBlocks = @()
$script:JobChips = @{ ratio = @{}; duration = @{}; tier = @{} }
$script:AllChips = @()
$script:JobSig = ""
$script:JobSigAt = [DateTime]::MinValue
$script:JobStatusText = ""
$script:VsStatusLockUntil = [DateTime]::MinValue

function New-TriSlot($key, $label, $accent) {
    $wrap = New-Object Windows.Controls.StackPanel
    $wrap.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
    $bd = New-Object Windows.Controls.Border
    $bd.CornerRadius = New-Object Windows.CornerRadius(8)
    $bd.Height = 76
    $bd.Width = 104
    $bd.Background = Tok 'Soft'
    $bd.BorderBrush = Tok 'Dash'
    $bd.BorderThickness = New-Object Windows.Thickness(1)
    $bd.AllowDrop = $true
    $bd.Tag = $key
    $bd.Cursor = "Hand"
    $g = New-Object Windows.Controls.Grid
    $dash = New-Object Windows.Shapes.Rectangle
    $dash.Margin = New-Object Windows.Thickness(4)
    $dash.RadiusX = 6
    $dash.RadiusY = 6
    $dash.Stroke = Tok 'Dash'
    $dash.StrokeThickness = 1.1
    $dash.StrokeDashArray = New-Object Windows.Media.DoubleCollection
    $dash.StrokeDashArray.Add(4) | Out-Null
    $dash.StrokeDashArray.Add(3) | Out-Null
    $hint = New-Object Windows.Controls.TextBlock
    $hint.Text = $label
    $hint.FontSize = 11
    $hint.Foreground = Tok 'Meta'
    $hint.HorizontalAlignment = "Center"
    $hint.VerticalAlignment = "Center"
    $hint.TextWrapping = "Wrap"
    $hint.TextAlignment = "Center"
    $img = New-Object Windows.Controls.Image
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
    $img.Stretch = "Uniform"
    $img.Margin = New-Object Windows.Thickness(2)
    $img.Visibility = "Collapsed"
    $img.AllowDrop = $true
    $img.Tag = $key
    $g.Children.Add($dash) | Out-Null
    $g.Children.Add($img) | Out-Null
    $g.Children.Add($hint) | Out-Null
    $bd.Child = $g
    $nm = New-Object Windows.Controls.TextBlock
    $nm.FontSize = $script:FsCaption
    $nm.Foreground = Tok 'Meta'
    $nm.TextTrimming = "CharacterEllipsis"
    $nm.Margin = New-Object Windows.Thickness(1, 3, 0, 0)
    $nm.Text = "未选（可空）"
    $wrap.Children.Add($bd) | Out-Null
    $wrap.Children.Add($nm) | Out-Null
    return @{ Node = $bd; Drop = $bd; Img = $img; Hint = $hint; Dash = $dash; Name = $nm; Accent = $accent; Path = $null; Wrap = $wrap }
}
$script:TriRow = New-Object Windows.Controls.StackPanel
$script:TriRow.Orientation = "Horizontal"
$script:TriRow.Margin = New-Object Windows.Thickness(0, 8, 0, 0)
$script:VsNodes["charSide"] = New-TriSlot "charSide" "侧面参考" "#2F7DE1"
$script:VsNodes["charBack"] = New-TriSlot "charBack" "背面参考" "#2F7DE1"
[void]$script:TriRow.Children.Add($script:VsNodes["charSide"].Wrap)
[void]$script:TriRow.Children.Add($script:VsNodes["charBack"].Wrap)
$gCharInner = $DropChar.Parent
$rTri = New-Object Windows.Controls.RowDefinition
$rTri.Height = "Auto"
[void]$gCharInner.RowDefinitions.Add($rTri)
[Windows.Controls.Grid]::SetRow($script:TriRow, 2)
[void]$gCharInner.Children.Add($script:TriRow)

function New-JobLabel($text) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = $script:FsMeta
    $t.Width = 56
    $t.VerticalAlignment = "Center"
    $t.Foreground = Tok 'Meta'
    $script:JobLabelBlocks += $t
    return $t
}
function New-JobChip($group, $value, $text) {
    $b = New-Object Windows.Controls.Button
    $b.Content = $text
    try { $b.Style = $win.FindResource("UtilBtn") } catch { }
    $b.FontSize = $script:FsMeta
    $b.Margin = New-Object Windows.Thickness(0, 0, 6, 0)
    $b.Padding = New-Object Windows.Thickness(10, 3, 10, 3)
    $b.Tag = "$group|$value"
    # 18-补：参数芯片补稳定 AutomationId（不改行为/文案/样式）
    $aidChip = switch ($group) {
        'ratio' { 'Param.Ratio.' + ([string]$value -replace ':', 'x') }
        'duration' { 'Param.Duration.' + $value + 's' }
        'tier' { 'Param.Quality.' + $(if ($value -eq 'draft') { 'Draft' } else { 'Final' }) }
        default { 'Param.' + $group + '.' + $value }
    }
    try { [Windows.Automation.AutomationProperties]::SetAutomationId($b, $aidChip) } catch { }
    $script:AllChips += $b
    return $b
}
function New-JobRow($label, $children) {
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = "Horizontal"
    $row.Margin = New-Object Windows.Thickness(0, 0, 0, 7)
    [void]$row.Children.Add((New-JobLabel $label))
    foreach ($c in $children) { [void]$row.Children.Add($c) }
    return $row
}
$script:ParamsCard = New-Object Windows.Controls.Border
$script:ParamsCard.CornerRadius = New-Object Windows.CornerRadius(14)
$script:ParamsCard.BorderThickness = New-Object Windows.Thickness(1)
$script:ParamsCard.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
$script:ParamsCard.Background = Brush $script:VsCardBg
$script:ParamsCard.BorderBrush = Brush $script:VsCardLine
$pSp = New-Object Windows.Controls.StackPanel
$pSp.Margin = New-Object Windows.Thickness(12, 10, 12, 8)
$headP = New-Object Windows.Controls.TextBlock
$headP.Text = "生成参数 · Job"
$headP.FontSize = 12.5
$headP.FontWeight = "SemiBold"
$headP.Foreground = Tok 'Accent'
$headP.Margin = New-Object Windows.Thickness(0, 0, 0, 8)
[void]$pSp.Children.Add($headP)

$rowRatio = New-JobRow "比例" @(
    (New-JobChip "ratio" "16:9" "16:9"),
    (New-JobChip "ratio" "9:16" "9:16"),
    (New-JobChip "ratio" "1:1" "1:1")
)
$script:JobChips.ratio["16:9"] = $rowRatio.Children[1]
$script:JobChips.ratio["9:16"] = $rowRatio.Children[2]
$script:JobChips.ratio["1:1"] = $rowRatio.Children[3]
[void]$pSp.Children.Add($rowRatio)

$rowDur = New-JobRow "时长" @(
    (New-JobChip "duration" 4 "4s"),
    (New-JobChip "duration" 5 "5s"),
    (New-JobChip "duration" 6 "6s"),
    (New-JobChip "duration" 8 "8s")
)
$script:JobChips.duration[4] = $rowDur.Children[1]
$script:JobChips.duration[5] = $rowDur.Children[2]
$script:JobChips.duration[6] = $rowDur.Children[3]
$script:JobChips.duration[8] = $rowDur.Children[4]
[void]$pSp.Children.Add($rowDur)

$rowTier = New-JobRow "质量" @(
    (New-JobChip "tier" "draft" "草稿"),
    (New-JobChip "tier" "final" "成片")
)
$script:JobChips.tier["draft"] = $rowTier.Children[1]
$script:JobChips.tier["final"] = $rowTier.Children[2]
[void]$pSp.Children.Add($rowTier)

$script:JobMotionBtn = New-Object Windows.Controls.Button
try { $script:JobMotionBtn.Style = $win.FindResource("UtilBtn") } catch { }
$script:JobMotionBtn.FontSize = $script:FsMeta
$script:JobMotionBtn.Padding = New-Object Windows.Thickness(10, 3, 10, 3)
$script:JobMotionBtn.Content = "固定 ↻"
    try { [Windows.Automation.AutomationProperties]::SetAutomationId($script:JobMotionBtn, 'Param.Motion.Cycle') } catch { }
$script:AllChips += $script:JobMotionBtn
$script:JobMotionBtn.Add_Click({
    $list = @("固定", "推近", "拉远", "横移", "跟拍", "环绕")
    $script:JobMotionTag = ($script:JobMotionTag + 1) % $list.Count
    $script:Job.motion = $list[$script:JobMotionTag]
    $script:JobMotionBtn.Content = $script:Job.motion + " ↻"
})
$rowMove = New-JobRow "运镜" @($script:JobMotionBtn)
[void]$pSp.Children.Add($rowMove)

$script:JobSeedBox = New-Object Windows.Controls.TextBox
$script:JobSeedBox.Width = 96
$script:JobSeedBox.Height = 25
$script:JobSeedBox.FontSize = $script:FsMeta
$script:JobSeedBox.Padding = New-Object Windows.Thickness(6, 2, 6, 2)
$script:JobSeedBox.VerticalContentAlignment = "Center"
$script:JobSeedBox.Text = [string]$script:Job.seed
$seedBtn = New-Object Windows.Controls.Button
try { $seedBtn.Style = $win.FindResource("UtilBtn") } catch { }
$seedBtn.FontSize = $script:FsMeta
$seedBtn.Padding = New-Object Windows.Thickness(10, 3, 10, 3)
$seedBtn.Margin = New-Object Windows.Thickness(6, 0, 0, 0)
$seedBtn.Content = "随机"
try { [Windows.Automation.AutomationProperties]::SetAutomationId($seedBtn, 'Param.Seed.Random') } catch { }
$script:AllChips += $seedBtn
$seedBtn.Add_Click({
    $script:Job.seed = [int](Get-Random -Minimum 100000 -Maximum 999999)
    $script:JobSeedBox.Text = [string]$script:Job.seed
})
$rowSeed = New-JobRow "种子" @($script:JobSeedBox, $seedBtn)
[void]$pSp.Children.Add($rowSeed)

$script:JobNegBox = New-Object Windows.Controls.TextBox
$script:JobNegBox.Height = 25
$script:JobNegBox.FontSize = 11
$script:JobNegBox.Padding = New-Object Windows.Thickness(6, 2, 6, 2)
$script:JobNegBox.VerticalContentAlignment = "Center"
$script:JobNegBox.Text = $script:JobNegativeDefault
$rowNeg = New-JobRow "负向" @($script:JobNegBox)
[void]$pSp.Children.Add($rowNeg)
$script:ParamsCard.Child = $pSp

$script:SlotsCard = New-Object Windows.Controls.Border
$script:SlotsCard.CornerRadius = New-Object Windows.CornerRadius(14)
$script:SlotsCard.BorderThickness = New-Object Windows.Thickness(1)
$script:SlotsCard.Margin = New-Object Windows.Thickness(0, 0, 0, 12)
$script:SlotsCard.Background = Brush $script:VsCardBg
$script:SlotsCard.BorderBrush = Brush $script:VsCardLine
$sSp = New-Object Windows.Controls.StackPanel
$sSp.Margin = New-Object Windows.Thickness(12, 10, 12, 10)
$headS = New-Object Windows.Controls.TextBlock
$headS.Text = "提示词六槽 · 可选，留空则用下面总提示词"
$headS.FontSize = 12.5
$headS.FontWeight = "SemiBold"
$headS.Foreground = Tok 'Prompt'
$headS.Margin = New-Object Windows.Thickness(0, 0, 0, 8)
[void]$sSp.Children.Add($headS)
$slotGrid = New-Object Windows.Controls.Grid
foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength(1, "Star"); [void]$slotGrid.ColumnDefinitions.Add($cd) }
foreach ($i in 0..2) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = "Auto"; [void]$slotGrid.RowDefinitions.Add($rd) }
for ($si = 0; $si -lt 6; $si++) {
    $name = $script:JobSlotNames[$si]
    $cell = New-Object Windows.Controls.StackPanel
    $cell.Margin = New-Object Windows.Thickness(0, 0, 8, 7)
    $lt = New-Object Windows.Controls.TextBlock
    $lt.Text = $name
    $lt.FontSize = 11
    $lt.Foreground = Tok 'Meta'
    $script:JobSlotLabels += $lt
    $tb = New-Object Windows.Controls.TextBox
    $tb.Height = 26
    $tb.FontSize = $script:FsMeta
    $tb.Padding = New-Object Windows.Thickness(6, 2, 6, 2)
    $tb.VerticalContentAlignment = "Center"
    $tb.Tag = $name
    $script:JobSlotBoxes[$name] = $tb
    [void]$cell.Children.Add($lt)
    [void]$cell.Children.Add($tb)
    [Windows.Controls.Grid]::SetRow($cell, [int][Math]::Floor($si / 2))
    [Windows.Controls.Grid]::SetColumn($cell, ($si % 2))
    [void]$slotGrid.Children.Add($cell)
}
[void]$sSp.Children.Add($slotGrid)
$script:SlotsCard.Child = $sSp

$spParent = $NodePrompt.Parent
if ($spParent -and $spParent.Children) {
    $idxP = $spParent.Children.IndexOf($NodePrompt)
    if ($idxP -ge 0) {
        $spParent.Children.Insert($idxP + 1, $script:ParamsCard)
        $spParent.Children.Insert($idxP + 2, $script:SlotsCard)
    }
}

function Sync-JobChips {
    $onBg = $script:UiTokens.Accent
    $offBg = $script:UiTokens.Soft
    $ink = $script:UiTokens.Ink
    $line = $script:UiTokens.Stroke
    foreach ($grp in @("ratio", "duration", "tier")) {
        $cur = [string]$script:Job[$grp]
        foreach ($k in @($script:JobChips[$grp].Keys)) {
            $chip = $script:JobChips[$grp][$k]
            if (-not $chip) { continue }
            if ([string]$chip.Tag.Split("|")[1] -eq $cur) {
                $chip.Background = Brush $onBg
                $chip.Foreground = Tok 'AccentInk'
                $chip.BorderBrush = Brush $onBg
            } else {
                $chip.Background = Brush $offBg
                $chip.Foreground = Brush $ink
                $chip.BorderBrush = Brush $line
            }
        }
    }
}
function Update-JobStatus {
    if (-not $script:studio) { return }
    if ((Get-Date) -lt $script:VsStatusLockUntil) { return }
    try {
        if (-not (Test-Path $script:JobRoot)) { return }
        $last = Get-ChildItem -LiteralPath $script:JobRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if (-not $last) { return }
        $jf = Join-Path $last.FullName "job.json"
        if (-not (Test-Path $jf)) { return }
        $j = Get-Content -LiteralPath $jf -Raw -Encoding UTF8 | ConvertFrom-Json
        $map = @{ queued = "排队中，等守夜人发帖"; posted = "已递总线"; awaiting_confirm = "等掌柜确认收货"; cloud_working = "云端生成中"; verifying = "对账中"; completed = "已完成"; failed = "失败"; posting = "已打包，正在发帖" }
        $label = $map[[string]$j.status]
        if (-not $label) { $label = [string]$j.status }
        $txt = "最近 Job " + [string]$j.id + " · " + $label
        if ($j.PSObject.Properties.Name -contains "statusNote" -and $j.statusNote) { $txt += " · " + [string]$j.statusNote }
        $mp4 = Join-Path (Join-Path $VsRoot "outputs") ([string]$j.id + ".mp4")
        if (Test-Path $mp4) { $txt += " · 成品可播" }
        if ($txt -ne $script:JobStatusText) {
            $script:JobStatusText = $txt
            $VsStatus.Text = $txt
        }
    } catch { }
}
$script:ApplyJobParamsTheme = {
    $dark = [bool]$script:dark
    $bg = $script:UiTokens.Card
    $line = $script:UiTokens.Stroke
    $ink = $script:UiTokens.Ink
    $meta = $script:UiTokens.Meta
    $field = $script:UiTokens.Soft
    foreach ($bd in @($script:ParamsCard, $script:SlotsCard)) {
        if ($bd) { $bd.Background = Brush $bg; $bd.BorderBrush = Brush $line }
    }
    foreach ($t in $script:JobLabelBlocks) { $t.Foreground = Brush $meta }
    foreach ($b in @($script:JobMotionBtn, $seedBtn)) {
        if ($b) { $b.Background = Tok 'Soft'; $b.Foreground = Brush $ink; $b.BorderBrush = Brush $line }
    }
    foreach ($t in $script:JobSlotLabels) { $t.Foreground = Brush $meta }
    foreach ($tb in @($script:JobSeedBox, $script:JobNegBox)) {
        if ($tb) { $tb.Background = Brush $field; $tb.Foreground = Brush $ink; $tb.BorderBrush = Brush $line }
    }
    foreach ($k in $script:JobSlotBoxes.Keys) {
        $tb = $script:JobSlotBoxes[$k]
        if ($tb) { $tb.Background = Brush $field; $tb.Foreground = Brush $ink; $tb.BorderBrush = Brush $line }
    }
    foreach ($k in @("charSide", "charBack")) {
        $n = $script:VsNodes[$k]
        if ($n) {
            $n.Drop.Background = Brush $field
            $n.Drop.BorderBrush = Tok 'Dash'
            if ($n.Dash) { $n.Dash.Stroke = Tok 'Dash' }
            $n.Name.Foreground = Brush $meta
            $n.Hint.Foreground = Brush $meta
        }
    }
    Sync-JobChips
}
$chipClick = {
    param($s, $e)
    $parts = ([string]$s.Tag).Split("|")
    if ($parts.Count -lt 2) { return }
    $grp = $parts[0]
    $val = $parts[1]
    if ($grp -eq "duration") { $script:Job.duration = [int]$val } else { $script:Job[$grp] = $val }
    Sync-JobChips
}
foreach ($c in $script:AllChips) {
    if ($c -ne $script:JobMotionBtn -and $c -ne $seedBtn) { $c.Add_Click($chipClick) }
}
$script:JobSeedBox.Add_TextChanged({ try { $script:Job.seed = [int]$script:JobSeedBox.Text } catch { } })
& $script:ApplyJobParamsTheme
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
    $path.Stroke = Tok 'Dash'
    $path.StrokeThickness = 2
    $VsCanvas.Children.Insert(0, $path) | Out-Null
    $script:VsLines += $path
}
function Add-Port($x, $y) {
    $e = New-Object Windows.Shapes.Ellipse
    $e.Width = 9; $e.Height = 9
    $e.Fill = Tok 'Dash'
    $e.Stroke = Tok 'AccentInk'
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
        if ($n.Dash) { $n.Dash.Visibility = "Collapsed" }
        $n.Path = $path
        $n.Name.Text = [IO.Path]::GetFileName($path)
        Reset-NodeHi $key
        Refresh-Flow
    } catch { $n.Name.Text = "⚠ 图片读取失败" }
}
function Refresh-Flow {
    try {
        $on = Brush "#35C759"; $off = Tok 'Dash'
        $FlowDotChar.Fill = if ($script:VsNodes["char"].Path) { $on } else { $off }
        $FlowDotBg.Fill = if ($script:VsNodes["bg"].Path) { $on } else { $off }
        $FlowDotScene.Fill = if ($script:VsNodes["scene"].Path -or $SceneText.Text.Trim()) { $on } else { $off }
        $FlowDotPrompt.Fill = if ($PromptText.Text.Trim()) { $on } else { $off }
        $tri = 0
        foreach ($tk in @("char", "charSide", "charBack")) { if ($script:VsNodes[$tk].Path) { $tri++ } }
        $BarCharT.Text = "人物 · 图片（参考 " + $tri + "/3）"
    } catch { }
}
function Reset-NodeHi($key) {
    $n = $script:VsNodes[$key]
    if (-not $n) { return }
    $n.Node.BorderBrush = Brush $script:VsCardLine
    $n.Node.BorderThickness = New-Object Windows.Thickness(1)
    $n.Node.RenderTransform = $null
}
foreach ($key in @("char", "bg", "scene", "charSide", "charBack")) {
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
$GenBtn.Add_Click({
    $charP = $script:VsNodes["char"].Path
    $sideP = $script:VsNodes["charSide"].Path
    $backP = $script:VsNodes["charBack"].Path
    $bgP = $script:VsNodes["bg"].Path
    $sceneP = $script:VsNodes["scene"].Path
    $sceneText = $SceneText.Text.Trim()
    $style = $StyleBox.Text.Trim()
    $prompt = $PromptText.Text.Trim()
    $missing = @()
    if (-not $charP) { $missing += "人物正面" }
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
        $slots = [ordered]@{}
        foreach ($sn in $script:JobSlotNames) { $slots[$sn] = [string]$script:JobSlotBoxes[$sn].Text.Trim() }
        $neg = [string]$script:JobNegBox.Text.Trim()
        $sig = (@($charP, $sideP, $backP, $bgP, $sceneP, $sceneText, $style, $prompt, $script:Job.ratio, $script:Job.duration, $script:Job.tier, $script:Job.motion, $script:Job.seed, $neg, (($slots.Values) -join ",")) -join "|")
        if ($sig -eq $script:JobSig -and ((Get-Date) - $script:JobSigAt).TotalSeconds -lt 30) {
            $VsStatus.Text = "⚠ 刚提交过同一个任务，30 秒内不重复提交（防重复）"
            $script:VsStatusLockUntil = (Get-Date).AddSeconds(8)
            return
        }
        $jobId = "job_" + (Get-Date -Format "yyyyMMddHHmmss")
        $jobRoot = Join-Path $VsRoot "jobs"
        $jobDir = Join-Path $jobRoot $jobId
        $inDir = Join-Path $jobDir "inputs"
        New-Item -ItemType Directory -Path $inDir -Force | Out-Null
        $inp = [ordered]@{ character = [ordered]@{ front = $null; side = $null; back = $null }; background = $null; scene = $null }
        $roleMap = @{ front = $charP; side = $sideP; back = $backP }
        foreach ($role in @("front", "side", "back")) {
            $srcP = $roleMap[$role]
            if ($srcP) {
                $fn = $role + "_" + [IO.Path]::GetFileName($srcP)
                Copy-Item -LiteralPath $srcP -Destination (Join-Path $inDir $fn) -Force
                $inp.character[$role] = "inputs/" + $fn
            }
        }
        if ($bgP) {
            $fn = "background_" + [IO.Path]::GetFileName($bgP)
            Copy-Item -LiteralPath $bgP -Destination (Join-Path $inDir $fn) -Force
            $inp.background = "inputs/" + $fn
        }
        if ($sceneP) {
            $fn = "scene_" + [IO.Path]::GetFileName($sceneP)
            Copy-Item -LiteralPath $sceneP -Destination (Join-Path $inDir $fn) -Force
            $inp.scene = "inputs/" + $fn
        }
        $job = [ordered]@{
            id = $jobId
            created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            prompt = $prompt
            sceneText = $sceneText
            style = $style
            mode = $(if ($charP) { "image" } else { "text" })
            ratio = [string]$script:Job.ratio
            durationSec = [int]$script:Job.duration
            seed = [int]$script:Job.seed
            tier = [string]$script:Job.tier
            motion = [string]$script:Job.motion
            prompt_slots = $slots
            negative = $neg
            inputs = $inp
            character_partial = ([bool](-not ($sideP -and $backP)))
            first_frame = $null
            last_frame = $null
            status = "queued"
            app = "v5.2"
        }
        $jobPath = Join-Path $jobDir "job.json"
        [IO.File]::WriteAllText($jobPath, ($job | ConvertTo-Json -Depth 6), $Utf8)
        $script:JobSig = $sig
        $script:JobSigAt = Get-Date
        try { Ensure-StudioEngine } catch { }
        $triCount = @($charP, $sideP, $backP | Where-Object { $_ }).Count
        $tags = "人物 " + $triCount + "/3｜" + $job.ratio + "｜" + $job.durationSec + "s｜" + $(if ($job.tier -eq "final") { "成片" } else { "草稿" }) + "｜seed " + $job.seed
        Append-Feed "Dave" "note" ("🎬 Job " + $jobId + " 已入队（" + $tags + "），等守夜人校验发帖；素材在 video_studio\jobs\" + $jobId)
        $VsStatus.Text = "✅ Job " + $jobId + " 已入队 · " + (Get-Date -Format "HH:mm:ss") + " · " + $tags
        Refresh-Feed
    } catch {
        $VsStatus.Text = "⚠ 提交失败：" + $_.Exception.Message
        try { [IO.File]::AppendAllText("D:\tmp\nailong\verify\6\job_err.txt", ((Get-Date -Format "HH:mm:ss") + " " + $_.Exception.ToString() + "`r`nSTACK:`r`n" + $_.ScriptStackTrace + "`r`n"), [Text.Encoding]::UTF8) } catch { }
        try { Append-Feed "Dave" "note" ("⚠ Job 打包失败：" + $_.Exception.Message) } catch { }
    }
})
function Add-PressFx($el) {
    try {
        $el.RenderTransformOrigin = New-Object Windows.Point(0.5, 0.5)
        $el.RenderTransform = New-Object Windows.Media.ScaleTransform(1, 1)
        $el.Add_PreviewMouseDown({ param($s, $e) Play-Press $s 0.86 90 })
        $el.Add_PreviewMouseUp({ param($s, $e) Play-Press $s 1.0 260 })
    } catch { }
}
Add-PressFx $GenBtn
Add-PressFx ($win.FindName("SendBtn"))
$script:LiveBusyUntil = [DateTime]::MinValue
$script:LiveSb = $null
function Start-LiveBadge {
    # 52 号：呼吸灯——只动小圆点 Opacity（1↔0.45、2 秒、easeInOut），不缩放、不动布局
    try {
        if ($script:LiveSb) { try { $script:LiveSb.Stop() } catch { } }
        $sb = New-Object Windows.Media.Animation.Storyboard
        $an = New-Object Windows.Media.Animation.DoubleAnimation
        $an.From = 1.0; $an.To = 0.45
        $an.Duration = New-Object Windows.Duration([TimeSpan]::FromSeconds(2))
        $an.AutoReverse = $true
        $an.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $ease = New-Object Windows.Media.Animation.QuadraticEase
        $ease.EasingMode = [Windows.Media.Animation.EasingMode]::EaseInOut
        $an.EasingFunction = $ease
        [Windows.Media.Animation.Storyboard]::SetTarget($an, $LiveDot)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($an, (New-Object Windows.Media.Animation.PropertyPath("Opacity")))
        $sb.Children.Add($an) | Out-Null
        $script:LiveSb = $sb
        $sb.Begin()
    } catch { }
}
function Stop-LiveBadge {
    try {
        if ($script:LiveSb) { $script:LiveSb.Stop(); $script:LiveSb = $null }
        if ($LiveDot) { $LiveDot.Opacity = 1.0 }
    } catch { }
}
function Update-PresenceBadge {
    # 47 L2 + 52：徽章读在场文件——ok 绿呼吸 / abnormal 红常亮 / 离线（文件超过 90s 没更新）灰不呼吸
    try {
        if ($script:presenceNext -and ((Get-Date) -lt $script:presenceNext)) { return }
        $script:presenceNext = (Get-Date).AddSeconds(2)
        $p = "D:\tmp\nailong\health\presence.json"
        $state = "offline"
        if (Test-Path -LiteralPath $p) {
            try {
                $o = ([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json)
                if ($o) {
                    $fresh = $true
                    if ($o.at) { try { $fresh = (((Get-Date) - [datetime]$o.at).TotalSeconds -lt 600) } catch { $fresh = $true } }
                    if (-not $fresh) { $state = "offline" }
                    elseif ([string]$o.status -eq "abnormal") { $state = "abnormal" }
                    else { $state = "ok" }
                }
            } catch { }
        }
        if ($state -eq $script:badgeState) { return }
        $script:badgeState = $state
        if ($state -eq "ok") {
            if ($LiveBadgeText) { $LiveBadgeText.Text = "营业中" }
            if ($LiveBadge) { $LiveBadge.Background = Tok 'LiveBadgeBg'; $LiveBadge.BorderBrush = Tok 'LiveBadgeLine' }
            if ($LiveBadgeText) { $LiveBadgeText.Foreground = Tok 'LiveGreen' }
            if ($LiveDot) { $LiveDot.Fill = Brush "#35C759"; $LiveDot.Opacity = 1.0 }
            Start-LiveBadge
        } elseif ($state -eq "abnormal") {
            Stop-LiveBadge
            if ($LiveBadgeText) { $LiveBadgeText.Text = "异常" }
            if ($LiveBadge) { $LiveBadge.Background = Brush $(if ($script:dark) { "#2BE5484D" } else { "#1AE5484D" }); $LiveBadge.BorderBrush = Brush $(if ($script:dark) { "#66E5484D" } else { "#4DE5484D" }) }
            if ($LiveBadgeText) { $LiveBadgeText.Foreground = Brush $(if ($script:dark) { "#F87171" } else { "#C62828" }) }
            if ($LiveDot) { $LiveDot.Fill = Brush "#E5484D" }
        } else {
            Stop-LiveBadge
            if ($LiveBadgeText) { $LiveBadgeText.Text = "离线" }
            if ($LiveBadge) { $LiveBadge.Background = Brush $(if ($script:dark) { "#2B6B7A8C" } else { "#1A6B7A8C" }); $LiveBadge.BorderBrush = Brush $(if ($script:dark) { "#666B7A8C" } else { "#4D6B7A8C" }) }
            if ($LiveBadgeText) { $LiveBadgeText.Foreground = Brush "#8A97A8" }
            if ($LiveDot) { $LiveDot.Fill = Brush "#8A97A8"; $LiveDot.Opacity = 0.6 }
        }
    } catch { }
}
function Tick-LiveBadge {
    Update-PresenceBadge
}
function Update-Clock {
    try { if ($StatusText) { $StatusText.Text = (Get-Date -Format "HH:mm:ss") } } catch { }
}
$script:studio = $false
# 25 号：唯一视图入口。四个视图互斥，可见性只在这里决定——
# 任何"关视图"的动作不再自己去开聊天流（旧实现三处都这么干，导致两视图叠画）。
    # 57 号：切换保滚动位
    if (-not $script:scrollPos) { $script:scrollPos = @{} }
    try {
        $oldView = $script:view
        if ($oldView -eq "chat" -and $FeedScroll) { $script:scrollPos["chat"] = $FeedScroll.VerticalOffset }
        if ($oldView -eq "out" -and $OutScroll) { $script:scrollPos["out"] = $OutScroll.VerticalOffset }
        if ($oldView -eq "collab" -and $CbScroll) { $script:scrollPos["collab"] = $CbScroll.VerticalOffset }
    } catch { }
function Set-View([string]$name) {
    if ($name -notin @('chat', 'studio', 'out', 'collab')) { $name = 'chat' }
    $script:view = $name
    $script:studio = ($name -eq 'studio')
    $script:out = ($name -eq 'out')
    $script:collab = ($name -eq 'collab')
    $isChat = ($name -eq 'chat')
    if ($FeedScroll) { $FeedScroll.Visibility = $(if ($isChat) { 'Visible' } else { 'Collapsed' }) }
    if ($InputBar) { $InputBar.Visibility = $(if ($isChat) { 'Visible' } else { 'Collapsed' }) }
    if ($StudioView) { $StudioView.Visibility = $(if ($script:studio) { 'Visible' } else { 'Collapsed' }) }
    if ($OutView) { $OutView.Visibility = $(if ($script:out) { 'Visible' } else { 'Collapsed' }) }
    if ($CollabView) { $CollabView.Visibility = $(if ($script:collab) { 'Visible' } else { 'Collapsed' }) }
    try {
        if ($name -eq "chat" -and $FeedScroll -and $script:scrollPos["chat"]) { $FeedScroll.ScrollToVerticalOffset([double]$script:scrollPos["chat"]) }
        if ($name -eq "out" -and $OutScroll -and $script:scrollPos["out"]) { $OutScroll.ScrollToVerticalOffset([double]$script:scrollPos["out"]) }
        if ($name -eq "collab" -and $CbScroll -and $script:scrollPos["collab"]) { $CbScroll.ScrollToVerticalOffset([double]$script:scrollPos["collab"]) }
    } catch { }
    Update-Rail
}
$script:view = 'chat'
$script:BoldChat = $false   # 32 号：聊天正文加粗开关（只作用于聊天视图条目）

# 26 层二③：全局动效收口。所有动画统一走 Storyboard，且只动 Opacity / RenderTransform。
# 29 号帧率①：应用内计时埋点（只写 health\ui.log，不参与任何业务判断）
function Write-UiTiming([string]$tag, [long]$ms) {
    try {
        $d = 'D:\tmp\nailong\health'
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
        [IO.File]::AppendAllText((Join-Path $d 'ui.log'), ((Get-Date -Format 'HH:mm:ss.fff') + ' | ' + $tag + ' ' + $ms + 'ms' + "`r`n"))
    } catch { }
}
# 32 号：聊天视图全部文字加粗（递归落到 TextBlock / TextBox）
function Set-AllBold($el) {
    if ($null -eq $el) { return }
    try {
        if ($el -is [Windows.Controls.TextBlock] -or $el -is [Windows.Controls.TextBox]) {
            $el.FontWeight = [Windows.FontWeights]::Bold
        }
    } catch { }
    try {
        $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
        for ($i = 0; $i -lt $n; $i++) { Set-AllBold ([Windows.Media.VisualTreeHelper]::GetChild($el, $i)) }
    } catch { }
}
function Play-PopIn($el) {
    if ($null -eq $el) { return }
    try {
        # 29 号 0 项：Opacity 用元素级 BeginAnimation（Storyboard 定向 Opacity 时
        # 全部条目停在 0、聊天视图整片空白，实测踩过）；先设 1 兜底，再从 0 动画到 1。
        $el.Opacity = 1
        $el.RenderTransformOrigin = New-Object Windows.Point(0.5, 1)
        $tg = New-Object Windows.Media.TransformGroup
        $tr = New-Object Windows.Media.TranslateTransform(0, 12)
        $sc = New-Object Windows.Media.ScaleTransform(0.93, 0.93)
        $tg.Children.Add($tr) | Out-Null
        $tg.Children.Add($sc) | Out-Null
        $el.RenderTransform = $tg
        $ease = New-Object Windows.Media.Animation.BackEase
        $ease.EasingMode = "EaseOut"; $ease.Amplitude = 0.45
        $sb = New-Object Windows.Media.Animation.Storyboard
        $a1 = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(200))))
        $a1.EasingFunction = $ease
        [Windows.Media.Animation.Storyboard]::SetTarget($a1, $el)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($a1, (New-Object Windows.Media.Animation.PropertyPath("Opacity")))
        $sb.Children.Add($a1) | Out-Null
        $a2 = New-Object Windows.Media.Animation.DoubleAnimation(12, 0, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(260))))
        $a2.EasingFunction = $ease
        [Windows.Media.Animation.Storyboard]::SetTarget($a2, $tr)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($a2, (New-Object Windows.Media.Animation.PropertyPath("Y")))
        $sb.Children.Add($a2) | Out-Null
        $a3 = New-Object Windows.Media.Animation.DoubleAnimation(0.93, 1, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(260))))
        $a3.EasingFunction = $ease
        [Windows.Media.Animation.Storyboard]::SetTarget($a3, $sc)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($a3, (New-Object Windows.Media.Animation.PropertyPath("ScaleX")))
        $sb.Children.Add($a3) | Out-Null
        $a4 = New-Object Windows.Media.Animation.DoubleAnimation(0.93, 1, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds(260))))
        $a4.EasingFunction = $ease
        [Windows.Media.Animation.Storyboard]::SetTarget($a4, $sc)
        [Windows.Media.Animation.Storyboard]::SetTargetProperty($a4, (New-Object Windows.Media.Animation.PropertyPath("ScaleY")))
        $sb.Children.Add($a4) | Out-Null
        $sb.Begin()
    } catch { }
}

function Play-Press($el, [double]$scale, [int]$ms) {
    if ($null -eq $el) { return }
    try {
        $st = $el.RenderTransform
        if (-not ($st -is [Windows.Media.ScaleTransform])) { return }
        $ease = New-Object Windows.Media.Animation.BackEase
        $ease.EasingMode = "EaseOut"; $ease.Amplitude = 0.5
        $sb = New-Object Windows.Media.Animation.Storyboard
        foreach ($prop in @("ScaleX", "ScaleY")) {
            $a = New-Object Windows.Media.Animation.DoubleAnimation($scale, (New-Object Windows.Duration([TimeSpan]::FromMilliseconds($ms))))
            $a.EasingFunction = $ease
            [Windows.Media.Animation.Storyboard]::SetTarget($a, $st)
            [Windows.Media.Animation.Storyboard]::SetTargetProperty($a, (New-Object Windows.Media.Animation.PropertyPath($prop)))
            $sb.Children.Add($a) | Out-Null
        }
        $sb.Begin()
    } catch { }
}

function Update-Rail {
    try {
        $active = $script:UiTokens.CharSoft
        $fg = $script:UiTokens.Ink2
        $accent = Tok 'Accent'
        $chatOn = (-not $script:studio) -and (-not $script:collab) -and (-not $script:out)
        $states = @{ chat = $chatOn; studio = [bool]$script:studio; out = [bool]$script:out; collab = [bool]$script:collab }
        $btns = @{ chat = $BtnChat; studio = $StudioBtn; out = $OutBtn; collab = $CollabBtn }
        foreach ($k in @('chat','studio','out','collab')) {
            $b = $btns[$k]
            if (-not $b) { continue }
            if ($states[$k]) {
                $b.Background = Brush $active
                $b.BorderBrush = $accent
                $b.BorderThickness = New-Object Windows.Thickness(3, 0, 0, 0)
            } else {
                $b.Background = Brush 'Transparent'
                $b.BorderThickness = New-Object Windows.Thickness(0)
            }
        }
        foreach ($b in @($BtnChat, $StudioBtn, $OutBtn, $CollabBtn, $ArchiveBtn, $ArchiveUndoBtn, $BootCopyBtn, $ShotBtn, $DarkBtn)) { if ($b) { $b.Foreground = Brush $fg } }
        if ($script:ViewW -and ($win.Width -ne $script:ViewW -or $win.Height -ne $script:ViewH)) { $win.Width = $script:ViewW; $win.Height = $script:ViewH }
    } catch { }
}
function Set-Studio($on) {
    if ($on) {
        Set-View 'studio'
        $script:studio = $true
        $StudioBtn.ToolTip = "回到聊天"
        Refresh-Flow
        try { Update-JobStatus } catch { }
    } else {
        Set-View 'chat'
        $StudioBtn.ToolTip = "视频工坊"
    }
    Update-Rail
}
$StudioBtn.Add_Click({ Set-Studio (-not $script:studio) })

# ===== 9 号：成品独立成栏 =====
$OutBtn = $win.FindName("OutBtn")
$OutView = $win.FindName("OutView")
$OutList = $win.FindName("OutList")
$OutScroll = $win.FindName("OutScroll")
$OutRefresh = $win.FindName("OutRefresh")
$OutTitle = $win.FindName("OutTitle")
$script:out = $false
    $script:OutSig = [char]0 + "init"   # 26：空列表签名与"未初始化"区分，否则首进成品视图会跳过渲染
$OutDir = Join-Path $VsRoot "outputs"
$script:ThumbDir = Join-Path $VsRoot "outputs\.thumbs"

function Ensure-Thumb($mp4) {
    $name = [IO.Path]::GetFileNameWithoutExtension($mp4)
    $dst = Join-Path $script:ThumbDir ($name + ".jpg")
    if (Test-Path -LiteralPath $dst) { return $dst }
    $ff = "D:\tmp\video_studio\engine\ffmpeg.exe"
    if (-not (Test-Path -LiteralPath $ff)) { return $null }
    try {
        if (-not (Test-Path $script:ThumbDir)) { New-Item -ItemType Directory -Path $script:ThumbDir -Force | Out-Null }
        $a = @("-y", "-ss", "1", "-i", $mp4, "-frames:v", "1", "-vf", "scale=300:-1", $dst)
        Start-Process -FilePath $ff -ArgumentList $a -WindowStyle Hidden -Wait
        if (Test-Path -LiteralPath $dst) { return $dst }
    } catch { }
    return $null
}

function Get-JobPrompt($id) {
    try {
        $jp = Join-Path $VsRoot ("jobs\" + $id + "\job.json")
        if (-not (Test-Path -LiteralPath $jp)) { return "（无对应 job 记录）" }
        $j = [IO.File]::ReadAllText($jp, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $p = [string]$j.prompt
        if (-not $p -and $j.prompt_slots) { $p = (($j.prompt_slots.PSObject.Properties | Where-Object { $_.Value } | ForEach-Object { $_.Value }) -join "，") }
        if (-not $p) { return "（该 job 无提示词）" }
        return $p
    } catch { return "" }
}

function Confirm-Dialog($msg) {
    $script:DlgResult = $false
    try {
        $dw = New-Object Windows.Window
        $dw.Title = "删除确认"
        $dw.Width = 420
        $dw.Height = 200
        $dw.WindowStartupLocation = "CenterOwner"
        $dw.Owner = $win
        $dw.Topmost = $true
        $dw.ResizeMode = "NoResize"
        $dw.WindowStyle = "ToolWindow"
        $dw.Background = Tok 'Card'
        $sp = New-Object Windows.Controls.StackPanel
        $sp.Margin = New-Object Windows.Thickness(18, 16, 18, 14)
        $tt = New-Object Windows.Controls.TextBlock
        $tt.Text = $msg
        $tt.FontSize = 12.5
        $tt.TextWrapping = "Wrap"
        $tt.Foreground = Tok 'Ink'
        [void]$sp.Children.Add($tt)
        $row = New-Object Windows.Controls.StackPanel
        $row.Orientation = "Horizontal"
        $row.HorizontalAlignment = "Right"
        $row.Margin = New-Object Windows.Thickness(0, 18, 0, 0)
        $bNo = New-Object Windows.Controls.Button
        try { $bNo.Style = $win.FindResource("UtilBtn") } catch { }
        $bNo.Content = "取消"
        $bNo.Padding = New-Object Windows.Thickness(16, 6, 16, 6)
        $bNo.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
        $bNo.Add_Click({ $script:DlgResult = $false; $dw.Close() }.GetNewClosure())
        $bYes = New-Object Windows.Controls.Button
        try { $bYes.Style = $win.FindResource("UtilBtn") } catch { }
        $bYes.Content = "确定删除"
        $bYes.Padding = New-Object Windows.Thickness(16, 6, 16, 6)
        $bYes.Background = Brush "#D9534F"
        $bYes.Foreground = Tok 'AccentInk'
        $bYes.BorderBrush = Brush "#D9534F"
        $bYes.Add_Click({ $script:DlgResult = $true; $dw.Close() }.GetNewClosure())
        [void]$row.Children.Add($bNo)
        [void]$row.Children.Add($bYes)
        [void]$sp.Children.Add($row)
        $dw.Content = $sp
        $dw.ShowDialog() | Out-Null
    } catch {
        try { [IO.File]::AppendAllText("D:\tmp\nailong\verify\9\out_err.txt", ((Get-Date -Format "HH:mm:ss") + " 确认窗失败：" + $_.Exception.Message + "`r`n"), [Text.Encoding]::UTF8) } catch { }
        return $false
    }
    return [bool]$script:DlgResult
}

function Show-Player($path) {
    try {
        $pw = New-Object Windows.Window
        $pw.Title = "播放 · " + [IO.Path]::GetFileName($path)
        $pw.Width = 980
        $pw.Height = 620
        $pw.WindowStartupLocation = "CenterScreen"
        $pw.Background = Brush "#101820"
        $pw.Topmost = $true
        $media = New-Object Windows.Controls.MediaElement
        $media.LoadedBehavior = "Play"
        $media.UnloadedBehavior = "Manual"
        $media.Stretch = "Uniform"
        $media.Source = New-Object Uri($path)
        $media.Add_MediaFailed({ param($s, $e) try { [IO.File]::AppendAllText("D:\tmp\nailong\verify\9\player_err.txt", ((Get-Date -Format "HH:mm:ss") + " " + $e.ErrorException.Message + "`r`n"), [Text.Encoding]::UTF8) } catch { } })
        $pw.Content = $media
        $pw.Add_Closing({ try { $media.Stop(); $media.Close() } catch { } })
        $pw.Add_KeyDown({ param($s, $e) if ($e.Key -eq "Escape") { $s.Close() } })
        $pw.ShowDialog() | Out-Null
        return $true
    } catch {
        try { [IO.File]::AppendAllText("D:\tmp\nailong\verify\9\player_err.txt", ((Get-Date -Format "HH:mm:ss") + " 内嵌播放失败：" + $_.Exception.Message + "`r`n"), [Text.Encoding]::UTF8) } catch { }
        try { Start-Process -FilePath $path } catch { }
        return $false
    }
}

function New-OutCard($f) {
    $id = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $dark = [bool]$script:dark
    $bg = $script:UiTokens.Card
    $line = $script:UiTokens.Stroke
    $ink = $script:UiTokens.Ink
    $meta = $script:UiTokens.Meta
    $field = $script:UiTokens.Soft
    $script:OutField = $field
    $script:OutInk = $ink
    $script:OutLine = $line
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = New-Object Windows.CornerRadius(12)
    $card.Background = Brush $bg
    $card.BorderBrush = Brush $line
    $card.BorderThickness = New-Object Windows.Thickness(1)
    $card.Padding = New-Object Windows.Thickness(9)
    $card.Margin = New-Object Windows.Thickness(6, 5, 6, 5)
    $card.MaxWidth = 9999
    $grid = New-Object Windows.Controls.Grid
    foreach ($w in @(132, 0, 0)) { $cd = New-Object Windows.Controls.ColumnDefinition; if ($w -eq 0) { $cd.Width = New-Object Windows.GridLength(1, "Star") } else { $cd.Width = New-Object Windows.GridLength($w, "Pixel") }; [void]$grid.ColumnDefinitions.Add($cd) }
    $thumbBox = New-Object Windows.Controls.Border
    $thumbBox.Width = 132; $thumbBox.Height = 74
    $thumbBox.CornerRadius = New-Object Windows.CornerRadius(8)
    $thumbBox.Background = Brush $field
    $thumbBox.BorderBrush = Brush $line
    $thumbBox.BorderThickness = New-Object Windows.Thickness(1)
    [Windows.Controls.Grid]::SetColumn($thumbBox, 0)
    $tp = Ensure-Thumb $f.FullName
    if ($tp) {
        $img = New-Object Windows.Controls.Image
        [Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
        $img.Stretch = "UniformToFill"
        $biT = New-Object Windows.Media.Imaging.BitmapImage ([Uri]$tp)
        $biT.DecodePixelWidth = 160
        $biT.CacheOption = "OnLoad"
        $img.Source = $biT
        $clip = New-Object Windows.Media.RectangleGeometry
        $clip.Rect = New-Object Windows.Rect(0, 0, 132, 74)
        $clip.RadiusX = 8; $clip.RadiusY = 8
        $img.Clip = $clip
        $thumbBox.Child = $img
    } else {
        $ph = New-Object Windows.Controls.TextBlock
        $ph.Text = "无首帧"
        $ph.FontSize = 11
        $ph.Foreground = Brush $meta
        $ph.HorizontalAlignment = "Center"
        $ph.VerticalAlignment = "Center"
        $thumbBox.Child = $ph
    }
    [void]$grid.Children.Add($thumbBox)
    $info = New-Object Windows.Controls.StackPanel
    $info.Margin = New-Object Windows.Thickness(10, 2, 6, 2)
    [Windows.Controls.Grid]::SetColumn($info, 1)
    $t1 = New-Object Windows.Controls.TextBlock
    $t1.Text = $id
    $t1.FontSize = 12.5
    $t1.FontWeight = "SemiBold"
    $t1.Foreground = Brush $ink
    $t1.TextTrimming = "CharacterEllipsis"
    $t2 = New-Object Windows.Controls.TextBlock
    $kb = [math]::Round($f.Length / 1KB, 0)
    $t2.Text = $f.LastWriteTime.ToString("MM-dd HH:mm") + " · " + $kb + " KB"
    $t2.FontSize = 11
    $t2.Foreground = Brush $meta
    $t2.Margin = New-Object Windows.Thickness(0, 2, 0, 0)
    $t3 = New-Object Windows.Controls.TextBlock
    $pr = Get-JobPrompt $id
    if (-not $pr) { $pr = "（无对应 job 记录）" }
    $t3.Text = $pr
    $t3.FontSize = $script:FsMeta
    $t3.Foreground = Brush $ink
    $t3.TextWrapping = "Wrap"
    $t3.TextTrimming = "CharacterEllipsis"
    $t3.MaxHeight = 34
    $t3.Margin = New-Object Windows.Thickness(0, 4, 0, 0)
    [void]$info.Children.Add($t1)
    [void]$info.Children.Add($t2)
    [void]$info.Children.Add($t3)
    [void]$grid.Children.Add($info)
    $btns = New-Object Windows.Controls.StackPanel
    $btns.Orientation = "Horizontal"
    $btns.VerticalAlignment = "Center"
    [Windows.Controls.Grid]::SetColumn($btns, 2)
    foreach ($spec in @(@("播放", $f.FullName, "play"), @("文件夹", $f.FullName, "folder"), @("删除", $f.FullName, "del"))) {
        $b = New-Object Windows.Controls.Button
        try { $b.Style = $win.FindResource("UtilBtn") } catch { }
        $b.Content = $spec[0]
        $b.Tag = $spec[1] + "|" + $spec[2]
        $b.FontSize = $script:FsMeta
        $b.MinWidth = 54
        $b.Padding = New-Object Windows.Thickness(8, 5, 8, 5)
        $b.HorizontalContentAlignment = "Center"
        $b.VerticalContentAlignment = "Center"
        $b.Margin = New-Object Windows.Thickness(5, 0, 0, 0)
        $b.Background = Brush $field
        $b.Foreground = Brush $ink
        $b.BorderBrush = Brush $line
        # 18-补：成品行按钮补稳定 AutomationId（按 job_id，悬停二态不改 ID）
        $aidSuffix = switch ($spec[2]) { 'play' { 'Play' } 'folder' { 'OpenFolder' } 'del' { 'Delete' } default { [string]$spec[2] } }
        try { [Windows.Automation.AutomationProperties]::SetAutomationId($b, ('Output.' + [string]$id + '.' + $aidSuffix)) } catch { }
        $b.Add_Click({
            param($s, $e)
            $parts = ([string]$s.Tag).Split("|")
            $path = $parts[0]
            switch ($parts[1]) {
                "play" { try { Append-Feed "Dave" "note" ("▶ 播放成品 " + [IO.Path]::GetFileName($path)) } catch { }; try { Show-Player $path | Out-Null } catch { try { Start-Process -FilePath $path } catch { } } }
                "folder" { try { Start-Process explorer.exe -ArgumentList ('/select,"' + $path + '"') } catch { } }
                "del" {
                    $btn = $s
                    if ($script:DelArmed -ne [string]$btn.Tag) {
                        # 兜底：键盘/程序触发时也能进入警示态（正常路径由鼠标悬停驱动）
                        $script:DelArmed = [string]$btn.Tag
                        $script:DelArmedBtn = $btn
                        try { $btn.Content = "确认删除？"; $btn.MinWidth = 84; $btn.Background = Brush "#D9534F"; $btn.Foreground = Tok 'AccentInk'; $btn.BorderBrush = Brush "#D9534F" } catch { }
                        return
                    }
                    $script:DelArmed = $null
                    $script:DelArmedBtn = $null
                    $jobId = [IO.Path]::GetFileNameWithoutExtension($path)
                    try { Remove-Item -LiteralPath $path -Force } catch { }
                    try { $rc2 = Join-Path $OutDir ("receipt_" + $jobId + ".json"); if (Test-Path -LiteralPath $rc2) { Remove-Item -LiteralPath $rc2 -Force } } catch { }
                    try { $th2 = Join-Path $script:ThumbDir ($jobId + ".jpg"); if (Test-Path -LiteralPath $th2) { Remove-Item -LiteralPath $th2 -Force } } catch { }
                    $script:OutSig = "`0force"
                    Refresh-Products
                    try { Append-Feed "Dave" "note" ("🗑 已删除成品 " + $jobId) } catch { }
                }
            }
        })
        if ($spec[2] -eq "del") {
            $b.Add_MouseEnter({
                param($s, $e)
                if ($script:DelArmedBtn -and $script:DelArmedBtn -ne $s) {
                    try { $script:DelArmedBtn.Content = "删除"; $script:DelArmedBtn.MinWidth = 64; $script:DelArmedBtn.Background = Brush $script:OutField; $script:DelArmedBtn.Foreground = Brush $script:OutInk; $script:DelArmedBtn.BorderBrush = Brush $script:OutLine } catch { }
                }
                $script:DelArmed = [string]$s.Tag
                $script:DelArmedBtn = $s
                try { $s.Content = "确认删除？"; $s.MinWidth = 84; $s.Background = Brush "#D9534F"; $s.Foreground = Tok 'AccentInk'; $s.BorderBrush = Brush "#D9534F" } catch { }
            })
            $b.Add_MouseLeave({
                param($s, $e)
                if ($script:DelArmed -eq [string]$s.Tag) {
                    $script:DelArmed = $null
                    $script:DelArmedBtn = $null
                    try { $s.Content = "删除"; $s.MinWidth = 64; $s.Background = Brush $script:OutField; $s.Foreground = Brush $script:OutInk; $s.BorderBrush = Brush $script:OutLine } catch { }
                }
            })
        }
        [void]$btns.Children.Add($b)
    }
    [void]$grid.Children.Add($btns)
    $card.Child = $grid
    return $card
}

function Refresh-Products {
    try {
        $files = @(Get-ChildItem -LiteralPath $OutDir -Filter "*.mp4" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $sig = (($files | ForEach-Object { $_.Name + ":" + $_.Length }) -join "|")
        if ($sig -eq $script:OutSig -and $script:out) { return }
        $script:OutSig = $sig
        $OutList.Children.Clear()
        $OutTitle.Foreground = Tok 'Ink'
        $OutTitle.Text = "成品 · 按时间倒序"
        if ($files.Count -eq 0) {
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = "还没有成品。工坊里点生成，掌柜回传后会出现在这里。"
            $tb.FontSize = 12
            $tb.Foreground = Brush $script:VsMeta
            $tb.Margin = New-Object Windows.Thickness(10, 16, 10, 0)
            [void]$OutList.Children.Add($tb)
            return
        }
        foreach ($f in $files) { [void]$OutList.Children.Add((New-OutCard $f)) }
        $OutTitle.Text = "成品 · 共 " + $files.Count + " 条（按时间倒序）"
    } catch {
        try { [IO.File]::AppendAllText("D:\tmp\nailong\verify\9\out_err.txt", ((Get-Date -Format "HH:mm:ss") + " " + $_.Exception.ToString() + "`r`n"), [Text.Encoding]::UTF8) } catch { }
    }
}

function Set-OutView($on) {
    $__sw = [Diagnostics.Stopwatch]::StartNew()
    if ($on) {
        Set-View 'out'
        Refresh-Products
    } else {
        Set-View 'chat'
    }
    Update-Rail
    try { Write-UiTiming ('set-view-out=' + $on) $__sw.ElapsedMilliseconds } catch { }
}
$OutBtn.Add_Click({ Set-OutView (-not $script:out) })
$OutRefresh.Add_Click({ $script:OutSig = "`0force"; Refresh-Products })

# ===== 协作台 / 渲染守夜人 =====
function Ensure-StudioEngine {
    $mine = $PID
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $mine -and $_.CommandLine -match 'studio_daemon2?\.ps1' }
    if ($running) { return }
    $v2 = "D:\tmp\video_studio\engine\launch_daemon2.vbs"
    if (Test-Path $v2) {
        Start-Process wscript.exe -ArgumentList ('"' + $v2 + '"') -WindowStyle Hidden
        return
    }
    $daemon = "D:\tmp\video_studio\engine\studio_daemon.ps1"
    if (Test-Path $daemon) {
        Start-Process wscript.exe -ArgumentList '"D:\tmp\video_studio\engine\launch_daemon.vbs"' -WindowStyle Hidden
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
    # S1：与 Read-Feed 共用 Read-Jsonl（指纹缓存 + 字节偏移增量读），不再各写一份解析逻辑
    return (Read-Jsonl (Join-Path $BusRoot $name) ('bus:' + $name))
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
    # 24-改：roster 只留 小猪 / 大厨 / GPT。客官不再单独成成员（取消红标）；
    # 其余一切识别不出的 from（存档、HC、客官历史帖、roster 外任何人）统一落到
    # 「未识别」中性灰类，**不许再并进大厨**，保证与绿标一眼能分开。历史帖不删。
    if ($from -match '调度|XIAOZHU|小猪|assistant') { return @{ label = "掌柜"; color = $script:UiTokens.RoleHost; bgL = "#E1EEFC"; bgD = "#1E3A56" } }
    if ($from -match 'GPT') { return @{ label = "GPT"; color = $script:UiTokens.RoleGpt; bgL = "#F0E6FA"; bgD = "#39264D" } }
    if ($from -match '工兵|LOCAL|DSH|后厨|大厨') { return @{ label = "大厨"; color = $script:UiTokens.RoleChef; bgL = "#DFF2E2"; bgD = "#1E4030" } }
    return @{ label = "未识别"; color = $script:UiTokens.RoleUnknown; bgL = "#EEF1F5"; bgD = "#2A3440" }
}
function New-CbCard($m, [bool]$isLog) {
    # 50 号（50-补2）：传菜口改用与聊天同一套气泡；任务帖带档位胶囊
    $kind = [string]$m.kind
    $prio = ''
    if ((-not $isLog) -and ($kind -eq 'task')) {
        $prio = 'P1'
        $t0 = [string]$m.text
        if ($t0.Length -gt 300) { $t0 = $t0.Substring(0, 300) }
        $pm = [regex]::Match($t0, 'P([012])\b')
        if ($pm.Success) { $prio = 'P' + $pm.Groups[1].Value }
    }
    return New-MsgBubble ([string]$m.from) $kind ([string]$m.text) ([string]$m.ts) $prio $isLog
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
        $empty.Foreground = Tok 'Hint'
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
    # 26：不清 cbKey —— 签名已含 view/主题/条数/筛选，未变化时复用现有卡片
    $active = @($script:UiTokens.CharSoft, $script:UiTokens.Accent)
    $idle = @($script:UiTokens.Card, $script:UiTokens.Ink2)
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
    $__sw = [Diagnostics.Stopwatch]::StartNew()
    if ($on) {
        Set-View 'collab'
        $CbInputBar.BorderBrush = Tok 'SurfaceStroke'
    # 26：不清 cbKey —— 签名已含 view/主题/条数/筛选，未变化时复用现有卡片
        Set-CbView $script:cbView
        $script:cbSeen = $script:sendTotal
    } else {
        Set-View 'chat'
    }
    Update-CollabBadge
    Update-Rail
    try { Write-UiTiming ('set-view-collab=' + $on) $__sw.ElapsedMilliseconds } catch { }
}
$CollabBtn.Add_Click({ Open-Collab })
$BtnChat.Add_Click({
    # 25 号：聊天视图由 Set-View 统一收口，四个标志位互斥，不再各点各关
    Set-View 'chat'
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
        $RootBorder.Background = Tok 'Surface'
        $RootBorder.BorderBrush = Tok 'SurfaceStroke'
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
    # UI-04：深浅主题都要走一次 Apply-Theme。此前仅深色分支调用，导致浅色启动
    # 从未执行 Update-Rail，导航选中态一直是透明（XAML 默认值）。
    try { Apply-Theme } catch { }
    Log-Boot 'loaded-enter'
    # 53 号：先画窗后填 feed —— 首帧交给消息循环，feed 在 Background 优先级异步构建
    $win.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background, [Action]{
        try {
            Refresh-Feed
            try { Log-Boot 'feed-ready' } catch { }
            try { Refresh-Collab; Update-CollabBadge } catch { }
            [IO.File]::WriteAllText("D:\tmp\live3_ok.txt", ("ok v5.3 entries=" + $script:lastCount + " at " + (Get-Date -Format "HH:mm:ss")), [Text.Encoding]::UTF8)
            Write-AppLog ('start entries=' + $script:lastCount)
        } catch { }
    }) | Out-Null
    Start-LiveBadge
    $InputBox.Focus() | Out-Null
})

$win.Add_Closing({ Write-AppLog 'closing-window'; Save-WindowState })

# 17 号④：全局未捕获异常兜底（Dispatcher + AppDomain 两路，能抓的都抓）
try {
    $win.Dispatcher.add_UnhandledException({
        param($s, $e)
        Write-AppLog ('dispatcher-unhandled: ' + $e.Exception.Message + ' @ ' + $e.Exception.StackTrace)
    })
} catch { }
try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($s, $e)
        Write-AppLog ('appdomain-unhandled: ' + $e.ExceptionObject.ToString())
    })
} catch { }

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Refresh-Feed; Tick-LiveBadge; Refresh-Collab; Update-CollabBadge; Update-JobStatus; if ($script:out) { Refresh-Products } })
$timer.Start()

# 52 号：顶栏实时时钟（每秒走字）
$clock = New-Object Windows.Threading.DispatcherTimer
$clock.Interval = [TimeSpan]::FromSeconds(1)
$clock.Add_Tick({ Update-Clock })
$clock.Start()
Update-Clock

# 恢复上次的窗口位置和大小
$ws = Read-WindowState
$script:big = [bool]$ws.big
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
# 10 号（08:14 更正版）：四视图统一 700×780，切视图一律回到此尺寸，不保留手动调整
$script:ViewW = 860.0
$script:ViewH = 645.0
$win.Width = [Math]::Min($script:ViewW, $wa.Width - 40)
$win.Height = [Math]::Min($script:ViewH, $wa.Height - 60)
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
Write-AppLog 'exit-dialog-returned'
