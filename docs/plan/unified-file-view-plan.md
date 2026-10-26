# 统一文件视图方案：所有展示资产可查名、可查路径、可单独打开

状态：审查稿（待批）。记录时间：2026-10-26。
关联：`docs/key-issues/frontend-decisions.md`（前端决策惯例）、`docs/plan/frontend-review-fixes.md`（ExtractStep 文件行样板的出处）、`docs/case-model.md`（跨仓台账契约）。

## 0. 已确认的分支决策（2026-10-26，用户拍板）

1. **视频类资产点"打开"只加载原片**（源片、clip、成片、轮次结果），不跳代理。用户知道软解环境 8K 会卡，仍选原片——单独打开的目的就是核对原始文件。
2. **vrgen 台账文件（vrgen_runs/）纳入 web 直读**：首尾候选图片、生成轮次 result.mp4 与 run.json。轮次列表与候选图本就有读台账的先例（`_rounds`、`_keyframe_rounds`、`keyframe_img`），本方案延续"展示层只读、不改台账"的边界，与硬规则 1（交互走 CLI）不冲突。
3. **覆盖范围**＝用户点名（源片、首尾候选、选定图、重绘图/成片、素材）＋三项扩围：生成轮次原始结果与 run.json、选区页源片文件行、合并页输入文件行。
4. **图片卡展示密度**：卡上加"打开"图标，文件名与路径放悬浮提示（title）；完整文件行只用于文件列表型面板。

## 1. 需求

用户原话：

> 我接下来希望所有流程中展示到的资产，比如选区界面看到的原始视频、首尾帧的候选图片、选定后图片、重绘后图片等等，都能像抽取页的输出文件一样，能看到这个文件的名称、路径、且能在浏览器里跳转到单独页面打开查看。

样板是抽取页"输出文件"面板：文件名 + 仓库相对路径 + 大小 + "播放/打开"链接（`target="_blank"`，浏览器原生查看器）。

## 2. 现状盘点（2026-10-26 核实）

### 2.1 资产清单：位置、伺服路由、页面现状

| 资产 | 物理位置 | 伺服路由 | 页面现状 |
|---|---|---|---|
| 抽取输出（clip.mp4 / clip_mask.png / clip.json / 首尾原始帧） | `cases/<c>/extracts/<v>/` | `/media/extract/<c>/<v>/<f>` | ✅ 名字+rel 路径+大小+打开/播放（样板，ExtractStep） |
| 合并成片 / pad 产物 | `cases/<c>/out/`、case 根 | `/video/out/<c>/<f>`（+outproxy） | 名字+大小+下载链接；输入文件只有名字大小无链接（MergeStep） |
| 源片 / 全景代理 | `sources/`、`cases/<c>/derived/pick/` | `/video/source/<c>`、`/video/proxy/<c>` | 仅内嵌播放，无文件信息（PickStep / CompareStep） |
| 素材（上传图/视频、gen 母版、clip/pad 候选、选定首尾帧） | `cases/<c>/assets/`、extracts 等 | `/img/asset/<c>/<id>`（缩略） | 只有缩略图，无路径无打开（GenerateAssets.vue:47） |
| 首尾原始帧（工作台底图） | `extracts/<v>/first|last_frame_raw.png` | `/img/asset/<c>/<id>` | 工作台内嵌，无打开（`_raw_frames` 已带 path/size） |
| 首尾候选图片 | `vrgen_runs/<c>/img-*/`（跨仓台账） | `/img/keyframe/<c>/<round>/<i>` | 网格卡片，无路径无打开 |
| 生成轮次原始结果 + run.json | `vrgen_runs/<c>/<round>/` | **没有路由** | `step_files` 显示路径文本，点不开 |

### 2.2 同类性结论

- **数据层已同构**：除首尾候选外，所有资产在后端都能落成 `_file_info(path)`（`app.py:694`：name / rel（仓库相对路径）/ exists / mtime / size）；首尾候选与轮次结果在台账里也有绝对路径，同样能算 rel。
- **伺服层碎片化**：8 条路由语义各异——proxy 带构建逻辑、asset 带缩略、keyframe 按 run.json 寻址、extract 按版本号寻址；轮次结果完全没有路由。
- **展示层三种 UI**：文件行（ExtractStep/MergeStep）、图片卡（Assets/Keyframe）、内嵌播放器（Pick/Compare/Results），互不复用。

## 3. 设计

### 3.1 后端：一条受白名单约束的"原始文件直开"路由

- `GET /file?p=<仓库相对路径>`：只此一条新路由，承担"单独页面打开"这一件事。
- 白名单根（resolve 后必须落在界内，否则 404）：
  - cases 根（`_ctx["cases_root"]`，覆盖 case 内一切文件）；
  - `sources/`（外部源片）；
  - vrgen 台账根 `_workdir()`（跨仓只读）。
- 行为：仅 GET；`Content-Disposition: inline`；按后缀给 Content-Type（mp4/png/jpg/jpeg/json/toml/txt/log，未知名给 `application/octet-stream`）；FileResponse 天然支持 Range（视频可拖动）。
- 机制而非禁令：不维护"哪些后缀允许"的清单——白名单管位置，类型只影响浏览器怎么展示。
- 现有 8 条路由全部保留原职：内嵌播放、缩略、代理构建各有行为，`/file` 不重复它们的事；以后新增资产类型不再新增伺服路由。

### 3.2 payload：`file_entry(path)` 统一描述

- `{**_file_info(path), "open_url": "/file?p=<rel>"}`；`rel` 为 None（仓库外文件，如配置在别处的源片）时不带 `open_url`，页面显示路径但无打开链接——这是记录在案的边界，不为它开绝对路径口子。
- 接入点（现有函数逐个补 `open_url`）：
  - `_asset_details`（素材卡）；
  - `_raw_frames`（首尾底图，已有 path/size，补 rel/open_url）；
  - `_keyframe_rounds`（候选 results 逐张补 `_file_info` + open_url）；
  - `_generation_groups`（轮次原始结果与 run.json，已 `_file_info`，补 open_url）；
  - `_outputs`、`_patch_step_files`/`_fullredraw_step_files`/`_gen_step_files`（列表类 outputs/inputs）；
  - PickStep 的源片：`_case_info` 增加 `source_file: file_entry(case.source_path)`。

### 3.3 前端：一个 FileRow 组件 + 卡片图标两种形态

- `src/components/common/FileRow.vue`：props `{ entry, kind? }`；展示 name + rel（回退 path）+ formatSize + 缺失标红（"文件缺失"）+ 右侧链接（视频"播放"、其它"打开"，`target="_blank"`）。ExtractStep 的 file-row 结构抽出为该组件并替换；MergeStep 的 file-groups 行同样替换。
- 图片卡形态（GenerateAssets、KeyframeStep 的候选网格/底图/定稿卡）：卡角落加"打开"el-link；`title` 悬浮显示 `文件名\nrel 路径`。不做完整文件行（决策 4）。
- 选区页：播放器工具条下加一行 FileRow（源片）。代理是派生缓存，不进文件视图。
- 生成记录：每轮展开区（或行尾）加 result.mp4 与 run.json 两个 FileRow（GenerateResults）。
- 视频打开一律 `/file` 原片（决策 1）；对比页、选区页内嵌播放继续走代理，互不影响。

## 4. 工作包与验收

每个工作包独立跑门禁（后端 ruff+pytest / 前端 lint+typecheck+vitest）。

- **WP1 `/file` 路由**：pytest 覆盖——白名单内各根的文件 200、正确 Content-Type；越界（`../`、绝对路径、URL 编码绕过、目录而非文件、不存在）一律 404；mp4 带 Range 请求 206。
- **WP2 `file_entry` 接入**：pytest 断言上述每个数据源的条目带 `open_url`（仓库外源不带）；现有 payload 字段不删（前端兼容）。
- **WP3 FileRow 组件**：vitest（正常行、缺失行、视频/图片文案）；ExtractStep、MergeStep 替换后浏览器目检不回退。
- **WP4 图片卡图标**：GenerateAssets、KeyframeStep 候选/底图/定稿卡加打开链接与悬浮；vitest 断言链接 href 与 title。
- **WP5 补齐三处扩围**：选区页源片行、生成记录轮次文件行、合并页输入行；真浏览器逐页验收（每类资产：名字正确、rel 路径正确、打开后浏览器原生显示、缺失标红）。

## 5. 边界与不做

- `vp.png`、素材缩略图等"生成物"不进文件视图：它们不是磁盘资产，是渲染缓存。
- 仓库外的源片：显示路径、无打开链接（不开绝对路径口子）。
- 不改现有 8 条路由的任何行为；`/file` 只读，永不写。
- 台账文件只读展示，不触发任何 vrgen CLI——跨仓边界与现状一致。
- 不做"下载"与"打开"的分野（inline 打开即所见；需要另存由浏览器自身完成）。

## 6. 风险

- `/file` 是单点路由：白名单逻辑必须有测试钉死（越界用例进 WP1），否则等于开了个任意文件读取口。单人本地工具的威胁模型有限，但机制要立住。
- 轮次 result.mp4 是 8K 原片，独立页打开在软解环境会卡——用户已知并接受（决策 1 的语义就是"核对原始文件"）。
- `_keyframe_rounds` 给每张候选补 `_file_info` 会增加每轮列表的 stat 次数（每轮 ≤4 张 + run.json，量级可忽略）。
