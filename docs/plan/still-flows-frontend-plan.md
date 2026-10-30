# 360 静图两条流程（patchimg / fullRedrawImg）前端接入计划

状态：审查稿，待批。记录时间 2026-10-30。上游决策：决策 46（`docs/plan/360-still-gen-flows-plan.md`，patchimg 视口局部，WP2 已验收）与决策 47（`docs/plan/360-still-ab-routes-plan.md`，fullRedrawImg 已实现 CLI、真实额度一轮待跑）。

## 0. 结论

- 目标：把 `patchimg`（360 图片视口局部重绘）与 `fullRedrawImg`（360 图片全幅 4K + 氛围参考重绘）作为与 patch（视频局部重绘）并列的 flow 开放到 web 前端。两条流程的输入与输出都是单张 2:1 ERP 图片，用户在浏览器里走完 建案例 → 选区（仅 patchimg）→ 抽取 → 生成 → 挑候选 → 贴回/拼接 → 对比 的完整链路。
- CLI 两条链已经就绪，本计划不新增 CLI 能力；缺口集中在 web 后端的流程放行与前端页面。
- 对话中提出的两个前提缺口，逐条判定如下（硬规则：复述原文照抄，判定紧跟其后）：
  - 复述 1：「case 不接受起点为图片」。判定：这句话只对 web 前端成立。CLI 侧 `case new --flow patchimg|fullRedrawImg --source <erp.png>` 已接受图片源并做 2:1 比例校验与 sha256 守卫（`vrstudio/src/vrstudio/case.py:179-193`）；web 侧 `api_cases` 对非 gen 流程强制要求 sources/ 里存在源视频（`vrstudio/src/vrstudio/web/app.py:1427-1428`），上传分支也只收视频后缀（`app.py:1400-1403`），所以图片源流程在 web 上建不了 case——真正的缺口是 web 这一段。
  - 复述 2：「cli 只能显式指定文件路径作为 inout，不接受以 case 为单位执行命令」。判定：不成立。两条图片流程的五步命令全部以 case 为单位执行（`extract name --case`、`generate submit --case`、`generate adopt --case --index`、`merge --case`），extract 与 merge 内部按 flow 分流（`vrstudio/src/vrstudio/cli/extract.py:236-265`、`cli/merge.py:384-392`），用户不需要给 CLI 传任何产物路径。
- 范围边界：本计划只做 patchimg 与 fullRedrawImg 两条并列流程。不含 A 路线分段链式与 case 分组（`360-still-ab-routes-plan.md` WP1/WP2 另案）、不含 img2video（决策 46 的 WP3 未开始）、不含 gen 整幅 360 缺口（决策 46 §3.4 登记的独立立项）。

## 1. CLI 已就绪的能力（本计划直接复用，不改）

- case 模型：`FLOWS` 已含两条图片流程（`case.py:27`）；图片源的 2:1 校验与 sha256 身份钉死（`case.py:179-193`）；patchimg 的默认草稿函数 `patchimg_default_draft`（`case.py:634`）与草稿读写 `set_draft`（`case.py:645`，patchimg 拒绝 frames 段）；`draft_ready` 支持两条流程的「缺哪段」判据（`case.py:667-678`）；`adopt_index` 候选下标指针（`case.py:565-571`）。
- extract：`extract name --case` 按 flow 分流——patchimg 写 `clip.png + clip_mask.png + still.json`（视口裁剪），fullRedrawImg 写 `padded.png + padded_mask.png + still_pad.json`（`plan_still` + `pad_still`）（`cli/extract.py:148、184、236-265`）。
- generate：`submit --case` 对 patchimg 组装「视口图 + mask + 可选参考图」的 `vrgen image submit`（`cli/generate.py:365-382、414、546-572`），对 fullRedrawImg 组装「基图 + mask + lighting_ref 参考集」并断言参考上限（`cli/generate.py:436-501、585-616`）；两条流程接受 `--resolution 1K|2K|4K`、`--num 1..4`、`--session-id`，拒绝 `--mode/--duration/--aspect-ratio/--scale/--var`（`cli/generate.py:548-552、588-591`）。`adopt --index` 对两条流程强制显式下标（`cli/generate.py:751-783`）。
- merge：`merge --case` 按 flow 分流——patchimg 走 `composite_frame` 贴回只写 inner（`cli/merge.py:145`），fullRedrawImg 走 `stitch_still` 还原 2:1（`cli/merge.py:247`）；分流入口在 `cli/merge.py:384-392`。
- vrgen 侧：`still360-local` 与 `fullRedrawImg` 模板、`edit_master/mask/lighting_ref` 角色文本均已完成（ab-routes §0.1、决策 46 §0.1）。
- 测试：`tests/test_fullredraw_img.py` 与 patchimg WP2 测试集守护 CLI 行为。
- web 已有的可复用挂点：`_rounds` 轮次列表走 vrgen `status --job`，图片轮次与视频轮次同一本台账（`app.py:508-528`）；`/file` 白名单只读路由已覆盖 workdir 根（`app.py:412、440`），候选图与产物图可以不经新路由直接按 URL 打开；`api_browse` 的 `kinds=assets` 已同时列视频与图片（`app.py:2857`）。

## 2. 缺口清单

### 2.1 web 后端（`web/app.py`）

- 建案例不接受图片源：`api_cases` 对非 gen 流程要求 sources/ 里存在视频文件（`app.py:1427-1428`）；上传分支只收视频后缀并把文件挪进 sources/（`app.py:1393-1413`）；`api_sources` 只列视频后缀（`app.py:2844-2847`）。需要让 patchimg/fullRedrawImg 接受图片源（sources/ 目录里的图片 + 上传图片两种入口），建案例后为 patchimg 写入默认草稿（现在只有 patch 写，`app.py:1445-1447`；`patchimg_default_draft` 已存在但 web 没调）。
- op 装配缺参数透传：`_op_argv` 的 submit/dry_run 分支只透传 vars/resolution/scale/mode/duration/aspect_ratio（`app.py:2604-2620`），缺 `--num` 与 `--session-id`（图片流程要控制候选张数与额度会话）；adopt 分支不透传 `--index`（`app.py:2621-2625`），而 CLI 对两条图片流程强制 `--index`（`cli/generate.py:759-765`），不补就会在 web 上必然报错。extract 与 merge 的 argv 以 case 为单位，两条图片流程可直接复用，不需要新 op——符合「共用优先」。
- 门控链没有图片流程的分支：`_gates` 的步骤放行判据只为 patch 写全（`app.py` `_gates` 函数，fullredraw/gen 各有分支）；patchimg 需要 draft_ready → extract → adopt → merge 的门，fullRedrawImg 没有 pick 步、extract 直接可跑。
- 产物表缺条目：`_step_files` 显式按三条 flow 分流（`app.py:1135-1141`），`_extracts`/`_brief` 只给 patch 列抽取版本（`app.py:1325、1465`）；图片流程的 `clip.png/clip_mask.png/still.json`（patchimg）与 `padded.png/padded_mask.png/still_pad.json/report.json`（fullRedrawImg）需要进产物清单，out 的交付物是 `<版本>_still.png` 而不是 mp4。
- pick 草稿端点只放行 patch：`api_draft` 对非 patch 直接拒绝（`app.py:2440-2441`）；几何画布的 store 与 `viewport/viewport_size/fov` 端点也以 patch 为前提（`app.py:2505-2506`）。patchimg 的视口/inner 草稿需要同一条路放行（`case_mod.set_draft` 本身已支持 patchimg，只是 web 端点拦住了）。
- 素材步未放行图片流程：fullRedrawImg 必须挂 X 张 `lighting_ref` 参考图并写 `[submit] selected`（ab-routes §4 的挂载方式），patchimg 也接受可选参考图；`api_assets` 与提交集写入（`case_mod.add_assets`、`set_submit_selected` 已存在）需要对这两条 flow 放行。
- 候选图的展示服务：`/img/keyframe/*` 只服务 patch 首尾帧工作台（`app.py:2880`）；图片候选的缩略图入口需要补（默认用 `/file` 直开 workdir 里的候选文件，不新增路由；若前端需要缩略图尺寸再加只读路由）。
- 静图对比缺后端支撑位：现有对比页围绕视频 A/B 播放与 seek；静图对比（源图 vs `out/<版本>_still.png`）需要的前端数据（两个文件的 open_url）产物表里已有来源，只需要前端组件。

### 2.2 前端（`frontend/src`）

- 类型与步骤表：`Flow` 只有 `'patch' | 'fullredraw' | 'gen'`（`types/case.ts:1`）；`FLOW_STEPS` 只有三条链（`constants/steps.ts`）。需要加 `'patchimg' | 'fullRedrawImg'` 与各自步骤链：patchimg = [选区, 抽取, 生成, 贴回, 对比]；fullRedrawImg = [抽取, 生成, 拼接, 对比]（无选区步）。
- 新建 case 弹窗：flow 下拉加两项（文案要与视频全景重绘 fullredraw 明确区分，例如「360 图片·局部重绘」「360 图片·全幅重绘」）；源选择从「sources/ 视频 + 上传视频」扩成按 flow 收图片；`CreateCasePayload` 的 `video` 字段语义扩展为源文件名（或加 `image` 字段，WP1 定）。
- patchimg 选区页：复用 patch 的几何画布（视口点击定位、inner 框、fov、视口尺寸档位），去掉时间轴 frames 段；inner 边界要画在预览上并提示「必须覆盖完整主体」（决策 46 §4.2 的失败路径）。
- 生成步：候选从视频轮次列表换成图片候选网格（N 张缩略图 + 人工挑一张提交 adopt，带 index）；提交参数从视频档（480p/720p/1080p、duration、scale）换成图片档（1K/2K/4K、num 1..4）；参考图挂载入口（lighting_ref 多选）复用现有素材选择组件。patch 的首尾帧工作台组件模式（候选网格 + pick）可以直接借用。
- 贴回/拼接步：产物展示从视频换成大图（`out/<版本>_still.png`）；fullRedrawImg 要展示 `report.json` 的接缝闸门结论（band correlation、verdict）。
- 对比步：静图 A/B 并排（源图 vs 交付图），替代视频对比播放器。
- 列表与任务：case 列表的 flow 筛选、标签文案加两条；任务列表的 op 标签沿用现有 op 集合（extract/submit/adopt/merge 不新增），不产生新的任务类型。

### 2.3 流程外围

- fullRedrawImg 的新形态（基图 + 必交 mask + lighting_ref）还没跑过真实额度轮：ab-routes §0.1 写明「先 1 张 1K 验证请求格式，再 4 张 4K」。前端开放前应先完成这一轮，否则第一条真实用户链路就是首次平台验证，失败会直接砸在页面上。
- `docs/case-model.md` 需要核对两条图片流程的完整契约（五步命令、产物清单、`[adopt] index`、fullRedrawImg 的 `[submit] selected` 挂载）是否已按现状写全；决策 46 WP0 与 ab-routes WP0 各写了一部分，本次统一核对补齐。
- 进度与任务态：web 队列按 argv 跑子进程，无流程耦合；但进度解析（phase 文案映射）需要核对图片流程 extract/merge 输出的 phase 名是否已被覆盖，缺的在映射表里补。

## 3. 需求卡（要点）

- 角色与场景：内部制作人员在本机工作站用浏览器处理 4K/8K 的 2:1 ERP 静图；单人本地工具，无并发与权限需求。
- 主任务：patchimg——框选视口与内部区域、写提示词变量、生成 N 张视口候选、挑一张贴回，得到选区外逐位不变的完整 ERP 图；fullRedrawImg——挂氛围参考图、生成 N 张全幅候选、挑一张拼接，得到接缝闭合的 2:1 成片。
- 失败路径沿用 CLI 已有约束，web 只负责把错误原样呈现：源图非 2:1 拒绝建案例（报实际宽高）；patchimg 的 inner 超出视口在 extract 被拒；候选未人工挑时 adopt 被拒；fullRedrawImg 的接缝闸门拒绝重构图候选。
- 验收基线：两条流程在 Playwright 下各走通 新建 → （选区）→ 抽取 → 生成（--check 演练路径）→ 挑候选 → 贴回 → 对比；现有 patch/fullredraw/gen 三条链不回退。

## 4. 工作包

### WP0：文档与契约核对

改动：`docs/case-model.md` 补全两条图片流程的 web 视角契约（建案例的源图字段、五步命令、产物清单、adopt index）；`docs/decisions.md` 登记本决策（两条图片流程前端开放，决策号顺延）；`docs/architecture.md` 流程总图补两条 web 链；AGENTS.md 索引本文。

验收：文档索引可追溯；case-model 里的字段与 `case.py` 现状逐条对得上。

### WP1：web 建案例接受图片源

改动：`api_sources` 列出图片后缀；`api_cases` 对 patchimg/fullRedrawImg 走图片源分支（sources/ 里的图片或上传图片；上传复用现有分片上传会话的收尾，图片体积小也可以走单请求，实现时取更省的一条）；建案例后为 patchimg 写 `patchimg_default_draft`；fullRedrawImg 建完即可 extract。

验收：web 建两种图片 case 各一，case.toml 落盘字段与 CLI 建的逐字节等价；非 2:1 源图的报错文案带实际宽高。

### WP2：web op 装配与门控

改动：`_op_argv` 的 submit/dry_run 透传 `--num`、`--session-id`（视频流程不受影响，缺省不传）；adopt 透传 `--index`（仅当 body 给出时追加）；`_gates` 加 patchimg 与 fullRedrawImg 两条门链；`_step_files`/`_extracts`/`_brief`/`_case_info` 补图片流程的产物与抽取版本。

验收：pytest 对 `_op_argv` 的图片流程 argv 快照（submit 带 num/resolution、adopt 带 index）；门控在无草稿/有草稿/已抽取/已采用各状态的 reason 与 evidence 正确。

### WP3：patchimg 选区页后端放行

改动：`api_draft` 放行 patchimg（viewport/inner 段，frames 仍拒）；几何 store 与 `viewport/viewport_size/fov` 端点对 patchimg 放行；fullRedrawImg 维持「没有选区草稿」的拒绝路径并给出正确文案。

验收：patchimg 的 pick 草稿写入与读取往返；`draft_ready` 缺段时门控放行理由正确。

### WP4：素材与提交集挂载

改动：`api_assets` 与提交集端点对两条图片流程放行；fullRedrawImg 挂 `lighting_ref` 并写 `[submit] selected`（复用 `case_mod.add_assets` + `set_submit_selected`，与链式脚本同一条路）；patchimg 的可选参考图同入口。

验收：fullRedrawImg 挂 1 张与 11 张参考图的 case.toml 结构正确；超上限在 submit 前被 `image_max_refs` 断言拦下且错误信息可读。

### WP5：前端页面

改动：`Flow` 类型与 `FLOW_STEPS` 加两条；新建弹窗的 flow 选项与图片源选择；patchimg 选区页（复用几何画布、去时间轴、inner 边界提示）；生成步的图片档参数与候选网格 + 挑 index；贴回/拼接产物大图与接缝报告；静图对比页；列表与任务标签。

验收：Playwright 按 §3 验收基线跑两条链；现有三条链的页面快照不回退。

### WP6：真实额度与总验收

改动：fullRedrawImg 按 ab-routes §3.5 跑真实额度轮（1K×1 验证请求格式，再 4K×4）；两条流程各做一次真实端到端（或以额度不可用时记录在案）；两仓库 `pytest` 全绿、`ruff` 干净。

验收：真实轮的接缝指标（band correlation 接近 1、verdict ok）与选区外 `maxdiff 0`（patchimg）写进 `docs/test-runs/`；验收记录落 main。

## 5. 契约与不动的东西

- `clip.json`、`still.json`、`still_pad.json`、`run.json` 的字段集不变；case.toml 只读已有的 `FLOW` 值、`viewport/inner`、`[extract]`、`[submit]`、`[adopt] index` 字段，不新增字段。
- vrgen 的 CLI 契约不变（`image submit` 的 `--image-role` 自由文本、模板与角色文本已完成）。
- web 的 op 集合不新增（extract/submit/dry_run/adopt/merge 复用），只补参数透传；视频三条链的行为与测试不动。
- 唯一权威点不新增：patchimg 的几何仍在 `still.json` + `patch/projection`；fullRedrawImg 的几何仍在 `still_pad.json` + `redraw/*`；web 只做装配与展示，不复制规则。

## 6. 风险

- fullRedrawImg 未跑过真实额度轮，请求格式问题会在前端首链路暴露——WP6 排在开放之前或同批最先执行。
- 候选网格的图片体积：4K 候选 PNG 单张数 MB，网格一次加载 N 张可能卡顿；用 `/file` 直开原图时前端要做懒加载或按需打开（缩略图路由作为后备方案）。
- 前端 flow 命名 `fullRedrawImg` 与既有 `fullredraw` 只差大小法，代码里容易写混；类型层用字面量联合约束，文案层用「图片·全幅重绘」与「视频·全景重绘」区分。
- patchimg 的选区画布复用 patch 组件时，frames 相关的状态与校验要真的摘干净，否则会出现「静图流程要求时间段」的假门。

## 7. 待确认

1. 图片源的进入方式：默认「上传 + sources/ 目录手放」两种都收（与视频一致）；要不要限制图片后缀集合为 `_IMAGE_EXTS`（默认是）。
2. fullRedrawImg 的参考图挂载入口放在生成页的引用条目（与 patch 一致，少一个步骤页）还是独立素材步（与 gen 一致）？默认生成页引用条目。
3. 前端开放是否以 WP6 的真实额度轮通过为门槛？默认是（先跑通再开放，避免首链路即首次平台验证）。
4. 候选缩略图默认用 `/file` 直开原图 + 前端懒加载，够不够用？若 4K PNG 加载体验差，再补一条只读缩略图路由（默认先不加）。
