# 新 host 设备部署手册（Windows）

本手册把一台干净的 Windows 设备变成 vrgen + vrstudio 的 host：三个仓库到位、Python 与前端依赖装好、
运行时数据还原、控制台能启动并验收。前提有两个——外部设备上带着完整的 `VRAIGC-transfer` 目录，
以及能访问 `https://github.com/MDX-0003/vrstudio-docs`；mglc 的 AK/SK 需要你另外准备。

## 1. 开始之前的材料与约束

### 1.1 需要准备的东西

- `VRAIGC-transfer` 整个目录（含两个压缩包、`tools\`、`MANIFEST*.txt`）。
- GitHub 可读权限：`vrstudio-docs`、`vrgen`、`vrstudio` 三个仓库。三者都是公开仓库时不需要登录凭据。
- mglc 的 AK/SK：新机器没有 `~/.mglc`，必须重新登录一次。
- Windows 10/11 x64。系统自带的 Windows PowerShell 5.1 就够，不要求 PowerShell 7。
- 磁盘空间：精简包约需 16 GB，全量包约需 42 GB（脚本按包大小自动算并提前拦下不够的情况）。
- 能访问 github.com 与 PyPI。本机实测访问 GitHub 会间歇性 `Recv failure: Connection was reset`，
  重试即可，不是配置错误。

### 1.2 根目录怎么选

根目录就是 docs 仓库的工作树，另外两个仓库是它的子目录。选目录时守三条：

- 用短英文路径，例如 `D:\VRAIGC`，不要放在中文目录、含空格的目录或 `Program Files` 下。
- 不要放在 OneDrive 等同步目录里：`cases/`、`sources/` 有几十 GB，同步会拖垮机器也会反复改动文件时间。
- 盘符确定后不要再改。case 里的路径虽然已经是仓库根相对写法，但 `vrstudio.toml` 里记的是绝对路径。

### 1.3 两个压缩包的区别

- `vrstudio-runtime-20261118.7z`（17.78 GiB）：52 个 case 的全量包，含所有历史成片与 relight 小样。
- `vrstudio-runtime-20261118-slim10.7z`（4.51 GiB）：最近 10 天用过的 28 个 case，去掉了小样、页面缓存、
  旧抽取版本和未被引用的源文件。

两个包的内部布局完全一致，`bootstrap.ps1` 用哪个都行。日常继续干活选精简包；要翻旧 case 选全量包。
只缺个别旧 case 时，从全量包里单独解出该 case 目录即可，做法见 §7.1。

## 2. 安装工具链

按 Git → uv → Node 的顺序装，每一步都用给出的命令验证，验证不过不要往下走。

### 2.1 Git for Windows

```powershell
winget install --id Git.Git -e --source winget
git --version
```

`git --version` 打印出版本号才算成功。没有 winget 时从 https://git-scm.com/download/win 下载安装包。

### 2.2 uv（Python 环境与 Python 3.11）

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uv --version
```

不需要自己安装 Python：两个仓库的 `.python-version` 都写着 `3.11`，`uv sync` 会自己下载对应解释器。

### 2.3 Node.js 20 LTS

```powershell
winget install --id OpenJS.NodeJS.LTS -e --source winget
node -v
npm -v
```

`node -v` 必须 ≥ `v20`。前端构建脚本 `npm run build` 会先跑 `vue-tsc`，Node 版本太低会在这一步报错。

### 2.4 7-Zip 与 mglc 不需要单独装

`VRAIGC-transfer\tools\` 里带着 `7z.exe`、`7z.dll` 和 `mglc.exe`。`bootstrap.ps1` 会优先用包旁边的 7z，
并在 PATH 里找不到 mglc 时把 `mglc.exe` 装到 `%LOCALAPPDATA%\Programs\mglc\bin`，同时写入用户 PATH
和 `VRGEN_MGLC_BIN` 环境变量（vrgen 的 `mglc_bin` 留空时靠这两个值找可执行文件）。

## 3. 建立工作区

1. 打开一个新的 PowerShell 窗口（普通用户权限即可，安装 mglc 只写用户级环境变量）。
2. 克隆 docs 仓库到根目录：

   ```powershell
   git clone https://github.com/MDX-0003/vrstudio-docs.git D:\VRAIGC
   ```

3. 确认根目录里出现 `AGENTS.md`、`docs\`、`scripts\`；此时还没有 `vrgen\` 与 `vrstudio\`，这是正常的。
4. 把 `VRAIGC-transfer` 拷到本机，例如 `D:\transfer`。直接从 U 盘解压也能跑，只是读盘慢很多。

## 4. 运行 bootstrap.ps1

### 4.1 命令

```powershell
cd D:\VRAIGC
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 `
  -Archive D:\transfer\vrstudio-runtime-20261118-slim10.7z
```

`-ExecutionPolicy Bypass` 不能省：Windows 默认执行策略会拦住未签名脚本，这是本机实测拦过的坑。

### 4.2 参数

- `-Root`：工作区根，默认取脚本的上一级，也就是 `D:\VRAIGC`。
- `-Archive`：压缩包路径。省略时脚本在根目录、`scripts\`、当前目录里找最新的 `vrstudio-runtime-*.7z`。
- `-Force`：运行时目录已存在且非空时，先改名成 `<目录>.bak-<时间戳>` 再解压。默认不加就是拒绝覆盖。
- `-SkipHash`：跳过 SHA256 校验（校验要读完整个包）。
- `-SkipDeps`：跳过 `uv sync` 与前端构建，只还原数据。

### 4.3 脚本依次做什么

1. 解析根目录与压缩包路径，打印两者。
2. 检查 git；没加 `-SkipDeps` 时继续检查 uv、node（≥ 20）、npm；找到 7z。
3. 校验压缩包的 SHA256（有同名 `.sha256` 文件时）。
4. 按压缩包大小估算所需空间并检查磁盘。
5. 克隆或更新 `vrgen`、`vrstudio`。已存在时先看工作树是否干净，有未提交改动直接停下。
6. `uv sync --extra dev`（vrgen）、`uv sync --extra dev --extra web`（vrstudio），
   然后在 `vrstudio\frontend` 跑 `npm ci` 与 `npm run build`。
7. 检查六个运行时目录是否被占用；通过后解压。解压完统计 case 数与各目录文件数。
8. 生成 `vrstudio\vrstudio.toml`，写入 `[generate] vrgen = "<根>/vrgen/.venv/Scripts/vrgen.exe"`。
   文件已存在时不覆盖。
9. PATH 里没有 mglc 时安装它；`~/.mglc/config.yaml` 不存在时提示去登录。
10. 跑两项目检：`vrgen.exe --help` 可执行、`scripts/migrate_source_paths.py` 报告 0 个待处理
    （全量包里 `relight_space_atmo_01` 的源文件早已丢失，会报 1 个，属已知情况，不影响其它 case）。

正常结束时最后会打印下一步命令。中途失败会以 `错误：…` 结束并返回退出码 1，
最后出现的 `==> 阶段名` 就是失败位置，对照 §8 的清单定位。

### 4.4 需要人工确认一次的校验

打开 `D:\transfer\vrstudio-runtime-20261118-slim10.7z.sha256`，内容应与下面一致
（脚本会自己比，手工核一次是为了排除包在拷贝中损坏）：

```
94FAC4846B5566469D73166957C961C67D2BAE5A3F85436642E1ACC70DB64642  vrstudio-runtime-20261118-slim10.7z
```

全量包的校验值写在 `vrstudio-runtime-20261118.7z.sha256` 与 `MANIFEST.txt` 里。

## 5. 登录与首次启动

### 5.1 登录 mglc

装完 mglc 后必须先开一个新终端，让新的 PATH 生效，然后执行：

```powershell
mglc login --access-key <AK> --secret-key <SK>
mglc virtual-ip list
```

`mglc virtual-ip list` 是只读诊断命令，能返回列表说明登录态可用、也不会消耗额度。

### 5.2 前台启动控制台

```powershell
cd D:\VRAIGC\vrstudio
uv run vrstudio serve --host 0.0.0.0 --port 8760
```

启动成功时打印三行：`vrstudio serve: http://0.0.0.0:8760/`、`sources/` 与 `cases/` 的实际路径、
日志目录。没有这三行就是没起来，往上翻报错。

### 5.3 后台常驻（可选）

登录后需要长期运行时，用任务计划程序拉起，避免关掉终端就停：

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -WindowStyle Hidden -Command "cd D:\VRAIGC\vrstudio; uv run vrstudio serve --host 0.0.0.0 --port 8760"'
Register-ScheduledTask -TaskName "vrstudio-serve" -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn) -RunLevel Limited
```

### 5.4 验收清单

按顺序做，任何一项不过先停在那一项排查。

1. 浏览器打开 `http://127.0.0.1:8760/`，case 列表显示 28 个（精简包）或 52 个（全量包）。
2. 打开一个 patch case，顶部源片能播放。首次播放要生成 4K 代理，等 1 分钟左右属于正常。
3. 零额度联调：在 `vrstudio` 目录执行
   `uv run vrstudio generate submit --case <case名> --check`。它实际执行 `vrgen submit --dry-run`，
   校验素材与提示词但不提交、不花额度。能打印出装配结果说明跨仓库调用链通了。
4. 打开一个 case 的对比页，左右两路视频都能播放。
5. 任务中心能列出历史任务；重启服务后只会回填最近有日志的已完成任务，队列本身在内存里。
6. 检查 `D:\VRAIGC\vrstudio\logs\serve\service-<今天>.jsonl` 里没有 `traceback`。

### 5.5 局域网访问

- 服务用 `--host 0.0.0.0` 才监听所有网卡，默认只监听 `127.0.0.1`。
- 放行端口：
  `New-NetFirewallRule -DisplayName 'vrstudio 8760' -Direction Inbound -Protocol TCP -LocalPort 8760 -Action Allow`
- 控制台没有登录认证，只有昵称 cookie。`0.0.0.0` 意味着同网段任何人都能打开页面、操作 case 与消耗额度，
  只在可信网络里这样开。

## 6. 日常使用需要知道的位置

- case 与素材：`<根>\vrstudio\cases\`、`<根>\vrstudio\sources\`。
- vrgen 台账：`<根>\vrstudio\vrgen_runs\<case名>\<轮次>\`，内含 `run.json`、`command.txt`、`mglc.log`。
- 服务日志：`<根>\vrstudio\logs\serve\service-YYYYMMDD.jsonl`、`client-YYYYMMDD.jsonl`；
  任务日志：`<根>\vrstudio\logs\tasks\YYYYMMDD\`。
- 本机配置：`<根>\vrstudio\vrstudio.toml`（`[generate] vrgen` 指向 vrgen 的 exe），不进 git。
- 前端产物：`<根>\vrstudio\src\vrstudio\web\static\next\`，由 `npm run build` 生成，不进 git。

## 7. 追加与重建

### 7.1 只补一个旧 case

从全量包里单独解出该 case 与它的台账，注意 7z 里的路径分隔符是反斜杠：

```powershell
D:\transfer\tools\7z.exe x D:\transfer\vrstudio-runtime-20261118.7z -oD:\VRAIGC `
  "vrstudio\cases\<case名>\*" "vrstudio\vrgen_runs\<case名>\*"
```

解完刷新页面即可看到该 case。它引用的源文件如果没在精简包里，需要从全量包的 `vrstudio\sources\`
里补同名文件，否则打开该 case 会报源文件不存在。

### 7.2 重新切一个迁移包

在旧 host（数据还在的那台）上，用 `VRAIGC-transfer\make_pack.py`：

```powershell
python D:\transfer\make_pack.py --days 7 --out D:\transfer\vrstudio-runtime-20261118-slim7.7z
```

`--days 0` 表示全部 case。脚本按“文件系统最后修改时间”选 case，依次裁掉 `derived/`、`out/samples/`、
非当前版本的 `extracts/`、未被引用的 `sources/`、`cases_qa/` 与 `.web-lock.json`。

## 8. 踩坑清单

按现象查，每条给出原因与处理。这些是在本机实际踩到或按代码确认过的。

### 8.1 工具链与脚本

- **报“无法加载文件 … 未对文件 … 进行数字签名”**：Windows 默认执行策略拦住了脚本。
  用 `powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 …` 启动，不要为此改全局策略。
- **报“文件来自其他计算机，可能被阻止”**：从网盘或 U 盘拷来的文件带了网络标记。
  执行 `Unblock-File D:\VRAIGC\scripts\bootstrap.ps1` 再去运行。
- **报 `Unexpected token` 且报错里的中文是乱码**：脚本被存成了不带 BOM 的 UTF-8，Windows PowerShell 5.1
  按 ANSI 解码中文串，字符串被截断。用 PowerShell 7 或 `Set-Content -Encoding utf8` 重新保存，
  仓库里的脚本本身是带 BOM 的，正常 clone 不会出这个问题。
- **`uv : 无法将“uv”项识别为 cmdlet…`**：装完 uv 没有刷新 PATH。关掉终端重开；仍不行就确认
  `%USERPROFILE%\.local\bin` 在 PATH 里。
- **`uv sync` 卡住或超时**：PyPI 访问不稳。配代理或镜像（`UV_DEFAULT_INDEX`）后重跑，
  已下载的部分会复用，不用清理缓存。
- **`uv sync` 报下载 Python 3.11 失败**：单独执行 `uv python install 3.11` 重试，成功后再跑 `uv sync`。
- **`npm ci` 报 `EBADENGINE` 或 lockfile 版本不匹配**：Node 版本不对（低于 20）。
  升到 20 LTS 后重跑；不要用 `npm install` 绕过，那会改掉 `package-lock.json`。
- **`ffmpeg` 相关报错，`vrstudio\bin\ffmpeg.exe` 不见了**：杀毒软件把它隔离了。
  从迁移包的 `vrstudio\bin\` 里解出 `ffmpeg.exe` 与 `ffprobe.exe`，并把该目录加入白名单。
- **patch 的补帧报 Vulkan 相关错误**：`rife-ncnn-vulkan` 需要可用的 Vulkan 驱动。
  没有独立显卡或驱动过旧时补帧不可用，其余流程不受影响，换用不补帧的路径即可。
- **`找不到 7z.exe`**：把 `VRAIGC-transfer\tools\` 整个拷到压缩包旁边或工作区根目录。
  脚本按“包旁边的 tools → 根目录的 tools → 程序文件里的 7-Zip”顺序查找。
- **mglc 装完当前窗口仍然找不到**：PATH 写的是用户级环境变量，只对新开的进程生效，重开终端。

### 8.2 路径与数据

- **`以下运行时目录已存在且非空：…`**：目标里已经有数据，脚本按约定拒绝覆盖。
  确认要用新包覆盖就加 `-Force`，脚本会把旧目录改名成 `<目录>.bak-<时间戳>`，不会删除。
- **`工作区所在盘只剩 X GB，这个包解压加依赖约需 Y GB`**：换盘或清理空间。
  精简包约需 16 GB，全量包约需 42 GB；脚本的需求值按压缩包大小的 2 倍加 6 GB 估算。
- **解压到一半报路径过长**：Windows 默认 260 字符限制。把根目录换短（如 `D:\VRAIGC`），
  或开启系统长路径支持后重跑，已经解出的部分保留。
- **打开旧 case 报“源文件不在了”**：`case.toml` 里记的是旧机器的绝对路径。
  在 `vrstudio` 目录执行 `uv run python scripts/migrate_source_paths.py` 看清单，
  确认后加 `--apply` 改写成仓库根相对路径。本次两个迁移包在打包前已经改好，正常不会遇到。
- **想把 `cases/` 或 `sources/` 放到别的盘**：现在没有这个开关。`serve --cases-dir` 只改 cases 根，
  `sources/`、`logs/`、`bin/` 都按仓库根拼路径，挪出去需要改代码，不要尝试。
- **`vrgen` 或 `vrstudio` 有未提交改动**：脚本会直接停下，因为它要先 `pull --ff-only`。
  在那台机器上先把改动提交或还原，再重跑。

### 8.3 服务与网络

- **启动时报端口被占用**：`portguard` 只会结束属于本项目（同一 venv）的旧实例，
  控制台会打印接管了哪个进程。若占用者是别的程序，换 `--port` 或先结束它，
  用 `Get-NetTCPConnection -LocalPort 8760` 看是谁。
- **局域网其它机器打不开**：依次确认三件事——启动参数是 `--host 0.0.0.0`、防火墙放行了 8760、
  访问的是本机局域网 IP 而不是 `127.0.0.1`。
- **页面打开是空白**：前端产物没构建。在 `vrstudio\frontend` 跑 `npm ci && npm run build`；
  用 `-SkipDeps` 还原过数据时最容易缺这一步。产物在 `src\vrstudio\web\static\next\`。
- **控制台里中文变乱码**：Windows 控制台默认 GBK。先执行 `chcp 65001` 再跑命令；
  Python 侧对 vrgen 子进程已经固定注入 `PYTHONUTF8`，服务内部的中文不受影响。
- **任务中心历史是空的**：队列在内存里，重启后只从 `logs/tasks/history.jsonl` 回填最近的、
  有日志文件的已完成任务，正在排队的任务不会恢复。
- **提示保存冲突、case 被别人修改**：同一 case 多窗口或多台机器同时改会触发 revision 冲突。
  新 host 上线后，旧机器不要继续开着同一个工作区的服务写数据。

### 8.4 安全

- **任何人都能打开控制台**：没有账号体系，只有昵称 cookie。对局域网开放时用防火墙限定来源，
  或只在 `127.0.0.1` 上通过远程桌面访问。

## 9. 出问题时的排查顺序

1. 看 `bootstrap.ps1` 最后一条 `==> 阶段名`，对照 §8 处理。
2. 手工复现失败的那一步：`git --version`、`uv --version`、`node -v`、`uv run vrstudio --version`、
   `mglc --help`。
3. 服务起不来时看控制台第一段 traceback 与 `logs\serve\service-<今天>.jsonl`。
4. 端口与进程：`Get-NetTCPConnection -LocalPort 8760 | Select-Object OwningProcess`，
   再 `Get-Process -Id <pid>` 确认是不是本项目的 Python。
5. 数据看起来不对时先确认 `cases/<名字>/case.toml` 存在、`sources/` 里源文件在、
   `vrgen_runs/<名字>/` 有轮次目录，这三样齐了再怀疑代码。

## 10. 常用命令

```powershell
# 以下命令都假定当前目录是 D:\VRAIGC\vrstudio
cd D:\VRAIGC\vrstudio

# 校验包
D:\transfer\tools\7z.exe t D:\transfer\vrstudio-runtime-20261118-slim10.7z
Get-FileHash D:\transfer\vrstudio-runtime-20261118-slim10.7z -Algorithm SHA256

# 启动控制台（前台）
uv run vrstudio serve --host 0.0.0.0 --port 8760

# 版本与自检
uv run vrstudio --version
uv run python scripts/migrate_source_paths.py

# 零额度联调
uv run vrstudio generate submit --case <case名> --check

# 生成工具
mglc virtual-ip list
```

## 11. 术语与对应位置

- **工作区根**：docs 仓库的工作树，`vrgen\` 与 `vrstudio\` 是它的子目录。代码里的 `REPO_ROOT`
  指 `vrstudio\` 自己，由 `vrstudio\src\vrstudio\config.py` 的位置推导，换机器不用改。
- **迁移包**：`VRAIGC-transfer` 里的 `.7z`，内部前缀是 `vrstudio\`，解压到工作区根即可与两个仓库并排。
- **台账**：vrgen 记录每次调用与轮次的目录树 `vrstudio\vrgen_runs\`，`bootstrap.ps1` 与数据一起还原。
- **路径锚点**：`case.toml` 的 `[source] path` 相对 `vrstudio\`，`[[assets]] path` 相对 case 目录，
  规则见 `docs/case-model.md` §1 与决策 101。
