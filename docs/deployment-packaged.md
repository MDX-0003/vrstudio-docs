# 打包版分发文档（安装器与便携版）

本文写给两种人：要把项目打成 Windows 安装包的人，和拿到安装包要在新机器上装起来的人。
打包版与源码部署是两条并列的分发方式——源码部署见 `deployment-new-host.md`，打包版不要求目标机装
Python、Node、uv。

## 1. 两种产物

- **安装器** `VRAIGC-<版本>-setup.exe`：双击安装，按当前用户装到
  `%LOCALAPPDATA%\Programs\VRAIGC`，带开始菜单项与卸载入口，安装时可选数据目录。
- **便携版** `VRAIGC-<版本>-portable.zip`：解压即用，多一个 `setup-config.ps1` 负责写本机配置。

两者装出来的程序目录相同：

```
VRAIGC\
  vrstudio.exe       控制台入口（同时是 CLI 入口）
  _internal\         Python 运行时与依赖、前端产物、默认配置
  vrgen\             vrgen.exe 与它的 _internal、templates
  bin\               ffmpeg.exe、ffprobe.exe、rife-ncnn-vulkan-*
  tools\             mglc 放置说明（mglc 不随包分发）
  README-install.txt 给使用者的安装说明
```

可写数据不在程序目录里，由配置 `[paths] data_root` 指定（决策 102），通常是
`D:\VRAIGC-data` 这样的非系统盘英文路径。

## 2. 构建

### 2.1 构建机需要什么

- Windows 10/11 x64，uv，Node.js 20+ 与 npm。
- 可选 **Inno Setup 6**：`winget install --id JRSoftware.InnoSetup -e`。没装也能构建，只是产出便携版。
- 可选 **7-Zip**：有的话便携版压得更快；没有就用 PowerShell 自带的压缩。

### 2.2 命令

```powershell
cd <工作区根>
powershell -ExecutionPolicy Bypass -File .\scripts\build-installer.ps1
```

常用参数：

- `-Version 0.1.1`：覆盖版本号，默认读 `vrstudio.__version__`。
- `-SkipFrontend`：跳过 `npm ci` 与 `npm run build`，前端产物已经是最新时用。
- `-SkipVrgen` / `-SkipVrstudio`：跳过对应仓库的 PyInstaller 构建，复用 `build\dist` 里的结果。
- `-Portable`：强制只出便携版 zip，不调用 Inno Setup。

脚本依次做四件事：构建前端、用 PyInstaller 打出 `vrgen` 与 `vrstudio` 两个目录式包、组装程序目录
（`build\app`，同时拷入 `bin\`、`tools\` 说明与 `README-install.txt`）、编译安装器。

产物：

```
build\VRAIGC-<版本>-setup.exe      安装器（需要 Inno Setup）
build\VRAIGC-<版本>-portable.zip   便携版（总会尝试，-Portable 时只出它）
build\app\                         组装好的程序目录，可以直接试运行
```

### 2.3 没有 Inno Setup 时

脚本会检测 `ISCC.exe`（`Program Files (x86)`、`Program Files`、`%LOCALAPPDATA%\Programs` 三处），
找不到就打便携版 zip，并在输出里说明。这样构建机不必为了出包安装 Inno Setup。
在别的机器上补装 Inno Setup 后重跑一次，就能同时得到安装器。

## 3. 安装版怎么装

1. 双击 `VRAIGC-<版本>-setup.exe`。首次运行会被 SmartScreen 拦一次，点“更多信息 → 仍要运行”；
   安装包没有数字签名，这是内部分发的既定取舍。
2. 选择程序目录（默认 `%LOCALAPPDATA%\Programs\VRAIGC`，按当前用户安装，不需要管理员权限）。
3. 选择数据目录：默认 `D:\VRAIGC-data`，机器上没有 D 盘时用
   `%LOCALAPPDATA%\VRAIGC\data`。如果数据是从旧机器搬过来的，直接指到迁移包解压出的目录。
4. 装完会自动写 `%APPDATA%\vrstudio\default.toml`：

   ```toml
   [paths]
   data_root = "D:\\VRAIGC-data"

   [generate]
   vrgen = "C:\\Users\\<用户>\\AppData\\Local\\Programs\\VRAIGC\\vrgen\\vrgen.exe"

   [bin]
   dir = "C:\\Users\\<用户>\\AppData\\Local\\Programs\\VRAIGC\\bin"
   ```

5. 安装器最后检测 mglc：找不到就弹窗说明去哪里拿、装到哪、用什么命令登录。

## 4. 便携版怎么装

1. 把 zip 解压到英文路径，例如 `D:\Apps\VRAIGC-portable`。解压后应该看到
   `VRAIGC\`、`setup-config.ps1`、`README-install.txt` 三样。
2. 运行配置脚本（双击可能被执行策略拦住，用命令行更稳）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-config.ps1
   ```

   它会问数据目录（回车用默认值），然后写 `%APPDATA%\vrstudio\default.toml`、
   建好 `cases/sources/vrgen_runs/logs`、检查 mglc。
   非交互场景直接给参数：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-config.ps1 `
     -AppDir D:\Apps\VRAIGC-portable\VRAIGC -DataRoot E:\VRAIGC-data
   ```

3. 配置已存在时脚本不会覆盖，改路径要加 `-Force`。

## 5. 首次使用要做的三件事

- **装 mglc 并登录**：向平台管理员要 `mglc-windows-amd64.zip`，解压到
  `%LOCALAPPDATA%\Programs\mglc\bin`，新开终端执行
  `mglc login --access-key <AK> --secret-key <SK>`，再用 `mglc virtual-ip list` 验证。
  登录态写在 `%USERPROFILE%\.mglc\config.yaml`，不随安装包分发。
- **确认数据目录**：里面应该有 `cases\`、`sources\`、`vrgen_runs\`、`logs\` 四个子目录；
  从旧机器迁移时把旧数据直接放进来，路径写法与源码版一致。
- **放行端口**：只有局域网其它机器要访问时才需要。

  ```powershell
  New-NetFirewallRule -DisplayName 'VRAIGC 8760' -Direction Inbound -Protocol TCP -LocalPort 8760 -Action Allow
  ```

## 6. 启动、升级、卸载

- 启动：双击 `vrstudio.exe` 或开始菜单里的 VRAIGC。不带子命令时它直接启动控制台并打开浏览器
  （`serve` 的默认参数：监听 `127.0.0.1:8760`）；要换端口或对局域网开放，用命令行：
  `vrstudio.exe --host 0.0.0.0 --port 8860`。`vrstudio.exe --help` 仍列出全部子命令。
- 需要不带浏览器、纯后台起服务时用 `vrstudio.exe serve --host 0.0.0.0 --port 8760`
  （`serve` 子命令默认不打开浏览器）。
- 升级：再跑一次新的安装器，覆盖程序目录；数据目录不在程序目录里，不受影响。
  便携版替换 `VRAIGC\` 目录即可，已写好的本机配置不用重做。
- 卸载：在“应用和功能”里卸载，只删程序目录；数据目录保留，需要时手动删。
- 回滚：保留上一版安装包或 zip，重装即可；数据格式没有版本升级步骤。

## 7. 排错

- **双击安装包没反应或被杀软拦下**：先确认文件完整（大小约 550 MB），把安装包加入白名单后重试。
- **SmartScreen 提示未知发布者**：点“更多信息 → 仍要运行”；这是未签名安装包的正常表现。
- **便携版双击 `setup-config.ps1` 一闪而过**：用
  `powershell -ExecutionPolicy Bypass -File .\setup-config.ps1` 运行，能看到具体报错。
- **启动报配置错误**：多半是 `%APPDATA%\vrstudio\default.toml` 的路径写错（反斜杠要写成双反斜杠，
  或直接用正斜杠）。删掉这个文件让安装器/`setup-config.ps1` 重写即可。
- **提示数据目录不存在**：改 `default.toml` 的 `data_root` 指向一个存在的目录，或加 `-Force` 重跑
  `setup-config.ps1`。
- **找不到 mglc 或登录过期**：重新执行第 5 节的安装与登录步骤；vrstudio 会去
  `%LOCALAPPDATA%\Programs\mglc\bin`、`<程序目录>\tools\mglc.exe`、PATH 三处找。
- **`ffmpeg` 相关报错**：检查 `bin\ffmpeg.exe` 是否被杀软隔离，从安装包或 zip 里补回来。
- **补帧报 Vulkan 错误**：机器缺少可用的 Vulkan 驱动，补帧不可用，其它流程正常。
- **端口 8760 被占用**：控制台会直接报“端口 8760 已被占用”，换一个端口重试
  （`vrstudio.exe --port 8761`），或先结束占用进程：
  `Get-NetTCPConnection -LocalPort 8760` 看 pid，再 `Get-Process -Id <pid>` 确认。
  本项目的旧实例会被自动接管，别家程序占用的不会被强行结束。
- **局域网打不开**：确认启动参数带 `--host 0.0.0.0`、防火墙放行 8760、访问的是本机局域网 IP。

## 8. 与源码部署的关系

- 源码部署（`bootstrap.ps1`）用于开发机和 host 迁移，依赖 git、uv、Node。
- 打包版用于分发给不装开发环境的人，程序目录只读、数据目录可写。
- 两者共用同一份 `case.toml`、`vrgen_runs`、`logs` 与 `[paths] data_root` 约定，数据可以互相搬。

## 9. 本轮验证结果与已知边界

已验证：

- 两个 exe 由 PyInstaller 目录式打出并运行：`vrstudio.exe` 能启动 `serve`，`/api/cases` 与 `/next/`
  都返回 200；`vrgen.exe --help` 正常。
- 冻结版按 `[paths] data_root` 把 `cases/logs/sources` 建在指定目录，程序目录保持干净。
- 便携版全流程：解压 → `setup-config.ps1` 写配置 → 启动 → 接口可用。
- 安装器编译成功（Inno Setup 6.7.3，550 MB）。

未验证，需要在正常桌面环境补一次：

- **安装器实际执行安装**。本构建环境里 setup 进程启动后停在 0 CPU、无日志、无目标目录，
  判断是非交互会话里弹窗不可见导致阻塞；编译与程序目录本身都正常。

其他边界：

- 不做代码签名，SmartScreen 会提示。
- 不随包分发 mglc。
- 安装器按当前用户安装，装到 `Program Files` 需要管理员且数据目录必须另放，不在支持范围。
