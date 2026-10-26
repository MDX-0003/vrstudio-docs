# 统一文件视图方案：所有展示资产可查名、可查路径、可单独打开

状态：已实施（2026-10-26，WP0–WP5 完成；浏览器验收记录见 `docs/test-runs/20261026-unified-file-view.md`）。
关联：`docs/key-issues/frontend-decisions.md`（前端决策惯例）、`docs/plan/frontend-review-fixes.md`（ExtractStep 文件行样板的出处）、`docs/case-model.md`（跨仓台账契约）。

## 0. 已确认的分支决策

1. **视频类资产点"打开"只加载原片**（源片、clip、成片、轮次结果），不跳代理。用户知道软解环境 8K 会卡，仍选原片——单独打开的目的就是核对原始文件。
2. **vrgen 台账文件（vrgen_runs/）纳入 web 直读**：首尾候选图片、生成轮次 result.mp4 与 run.json。轮次列表与候选图本就有读台账的先例（`_rounds`、`_keyframe_rounds`），本方案延续"展示层只读、不改台账"的边界，与硬规则 1（交互走 CLI）不冲突。
3. **覆盖范围**＝用户点名（源片、首尾候选、选定图、重绘图/成片、素材）＋三项扩围：生成轮次原始结果与 run.json、选区页源片文件行、合并页输入文件行。
4. **图片卡展示密度**：卡上加"打开"图标，文件名与路径放悬浮提示（title）；完整文件行只用于文件列表型面板。
5. **寻址按白名单根，不按仓库相对路径**（2026-10-26 讨论确认）。`/file?root=<cases|sources|workdir>&p=<根内相对路径>`；`rel` 只做展示，不再兼任寻址。理由：`--cases-dir` 与 `generate.workdir` 都可指向仓库外，`rel` 在这些环境下为 None，用它寻址会让打开链接静默消失；现有 web 测试也都用临时目录当 cases 根。
6. **生成记录逐轮给文件条目**（2026-10-26 讨论确认）：`_rounds` 逐轮读 `run.json` 的 `result`，给每轮附 result 与 run.json 两个 `file_entry`；不只覆盖被采用的轮次。
7. **伺服面回收**（2026-10-26 讨论确认）：`/media/extract` 在 WP3 替换后没有调用方，删除；`/video/out` 的内嵌原片回退改用 `open_url`，路由一并删除。`/video/source` 保留（仓库外源片不在白名单内），`/img/asset`（缩略）与 `/img/keyframe`（候选原图展示）保留。
8. **对比页不加文件行**（2026-10-26 讨论确认）：对比页的源片与成片在选区页、合并页、生成页已可查与可打开；对比页只把右路代理未就绪时的回退从 `/video/out` 改到 `open_url`。此边界写进 §5，避免以后被当成遗漏。

## 1. 需求

用户原话：

> 我接下来希望所有流程中展示到的资产，比如选区界面看到的原始视频、首尾帧的候选图片、选定后图片、重绘后图片等等，都能像抽取页的输出文件一样，能看到这个文件的名称、路径、且能在浏览器里跳转到单独页面打开查看。

样板是抽取页"输出文件"面板：文件名 + 仓库相对路径 + 大小 + "播放/打开"链接（`target="_blank"`，浏览器原生查看器）。该面板当前的链接走家族路由 `/media/extract/...`；本方案把它统一改成 `/file`，由 WP3 完成。

## 2. 现状盘点（2026-10-26 核实，含两处修正）

### 2.1 资产清单：位置、伺服路由、页面现状

| 资产 | 物理位置 | 伺服路由 | 页面现状 |
|---|---|---|---|
| 抽取输出（clip.mp4 / clip_mask.png / clip.json / 首尾原始帧） | `cases/<c>/extracts/<v>/` | `/media/extract/...`（将被 `/file` 取代） | ✅ 名字+rel 路径+大小+打开/播放（样板，ExtractStep） |
| 合并成片 / pad 产物 | `cases/<c>/out/`、case 根 | `/video/out/...`（将删除）、`/video/outproxy` | 名字+大小+下载链接；输入文件只有名字大小无链接（MergeStep） |
| 源片 / 全景代理 | `sources/`、`cases/<c>/derived/pick/` | `/video/source/<c>`、`/video/proxy/<c>` | 仅内嵌播放，无文件信息（PickStep / CompareStep） |
| 素材（上传图/视频、gen 母版、clip/pad 候选、选定首尾帧） | `cases/<c>/assets/`、extracts 等 | `/img/asset/<c>/<id>`（**320px JPEG 缩略**，`app.py:1373`） | 卡上只有缩略图；路径仅在无尺寸信息时作回退显示（GenerateAssets.vue:46） |
| 首尾原始帧（工作台底图） | `extracts/<v>/first|last_frame_raw.png` | `/img/asset/<c>/<id>`（同样是缩略） | 工作台内嵌缩略图，无打开（`_raw_frames` 已带 path/size） |
| 首尾候选图片 | `vrgen_runs/<c>/img-*/`（跨仓台账） | `/img/keyframe/<c>/<round>/<i>` | 网格卡片；**该路由返回的是候选原图字节**（`app.py:2089`），缺的只是名字与路径展示 |
| 生成轮次原始结果 + run.json | `vrgen_runs/<c>/<round>/` | **没有路由**；`_rounds` 只给轮次名与目录 | `step_files` 只覆盖被采用的轮次；其余轮次点不开 |

**修正一**：首尾候选不是"没有路由"。`/img/keyframe` 已经伺服原图字节，缺的是文件名与路径展示；本方案统一改走 `/file` 以保持"打开原始文件"只有一种机制，但工作量上它不需要新增伺服面。

**修正二**：首尾原始帧与定稿图的现状比原稿写的更差。它们的 `<img src>` 走 `/img/asset`，而该路由会把图缩到 320px 再编成 JPEG（`app.py:1373-1392`、`:1395-1430`）。也就是说这些展示资产当前看到的不是原图；`/file` 不只是补链接，也是把原始文件从缩略通道里解放出来。

### 2.2 同类性结论

- **数据层接近同构，但有例外**：`_file_info(path)`（`app.py:694`）给出 name / rel / exists / mtime / size，素材卡与步骤文件已用它；例外有三处——`_outputs` 完全没有 `_file_info` 字段（只有 file/url/proxy_*），`_raw_frames` 是手写形状（无 name/mtime），首尾候选与轮次结果只有绝对路径。接入时不能只"补一个 open_url"，要按 §3.2 逐个说明重建或补字段。
- **伺服层碎片化**：8 条路由语义各异——proxy 带构建逻辑、asset 带缩略、keyframe 按 run.json 寻址、extract 按版本号寻址；轮次结果完全没有路由。
- **展示层三种 UI**：文件行（ExtractStep/MergeStep）、图片卡（Assets/Keyframe）、内嵌播放器（Pick/Compare/Results），互不复用。

## 3. 设计

### 3.1 后端：一条按白名单根寻址的"原始文件直开"路由

- `GET /file?root=<cases|sources|workdir>&p=<根内相对路径>`：只此一条新路由，承担"单独页面打开"这一件事。
- 根表（唯一的白名单来源，集中在 `_open_root(path)` 与 `_file_target(root, p)` 两个函数里）：
  - `cases` → `_ctx["cases_root"]`（默认仓库 `cases/`，`serve --cases-dir` 可改）；
  - `sources` → `sources_dir()`（仓库 `sources/`）；
  - `workdir` → `_workdir()`（`generate.workdir`，默认仓库 `vrgen_runs/`，可配绝对路径）。
- 校验与行为：
  - `root` 不在根表内 → 404。
  - `p` 必须是相对路径：拒绝绝对路径、盘符、UNC、以分隔符开头；统一把 `\` 归一成 `/` 再 `Path()`。
  - `(根目录 / p).resolve()` 必须 `relative_to(根目录.resolve())`，否则 404（同时兜住 symlink/junction 逃逸）。
  - 目标必须是已存在的普通文件；目录、不存在、越界一律 404。
  - 仅 GET（Starlette 的 GET 路由自动带 HEAD）；`FileResponse(path, media_type=…, filename=p.name, content_disposition_type="inline")`，Range 由 FileResponse 提供，视频可拖动。
  - Content-Type 的扩展名集合复用两侧已有的视频/图片集合（`case.py:56` 与 `app.py:82` 的并集：mp4/m4v/mov/mkv/avi/webm、png/jpg/jpeg/webp），`json` 给 `application/json`，`txt/toml/log` 给 `text/plain; charset=utf-8`，其余给 `application/octet-stream`；响应统一加 `X-Content-Type-Options: nosniff`。
- **为什么不用 `rel` 寻址**：`rel` 相对 `config_mod.REPO_ROOT`，仓库外为 None（`app.py:694-713`）；而 `--cases-dir`、`generate.workdir` 都可以指到仓库外，现有 web 测试也全部用临时目录当 cases 根（`tests/test_web_console.py:45-48`）。用 `rel` 拼 URL 会让这些环境下所有打开链接静默消失，WP2 的断言也无法在测试基建上成立。`rel` 保留原语义，只做展示。
- 伺服面回收（与 §0 决策 7 一致）：
  - 删除 `/media/extract`：全仓只有 `ExtractStep.vue:37` 使用，旧模板与静态脚本无引用，WP3 替换后无调用方；测试同步迁到 `/file`。
  - 删除 `/video/out`：`_outputs` 的 `url` 字段改由 `open_url` 承担，GenerateResults 与对比页的代理未就绪回退改用 `open_url`（`/file` 支持 Range，能播）。
  - 保留 `/video/source`（仓库外源片不在白名单内，打不开也必须能播）、`/video/proxy`、`/video/outproxy`、`/img`（VP 重绘）、`/img/asset`（缩略）、`/img/keyframe`（候选展示）。
- **白名单暴露面（安全边界，必须记录）**：`workdir` 根意味着 `command.txt`、`mglc.log`、`prompt.txt`、`run.json` 都可被 URL 直读；实测 `vrgen_runs/walk_02/gen-multi-730e1703/run.json` 含带 `q-ak` 与 `q-signature` 的签名下载 URL 与 task id。这与已有 `/api/browse`（可列任意目录）同属本地信任边界；单用户、127.0.0.1 下可接受。若将来用 `--host 0.0.0.0` 对局域网开放，`/file` 必须另做鉴权或收窄到固定文件名，不在本次范围。

### 3.2 payload：`file_entry(path)` 统一描述

- `_open_root(path) -> "cases" | "sources" | "workdir" | None`：按 resolve 后的包含关系判定，是白名单的唯一权威。
- `file_entry(path) -> {**_file_info(path), "open_url": …}`：`open_url` 只在**文件存在且根命中**时出现；不存在或缺根时条目照常返回（页面标红）但不带链接，避免点开 404。`rel` 语义不变。
- 接入点（逐个说明改法，不再笼统写"补 open_url"）：
  - `_asset_details`（素材卡）：已有 name/rel/size，改为 `**file_entry(path)` + 原有 id/kind/role/label/source/role_fixed/url/meta。
  - `_raw_frames`（首尾底图）：改为 `file_entry(path)` + 保留 id/role/label/width/height。
  - `_keyframe_state` 的 `_pick_row`（首尾**选定图**，用户点名项）：新增 `file` 字段（`file_entry`），`first`/`last` 各带一份；`sheet_candidates` 补 `rel` 与 `open_url`（现在只有 `path`）。
  - `_keyframe_rounds`（首尾候选）：每张候选补 `file_entry`；原有 `url` 继续供 `<img>` 与缩略网格。
  - `_generation_groups`（采用轮的原始结果与 run.json）：补 `open_url`。
  - `_outputs`（成片）：条目重建为 `file_entry` + `file`/`proxy_url`/`proxy_state`/`proxy_width`/`version`/`partial`；**删除 `url` 字段**（由 `open_url` 取代），前端 `OutputFile` 同步改。
  - `_patch_step_files` / `_fullredraw_step_files` / `_gen_step_files`：所有 inputs/outputs 由 `_file_info` 改为 `file_entry`。
  - `_rounds`（生成记录，新增）：逐轮读 `<round_dir>/run.json` 的 `result`（读不到回退 `<round_dir>/result.mp4`），给每轮附 `files: {result, run_json}` 两个 `file_entry`；`run.json` 自身也作为条目返回。保持"读台账只读"的边界。
  - `_case_info`：新增 `source_file: file_entry(Path(case.source_path))`（仓库外源片只有 path，没有 open_url）。
- 兼容：除 `_outputs.url` 外，现有字段只增不删；`source_url`（内嵌播放用）保持不变。

### 3.3 前端：一个 FileRow 组件 + 卡片图标两种形态

- `src/components/common/FileRow.vue`：props 只有 `{ entry }`；视频还是图片按后缀判断（不再加 `kind` 入参）。展示 name + `rel || path` + `formatSize` + 存在性（不存在标红"文件缺失"）；右侧链接只在 `entry.exists && entry.open_url` 时渲染，视频文案"播放"、其它"打开"，`target="_blank"`。
- 列表型面板替换：ExtractStep 的输出列表改为 `<FileRow>` 并改用 `open_url`（不再拼 `/media/extract`）；MergeStep 的合并输入/输出、pad 输出、裁回输出三组行改为 `<FileRow>`；合并页"成片"面板保留"整片/仅中间段"标注，只把 `href` 换成 `open_url`。
- 图片卡形态（GenerateAssets、KeyframeStep 的候选网格/底图/定稿卡）：卡角落加"打开"`el-link`，`title` 悬浮显示 `文件名\nrel 路径`（缺 rel 时显示绝对路径）。不做完整文件行（决策 4）。
- 候选网格的结构必须调整：KeyframeStep 的候选卡整体是 `<button>`（`KeyframeStep.vue:400-411`，点击即定稿），按钮内不能嵌链接（HTML 与可访问性都不合法，点击还会同时触发定稿）。做法是把打开链接做成按钮的兄弟节点、绝对定位在卡片角落，或改用容器 `div` + 独立"定稿"按钮；无论哪种，`@click` 不得冒泡到定稿。
- 选区页：播放器工具条下加一行 `<FileRow :entry="info.source_file">`。代理是派生缓存，不进文件视图。
- 生成记录：每轮（`GenerateResults`）行尾加 result.mp4 与 run.json 两个 `<FileRow>`；"最近成片"内嵌播放的代理未就绪回退改用 `open_url`。
- 对比页：不加文件行（决策 8）；右路代理未就绪回退改用 `open_url`。
- 类型同步：`FileInfo` 增 `open_url?: string | null`；`RawFrame`、`AssetDetail`、`KeyframePick`、`KeyframeRound.results` 各自补 `file`/`open_url`/`rel`；`OutputFile` 的 `url` 换成 `open_url`；`AssetRow`（`types/case.ts`）增 `rel`/`open_url`，并在 `GenerateStep.toAssetRow`（`GenerateStep.vue:165-179`）里透传——素材卡拿到的不是 `AssetDetail`，这一层不改就带不过去。
- 开发代理：`frontend/vite.config.ts` 的 `server.proxy` 增加 `/file`，否则 `npm run dev` 下新链接全部 404。

## 4. 工作包与验收

顺序：WP0 → WP1 → WP2 →（WP3、WP4）→ WP5。每个工作包独立跑门禁（后端 ruff+pytest / 前端 lint+typecheck+vitest）。

- **WP0 门禁与契约（优先，无新功能）**
  - `ci.yml` 的 test job 改为 `uv sync --extra dev --extra web`；现在只装 dev，`uv sync --extra dev --dry-run` 会卸载 starlette，web 测试在 CI 上收集即失败，WP1/WP2 的门禁不生效。
  - `vite.config.ts` 增加 `/file` 代理。
  - 本文件 §3.1/§3.2 的根表、`_open_root` 返回域、`open_url` 出现条件作为实现依据落定。
  - 顺手把 7 个存量未过 prettier 的前端文件复格式（仅换行与缩进，无行为改动）：`GeneratePrompt.vue`、`CompareStep.vue`、`ExtractStep.vue`、`PickStep.vue` 与三个对应单测。
  - 验收：`uv sync --extra dev --extra web --dry-run` 保留 starlette；本地 `uv run pytest tests/test_web_console.py` 全绿；`npm run lint`、`format:check`、`typecheck`、`test` 全绿。
- **WP1 `/file` 路由**：pytest 覆盖——`cases`/`sources`/`workdir` 三个根各取一个文件 200 且 Content-Type 正确；越界（`../`、绝对路径、盘符/UNC、URL 编码绕过、目录、不存在、未知 root）一律 404；mp4 带 Range 请求返回 206。测试用临时目录当三个根（workdir 按现有方式 monkeypatch），不依赖仓库内数据。
- **WP2 `file_entry` 接入**：pytest 断言上述每个数据源的条目带 `open_url`；不存在的文件与仓库外路径（临时目录之外）的条目字段齐全但**不带** `open_url`；`_outputs` 不再有 `url`；`_rounds` 每轮带 result 与 run_json 两个条目，且未采用轮次也有。现有 payload 字段（除 `_outputs.url`）不删。
- **WP3 FileRow 组件 + 删 `/media/extract`**：vitest（正常行、缺失行、视频/图片文案、无 `open_url` 时不渲染链接）；ExtractStep、MergeStep 替换后浏览器目检不回退；删除 `/media/extract` 路由与其测试（用例迁到 `/file`）。
- **WP4 图片卡图标**：GenerateAssets、KeyframeStep 候选/底图/定稿卡加打开链接与悬浮；vitest 断言链接 href、title，以及"点打开不触发定稿"。
- **WP5 补齐扩围 + 删 `/video/out`**：选区页源片行、生成记录逐轮文件行、合并页输入行；`_outputs` 消费方（GenerateResults、CompareStep）改用 `open_url` 后删除 `/video/out`；真浏览器逐页验收（每类资产：名字正确、rel 路径正确、打开后浏览器原生显示、缺失标红）。

## 5. 边界与不做

- `vp.png`、素材缩略图等"生成物"不进文件视图：它们不是磁盘资产，是渲染缓存。
- 仓库外的源片：显示路径、无打开链接（不开绝对路径口子）。
- 不改保留路由的任何行为；`/file` 只读，永不写。
- 台账文件只读展示，不触发任何 vrgen CLI——跨仓边界与现状一致。
- 不做"下载"与"打开"的分野（inline 打开即所见；需要另存由浏览器自身完成）。
- 对比页不加文件行：源片与成片在选区页、合并页、生成页已可查；对比页只负责看画面。
- 台账根的暴露面（含 run.json 的签名 URL）按 §3.1 记录；局域网开放时的鉴权不在本次范围。

## 6. 风险

- `/file` 是单点路由：白名单与越界校验必须有测试钉死（用例进 WP1），否则等于开了个任意文件读取口。单人本地工具的威胁模型有限，但机制要立住。
- `p` 归一化与包含判断必须跨平台：CI 同时跑 Windows 与 Ubuntu，URL 里用 posix 分隔符，服务端统一归一后再校验。
- 删除 `/media/extract` 与 `/video/out` 后，旧标签页/书签里的这两个地址会 404；单用户本地工具可接受，刷新页面即可。
- 轮次 result.mp4 是 8K 原片，独立页打开在软解环境会卡——用户已知并接受（决策 1 的语义就是"核对原始文件"）。
- `_keyframe_rounds` 给每张候选、`_rounds` 给每轮补 `_file_info` 会增加 stat 与小型 JSON 读；与 `_rounds` 现有的一次 vrgen 子进程相比可忽略，暂不引入缓存（硬规则 5 禁止模块级可变缓存）。
- 台账根白名单会把 `mglc.log`、`run.json` 里的签名 URL 暴露给能访问 serve 的客户端；本机单用户可接受，开放到局域网前必须重新评估。
