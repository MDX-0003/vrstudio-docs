# 360 图片两条流程（patchimg / fullRedrawImg）前端接入计划

状态：实施中（v2 已于 2026-10-30 获批；WP0–WP5 已实施，WP6 前端进行中，WP1/WP7 需要平台额度后才能做）。记录时间 2026-10-30。上游决策：决策 46（`docs/plan/360-img-gen-flows-plan.md`，patchimg 视口局部，WP2 已验收）与决策 47（`docs/plan/360-img-ab-routes-plan.md`，fullRedrawImg 已实现 CLI、真实额度一轮待跑）。

v2 修订依据（2026-10-30 评审）：flow 值保留 `patchimg` 与 `fullRedrawImg`；其余 `still` 相关命名按「媒体类型做前缀」统一为 `image`/`img`（§0.1，WP0 执行）；补齐图片模型与会话参数、门控 else 兜底、草稿段单一判定、真实额度轮前置四项；代码引用改为函数名为主、行号为辅。

## 0. 结论

- 目标：把 `patchimg`（360 图片视口局部重绘）与 `fullRedrawImg`（360 图片全幅 4K + 氛围参考重绘）作为与 patch（视频局部重绘）并列的 flow 开放到 web 前端。两条流程的输入与输出都是单张 2:1 ERP 图片，用户在浏览器里走完 建案例 → 选区（仅 patchimg）→ 抽取 → 生成 → 挑候选 → 贴回/拼接 → 对比 的完整链路。
- 交付形态：前端 flow 下拉从 3 项变 5 项，新增「图片·局部重绘」（patchimg）与「图片·全幅重绘」（fullRedrawImg）。两条新链都是「单张 2:1 ERP 图进、同尺寸 2:1 ERP 图出」，patchimg 保证选区外逐位不变，fullRedrawImg 以接缝闸门换整幅氛围重绘。
- CLI 的业务能力已就绪（§1），本计划对 CLI 的改动只有命名统一（§0.1）与数值域校验两项，不新增子命令、不新增 op、不新增 case.toml 字段。
- 对话中提出的两个前提缺口，逐条判定如下（硬规则：复述原文照抄，判定紧跟其后）：
  - 复述 1：「case 不接受起点为图片」。判定：这句话只对 web 前端成立。CLI 侧 `case new --flow patchimg|fullRedrawImg --source <erp.png>` 已接受图片源并做 2:1 比例校验与 sha256 守卫（`case.py` 的 `create` 内图片分支，2:1 判据与 sha256 钉死相邻）；web 侧 `api_cases` 对非 gen 流程强制要求 sources/ 里存在源视频（`app.py:1441-1442`），上传分支也只收视频后缀（`app.py:1414-1417`），所以图片源流程在 web 上建不了 case——真正的缺口是 web 这一段。
  - 复述 2：「cli 只能显式指定文件路径作为 inout，不接受以 case 为单位执行命令」。判定：不成立。两条图片流程的五步命令全部以 case 为单位执行（`extract name --case`、`generate submit --case`、`generate adopt --case --index`、`merge --case`），extract 与 merge 内部按 flow 分流（`cli/extract.py:236-265`、`cli/merge.py:384-392`），用户不需要给 CLI 传任何产物路径。
- 范围边界：本计划只做 patchimg 与 fullRedrawImg 两条并列流程。不含 A 路线分段链式与 case 分组（`360-img-ab-routes-plan.md` WP1/WP2 另案）、不含 img2video（决策 46 的 WP3 未开始）、不含 gen 整幅 360 缺口（决策 46 §3.4 登记的独立立项）。

## 0.1 命名统一（方案 A，WP0 执行）

`still` 是英文「静帧」的行话，中文读者要多一次映射；而且现有名字没有统一规则：`patch` / `patchimg`、`fullredraw` / `fullRedrawImg`（只差大小写）、`still` / `image_pad` / `img2video` 混着来。规则定为**媒体类型做前缀**：视频链保持现名，图片链统一 `image`/`img`。

- **flow 值不动**：`FLOWS` 仍是 `("patch", "patchimg", "fullRedrawImg", "fullredraw", "gen")`（`case.py:27`）。`patchimg` 与 `fullRedrawImg` 是用户拍定的对外名字，磁盘上已有 case.toml 据此写入，改它要迁移、收益又不抵成本。展示层用中文前缀区分媒体类型（§2.2）。
- **契约文件与产物改名**：`extracts/<版本>/image.json` → `image.json`；`extracts/<版本>/image_pad.json` → `image_pad.json`；`out/<版本>_image.png` → `out/<版本>_image.png`（与视频链 `_space.mp4`/`_frame.mp4` 的语义后缀命名法对齐）。
- **代码标识改名**：`redraw/image.py` → `redraw/image.py`；`tests/test_image.py` → `tests/test_image.py`；`StillGeometry`/`save_still`/`load_still` → `ImageGeometry`/`save_image`/`load_image`；`StillManifest`/`from_still_plan` → `ImageManifest`/`from_image_plan`；`plan_image`/`pad_image`/`stitch_image` → `plan_image`/`pad_image`/`stitch_image`；`StillError` → `ImageError`；`STILL_RATIO_LABEL` → `IMAGE_RATIO_LABEL`。
- **manifest 的 `kind` 字段值**：`image_pad.json` 里的 `"kind": "still"` → `"kind": "image"`，读取端同步校验（`redraw/manifest.py`）。
- **vrgen 模板名**：`img360-local` → `img360-local`（`cli/generate.py` 的默认模板值 + vrgen 的模板文件与台账显示名），两侧同一批改。
- **文档**：本文件已改名为 `docs/plan/img-flows-frontend-plan.md`；两份上游方案在 WP0 改名为 `360-img-gen-flows-plan.md` 与 `360-img-ab-routes-plan.md` 并替换正文用语；`AGENTS.md` 索引、`docs/architecture.md`、`docs/decisions.md` 的引用同步。
- **迁移方式**：一次性脚本按目录重命名已产出的 extract 文件与 out 文件，不做双读。代价可控——extract 不花额度，任何被改坏的 extract 目录重跑一次即可。`image_pad.json` 在 `redraw/manifest.py` 里被标注为 frozen external contract，按硬规则 2 先在 `docs/case-model.md` 立项（改名 + `kind` 值），再两侧改代码与测试。

## 1. CLI 已就绪的能力（本计划直接复用，不改）

- case 模型：`FLOWS` 已含两条图片流程（`case.py:27`）；图片源的 2:1 校验与 sha256 身份钉死（`case.py` `create` 的图片分支）；patchimg 的默认草稿函数 `patchimg_default_draft`（`case.py:634`）与草稿读写 `set_draft`（`case.py:645`，patchimg 拒绝 frames 段）、`draft_ready`（`case.py:667`）、`adopt_index`（`case.py:565`）；草稿段常量 `_PATCH_SECTIONS`/`_PATCHIMG_SECTIONS`/`_FULLREDRAW_IMG_SECTIONS` 是 flow→允许段的唯一权威。
- extract：`extract name --case` 按 flow 分流（`cli/extract.py:236-265`）——patchimg 的 `_extract_still` 写 `clip.png + clip_mask.png + image.json`（视口裁剪），fullRedrawImg 的 `_extract_full_redraw_img` 写 `padded.png + padded_mask.png + image_pad.json`（`plan_image` + `pad_image`）。
- generate：`submit --case` 对 patchimg 走 `assemble_still`（`cli/generate.py:412-431`）组装「视口图 + mask + 可选参考图」并由 `_submit_still`（545-581）提交；对 fullRedrawImg 走 `assemble_full`（473-506，参考上限 `image_max_refs` 断言在 498-502）并由 `_submit_full`（584-625）提交；flow 分流入口在 665-682。两条流程接受 `--resolution 1K|2K|4K`、`--num`、`--session-id`、`--image-model-id`（参数声明 630-660），拒绝 `--mode/--duration/--aspect-ratio/--scale/--var`（548-552、588-591）。`adopt` 对两条流程强制显式下标（`if index is None` 在 772-773，反向拒绝在 797-798）。
- 演练路径：`--check` 对两条图片流程同样有效（`_submit_still`/`_submit_full` 都接 `check`），即无额度也能跑通提交前的素材与提示词校验——这是 Playwright 验收不花钱的依据。
- merge：`merge --case` 按 flow 分流（`cli/merge.py:384-392`）——patchimg 的 `_merge_still` 走 `SegmentMaps.paste_inner`（194）只写 inner，fullRedrawImg 的 `_merge_full` 走 `stitch_image`（280-294）还原 2:1；两条都写 `out/<版本>_image.png`（202、306）。
- vrgen 侧：`img360-local`（改名后）与 `fullRedrawImg` 模板、`edit_master/mask/lighting_ref` 角色文本均已完成（ab-routes §0.1、决策 46 §0.1）。
- 测试：`tests/test_fullredraw_img.py` 与 `tests/test_patchimg.py` 守护 CLI 行为。
- web 已有的可复用挂点：`_rounds` 轮次列表走 vrgen `status --job`，图片轮次与视频轮次同一本台账（`app.py:508-528`）；`/file` 白名单只读路由已覆盖 workdir 根（`app.py:412、440`、路由 2914）；`keyframe_img`（`app.py:2369-2388`）按 `<case>/<round>/run.json` 的 `results[index-1]` 出图，**对任何 flow 都通用**，图片候选零改动即可展示；`api_browse` 的 `kinds=assets` 已同时列视频与图片（2886-2899）；`api_params` 已能把 `image_model_id` 与 `session_id` 写进 vrgen generation.toml（2425-2464）。

## 2. 缺口清单

### 2.1 web 后端（`web/app.py`）

- 建案例不接受图片源：`api_cases` 对非 gen 流程要求 sources/ 里存在视频文件（1441-1442）；上传分支只收视频后缀并把文件挪进 sources/（1407-1427，后缀检查 1414-1417）；`api_sources` 只列视频后缀（2880-2883）。需要让 patchimg/fullRedrawImg 接受图片源（sources/ 目录里的图片 + 上传图片两种入口），建案例后为 patchimg 写默认草稿（现在只有 patch 写，1459-1461；`patchimg_default_draft` 已存在但 web 没调）。
- op 装配缺参数透传：`_op_argv`（2622-2679）的 submit/dry_run 分支只透传 vars/resolution/scale/mode/duration/aspect_ratio（2640-2656），缺 `--num`、`--session-id`、`--image-model-id`；adopt 分支（2657-2661）不透传 `--index`，而 CLI 对两条图片流程强制下标（772-773），不补就会在 web 上必然报错。extract 与 merge 的 argv 以 case 为单位，两条图片流程可直接复用，不需要新 op——符合「共用优先」。
- 会话门只在首尾帧路径存在：`_current_session`（1958-1964）被 `_keyframe_argv` 用并要求 `> 0`（2035-2037），提示「图片生成按项目会话计费」。图片两条流程同样按会话计费，生成页必须走同一个门；模型与会话的持久值已有落点（`api_params` 的 `image_model_id`/`session_id`），不需要新存储。
- 门控链没有图片流程的分支，而且有 else 兜底：`_gates`（1160-1277）只有 patch（1183）、fullredraw（1234）与 else（1255，即 gen）三条分支。图片流程会静默落进 else，拿到 gen 的 `assets`/`generate` 步骤与 `result.mp4` 判据，页面不报错但全是错的门。补两条门链的同时要去掉 else 兜底，未知 flow 直接抛错（机制替代禁令）。
- 草稿段判定分散在端点：`api_draft` 明确拒绝非 patch（2476-2477）；`api_fov` 有显式 flow 门（2541-2542，报「只有 patch 有 fov 草稿」）；而 `get_store`（196-206）、`api_viewport`、`api_viewport_size`、`api_inner`、`api_nudge` 完全不校验 flow。后果是 fullRedrawImg 现在就能把 `[viewport]` 写进 case.toml，而该 flow 只允许 `[extract]`，`set_draft` 抛异常变成 500 而不是一句人话。收敛方式：web 只查 `case.py` 已有的三个 `_*_SECTIONS` 常量，越界段在任何端点之前按真实原因拒绝。
- 产物表缺条目：`_step_files`（1148-1157，分流 1151-1156）显式按三条 flow 分流，`_extracts`（1339）与 `_brief`（1479）只给 patch 列抽取版本；图片流程的 `clip.png/clip_mask.png/image.json`（patchimg）与 `padded.png/padded_mask.png/image_pad.json/report.json`（fullRedrawImg）需要进产物清单，out 的交付物是 `<版本>_image.png` 而不是 mp4。
- 素材步未放行图片流程：fullRedrawImg 必须挂 X 张 `lighting_ref` 参考图并写 `[submit] selected`（ab-routes §4 的挂载方式），patchimg 也接受可选参考图；`api_assets` 与提交集写入（`case_mod.add_assets`、`set_submit_selected` 已存在）需要对这两条 flow 放行。
- 候选图路由名与环境不符：`/img/keyframe/*`（路由 2916）处理器叫 `keyframe_img`，但取的是「任意 case 任意轮次的结果图」，与首尾帧无关。图片候选直接可用，只需要改名为 `/img/round/*` 并保留 404 语义，不新增路由。
- 数值域没有校验：`--num`（646-647）与 `--resolution`（641-643）的值域只写在 help 文案里。web 按计划透传 body 后，非法值会一路走到平台再报错。修在 CLI 层（`num` 1..4、`resolution` 1K|2K|4K 断言），web 保持纯透传。
- 静图对比缺后端支撑位：现有对比页围绕视频 A/B 播放与 seek；静图对比（源图 vs `out/<版本>_image.png`）需要的前端数据（两个文件的 open_url）产物表里已有来源，只需要前端组件；patchimg 的「选区外逐位不变」需要 `report.json` 的 `changed`/`maxdiff_outside` 一类字段透出，否则这条流程最关键的承诺在页面上不可见。

### 2.2 前端（`frontend/src`）

- 类型与步骤表：`Flow` 只有 `'patch' | 'fullredraw' | 'gen'`（`types/case.ts:1`）；`FLOW_STEPS` 只有三条链（`constants/steps.ts:17-21`）；`flowMeta` 是 `Record<Flow, …>`（`constants/flow.ts:3-7`），新增成员时 TypeScript 会强制补齐，这是好事。需要加 `'patchimg' | 'fullRedrawImg'` 与各自步骤链：patchimg = [选区, 抽取, 生成, 贴回, 对比]；fullRedrawImg = [抽取, 生成, 拼接, 对比]（无选区步）。
- 新建 case 弹窗：flow 下拉加两项，文案用媒体前缀区分——「图片·局部重绘」「图片·全幅重绘」，同时给视频链补前缀「视频·局部重绘」「视频·全画幅重绘」（纯标签改动，不动行为）；源选择从「sources/ 视频 + 上传视频」扩成按 flow 收图片；`CreateCasePayload` 的 `video` 字段语义扩展为源文件名（或加 `image` 字段，WP2 定）。
- patchimg 选区页：复用 patch 的几何画布（视口点击定位、inner 框、fov、视口尺寸档位），去掉时间轴 frames 段；inner 边界要画在预览上并提示「必须覆盖完整主体」（决策 46 §4.2 的失败路径）。
- 生成步：候选从视频轮次列表换成图片候选网格（N 张缩略图 + 人工挑一张提交 adopt，带 index）；提交参数从视频档（480p/720p/1080p、duration、scale）换成图片档（1K/2K/4K、num 1..4、image_model_id）；先选项目生成会话（与首尾帧同一条门）；参考图挂载入口（lighting_ref 多选）复用现有素材选择组件。patch 的首尾帧工作台组件模式（候选网格 + pick）可以直接借用。
- 贴回/拼接步：产物展示从视频换成大图（`out/<版本>_image.png`）；fullRedrawImg 要展示 `report.json` 的接缝闸门结论（band correlation、verdict）。
- 对比步：静图 A/B 并排（源图 vs 交付图）替代视频对比播放器；patchimg 增加差异视图（选区外与源图的逐像素差异高亮 + `changed`/`maxdiff_outside` 数字），否则用户无法自查这条流程的验收条件。
- 列表与任务：case 列表的 flow 筛选、标签文案加两条；任务列表的 op 标签沿用现有 op 集合（extract/submit/adopt/merge 不新增），不产生新的任务类型。

### 2.3 流程外围

- fullRedrawImg 的新形态（基图 + 必交 mask + lighting_ref）还没跑过真实额度轮：ab-routes §0.1 写明「先 1 张 1K 验证请求格式，再 4 张 4K」。这一轮必须在 web 开发开始前完成：请求格式若不成立，前端链路的参数装配方向要跟着改，先做页面等于白做。
- `docs/case-model.md` 需要核对两条图片流程的完整契约（五步命令、产物清单、命名统一后的文件名、`[adopt] index`、fullRedrawImg 的 `[submit] selected` 挂载、manifest 的 `kind` 值）是否已按现状写全；决策 46 WP0 与 ab-routes WP0 各写了一部分，本次统一核对补齐。
- 进度与任务态：web 队列按 argv 跑子进程，无流程耦合；但进度解析（phase 文案映射）需要核对图片流程 extract/merge 输出的 phase 名是否已被覆盖，缺的在映射表里补。

## 3. 需求卡（要点）

- 角色与场景：内部制作人员在本机工作站用浏览器处理 4K/8K 的 2:1 ERP 图片；单人本地工具，无并发与权限需求。
- 主任务：patchimg——框选视口与内部区域、写提示词变量、生成 N 张视口候选、挑一张贴回，得到选区外逐位不变的完整 ERP 图；fullRedrawImg——挂氛围参考图、生成 N 张全幅候选、挑一张拼接，得到接缝闭合的 2:1 成片。
- 失败路径沿用 CLI 已有约束，web 只负责把错误原样呈现：源图非 2:1 拒绝建案例（报实际宽高）；patchimg 的 inner 超出视口在 extract 被拒；候选未人工挑时 adopt 被拒；fullRedrawImg 的接缝闸门拒绝重构图候选；未选会话时提交被拒。
- 验收基线：两条流程在 Playwright 下各走通 新建 → （选区）→ 抽取 → 生成（`--check` 演练路径）→ 挑候选 → 贴回 → 对比；现有 patch/fullredraw/gen 三条链不回退。

## 4. 工作包

### WP0：命名统一与文档契约

改动：按 §0.1 执行全部改名（契约文件、产物、代码标识、manifest 的 `kind` 值、vrgen 模板名）；一次性迁移脚本处理已有 extract 与 out 文件；`docs/case-model.md` 立项并补全两条图片流程的契约（建案例的源图字段、五步命令、产物清单、adopt index、`kind` 值）；`docs/decisions.md` 登记命名决策与前端开放决策（决策号顺延）；`docs/architecture.md` 流程总图补两条 web 链并把两份上游方案改名；`AGENTS.md` 索引同步。

验收：文档索引可追溯；case-model 里的字段与 `case.py` 现状逐条对得上；`uv run pytest` 全绿、`ruff` 干净；迁移脚本对一个已有图片 case 跑完后 extract 与 merge 能重跑通过。

### WP1：fullRedrawImg 真实格式验证（原 WP6 前半，前移为门槛）

改动：按 ab-routes §3.5 跑 `--resolution 1K --num 1`，只验证「基图 + mask + X 张 lighting_ref」的请求格式与上传尺寸限制成立；结果写进 `docs/test-runs/`。

验收：请求被平台接受并出图；上报尺寸、参考图张数与耗时。若被拒，记录拒因并按拒因修订 §2.1 的装配方案再回到 WP2——这一步没过，后面不做。

### WP2：web 建案例接受图片源

改动：`api_sources` 列出图片后缀；`api_cases` 对 patchimg/fullRedrawImg 走图片源分支（sources/ 里的图片或上传图片；上传复用现有分片上传会话的收尾，图片体积小也可走单请求，实现时取更省的一条）；建案例后为 patchimg 写 `patchimg_default_draft`；fullRedrawImg 建完即可 extract。

验收：web 建两种图片 case 各一，case.toml 落盘字段与 CLI 建的逐字节等价；非 2:1 源图的报错文案带实际宽高；图片后缀集合取 `_IMAGE_EXTS`。

### WP3：op 装配、会话门、门控与产物表

改动：`_op_argv` 的 submit/dry_run 透传 `--num`、`--session-id`、`--image-model-id`（视频流程不受影响，缺省不传）；adopt 透传 `--index`（仅当 body 给出时追加）；`_gates` 加 patchimg 与 fullRedrawImg 两条门链并去掉 else 兜底；`_step_files`/`_extracts`/`_brief`/`_case_info` 补图片流程的产物与抽取版本；CLI 侧补 `--num` 与 `--resolution` 的值域断言。

验收：pytest 对 `_op_argv` 的图片流程 argv 快照（submit 带 num/resolution/model/session、adopt 带 index）；门控在无草稿/有草稿/已抽取/已采用各状态的 reason 与 evidence 正确；未知 flow 请求门控返回明确错误；非法 num/resolution 在 CLI 直接报出允许值。

### WP4：草稿段单一判定

改动：web 的草稿相关端点（`api_draft`、`api_fov`、`api_viewport`、`api_viewport_size`、`api_inner`、`api_nudge`、几何 store）改为统一查 `case.py` 的 `_*_SECTIONS` 常量：patchimg 放行 viewport/inner、仍拒 frames；fullRedrawImg 对所有草稿段返回「该流程没有选区草稿」的明确文案。

验收：patchimg 的 pick 草稿写入与读取往返；fullRedrawImg 写 viewport 得到 4xx 与可读文案而不是 500；`draft_ready` 缺段时门控放行理由正确。

### WP5：素材挂载与候选图路由

改动：`api_assets` 与提交集端点对两条图片流程放行；fullRedrawImg 挂 `lighting_ref` 并写 `[submit] selected`（复用 `case_mod.add_assets` + `set_submit_selected`，与链式脚本同一条路）；patchimg 的可选参考图同入口；`/img/keyframe/*` 改名为 `/img/round/*`，前端引用同步。

验收：fullRedrawImg 挂 1 张与 11 张参考图的 case.toml 结构正确；超上限在 submit 前被 `image_max_refs` 断言拦下且错误信息可读；图片候选能经 `/img/round/*` 与 `/file` 两条路径打开。

### WP6：前端页面

改动：`Flow` 类型与 `FLOW_STEPS`/`flowMeta` 加两条；新建弹窗的 flow 选项与图片源选择；patchimg 选区页（复用几何画布、去时间轴、inner 边界提示）；生成步的图片档参数、候选网格 + 挑 index、会话选择；贴回/拼接产物大图与接缝报告；静图对比页与 patchimg 差异视图；列表与任务标签。

验收：Playwright 按 §3 验收基线跑两条链；现有三条链的页面快照不回退。

### WP7：真实额度端到端与总验收

改动：两条流程各做一次真实端到端（fullRedrawImg 按 ab-routes §3.5 跑 `4K --num 4`）；额度不可用时记录在案；两仓库 `pytest` 全绿、`ruff` 干净。

验收：真实轮的接缝指标（band correlation 接近 1、verdict ok）与选区外 `maxdiff 0`（patchimg）写进 `docs/test-runs/`；验收记录落 main。

## 5. 契约与不动的东西

- `clip.json`、`_pad.json`、`run.json` 三个冻结契约字段集不变。`clip.json` 与 `_pad.json` 不因图片流程改动。
- 图片两条流程的 sidecar 由 `image.json`/`image_pad.json` 改名为 `image.json`/`image_pad.json`，字段集不变，`kind` 值改为 `image`；改名按硬规则 2 立项（WP0），两侧代码与测试同批改。
- 图片流程的 flow 值不变：`patchimg`、`fullRedrawImg`；case.toml 只读已有的 `FLOW` 值、`viewport/inner`、`[extract]`、`[submit]`、`[adopt] index` 字段，不新增字段。
- vrgen 的 CLI 契约不变（`image submit` 的 `--image-role` 仍是自由文本；模板与角色文本已完成），只有模板名按 §0.1 改名。
- web 的 op 集合不新增（extract/submit/dry_run/adopt/merge 复用），只补参数透传与门链；视频三条链的行为与测试不动，仅标签文案加媒体前缀。
- 唯一权威点不新增：patchimg 的几何仍在 `image.json` + `patch/projection`；fullRedrawImg 的几何仍在 `image_pad.json` + `redraw/*`；flow→允许草稿段仍在 `case.py` 的三个常量；web 只做装配与展示，不复制规则。

## 6. 风险

- fullRedrawImg 未跑过真实额度轮，请求格式问题会在前端首链路暴露——WP1 已前移为门槛。
- 改名横跨三处契约面（extract sidecar、out 产物名、vrgen 模板名），任何一处只改一半都会让 CLI 与 web 对不上；WP0 一次改完，并用一个已有 case 的 extract+merge 重跑做验收。
- 旧 extract 目录在改名后不再被识别：用一次性迁移脚本处理，不做双读；extract 不花额度，最坏情况是重跑一次。
- 候选网格的图片体积：4K 候选 PNG 单张数 MB，网格一次加载 N 张可能卡顿；用 `/img/round/*` 或 `/file` 直开原图时前端要做懒加载（缩略图路由作为后备方案，默认不加）。
- patchimg 的选区画布复用 patch 组件时，frames 相关的状态与校验要真的摘干净，否则会出现「静图流程要求时间段」的假门。
- 图片流程没有 `result.mp4` 这类统一「已采用」判据，门控 evidence 与产物表必须按 flow 给出各自的文件名，不能再共用视频的判据。

## 7. 待确认

1. 图片源的进入方式：默认「上传 + sources/ 目录手放」两种都收（与视频一致），后缀取 `_IMAGE_EXTS`。
2. fullRedrawImg 的参考图挂载入口放在生成页的引用条目（与 patch 一致，少一个步骤页）还是独立素材步（与 gen 一致）？默认生成页引用条目。
3. 视频链标签是否统一补「视频·」前缀（与两条图片链对称）？默认补，纯文案改动。
4. 候选缩略图默认用 `/img/round/*` 直开原图 + 前端懒加载，够不够用？若 4K PNG 加载体验差，再补一条只读缩略图路由（默认先不加）。

## 8. 实施记录（2026-10-30）

已完成：

- WP0：改名全部落地。契约文件 `image.json` / `image_pad.json`、产物 `out/<版本>_image.png`、vrgen 模板 `img360-local`、manifest 的 `kind: "image"`、模块 `redraw/image.py`、符号 `plan_image`/`pad_image`/`stitch_image`/`ImageGeometry`/`ImageManifest`/`ImageFlowError`（不能叫 `ImageError`：`media.imageio.ImageError` 已占用，两者在 `extract` 同一个 `except` 里都要用）。两份上游方案改名为 `360-img-gen-flows-plan.md`、`360-img-ab-routes-plan.md`，`AGENTS.md`/`architecture.md`/`decisions.md`/`case-model.md`/`decisions` 54 号同步。迁移脚本按目录改名已产出的 extract 与 out 文件（extract 不花额度，最坏重跑一次）。
- WP2：`api_cases` 按 flow 取后缀集合，图片流程收 2:1 图片源（`sources/` 与上传两条入口），建完为 patchimg 写 `patchimg_default_draft`；`api_sources` 返回 `files`/`videos`/`images`；2:1 校验仍是 `case.create` 一处，错误文案带实际宽高。
- WP3：`_op_argv` 的 submit/dry_run 透传 `--num`/`--image-model-id`/`--session-id`，adopt 透传 `--index`；`_gates` 加两条门链并去掉 else 兜底（未知 flow 直接抛错），`_step_files` 同样；`_extracts`/`_outputs`/`_derived`/`_case_info` 按 flow 给单帧产物；CLI 补 `--num 1..4` 与图片档 `1K|2K|4K` 的值域断言；`TEMPLATE_BY_FLOW` 补两条图片流程（否则 web 的提示词面板会 KeyError）；`_apply_mode_gate` 对图片流程直接跳过（参考图可选，不该被「必须勾选素材」挡）。
- WP4：选区类端点收敛到一个 `_selection_store`：只有 patch/patchimg 放行，其余流程返回「没有选区草稿」的 4xx；`api_draft` 放行 patchimg 且 `set_draft` 仍是「flow→允许段」的唯一权威（patchimg 传 frames 由它拒绝）。
- WP5：`/img/keyframe/*` 改名 `/img/round/*`（它取的是轮次结果，与首尾帧无关）；`api_proxy` 对图片流程明确拒绝；`api_assets` 原本就不按 flow 拦，图片参考图走同一条 `add_assets`。
- PreviewStore 增加图片源分支：单张图只解一次，`frame_count=1`、`fps=0`，解码结果直接作为第 0 帧工作副本，视口预览与几何写回沿用 patch 的同一条路。
- `_case_info` 新增 `adopt_index`、`image_rounds`（轮次与候选下标/URL）、`image_report`（merge 报告），供前端候选网格与对比页使用。
- WP6：前端已完成（`Flow` 类型与两条步骤链、新建弹窗按 flow 收源文件、patchimg 选区页去时间轴、图片生成面板（图片档/候选张数/图片模型/项目会话/候选网格与带下标的 adopt）、贴回与拼接页的大图与报告数字、图片对比页与 patchimg 差异高亮、列表与任务标签、`flowMeta` 统一切成媒体前缀）。图片流程的角色下拉用 `IMAGE_ROLE_MODE` 作词表上下文，并排除装配器自动附带的 `edit_master`。前端 `typecheck`/`lint`/`test`（115 条）/`build` 全绿。
- WP6 收尾（2026-11-02，条目 24）：图片生成页补任务日志与状态回显。任务块从 `GenerateResults` 抽成共用 `TaskPanel`，图片面板复用；状态在有本地运行态时用本地状态、否则按 `image_rounds` 最新有结果的轮次反推；候选改取「最新有结果的轮次」，已采用轮次常驻「查看大图 / 去拼接 / 去对比」入口；任务历史落盘到 `logs/tasks/<day>/tasks.jsonl`，serve 重启后仍能查日志尾巴。
- WP6 收尾（2026-11-02，条目 25）：图片对比页与视频同构。`Erp360Compare` 纹理来源抽象成视频或图片，图片对比页改为同一块 canvas、分割线、拖动转头、滚轮变焦、视角复位、全屏；右路默认最新成片并带下拉，新增「打开原图 / 下载」，`/file?download=1` 返回 attachment；不做差异高亮。
- 真实 case 冒烟（只读，新增四个修复）：
  - patchimg 的「重置选区」原来只认 `clip.json`，图片流程必定 400；`api_reset_draft` 改为按 flow 读 `image.json`，并对 fullRedrawImg 明确返回「没有选区草稿」。
  - `image_rounds` 的 `gate` 在台账里是对象（verdict/kind/images），原样下发会让页面显示 `[object Object]`；改为只下发 verdict 词。
  - fullRedrawImg 的提示词模板要 `canvas_w`/`band_w`/左右带列号，预览只传角色时 `rendered` 为空；`_prompt_preview_args` 补 `--canvas`/`--source`（按 sidecar 读几何，不写盘）。
  - 迁移脚本只改了文件名，manifest 内部的 `kind` 仍是 `"still"`，新读取端要求 `"image"` → 几何读不出来；迁移脚本补一步重写 `kind`，并在真实 case 上重跑。
- 测试：新增 `tests/test_web_image_flows.py`（24 条：op 装配、两条门链、建案例收图片源与非 2:1 拒绝、草稿段判定、重置选区、图片预览、候选路由与轮次下发、代理拒绝、CLI 值域）与迁移测试三条。vrstudio（排除并行工作中的 `tests/test_relight.py`）与 vrgen 的 pytest 全绿、ruff 干净。

未完成：

- WP1 fullRedrawImg 真实格式验证（1K×1）与 WP7 真实额度端到端：都要花平台额度，等用户确认后执行。
- 浏览器验收（Playwright 两条链、`--check` 演练路径）尚未跑：本轮只做到类型检查、单测与生产构建。
- `erp_test` 是视口局部改造前的实验 case，它的 extracts 是全幅 pad 结构（`image_pad.json`），flow 却是 patchimg；打开它会显示「未抽取」。需要时重跑一次 extract 即可，不做兼容。

迁移记录：`scripts/migrate_image_names.py` 已在本机真实 case 上跑过两次（先改名 11 个文件，后重写 6 个 manifest 的 `kind`）：`erp_test`、`frdi_day1`、`frdi_lo1` 的 `still_pad.json` 与 `out/*_still.png`，`wp2_live` 的 `still.json` 与 `out/*_still.png`；两次之后跑 dry-run 都是空计划，说明迁移可重复执行。改名后没有立刻重跑 extract+merge，第一次打开时按计划重跑一次即可（extract 不花额度）。
