<#
.SYNOPSIS
  打包前验收：用打包出来的 exe 对真实 case 跑一遍合成/单帧命令。

.DESCRIPTION
  只验“服务能起来”会漏掉 rife/ffmpeg 这类只在特定素材上才走到的问题。这个脚本把
  真实 case 复制到工作区里的临时数据根，用打包后的 vrstudio.exe 跑：
    - patch / patchimg / fullRedraw* ：merge --case（覆盖解码、rife 补帧、合成、编码）
    - relight                        ：relight --case --sample 3（覆盖对齐、光场、单帧输出）
  跑完打印逐条结果；任何一条失败就以非零退出码结束。

  复制过的 case 与产物都留在 WorkRoot 里，便于失败后复查。

.PARAMETER App
  程序目录或 vrstudio.exe 路径；默认 <工作区根>\build\app\vrstudio.exe。

.PARAMETER DataRoot
  真实数据根（只读来源）；默认 <工作区根>\vrstudio。

.PARAMETER WorkRoot
  临时数据根；默认 <工作区根>\build\preflight。

.PARAMETER Only
  只跑这些 case。

.PARAMETER Cases
  不指定 -Only 时，最多挑几个非 relight case 与一个 relight case；默认 2 + 1。加 -Full 跑全部。

.EXAMPLE
  .\scripts\preflight-packaged.ps1 -DataRoot D:\VRAIGC-data -Cases 3
#>
[CmdletBinding()]
param(
    [string]$App,
    [string]$DataRoot,
    [string]$WorkRoot,
    [string[]]$Only = @(),
    [int]$Cases = 2,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "  ok   $Text" -ForegroundColor Green }
function Write-Bad { param([string]$Text) Write-Host "  FAIL $Text" -ForegroundColor Red }

$Root = Split-Path -Parent $PSScriptRoot
if (-not $App) { $App = Join-Path $Root 'build\app\vrstudio.exe' }
if (Test-Path $App -PathType Container) { $App = Join-Path $App 'vrstudio.exe' }
if (-not (Test-Path $App)) { Write-Bad "找不到 vrstudio.exe：$App"; exit 1 }
if (-not $DataRoot) { $DataRoot = Join-Path $Root 'vrstudio' }
if (-not (Test-Path (Join-Path $DataRoot 'cases'))) { Write-Bad "数据根没有 cases\：$DataRoot"; exit 1 }
if (-not $WorkRoot) { $WorkRoot = Join-Path $Root 'build\preflight' }

Write-Step "打包前验收：$App"
$version = & $App --version 2>&1
if ($LASTEXITCODE -ne 0) { Write-Bad "vrstudio.exe --version 失败：$version"; exit 1 }
Write-Ok "版本：$version"

$binDir = Join-Path (Split-Path -Parent $App) 'bin'
foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
    if (Test-Path (Join-Path $binDir $name)) { Write-Ok "外部二进制：$name" }
    else { Write-Bad "缺少 $binDir\$name" }
}

# 读 case.toml 的两个事实：flow 与 [source] path。
function Read-CaseMeta {
    param([string]$TomlPath)
    $text = [System.IO.File]::ReadAllText($TomlPath, [System.Text.UTF8Encoding]::new($false))
    $flow = if ($text -match '(?m)^\s*flow\s*=\s*"([^"]+)"') { $Matches[1] } else { '' }
    $source = ''
    $section = [regex]::Match($text, '(?ms)^\[source\]\s*(.*?)(^\[|\z)')
    if ($section.Success -and $section.Groups[1].Value -match '(?m)^\s*path\s*=\s*"([^"]+)"') {
        $source = $Matches[1]
    }
    return [pscustomobject]@{ Flow = $flow; Source = $source }
}

# -File 方式传参时 "a,b" 是一个字符串，这里统一拆开。
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
    Where-Object { $_ })

$all = @()
foreach ($dir in Get-ChildItem (Join-Path $DataRoot 'cases') -Directory) {
    $toml = Join-Path $dir.FullName 'case.toml'
    if (-not (Test-Path $toml)) { continue }
    $meta = Read-CaseMeta $toml
    $all += [pscustomobject]@{ Name = $dir.Name; Dir = $dir.FullName; Flow = $meta.Flow; Source = $meta.Source }
}

if ($Only.Count -gt 0) {
    $selected = $all | Where-Object { $Only -contains $_.Name }
} elseif ($Full) {
    $selected = $all
} else {
    $nonRelight = $all | Where-Object { $_.Flow -ne 'relight' } | Select-Object -First $Cases
    $relight = $all | Where-Object { $_.Flow -eq 'relight' } | Select-Object -First 1
    $selected = @($nonRelight) + @($relight)
}
if (-not $selected) {
    Write-Bad "没有可用的 case（-Only: $($Only -join ', ')）"
    Write-Host ("  可用： " + (($all | ForEach-Object { $_.Name }) -join '、'))
    exit 1
}

Write-Step "准备临时数据根：$WorkRoot"
$env:VRSTUDIO_DATA_ROOT = $WorkRoot
if (Test-Path $WorkRoot) { Remove-Item $WorkRoot -Recurse -Force }
foreach ($sub in @('cases', 'sources', 'vrgen_runs', 'logs')) {
    New-Item -ItemType Directory -Force (Join-Path $WorkRoot $sub) | Out-Null
}
$copiedSources = @{}
foreach ($case in $selected) {
    Copy-Item $case.Dir (Join-Path $WorkRoot "cases\$($case.Name)") -Recurse
    if ($case.Source) {
        $rel = $case.Source.Replace('\', '/')
        if (-not $copiedSources.ContainsKey($rel)) {
            $from = Join-Path $DataRoot $rel
            if (Test-Path $from) {
                $to = Join-Path $WorkRoot $rel
                New-Item -ItemType Directory -Force (Split-Path -Parent $to) | Out-Null
                Copy-Item $from $to -Force
                $copiedSources[$rel] = $true
            } else {
                Write-Host "  注意 源文件不存在，跳过：$from" -ForegroundColor Yellow
            }
        }
    }
}
Write-Ok "复制 $(@($selected).Count) 个 case、$($copiedSources.Count) 个源文件"

$failures = @()
foreach ($case in $selected) {
    Write-Step "试跑 $($case.Name)（$($case.Flow)）"
    $log = Join-Path $WorkRoot "$($case.Name).log"
    if ($case.Flow -eq 'relight') {
        $argv = @('relight', '--case', $case.Name, '--sample', '3')
    } elseif ($case.Flow -eq 'gen') {
        Write-Host '  gen 流程没有本地合成命令，跳过' -ForegroundColor Yellow
        continue
    } else {
        $argv = @('merge', '--case', $case.Name)
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # 原生命令写 stderr 不算脚本错误，退出码自己判
    & $App @argv 2>&1 | Out-File -FilePath $log -Encoding utf8
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -eq 0) {
        Write-Ok "$($case.Name) 通过"
    } else {
        Write-Bad "$($case.Name) 失败（退出码 $code），日志：$log"
        Get-Content $log -ErrorAction SilentlyContinue | Select-Object -Last 8 |
            ForEach-Object { Write-Host "        $_" }
        $failures += $case.Name
    }
}

Write-Step '结果'
if ($failures.Count -eq 0) {
    Write-Ok "全部通过（$($selected.Count) 个 case）；临时数据根保留在 $WorkRoot"
    exit 0
}
Write-Bad "失败 $($failures.Count) 个：$($failures -join '、')"
exit 1
