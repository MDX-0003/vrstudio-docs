<#
.SYNOPSIS
  构建 VRAIGC 离线安装版（决策 102）。

.DESCRIPTION
  依次做四件事：构建前端产物、用 PyInstaller 打出 vrgen 与 vrstudio 两个目录式包、
  组装程序目录（含 bin/ 外部二进制与安装说明）、用 Inno Setup 编译安装器。

  产物：
    <根>\build\app\                    程序目录（可先手动试运行）
    <根>\build\VRAIGC-<版本>-setup.exe 安装器（需要 Inno Setup 6）

  本机需要：uv、Node 20+、npm、Inno Setup 6（默认装在 Program Files (x86)）。
  不打包 mglc；安装器只做检测与提示。

.PARAMETER Root
  工作区根；默认取本脚本的上一级。

.PARAMETER Version
  版本号；默认读 vrstudio.__version__。

.PARAMETER SkipFrontend
  跳过 npm ci 与 npm run build（前端产物已经是最新的）。

.PARAMETER SkipVrgen
  跳过 vrgen 的 PyInstaller 构建（已有 dist\vrgen）。

.PARAMETER SkipVrstudio
  跳过 vrstudio 的 PyInstaller 构建（已有 dist\vrstudio）。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Version,
    [switch]$SkipFrontend,
    [switch]$SkipVrgen,
    [switch]$SkipVrstudio
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
    if (-not $PSScriptRoot) { Write-Host '错误：拿不到脚本目录，请用 -Root 指定工作区根。' -ForegroundColor Red; exit 1 }
    $Root = Split-Path -Parent $PSScriptRoot
}

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "  ok   $Text" -ForegroundColor Green }
function Fail { param([string]$Text) Write-Host "`n错误：$Text" -ForegroundColor Red; exit 1 }

$Root = (Get-Item ([System.IO.Path]::GetFullPath($Root))).FullName
$vrgen = Join-Path $Root 'vrgen'
$vrstudio = Join-Path $Root 'vrstudio'
foreach ($path in @($vrgen, $vrstudio)) {
    if (-not (Test-Path $path)) { Fail "找不到子仓库：$path" }
}

$build = Join-Path $Root 'build'
$dist = Join-Path $build 'dist'
$app = Join-Path $build 'app'
New-Item -ItemType Directory -Force $build, $dist | Out-Null

if (-not $Version) {
    Push-Location $vrstudio
    try { $Version = (& uv run python -c "import vrstudio; print(vrstudio.__version__)").Trim() }
    finally { Pop-Location }
}
if (-not $Version) { Fail '取版本号失败；用 -Version 指定' }
Write-Step "构建 VRAIGC $Version"

if (-not $SkipFrontend) {
    Write-Step '构建前端产物'
    Push-Location (Join-Path $vrstudio 'frontend')
    try {
        & npm ci
        if ($LASTEXITCODE -ne 0) { Fail 'npm ci 失败' }
        & npm run build
        if ($LASTEXITCODE -ne 0) { Fail 'npm run build 失败' }
    }
    finally { Pop-Location }
    Write-Ok '前端产物已更新'
} else {
    Write-Host '  已跳过前端构建（-SkipFrontend）'
}

function Invoke-PyInstaller {
    param([string]$Repo, [string]$Spec, [string]$Label)
    Write-Step "打包 $Label"
    Push-Location $Repo
    try {
        & uv run --with pyinstaller pyinstaller --noconfirm --clean `
            --distpath $dist --workpath (Join-Path $build 'work') $Spec
        if ($LASTEXITCODE -ne 0) { Fail "$Label 打包失败" }
    }
    finally { Pop-Location }
    Write-Ok "$Label 已打包"
}

if (-not $SkipVrgen) {
    Invoke-PyInstaller $vrgen (Join-Path $vrgen 'packaging\vrgen.spec') 'vrgen'
}
if (-not $SkipVrstudio) {
    Invoke-PyInstaller $vrstudio (Join-Path $vrstudio 'packaging\vrstudio.spec') 'vrstudio'
}

Write-Step '组装程序目录'
if (Test-Path $app) { Remove-Item $app -Recurse -Force }
New-Item -ItemType Directory -Force $app | Out-Null

Copy-Item (Join-Path $dist 'vrstudio\*') $app -Recurse -Force
$exe = Join-Path $app 'vrstudio.exe'
if (-not (Test-Path $exe)) { Fail "dist\vrstudio 里没有 vrstudio.exe" }
# 试运行过的 dist 可能带出数据目录与本机配置，它们不属于安装包。
foreach ($name in @('cases', 'sources', 'logs', 'vrgen_runs', 'vrstudio.toml')) {
    $stray = Join-Path $app $name
    if (Test-Path $stray) { Remove-Item $stray -Recurse -Force }
}
New-Item -ItemType Directory -Force (Join-Path $app 'vrgen') | Out-Null
Copy-Item (Join-Path $dist 'vrgen\*') (Join-Path $app 'vrgen') -Recurse -Force
if (-not (Test-Path (Join-Path $app 'vrgen\vrgen.exe'))) { Fail 'dist\vrgen 里没有 vrgen.exe' }

New-Item -ItemType Directory -Force (Join-Path $app 'bin') | Out-Null
foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
    $src = Join-Path $vrstudio "bin\$name"
    if (-not (Test-Path $src)) { Fail "缺少 $src（外部二进制不进 git，需要本机已有）" }
    Copy-Item $src (Join-Path $app 'bin') -Force
}
$rife = Get-ChildItem (Join-Path $vrstudio 'bin') -Directory -Filter 'rife-ncnn-vulkan*' |
    Select-Object -First 1
if ($rife) {
    Copy-Item $rife.FullName (Join-Path $app 'bin') -Recurse -Force
} else {
    Write-Host '  注意 没找到 rife 目录，补帧功能将不可用' -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force (Join-Path $app 'tools') | Out-Null
@'
mglc 不随安装包分发（决策 102）。
把 mglc.exe 放到本目录，或放到 %LOCALAPPDATA%\Programs\mglc\bin 并加入用户 PATH。
登录：mglc login --access-key <AK> --secret-key <SK>
说明见安装目录下的 README-install.txt。
'@ | Set-Content -Encoding utf8 (Join-Path $app 'tools\README-mglc.txt')

Copy-Item (Join-Path $Root 'packaging\README-install.txt') (Join-Path $app 'README-install.txt') -Force
Write-Ok "程序目录：$app"

Write-Step '编译安装器'
$iscc = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    Write-Host '  没找到 Inno Setup 6（ISCC.exe）。' -ForegroundColor Yellow
    Write-Host "  程序目录已就绪，可直接试运行：$app\vrstudio.exe" -ForegroundColor Yellow
    Write-Host '  安装 Inno Setup 6 后重跑本脚本即可产出安装器。' -ForegroundColor Yellow
    exit 1
}
& $iscc "/DAppVersion=$Version" "/DStageDir=$app" "/DOutputDir=$build" `
    (Join-Path $Root 'packaging\vraigc.iss')
if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup 编译失败' }
Write-Ok "安装器：$build\VRAIGC-$Version-setup.exe"
