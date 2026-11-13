param(
    [Parameter(Position = 0)][string]$Cmd = "board",
    [Parameter(Position = 1)][string]$Arg1,
    [string]$From = "",
    [string]$To = "all",
    [string]$Kind = "note",
    [string]$Text = "",
    [string]$Ref = "",
    [string]$Note = "",
    [int]$Limit = 20,
    [switch]$Json
)

# 奶龙三方协作总线（用户 + 助手A + 助手B）
# 目录：D:\tmp\nailong\bus\
#   board.jsonl     留言板（人看的对话）
#   activity.jsonl  动作日志（谁改了什么）
#   agents.json     已注册的成员
#   claims\         文件占用声明（防两个助手同时改同一个文件）

$ErrorActionPreference = 'Stop'
$BusRoot = "D:\tmp\nailong\bus"
$Utf8 = New-Object Text.UTF8Encoding($false)

function Initialize-Bus {
    foreach ($d in @($BusRoot, (Join-Path $BusRoot "claims"))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}
function Get-BusFile([string]$name) { return (Join-Path $BusRoot $name) }

function Add-BusLine([string]$file, $obj) {
    Initialize-Bus
    $line = ($obj | ConvertTo-Json -Compress -Depth 5) + "`n"
    $path = Get-BusFile $file
    for ($i = 0; $i -lt 12; $i++) {
        try {
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
            $sw = New-Object IO.StreamWriter($fs, $Utf8)
            $sw.Write($line)
            $sw.Flush()
            $sw.Dispose()
            $fs.Dispose()
            return
        } catch {
            [Threading.Thread]::Sleep(60 + (Get-Random -Maximum 80))
        }
    }
    throw "写总线失败: $path"
}

function Read-BusLines([string]$file) {
    $path = Get-BusFile $file
    $items = @()
    if (-not (Test-Path $path)) { return $items }
    foreach ($l in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
        if (-not $l.Trim()) { continue }
        try { $items += ($l | ConvertFrom-Json) } catch { }
    }
    return $items
}

function Register-Agent([string]$name, [string]$note) {
    if (-not $name) { return }
    $path = Get-BusFile "agents.json"
    $map = @{}
    if (Test-Path $path) {
        try {
            $j = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $map[$p.Name] = $p.Value }
        } catch { }
    }
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($map.ContainsKey($name)) {
        $map[$name].last_seen = $now
        if ($note) { $map[$name].note = $note }
    } else {
        $map[$name] = [ordered]@{ first_seen = $now; last_seen = $now; note = $note }
    }
    [IO.File]::WriteAllText($path, ($map | ConvertTo-Json -Depth 5), $Utf8)
}

function Get-SafeName([string]$s) { return ($s -replace '[^\w\.\-]', '_') }

# ---------------- 命令 ----------------
Initialize-Bus

switch ($Cmd.ToLower()) {
    "post" {
        $msg = [ordered]@{
            ts   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            from = $(if ($From) { $From } else { "unknown" })
            to   = $To
            kind = $Kind
            text = $Text
            ref  = $Ref
            id   = [guid]::NewGuid().ToString("N").Substring(0, 8)
        }
        Register-Agent $From "发布留言"
        Add-BusLine "board.jsonl" $msg
        Write-Output ("posted " + $msg.id)
    }
    "log" {
        # 51 号：动作日志停写（activity.jsonl 不再产生新行）
        Write-Output "log disabled (order 51)"
    }
    "claim" {
        # 51 号：占用机制撤除
        Write-Output "claim disabled (order 51)"
    }
    "release" {
        # 51 号：占用机制撤除
        Write-Output "release disabled (order 51)"
    }
    "claims" {
        $files = Get-ChildItem (Join-Path $BusRoot "claims") -Filter "*.json" -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                $c = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
                "{0}  {1}  ({2})" -f $c.resource, $c.owner, $c.ts
            } catch { }
        }
    }
    "board" {
        $items = Read-BusLines "board.jsonl" | Select-Object -Last $Limit
        foreach ($m in $items) {
            "[{0}] {1} → {2} ({3}) {4}" -f $m.ts, $m.from, $m.to, $m.kind, $m.text
        }
    }
    "activity" {
        $items = Read-BusLines "activity.jsonl" | Select-Object -Last $Limit
        foreach ($m in $items) { "[{0}] {1}  {2}" -f $m.ts, $m.from, $m.text }
    }
    "whoami" {
        "bus root : $BusRoot"
        "user     : $env:USERNAME"
        $path = Get-BusFile "agents.json"
        if (Test-Path $path) { Get-Content $path -Raw -Encoding UTF8 }
    }
    default { "用法: bus.ps1 post|log|claim|release|claims|board|activity|whoami" }
}