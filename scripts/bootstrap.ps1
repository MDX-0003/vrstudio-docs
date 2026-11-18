<#
.SYNOPSIS
  在新设备上搭起 vrgen + vrstudio 工作区，并还原运行时数据。

.DESCRIPTION
  以 docs 仓库的工作树为根（本脚本所在仓库），按固定布局准备两个子仓库并解包：

    <Root>\             docs 仓库（AGENTS.md、docs\、scripts\bootstrap.ps1）
      vrgen\            git clone
      vrstudio\         git clone + 运行时数据解压落点

  做四件事：检查工具链、克隆/更新两个子仓库、安装 Python 与前端依赖、解压运行时数据。
  已存在的运行时目录默认拒绝覆盖；确认要覆盖时加 -Force（先改名备份再解压）。

.PARAMETER Root
  工作区根；默认取本脚本的上一级（即 docs 仓库根）。

.PARAMETER Archive
  运行时数据压缩包；默认在 Root、scripts\ 与当前目录里找最新的 vrstudio-runtime-*.7z。

.PARAMETER RepoBase
  仓库地址前缀，默认 https://github.com/MDX-0003。

.PARAMETER Force
  运行时目录已存在且非空时，改名备份（<目录>.bak-<时间戳>）后再解压。

.PARAMETER SkipHash
  跳过压缩包的 SHA256 校验（校验要读一遍 18 GB）。

.PARAMETER SkipDeps
  跳过 uv sync 与前端构建（只还原数据，或依赖已经装好）。

.EXAMPLE
  .\scripts\bootstrap.ps1 -Archive D:\transfer\vrstudio-runtime-20261118.7z
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Archive,
    [string]$RepoBase = 'https://github.com/MDX-0003',
    [switch]$Force,
    [switch]$SkipHash,
    [switch]$SkipDeps
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Root) {
    # $PSScriptRoot 在参数默认值里并非在所有调用方式下都可用，放到脚本体里再算。
    if (-not $PSScriptRoot) { Write-Host '错误：拿不到脚本目录，请用 -Root 指定工作区根。' -ForegroundColor Red; exit 1 }
    $Root = Split-Path -Parent $PSScriptRoot
}

# 运行时数据目录：解压后必须在这些位置上
$RuntimeDirs = @('cases', 'cases_qa', 'sources', 'vrgen_runs', 'logs', 'bin')

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "  ok   $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  注意 $Text" -ForegroundColor Yellow }
function Fail { param([string]$Text) Write-Host "`n错误：$Text" -ForegroundColor Red; exit 1 }

function Find-Command {
    param([string]$Name, [string]$Hint)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail "缺少 $Name。$Hint" }
    return $cmd.Source
}

function Invoke-Native {
    param([string]$Label, [scriptblock]$Block)
    & $Block
    if ($LASTEXITCODE -ne 0) { Fail "$Label 失败（退出码 $LASTEXITCODE）" }
}

# ── 0. 参数与路径 ──────────────────────────────────────────────────────────
$Root = [System.IO.Path]::GetFullPath($Root)
if (-not (Test-Path $Root)) { Fail "Root 不存在：$Root" }
$Root = (Get-Item $Root).FullName

if (-not $Archive) {
    $found = @(
        Get-ChildItem -Path @($Root, $PSScriptRoot, (Get-Location).Path) `
            -Filter 'vrstudio-runtime-*.7z' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    )
    if ($found.Count -eq 0) {
        Fail "没找到 vrstudio-runtime-*.7z。用 -Archive 指定压缩包路径。"
    }
    $Archive = $found[0].FullName
}
if (-not (Test-Path $Archive)) { Fail "压缩包不存在：$Archive" }
$Archive = (Get-Item $Archive).FullName

Write-Host "工作区根：$Root"
Write-Host "运行时包：$Archive"

# ── 1. 工具链 ──────────────────────────────────────────────────────────────
Write-Step '检查工具链'
$git = Find-Command 'git' '安装 Git for Windows：https://git-scm.com/download/win'
Write-Ok "git     $(& $git --version)"

if (-not $SkipDeps) {
    $uv = Find-Command 'uv' '安装 uv：powershell -c "irm https://astral.sh/uv/install.ps1 | iex"'
    Write-Ok "uv      $(& $uv --version)"
    $node = Find-Command 'node' '安装 Node.js 20 LTS：https://nodejs.org/'
    $nodeVersion = (& $node --version).TrimStart('v')
    $nodeMajor = [int]($nodeVersion.Split('.')[0])
    if ($nodeMajor -lt 20) { Fail "Node.js 版本过低：$nodeVersion，需要 >= 20" }
    Write-Ok "node    $nodeVersion"
    $npm = Find-Command 'npm' '随 Node.js 一起安装'
    Write-Ok "npm     $(& $npm --version)"
}

$sevenZip = $null
foreach ($candidate in @(
        (Join-Path $Root 'tools\7z.exe'),
        (Join-Path (Split-Path -Parent $Archive) 'tools\7z.exe'),
        'C:\Program Files\7-Zip\7z.exe')) {
    if (Test-Path $candidate) { $sevenZip = $candidate; break }
}
if (-not $sevenZip) {
    $cmd = Get-Command '7z' -ErrorAction SilentlyContinue
    if ($cmd) { $sevenZip = $cmd.Source }
}
if (-not $sevenZip) {
    Fail "找不到 7z.exe：把迁移包里的 tools\ 目录一并拷过来，或安装 7-Zip。"
}
Write-Ok "7z      $sevenZip"

# ── 2. 压缩包校验 ──────────────────────────────────────────────────────────
$hashFile = "$Archive.sha256"
if (-not $SkipHash) {
    if (Test-Path $hashFile) {
        $expected = ((Get-Content $hashFile -Raw) -split '\s+')[0].Trim().ToUpper()
        Write-Step '校验压缩包 SHA256（要读一遍 18 GB，约 1-2 分钟）'
        $actual = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToUpper()
        if ($actual -ne $expected) {
            Fail "SHA256 不匹配。期望 $expected，实际 $actual。重新拷一遍压缩包。"
        }
        Write-Ok 'SHA256 匹配'
    } else {
        Write-Warn "没有 $hashFile，跳过校验"
    }
}

$drive = (Get-Item $Root).PSDrive
if ($drive -and $drive.Free) {
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    $archiveGB = (Get-Item $Archive).Length / 1GB
    # 解压后约为压缩包的 1.2 倍，再留 6 GB 给依赖与前端构建。
    $needGB = [math]::Ceiling($archiveGB * 2 + 6)
    if ($freeGB -lt $needGB) {
        Fail "工作区所在盘只剩 $freeGB GB，这个包解压加依赖约需 $needGB GB。"
    }
    Write-Ok "磁盘剩余 $freeGB GB（需要约 $needGB GB）"
}

# ── 3. 两个子仓库 ──────────────────────────────────────────────────────────
Write-Step '准备子仓库'
foreach ($name in @('vrgen', 'vrstudio')) {
    $path = Join-Path $Root $name
    if (Test-Path $path) {
        if (-not (Test-Path (Join-Path $path '.git'))) {
            Fail "$path 已存在但不是 git 仓库；挪走后重跑。"
        }
        $dirty = & $git -C $path status --porcelain
        if ($dirty) { Fail "$name 有未提交改动，先处理再重跑。" }
        & $git -C $path fetch --prune --quiet
        & $git -C $path checkout main --quiet
        Invoke-Native "更新 $name" { & $git -C $path pull --ff-only --quiet }
        Write-Ok "$name 已更新到 origin/main"
    } else {
        Invoke-Native "克隆 $name" { & $git clone --quiet "$RepoBase/$name.git" $path }
        Write-Ok "$name 已克隆"
    }
}

# ── 4. 依赖 ────────────────────────────────────────────────────────────────
if ($SkipDeps) {
    Write-Warn '已跳过 uv sync 与前端构建（-SkipDeps）'
} else {
    Write-Step '安装 Python 依赖（vrgen）'
    Push-Location (Join-Path $Root 'vrgen')
    try { Invoke-Native 'uv sync (vrgen)' { & $uv sync --extra dev } }
    finally { Pop-Location }

    Write-Step '安装 Python 依赖（vrstudio）'
    Push-Location (Join-Path $Root 'vrstudio')
    try { Invoke-Native 'uv sync (vrstudio)' { & $uv sync --extra dev --extra web } }
    finally { Pop-Location }

    Write-Step '构建前端产物'
    Push-Location (Join-Path $Root 'vrstudio\frontend')
    try {
        Invoke-Native 'npm ci' { & $npm ci }
        Invoke-Native 'npm run build' { & $npm run build }
    }
    finally { Pop-Location }
    Write-Ok '前端产物已构建（serve 直接读 dist，不需要再起 vite）'
}

# ── 5. 运行时数据 ──────────────────────────────────────────────────────────
Write-Step '还原运行时数据'
$repoPath = Join-Path $Root 'vrstudio'
$occupied = @()
foreach ($dir in $RuntimeDirs) {
    $path = Join-Path $repoPath $dir
    if (-not (Test-Path $path)) { continue }
    # 刚 clone 下来时 bin/ 里有被跟踪的 README.md，那不算占用；只有包外的额外文件才算。
    $tracked = @(& $git -C $repoPath ls-files -- $dir)
    $extra = @(Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $rel = $_.FullName.Substring($repoPath.Length + 1).Replace('\', '/')
        $tracked -notcontains $rel
    })
    if ($extra.Count -gt 0) { $occupied += $dir }
}
if ($occupied.Count -gt 0) {
    if (-not $Force) {
        Fail ("以下运行时目录已存在且非空：" + ($occupied -join '、') +
            "。确认要用迁移包覆盖就加 -Force（原目录先改名备份）。")
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($dir in $occupied) {
        $path = Join-Path $Root "vrstudio\$dir"
        $backup = "$path.bak-$stamp"
        Move-Item $path $backup
        Write-Warn "$dir 已备份为 $(Split-Path -Leaf $backup)"
    }
}

Invoke-Native '解压运行时数据' { & $sevenZip x $Archive "-o$Root" -y -bso0 -bsp0 }

$caseCount = @(Get-ChildItem (Join-Path $Root 'vrstudio\cases') -Filter 'case.toml' -Recurse -File).Count
if ($caseCount -lt 1) { Fail "解压后 vrstudio\cases 下没有任何 case.toml，包可能是错的。" }
Write-Ok "cases：$caseCount 个 case.toml"
foreach ($dir in $RuntimeDirs) {
    $path = Join-Path $Root "vrstudio\$dir"
    if (-not (Test-Path $path)) { continue }      # 精简包可以不带 cases_qa 等目录
    $count = @(Get-ChildItem $path -Recurse -File -Force).Count
    Write-Ok ("{0,-10} {1,5} 个文件" -f $dir, $count)
}

# ── 6. 本机配置 ────────────────────────────────────────────────────────────
Write-Step '生成本地配置'
$vrgenExe = Join-Path $Root 'vrgen\.venv\Scripts\vrgen.exe'
$tomlPath = Join-Path $Root 'vrstudio\vrstudio.toml'
if (-not (Test-Path $vrgenExe)) {
    Write-Warn "找不到 $vrgenExe（-SkipDeps 时正常），vrstudio.toml 未生成"
} elseif (Test-Path $tomlPath) {
    Write-Ok 'vrstudio.toml 已存在，保持不动'
} else {
    $line = "[generate]`nvrgen = `"$($vrgenExe.Replace('\', '/'))`"`n"
    [System.IO.File]::WriteAllText($tomlPath, $line, (New-Object System.Text.UTF8Encoding($true)))
    Write-Ok "已写入 vrstudio.toml（generate.vrgen = $vrgenExe）"
}

# ── 7. mglc ────────────────────────────────────────────────────────────────
Write-Step '检查生成工具 mglc'
$mglcCmd = Get-Command 'mglc' -ErrorAction SilentlyContinue
if ($mglcCmd) {
    Write-Ok "mglc 已在 PATH：$($mglcCmd.Source)"
} else {
    $bundled = @(
        (Join-Path (Split-Path -Parent $Archive) 'tools\mglc.exe'),
        (Join-Path $Root 'tools\mglc.exe'),
        (Join-Path $PSScriptRoot 'tools\mglc.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $bundled) {
        Fail '未找到 mglc：把迁移包旁的 tools\mglc.exe 拷过来，或手动安装后重跑。'
    }
    $dest = Join-Path $env:LOCALAPPDATA 'Programs\mglc\bin'
    New-Item -ItemType Directory -Force $dest | Out-Null
    $mglcPath = Join-Path $dest 'mglc.exe'
    Copy-Item $bundled $mglcPath -Force
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$dest*") {
        [Environment]::SetEnvironmentVariable('PATH', "$userPath;$dest", 'User')
        $env:PATH = "$env:PATH;$dest"
    }
    [Environment]::SetEnvironmentVariable('VRGEN_MGLC_BIN', $mglcPath, 'User')
    $env:VRGEN_MGLC_BIN = $mglcPath
    Write-Ok "mglc 已安装到 $dest（用户 PATH 与 VRGEN_MGLC_BIN 已写入）"
}

$loginDir = Join-Path $HOME '.mglc'
if (-not (Test-Path (Join-Path $loginDir 'config.yaml'))) {
    Write-Warn 'mglc 还没有登录态：稍后执行 mglc login --access-key <AK> --secret-key <SK>'
}

# ── 8. 自检 ────────────────────────────────────────────────────────────────
if (-not $SkipDeps -and (Test-Path $vrgenExe)) {
    Write-Step '自检'
    & $vrgenExe --help | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'vrgen CLI 可执行' } else { Write-Warn 'vrgen --help 返回非 0' }
    Push-Location (Join-Path $Root 'vrstudio')
    try {
        $migrate = & $uv run python scripts/migrate_source_paths.py 2>&1
        $migrate | ForEach-Object { "     $_" }
        if ($LASTEXITCODE -eq 0) { Write-Ok 'case 源路径全部是仓库根相对写法' }
        else { Write-Warn '有 case 的源路径需要人工处理（见上面列出的条目）' }
    }
    finally { Pop-Location }
}

# ── 9. 后续人工步骤 ────────────────────────────────────────────────────────
Write-Host @"

工作区已就绪：$Root
下一步（手动）：
  1) mglc login --access-key <AK> --secret-key <SK>      # 本机首次运行需要
  2) cd "$Root\vrstudio"; uv run vrstudio serve --host 0.0.0.0 --port 8760
  3) 局域网访问放行端口：
     New-NetFirewallRule -DisplayName 'vrstudio 8760' -Direction Inbound -Protocol TCP -LocalPort 8760 -Action Allow

注意：web 控制台没有登录认证（只有昵称 cookie），--host 0.0.0.0 等于同网段谁都能操作 case 与额度。
     只在可信网络里这样开；否则保持 127.0.0.1。
"@
