<#
.SYNOPSIS
  构建 VRAIGC 离线安装版（决策 102）。

.DESCRIPTION
  依次做五件事：构建前端产物、用 PyInstaller 打出 vrgen 与 vrstudio 两个目录式包、
  组装程序目录（含 bin/ 外部二进制与安装说明）、（可选）打包前验收、用 Inno Setup 编译安装器。

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

.PARAMETER Verify
  组装完程序目录后，用 scripts\verify-package.ps1 拿真实 case 跑一遍
  merge / relight，验收不通过就不生成安装包。默认关闭：它需要真实数据，也慢。

.PARAMETER DataRoot
  -Verify 用的真实数据根；不写时由验收脚本自己按默认位置找。

.PARAMETER VerifyCases
  -Verify 时只跑这些 case，例如 -VerifyCases walk_4k；不写则用验收脚本的默认挑选。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Version,
    [switch]$SkipFrontend,
    [switch]$SkipVrgen,
    [switch]$SkipVrstudio,
    [switch]$Portable,
    [switch]$Verify,
    [string]$DataRoot,
    [string[]]$VerifyCases = @()
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
Copy-Item (Join-Path $Root 'packaging\launchers\*.cmd') $app -Force
Write-Ok "程序目录：$app"

if ($Verify) {
    Write-Step '打包前验收（用刚组装好的 exe 跑真实 case）'
    $verifyScript = Join-Path $Root 'scripts\verify-package.ps1'
    if (-not (Test-Path $verifyScript)) { Fail "找不到验收脚本：$verifyScript" }
    $verifyArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifyScript,
                    '-App', (Join-Path $app 'vrstudio.exe'))
    if ($DataRoot) { $verifyArgs += @('-DataRoot', $DataRoot) }
    if ($VerifyCases.Count -gt 0) { $verifyArgs += @('-Only', ($VerifyCases -join ',')) }
    & powershell.exe @verifyArgs
    if ($LASTEXITCODE -ne 0) { Fail '打包前验收未通过，安装包没有生成' }
    Write-Ok '打包前验收通过'
}

Write-Step '编译安装器'
$iscc = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

function New-PortablePackage {
    param([string]$Version, [string]$AppDir, [string]$OutDir)
    $stageDir = Join-Path $build 'portable'
    if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
    New-Item -ItemType Directory -Force $stageDir | Out-Null
    Copy-Item $AppDir (Join-Path $stageDir 'VRAIGC') -Recurse -Force
    Copy-Item (Join-Path $Root 'packaging\setup-config.ps1') $stageDir -Force
    Copy-Item (Join-Path $Root 'packaging\README-install.txt') $stageDir -Force
    $zip = Join-Path $OutDir "VRAIGC-$Version-portable.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    $sevenZip = @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    Push-Location $stageDir
    try {
        if ($sevenZip) {
            & $sevenZip a -tzip -mx1 $zip 'VRAIGC' 'setup-config.ps1' 'README-install.txt' | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail '7-Zip 压缩便携版失败' }
        } else {
            Compress-Archive -Path 'VRAIGC', 'setup-config.ps1', 'README-install.txt' `
                -DestinationPath $zip -CompressionLevel Fastest
        }
    }
    finally { Pop-Location }
    Remove-Item $stageDir -Recurse -Force
    return $zip
}

if ($Portable) {
    Write-Step '打包便携版'
    $zip = New-PortablePackage -Version $Version -AppDir $app -OutDir $build
    Write-Ok "便携版：$zip"
    exit 0
}

if (-not $iscc) {
    Write-Host '  没找到 Inno Setup 6（ISCC.exe），改为产出便携版 zip。' -ForegroundColor Yellow
    $zip = New-PortablePackage -Version $Version -AppDir $app -OutDir $build
    Write-Ok "便携版：$zip"
    Write-Host @'
  对方用法：解压到任意英文路径，先运行 setup-config.ps1 写配置，
  再双击 VRAIGC\vrstudio.exe 启动。
  想产出安装器：安装 Inno Setup 6（winget install --id JRSoftware.InnoSetup -e）后重跑本脚本。
'@ -ForegroundColor Yellow
    exit 0
}
& $iscc "/DAppVersion=$Version" "/DStageDir=$app" "/DOutputDir=$build" `
    (Join-Path $Root 'packaging\vraigc.iss')
if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup 编译失败' }
Write-Ok "安装器：$build\VRAIGC-$Version-setup.exe"
