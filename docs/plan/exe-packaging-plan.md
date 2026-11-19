# 离线安装版打包计划（PyInstaller + Inno Setup）

对方要求把现在的 Web 版做成离线的 Windows 安装程序：目标机器不装 Python、Node、uv，
双击装完就能用浏览器打开控制台。本文记录要做的工作包、改动位置与验收方式。

前提与边界：

- 仍然需要联网做生成，mglc 必须已在目标机器上（安装器只做检测与提示，不随包分发）。
- 数据不进安装包，首次由安装向导指定数据根，或指向已有的迁移包解压结果。
- 不做代码签名，SmartScreen 警告写进交付说明。

## 1. 运行期目录约定

```
<程序目录> = %LOCALAPPDATA%\Programs\VRAIGC
  vrstudio.exe            控制台入口（同时是 CLI 入口）
  _internal\              冻结进包的 Python 代码与依赖（sys._MEIPASS）
  config\default.toml     内置默认配置
  bin\                    ffmpeg.exe、ffprobe.exe、rife-ncnn-vulkan-*
  tools\                  （可选）本机安装 mglc 的存放位置提示文件
  vrgen\vrgen.exe         vrgen CLI
  vrgen\_internal\        vrgen 的依赖
  vrgen\templates\        vrgen 提示词模板

<数据根> = D:\VRAIGC-data（安装向导里选，非系统盘英文路径）
  cases\  sources\  vrgen_runs\  logs\
```

`paths.py` 是唯一解析点：

- `is_frozen()`：`getattr(sys, "frozen", False)`。
- `app_dir()`：冻结取 `sys.executable` 的父目录，源码取仓库根。
- `resource_dir()`：冻结取 `sys._MEIPASS`，源码取仓库根；只读资源都按它找。
- `data_root()`：读 `[paths] data_root`，空则回退 `app_dir()`；相对路径按 `app_dir()` 解析。
- `user_config_dir()`：`%APPDATA%\vrstudio`。

`binres.py`、`media/ffmpeg.py`、`patch/rife.py` 里的 `parents[3]` 在冻结后等于程序目录，
因此 `bin\` 放在程序目录即可，代码不改。

## 2. 工作包

### WP0 文档与决策

- 决策 102：数据根、程序目录与资源目录、自举方式、安装形态。
- `case-model.md` §1：锚点由“仓库根”改成“数据根”。
- `architecture.md` §6：补安装版形态。
- 本文。

### WP1 vrstudio 路径与配置

- 新增 `src/vrstudio/paths.py`。
- `config.py`：`[paths]` 进 `default.toml` 与 `_FALLBACK`；`DEFAULTS_FILE` 改 `resource_dir()`；
  搜索顺序补 `<程序目录>\vrstudio.toml`、`%APPDATA%\vrstudio\default.toml`；校验 `data_root` 类型。
- 数据根调用点：`case.cases_root`、`case._workdir`、`case.stored_path`/`_stored_path`、
  `cli/generate._workdir`、`progress.logs_dir`、`web/app.sources_dir`。

### WP2 冻结相关适配

- `web/tasks.py` 的 `vrstudio_argv()`：冻结时返回 `[sys.executable, *args]`。
- `procenv.utf8_env()`：存在 `<程序目录>\tools\mglc.exe` 时注入 `VRGEN_MGLC_BIN`（不覆盖已有值）。
- 确认 `portguard` 的项目判定在冻结后仍成立（`sys.executable` 所在目录已在判定集合里）。

### WP3 vrgen 资源根

- `src/vrgen/paths.py`：`REPO_ROOT` 改 `resource_dir()` 语义（冻结取 `sys._MEIPASS`）。
- 模板与默认配置随包进 `_internal`，台账位置不变（vrstudio 传绝对 `--workdir`）。

### WP4 打包脚本

- `vrstudio/packaging/vrstudio.spec`：`--add-data` 收前端产物、`roles.json`、`config/default.toml`；
  隐藏导入覆盖 uvicorn 的 loops/protocols/lifespan 与 starlette；`console=True`。
- `vrgen/packaging/vrgen.spec`：收 `templates/`、`config/default.toml`。
- `scripts/build-installer.ps1`（docs 仓库）：前端构建 → 两次 PyInstaller → Inno Setup；
  版本号取自 `vrstudio.__version__` 与 git 短哈希。

### WP5 安装器与首次运行

- `packaging/vraigc.iss`（docs 仓库）：按当前用户安装、数据目录选择页、写入
  `%APPDATA%\vrstudio\default.toml`（`data_root`、`generate.vrgen`、`bin.dir`）。
- 安装后检测：mglc 是否在 PATH 或 `%LOCALAPPDATA%\Programs\mglc\bin`；缺失时弹出说明，
  给出安装位置与 `mglc login --access-key <AK> --secret-key <SK>` 的填写方式。
- 卸载只删程序目录，数据目录保留。

### WP6 验收

1. 门禁：`uv run pytest` 全绿、`uv run ruff check .` 干净，新增 `tests/test_paths.py`。
2. 本机打包后跑通：列表、打开一个 case 的对比页、`generate submit --check`、一段短 relight。
3. 干净 Windows（无 Python/Node/uv）：安装 → 指数据根 → 四项验收；卸载后数据目录仍在。
4. 缺 mglc、缺 Vulkan 两种环境各跑一次，确认提示可读。

## 3. 已知风险

- uvicorn 与 cv2 的隐藏导入遗漏会让 exe 启动即崩，需要 `--debug` 构建逐项补。
- `sys._MEIPASS` 在 PyInstaller 6 的目录式下指向 `_internal`，升级 PyInstaller 大版本时要重新验证。
- 未签名 exe 会被 SmartScreen 拦，目标机器首次运行需要手工放行。
- mglc 随版本更新，安装版里的提示要写成“去固定位置找最新版”，不能写死版本号。

## 4. 实施状态（2026-11-18）

- WP0–WP5 已完成：决策 102、`paths.py`、`[paths] data_root`、冻结自举与 mglc/bin 环境变量注入、
  两份 spec、`build-installer.ps1`、`vraigc.iss`、`setup-config.ps1`（便携版用）。
- 安装器在开发机完成一次真实安装（用户操作），数据目录与配置写入正常；此前“静默安装卡住”的
  判断非脚本问题，是构建环境里不可见弹窗导致。
- 启动分两种模式：开始菜单两条入口（本机 / 局域网），对应 `vrstudio.exe` 与 `vrstudio.exe --lan`；
  便携版生成 `启动-本机.cmd` / `启动-局域网.cmd`。
- 外部依赖不写 PATH：ffmpeg/rife 走程序目录 `bin\`，vrgen 走配置绝对路径，mglc 依次查
  `<程序目录>\tools`、`%LOCALAPPDATA%\Programs\mglc\bin`、`VRGEN_MGLC_BIN`、PATH。
- 打包前验收脚本 `scripts/verify-package.ps1`：把真实 case 复制到临时数据根，用打包后的 exe
  跑 `merge --case` 与 `relight --case --sample 3`；任何一条失败即非零退出。`VRSTUDIO_DATA_ROOT`
  环境变量用于这类临时覆盖。
- 已修：中文素材名导致 `cv2.imwrite` 静默失败、rife 收到空目录后访问冲突崩溃（源码版同样存在）。
- WP6 剩余：安装器在另一台干净机器上装一次并跑同一套打包前验收。
- 分发说明见 `docs/deployment-packaged.md`。
- 2026-11-19 补配置隔离（决策 103）：源码形态不再读取安装器写的 `%APPDATA%\vrstudio\default.toml`，只读仓库根 `vrstudio.toml`；`config set/show` 的写入口按运行形态区分。安装版行为不变，已构建的安装包不需要重装。
