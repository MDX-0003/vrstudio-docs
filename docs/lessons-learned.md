# 经验与教训记录

状态：持续更新。本文记录可复用的排查步骤、测试经验与踩坑结论，作为项目内的
长期 memory；具体任务进度仍以 `docs/plan/` 和 `docs/test-runs/` 为准。

## 1. 2026-10-25 · Playwright MCP 浏览器 profile 被占用

### 现象

调用 Playwright MCP 的 `browser_navigate` 时返回：

```text
Error: Browser is already in use for
C:\Users\Administrator\AppData\Local\ms-playwright-mcp\mcp-chrome-2e8d960,
use --isolated to run multiple instances of the same browser
```

同时 `browser-use` 的守护进程启动失败，日志提示：

```text
DevToolsActivePort not found ... enable chrome://inspect/#remote-debugging,
or set BU_CDP_WS for a remote browser
```

### 诊断步骤

1. 先查占用 profile 的进程，而不是直接杀浏览器：

   ```powershell
   Get-CimInstance Win32_Process |
     Where-Object { $_.CommandLine -like '*ms-playwright-mcp*' -or $_.CommandLine -like '*mcp-chrome-2e8d960*' } |
     Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine |
     Format-List
   ```

2. 同时查 profile 目录与锁文件：

   ```powershell
   $p='C:\Users\Administrator\AppData\Local\ms-playwright-mcp\mcp-chrome-2e8d960'
   Get-ChildItem $p -Force | Select-Object Name,Length,LastWriteTime
   ```

3. 查父进程链。本次结果是：
   - Chrome `22772`，启动于 2026-10-23 19:19，`--user-data-dir=...\mcp-chrome-2e8d960`，`--remote-debugging-pipe`。
   - 父进程 Node `30052`，启动于 2026-10-23 18:51，命令是 `@playwright/mcp/cli.js`。
   - 祖父进程 `cmd.exe 16880`，命令是 `playwright-mcp`。
   - 当前会话另有一个 2026-10-25 8:50 启动的新 MCP server，但同一个 profile 被旧浏览器占用。

### 根因

不是端口冲突，也不是网络问题，而是 Playwright MCP 的浏览器 profile 被一个
**两天前启动、没有退出的旧 MCP 浏览器**占着。新的 MCP server 试图复用同一个
`--user-data-dir`，发现已有实例，于是拒绝启动。

### 处理

在确认旧实例是残留、没有当前会话在用它之后，关闭整棵旧进程树：

```powershell
taskkill /PID 16880 /T /F
```

本次关闭了旧 `cmd -> node -> chrome` 树，然后重新调用 `browser_navigate`，
当前 MCP server 成功启动了新浏览器。

### 判断旧实例是否可以关闭

至少同时看：

- 启动时间是否明显早于当前会话。
- 父进程是否还是旧的 `playwright-mcp` 或 `@playwright/mcp/cli.js`。
- 浏览器标题与页面是否停在旧任务（本次是 `vrstudio`）。
- 当前会话是否已有自己的 MCP server 进程。

不要因为错误信息里出现 `Browser is already in use` 就关闭用户正常使用的 Chrome；
只处理命令行里带 `--user-data-dir=...ms-playwright-mcp...` 的实例。

### 不要做的事

- 不要先 `npm install playwright` 或改项目依赖来“修” MCP；MCP 的浏览器由
  MCP server 自己管理。
- 不要把 `browser-use` 当成默认可用的备选；它需要 Chrome 远程调试端口或
  `BU_CDP_WS`，未配置时会直接报 `DevToolsActivePort not found`。
- 不要只删 profile 里的锁文件而不处理进程；浏览器仍在运行时，锁会再次出现。
- 不要在未确认旧实例归属时杀进程；先看父进程、启动时间与当前会话。

### 验证

- `browser_navigate` 成功，页面标题与 URL 正常。
- 当前 MCP server 进程启动时间是当前会话。
- profile 对应浏览器由一个当前会话的 MCP server 持有。

### 预防

- MCP 测试使用固定但独立的 profile；不要和用户日常浏览器混用。
- 测试结束尽量关闭 MCP 浏览器，避免跨天残留。
- 如果环境支持 `--isolated`，优先为一次性测试使用隔离实例。
- 记录 profile 路径、进程 ID、父进程与启动时间，方便下次判断。

## 2. 2026-10-25 · 整页导航与 SPA 路由切换不是一回事

### 现象

在测试“上传中切页是否取消上传”时，用 Playwright 的 `page.goto()` 切到
`/next/cases`，网络里只有 `POST /api/uploads` 和 `PUT /api/uploads/...`，
没有 `DELETE`，服务端残留不完整上传。

### 结论

- `page.goto()` 是整页导航，浏览器会销毁当前 JavaScript 上下文，Vue 的
  `onUnmounted` 不会执行；普通 `fetch` 的 DELETE 也会被中止。
- 点击 Vue Router 的侧栏链接是 SPA 路由切换，组件会正常 unmount，`onUnmounted`
  会执行。
- 上传弹窗是模态的，打开时侧栏链接被遮罩拦截；用户实际能触发的整页卸载路径
  更接近关闭标签页、刷新页面或浏览器前进/后退，而不是点侧栏。
- 因此，测试“切页取消上传”必须明确是 SPA 切换、整页导航还是关闭标签页，
  不能用一个 `page.goto()` 代表全部情况。

### 测试建议

- SPA 切换：点击 `router-link`，检查组件卸载后的 DELETE 是否到达。
- 整页卸载：关闭标签页/刷新，检查是否需要 `keepalive` 或 `sendBeacon`。
- 网络延迟：用 Playwright `page.route()` 延迟 PUT，确保上传在切页时仍在进行。
- 断言不能只看前端调用；要看服务端 `.uploads/<id>/` 是否消失，或网络里是否
  真的出现 DELETE。

## 3. 2026-10-25 · 测试前先确认“只读数据”与“可写数据”

浏览器验收经常需要修改提示词、设置或上传文件。执行前先分清：

- 哪些 case 是只读的，不能改提示词、提交集、素材。
- 哪些设置是全局的（显示名），测试后必须恢复。
- 哪些上传会产生服务端临时目录，测试后是否保留、何时清理。
- 哪些操作会扣费，必须单独批准。

本次没有修改 QA case 的提示词，因此长文本实际保存路径没有在浏览器里验证；
后续如果要测，应该使用可丢弃的临时 case，或先记录原值并在测试后恢复。

## 4. 2026-10-26 · 本机 vrstudio.toml 会让全量 pytest 变红

### 现象

`uv run pytest` 有 9 例失败，全部在 `tests/test_web_proxy.py`：断言默认 `web.proxy_max_w == 4096`，实际读到 2048；代理 sidecar 的 ready/disabled 判定与预期相反。

### 诊断步骤

1. 确认失败集中在一个模块，且断言的是配置默认值。
2. 查仓库根的 `vrstudio.toml`（gitignore）：本机按决策 17 设了 `proxy_max_w = 2048`。
3. 把该文件临时移开，只跑 `tests/test_web_proxy.py`，13 例全绿；再跑全量 386 例全绿；随后原样移回。

### 根因

`config_mod.load()` 不传 `cwd` 时按“用户目录 → 当前目录”的优先级读取 `vrstudio.toml`；代理测试直接断言内置默认值，没有隔离开发者机器的本地覆盖。与本次功能改动无关。

### 处理

临时移开本地配置验证后恢复；没有改代理逻辑，也没有改测试。

### 验证

默认配置下 `uv run pytest` 386 passed；`vrstudio.toml` 恢复后本机仍按 2048 运行服务。

### 预防

- 全量门禁变红且集中在 `test_web_proxy` 时，先看本机 `vrstudio.toml`，不要先动代理实现。
- 长期做法：这类断言默认值的测试显式传 `config_mod.load(cwd=tmp_path)` 或 monkeypatch `load`，不读开发者本地文件。本次未改，留作独立修复。

## 5. 2026-10-28 · 旧进程跑新配置：KeyError 与说谎的 traceback

### 现象

serve 在 `/`、`/case/walk_01`、`/api/case/walk_01` 上连续 500，最后一行是 `KeyError: 'default_frontend'`，栈指向 `config.py` 的 `_validate`。同一条 traceback 里还夹着几句不可能执行的行：`def _media_meta(...)`、`return None`、`return JSONResponse({"error": "no such case"}, status_code=404)`。

### 诊断步骤

1. 把 traceback 里「正在执行的行」对回当前文件：`app.py` 第 398 行的 `_open_roots` 与第 398 行的 `return None` 不是同一段代码，说明行号与源码错位。
2. 查进程创建时间：监听 8760 的进程建于 18:15:00，报错发生在 18:14:04，报错时跑的是更早的旧进程。
3. 查 `logs/serve/service-*.jsonl`：同一秒有成对的 `request.error` 与 `Exception in ASGI application`，异常都是同一个 `KeyError`；同一秒还有一条 `TemplateNotFound: 'wizard.html'`，模板已被退役改动删除。
4. `git grep default_frontend` 为空：新代码与新默认值都没有这个键。

### 根因

配置数据热、Python 代码冷。`Config.load()` 每次调用都重新读 `config/default.toml`，而 `_validate` 是进程启动时导入的函数对象；退役改动把两者一起改了，旧进程读新文件、跑旧校验，每个走到配置的请求都拿到一套与自身代码不匹配的配置。

### 处理

配置改为启动时定格（决策 43）：`config.activate()` 在 `serve` 与 `build_app()` 里装配一次，请求路径只读 `config.active()`；`serve` 装配失败按退出码 2 退出并写明原因。同时把 `_validate` 的缺键改成 `ConfigError`，并把 `uvicorn.error` 与 `request.error` 的重复异常日志合并成一条。

### 验证

`pytest` 418 条通过、`ruff` 干净；坏配置下 `serve` 退出码 2；临时服务上中文昵称可存可取。详见 `docs/test-runs/20261028-config-snapshot-and-log-dedup.md`。

### 预防

- traceback 里出现 `def`、静态 `return`，或者显示的源码与异常类型无关时，先怀疑进程是旧的，再读代码。
- 删配置键、改默认值、删模板或静态文件之后，所有在跑的服务都要重启；宁可重启，不要指望旧进程兼容新文件。
- 同一条异常在日志里出现两次，说明中间件与 uvicorn 各记了一遍，查日志一律按 `request.error`（带 rid 与路径）为准。
- 按消息文本过滤日志记录时，先照抄真实日志里的文案再写判据：uvicorn 的 `Exception in ASGI application` 带尾随换行，第一版过滤器写成精确相等，单元测试用自造的不带换行文案全过，真实路径上照样重复记录。过滤与去重这类改动要用真实进程验证一遍，不能只看 TestClient。

## 6. 2026-10-29 · patchimg 8K 真实验收：上传 403、inner 覆盖与冗余带

### 现象

用 8192x4096 的 ERP 图跑 patchimg 全流程。`extract` 生成 9558x4096 的 `padded.png`
（117.6 MB）与 `padded_mask.png`（39.2 MB）。`generate submit` 在 mglc 上传阶段
连续两次返回 `code 10101: 上传文件失败: 上传失败 HTTP 403 AccessDenied`，轮次停在
`prepared`，没有拿到 task id。把提交副本缩到长边 4096（`upload.png` / `upload_mask.png`）
后同一 session 提交成功，返回 4 张候选。

### 诊断步骤

1. 读 `vrgen_runs/erp_test/img-61002501/mglc.log`：`model --type image --model-id 44`
   成功，失败发生在 `image generate`；`run.json` 的 stage 仍是 `prepared`。
2. 直接跑 `mglc model --type image --model-id 44`：只公布 ratios、resolutions、
   maxReferenceCount、maxPromptLength，没有 `refImageValidator`，所以本地的
   `_check_input_images` 无从判断。
3. 重试同一命令，403 立即返回且资源 key 前缀相同；文件大小是唯一异常（117 MB）。
4. 用 4096 宽的上传副本重试，成功。

### 根因

平台的图片上传接口对超大 PNG 返回通用 403，而不是“尺寸超限”的校验错误；图片模型
输出只有 4K，9558 宽的全幅输入既超出上传能力，也没有对应的输出分辨率收益。

### 处理

- `assemble_still` 增加上传副本：`padded.png` 与 `padded_mask.png` 超过
  `generate.image_upload_max_side`（默认 4096）时长边缩到该值，base 用 INTER_AREA，
  mask 用 INTER_NEAREST 保持二值；写入 `upload.png` / `upload_mask.png`。
- canonical `padded.png` 与 `image_pad.json` 仍是满分辨率；`stitch_image` 把模型输出
  还原到画布尺寸，最终 ERP 保持 8192x4096。
- 实测同时暴露两处约束，已补机制：
  - 局部 inner 必须覆盖完整主体。第一次 inner 960x540 只到腰部，候选虽然把整身改成
    金袍，但贴回会在腰线切断；扩到 1080x800（x=420,y=280）后完整。
  - 局部选区必须落在干净主内容 `[P, W-2P)` 内。第一次选香炉（yaw 110）压到右侧
    冗余带，pad 把黑区复制到另一侧，mask 变成横贯画布的宽条；`extract` 现在直接
    拒绝并提示移开接缝或缩小 inner。
- `vrgen` 的 `RunStore.open` 增加按轮次目录名匹配；`adopt --round img-xxxx` 不再报
  no run matching。

### 验证

- 源图 `sources/360erp_test.png`，session 2062569522605504，4 张候选，gate ok。
- 采用 `img-61e3e701` 的第 4 张；`merge` 输出
  `cases/erp_test/out/20261029-103543_image.png`（8192x4096）。
- 报告：`d*=-7`，`corr=0.933`，`gate=warn`（代价曲线平，不是失败），
  接缝 `wrap 0.437 / percentile 48.1 → ok`，选区外 `maxdiff 0`，
  `changed 700816/701031`。
- 目视：人物完整换成金袍，柱子、地面、桌子与大殿其他部分保持；8K 局部细节受 4K
  输出上限影响，贴回后偏软。

### 预防

- patchimg 默认只传 4096 长的上传副本；要确认平台接受原尺寸时用
  `--set generate.image_upload_max_side=0`，但 117 MB 级输入会 403。
- 选 inner 时用预览确认框住完整主体，并留在干净主内容内；CLI 先看
  `padded_mask.png` 或 extract 的报错，不要直接提交。
- 平台对超限输入可能给通用 403；遇到上传阶段的 403 先查文件大小，再查凭证与 URL。

### 相关文件/命令

- `vrstudio/src/vrstudio/cli/generate.py` `_upload_inputs`
- `vrstudio/config/default.toml` `generate.image_upload_max_side`
- `vrstudio/src/vrstudio/cli/extract.py` 冗余带守卫
- `vrstudio/src/vrstudio/patch/still.py` `changed_inside` 按像素统计
- `vrgen/src/vrgen/round/ledger.py` `RunStore.open` 目录名匹配

## 7. 2026-11-18 · 打包与分发：只在离线安装版暴露的问题

离线安装版的目标机器不装 Python、Node 与 uv，程序目录只读，可写数据在另一个盘。这个前提让
源码版里被掩盖的问题集中暴露，下面按现象与处理记录。

### 现象一：exe 启动即崩或页面空白

- **根因**：PyInstaller 只能静态分析导入，uvicorn 的 loop、protocol、lifespan 实现与
  `anyio`、`h11`、`psutil` 都是运行时按名字导入的，没有显式收进去。
- **处理**：`vrstudio/packaging/vrstudio.spec` 用 `collect_submodules("uvicorn")` 加上
  一份显式列表；前端产物、`roles.json`、`config/default.toml` 用 `--add-data` 收进 `_internal`。
- **预防**：打包后先跑 `vrstudio.exe --version` 与 `serve`，再跑一次
  `scripts/verify-package.ps1`；只验证 exe 能启动会漏掉隐藏导入。

### 现象二：冻结后找不到 bin、config 或前端产物

- **根因**：PyInstaller 6 的目录式包里 `__file__` 落在 `<程序目录>\_internal\`，
  源码里按仓库根推算的 `parents[2]`/`parents[3]` 在冻结后语义变了。
- **处理**：新增 `vrstudio/src/vrstudio/paths.py` 作为唯一解析点：`app_dir()` 取
  `sys.executable` 的父目录，`resource_dir()` 冻结时取 `sys._MEIPASS`，`data_root()`
  读 `[paths] data_root`。`bin\` 放在程序目录，资源放 `_internal`，两边各按对应函数找。
- **预防**：新增资源路径时只允许经过 `paths.py`；升级 PyInstaller 大版本后重新验证
  `_MEIPASS` 指向。

### 现象三：程序目录里堆出了 cases、logs 与 vrstudio.toml

- **根因**：源码版的可写数据默认落在仓库根，冻结后这个根就是程序目录；安装到
  `Program Files` 或 `%LOCALAPPDATA%` 时既没有写权限，升级也会把数据一起覆盖。
- **处理**：决策 102 增加 `[paths] data_root`，安装器在向导里让用户选非系统盘目录，
  卸载只删程序目录；升级时从 `%APPDATA%\vrstudio\default.toml` 读回已有数据目录并预填。
- **预防**：打包目录组装完要检查 `cases`、`sources`、`logs`、`vrgen_runs`、
  `vrstudio.toml` 是否被 exe 试运行带进 `dist`，`build-installer.ps1` 会主动删掉它们。

### 现象四：中文素材名让合成结果静默缺失，rife 随后访问空目录崩溃

- **根因**：OpenCV 的 `cv2.imwrite` 对非 ASCII 路径返回 False 而不抛异常；rife 拿到空目录
  后越界访问。源码版同样存在，只是验收素材多为英文名没有触发。
- **处理**：写图改走带编码处理的封装，rife 调用前检查输入目录非空并给出可读报错。
- **预防**：验收 case 必须带一个中文素材名的路径；`verify-package.ps1` 的 patch 合成用例
  专门覆盖这一条。

### 现象五：安装包与便携版对外分发时的固定动作

- **根因**：没有代码签名，SmartScreen 会拦；mglc 是平台工具，不能随包分发；
  发布目录里放校验文件与维护说明会让非技术使用者多面对一堆文件。
- **处理**：安装器与便携版都只在首次运行时提示“更多信息 → 仍要运行”；mglc 由使用者
  自行放到 `%LOCALAPPDATA%\Programs\mglc\bin`，安装器只做检测与提示；对外发布目录只放
  两个产物加一页 `先看这里.txt`，校验值在构建机上现算。
- **预防**：分发说明写进 `docs/deployment-packaged.md`，发布说明模板放在
  `packaging/release/` 下，不靠口头交接。

### 现象六：打运行时数据包时日志被截断

- **根因**：`serve` 正在运行，`logs/serve/service-<日期>.jsonl` 被进程占用，7z 读到的是
  打开时刻的副本。
- **处理**：打包前停掉服务，或按 MANIFEST 里的说明对正在写入的文件做复制后再追加。
- **预防**：数据包生成时记录打包时间与截断位置；`.web-lock.json`、`derived/`、
  `out/samples/` 与旧 `extracts/` 打包前就裁掉，缩减体积也减少变动文件。

### 现象七：测试在仓库内落临时目录，让与代码无关的断言失败

- **根因**：Windows 上 `TEMP` 不可用时 `tempfile` 回退到仓库根，`pytest-of-*` 落在
  `vrstudio/` 内；有的测试断言“case 在仓库外时相对路径为 None”，于是失败。
- **处理**：把 `pytest-of-*` 与 `vrgen-*.json` 写进 `.gitignore`，测试失败时先看临时目录
  落在哪；这不属于代码缺陷。
- **预防**：跑全量门禁前确认 `TEMP` 可用，或直接接受这类环境失败并在记录里注明。

### 相关文件/命令

- `vrstudio/packaging/vrstudio.spec`、`vrgen/packaging/vrgen.spec`
- `vrstudio/src/vrstudio/paths.py`、`vrgen/src/vrgen/paths.py`
- `scripts/build-installer.ps1`、`scripts/verify-package.ps1`
- `packaging/vraigc.iss`、`packaging/setup-config.ps1`、`packaging/release/`
- `docs/deployment-packaged.md`、`docs/plan/exe-packaging-plan.md`

## 8. 记录模板

以后新增经验时按以下结构追加，不覆盖旧记录：

```text
## 日期 · 标题

### 现象
### 诊断步骤
### 根因
### 处理
### 验证
### 预防
### 相关文件/命令
```

- 2026-10-27 对比页 Playwright 验收：应用层的「设置显示名」el-dialog 会盖住整个页面，点击类操作全部落在 overlay 上（超时或无效）；先点「稍后」关掉弹窗再交互。elementFromPoint 可用来快速发现遮挡。无头页面失焦时 rAF 节流到 1fps，测量前 bringToFront 并检查 document.hidden。

- 2026-10-27 前端改动的两份形态：8760 服务的是 frontend/ 的构建产物（src/vrstudio/web/static/next），vite dev（5173）才是源码实时版；改了 frontend/src 后必须 cd frontend && npm run build 才能在 8760 看到变化，且无需重启 serve（静态文件现读盘）。用户看到旧版入口还在、新功能没生效时，先查产物时间戳再怀疑代码回退。
