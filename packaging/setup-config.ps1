<#
.SYNOPSIS
  便携版的首次配置：写本机配置、准备数据目录、检查 mglc。

.DESCRIPTION
  便携版（zip 解压，没有安装器）用这个脚本完成安装器本来会做的三件事：
  1. 在 %APPDATA%\vrstudio\default.toml 写入数据根、vrgen 与 bin 的绝对路径；
  2. 建好数据目录下的 cases / sources / vrgen_runs / logs；
  3. 检查 mglc 是否可用，并打印带 AK/SK 占位符的登录命令。

  数据目录默认 D:\VRAIGC-data（没有 D 盘时用 %LOCALAPPDATA%\VRAIGC\data），
  也可以在命令行用 -DataRoot 指定，或运行后按提示输入。

.EXAMPLE
  .\setup-config.ps1
  .\setup-config.ps1 -AppDir D:\Apps\VRAIGC -DataRoot E:\VRAIGC-data
#>
[CmdletBinding()]
param(
    [string]$AppDir,
    [string]$DataRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "  ok   $Text" -ForegroundColor Green }
function Fail { param([string]$Text) Write-Host "`n错误：$Text" -ForegroundColor Red; exit 1 }

# 脚本可能在 VRAIGC 目录里，也可能和 VRAIGC 并排；两种都认。
if (-not $AppDir) {
    $sibling = Join-Path $PSScriptRoot 'VRAIGC'
    if (Test-Path (Join-Path $sibling 'vrstudio.exe')) { $AppDir = $sibling }
    elseif (Test-Path (Join-Path $PSScriptRoot 'vrstudio.exe')) { $AppDir = $PSScriptRoot }
    else { Fail "找不到 vrstudio.exe：用 -AppDir 指定程序目录。" }
}
$AppDir = (Get-Item $AppDir).FullName
$exe = Join-Path $AppDir 'vrstudio.exe'
$vrgen = Join-Path $AppDir 'vrgen\vrgen.exe'
$binDir = Join-Path $AppDir 'bin'
foreach ($path in @($exe, $vrgen)) {
    if (-not (Test-Path $path)) { Fail "程序目录不完整，缺少 $path" }
}
if (-not (Test-Path (Join-Path $binDir 'ffmpeg.exe'))) {
    Write-Host '  注意 没有找到 bin\ffmpeg.exe，视频流程会失败' -ForegroundColor Yellow
}

if (-not $DataRoot) {
    if (Test-Path 'D:\') { $DataRoot = 'D:\VRAIGC-data' }
    else { $DataRoot = Join-Path $env:LOCALAPPDATA 'VRAIGC\data' }
    Write-Host "数据目录（存放 cases/sources/vrgen_runs/logs）："
    $answer = Read-Host "  直接回车用默认 [$DataRoot]，或输入其它路径"
    if ($answer.Trim()) { $DataRoot = $answer.Trim() }
}
$DataRoot = [System.IO.Path]::GetFullPath($DataRoot)
New-Item -ItemType Directory -Force $DataRoot | Out-Null
foreach ($name in @('cases', 'sources', 'vrgen_runs', 'logs')) {
    New-Item -ItemType Directory -Force (Join-Path $DataRoot $name) | Out-Null
}
Write-Ok "数据目录：$DataRoot"

function ConvertTo-TomlString {
    param([string]$Value)
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

$configDir = Join-Path $env:APPDATA 'vrstudio'
$configPath = Join-Path $configDir 'default.toml'
if ((Test-Path $configPath) -and -not $Force) {
    Write-Host "`n本机配置已存在：$configPath" -ForegroundColor Yellow
    Write-Host "  要改成新的程序目录或数据目录，加 -Force 重跑（会覆盖）。" -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Force $configDir | Out-Null
    $lines = @(
        '# 由 setup-config.ps1 写入：数据根与两个可执行文件位置（决策 102）',
        '[paths]',
        ('data_root = "' + (ConvertTo-TomlString $DataRoot) + '"'),
        '',
        '[generate]',
        ('vrgen = "' + (ConvertTo-TomlString $vrgen) + '"'),
        '',
        '[bin]',
        ('dir = "' + (ConvertTo-TomlString $binDir) + '"')
    )
    # 不带 BOM：tomllib 会拒绝 BOM；配置加载层虽已兼容 utf-8-sig，这里仍保持干净。
    [System.IO.File]::WriteAllText($configPath, ($lines -join "`r`n") + "`r`n",
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "已写本机配置：$configPath"
}

Write-Step '检查生成工具 mglc'
$mglcLocal = Join-Path $env:LOCALAPPDATA 'Programs\mglc\bin\mglc.exe'
$onPath = Get-Command 'mglc' -ErrorAction SilentlyContinue
if ($onPath) {
    Write-Ok "mglc 在 PATH：$($onPath.Source)"
} elseif (Test-Path $mglcLocal) {
    Write-Ok "mglc 已安装：$mglcLocal（如果没进 PATH，vrstudio 仍会通过 VRGEN_MGLC_BIN 找到它）"
} else {
    Write-Host @'

  未检测到 mglc。生成功能需要它：
    1) 向管理员索取 mglc 的 Windows 版本（mglc-windows-amd64.zip）；
    2) 解压到 %LOCALAPPDATA%\Programs\mglc\bin，确认其中有 mglc.exe；
    3) 新开一个终端执行：
         mglc login --access-key <AK> --secret-key <SK>
       AK/SK 向平台管理员申请；登录态写在 %USERPROFILE%\.mglc\config.yaml。
    4) 验证：mglc virtual-ip list
'@ -ForegroundColor Yellow
}

# 便携版没有开始菜单，写两个双击入口；参数与安装版的快捷方式一致。
$shellDir = Split-Path -Parent $AppDir
$localCmd = "@echo off`r`nchcp 65001 >nul`r`n`"$exe`"`r`npause`r`n"
$lanCmd = "@echo off`r`nchcp 65001 >nul`r`n`"$exe`" --lan`r`npause`r`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $shellDir '启动-本机.cmd'), $localCmd, $utf8)
[System.IO.File]::WriteAllText((Join-Path $shellDir '启动-局域网.cmd'), $lanCmd, $utf8)
Write-Ok "已生成启动入口：$shellDir\启动-本机.cmd、启动-局域网.cmd"

Write-Host @"

配置完成。启动方式（两种模式）：
  本机：    "$exe"
  局域网：  "$exe" --lan
           控制台会打印本机局域网地址；其它机器用它访问，并放行端口：
           New-NetFirewallRule -DisplayName 'VRAIGC 8760' -Direction Inbound -Protocol TCP -LocalPort 8760 -Action Allow

也可以直接双击上面生成的 启动-本机.cmd 或 启动-局域网.cmd。
"@
