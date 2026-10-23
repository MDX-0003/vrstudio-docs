# 实施路线图

每个里程碑有明确验收标准；M1 起"全绿"指 `uv run pytest` + `uv run ruff check .` 干净。

## M0 脚手架（本次交付）

- [x] E:\VRAIGC 工作区：AGENTS.md + docs/（architecture / case-model / decisions / roadmap）
- [x] vrgen、vrstudio 两仓库：git init（main）、uv 工程（3.11 + src layout）、pytest + ruff、CI workflow
- [x] CLI 骨架按契约声明全部子命令（stub），冒烟测试断言命令面
- [x] `uv sync --extra dev` 可装、`uv run pytest` 全绿、首提交完成

## M1 vrgen 最小可用（代码完成，真实额度下的一轮提交待验收）

- [x] 迁入 vrpad `aigc/platform|prep|round`（原样），重写 `jobs.py` + `cli.py` 的 submit（a35ee41）
- [ ] `vrgen submit --job t --refs refs.json` 完成一次真实 mglc 调用并落台账
  （原 `--input`/`--mask` 参数面已由决策 33 删除，验收按统一清单重跑）
  —— 调用链已真实化并有回归覆盖；受配额限制，真实素材的一轮完整提交还没跑过
- [x] `vrgen register --file` 手动后端写同构台账（M3 提前交付：`manual.py` 内容寻址注册 + run.json 契约 + `jobs.py` prompt-vars 自适应）
- [x] 断点续跑：submit 中断后重发不重复扣额度（a35ee41，task_id 防重发回归测试）
- 验收：用 fullredraw 的输入包（pad 画布 + mask）真实出一轮结果（与 M4 的 fullredraw 验收合并进行）

## M2 vrstudio 契约搬运（2026-10-16 完成，e2032f1）

- [x] `patch/`（vrpatch 核心库）、`redraw/`（vrpad 核心库）原样迁入，测试随迁（test_aigc 除外——属 vrgen；test_web_* 除外——属 M4）
- [x] `media/` 合并（videoio/binres ← vrpad，ffmpeg.py ← vrpatch；三档 profile 文档化于 media/__init__）
- [x] 分层 config（去 [aigc] 段）+ progress 合并（vrpatch 系改名 PhaseLog/PhaseRateMeter）
- 验收达成：随迁测试 170 个全绿。逐字节一致由 M3 的 ship_01 复现代偿——同源同配置下
  接缝指标与 vrpad 历史成片逐位一致（wrap 0.8928 / percentile 81.2 / worst 9.1598）。

## M3 generate 接线（2026-10-16 完成，vrgen c07b327 + vrstudio 4d1452c）

- [x] `cli/case.py`（new/list/show）+ 统一 case 模型库 `src/vrstudio/case.py` + `cli/generate.py`（输入包解析 → vrgen CLI 子进程 → adopt 落账）
- [x] fullredraw 全流程 CLI 跑通：case → pad → register/submit → adopt → recompose → out/
- 验收达成：合成素材 e2e（pytest，比例错的返回件也重组回源尺寸）+ ship_01 真实复现
  （同源 ship_ue.mp4，register vrpad 历史返回件，recompose 后 wrap/worst/帧数与历史
  报告逐位一致）。注意：submit 走 mglc 属 M1，本次验收以 manual 后端完成。

## M4 patch 流程 + web 控制台

- [x] patch 后端接线（2026-10-16）：统一 case 草稿 API（`set_draft`/`draft_ready`）、
  `vrstudio extract name --case`（草稿冻结进 extracts/，老式 case.toml 入口保留）、
  `vrstudio merge --case`（源哈希守卫 + extracts/<current> 自动定位 + out/ 默认落点；
  自动 restore/scalefit 本就内置于 merge）；ai-clip 注册即 `generate register/adopt`
  （M3 已交付，web 将直接调用）。测试 196 绿。
- [x] web 技术栈对比文档（决策 11）：`docs/web-stack.md`，推荐路线 A（沿用
  Starlette + jinja2 + 原生 JS），预留升 HTMX 的让步通道，否决前后端分离
- [x] web 骨架迁入与软向导（2026-10-16）：`src/vrstudio/web/`（app/tasks/render ← vrpatch
  迁入并接统一 case 模型；`serve` 命令落地，`--host 0.0.0.0` 支持局域网）。页面：case
  列表 + 向导（软向导门控判据全在服务端）；pick 交互原样迁入（点击定视口/拖框 inner/
  摇杆/逐帧）；generate 页轮次列表 + mglc.log tail；对比页同步播放 + 滑动分割线。
  patch 流程已浏览器验收（合成素材：建 case → pick → 队列抽取 → register → adopt →
  merge → out/ 成片对比，全程不离开浏览器）；fullredraw 向导页已实现（pad/recompose
  入队），待真素材验收。web 单测 14 个，总计 210 绿。
- [x] M4 后续迭代（2026-10-16 至 2026-10-19，依次落地）：
  - 提示词面板：模板正文只读 + 变量即改即存 + 自定义增删（995e700，决策 18）
  - 对比页改 360° 全景观看（erp360.js 双路共视角）与统一进度条/播放键（5954505）
  - 编码统一为浏览器可播的 H.264 420，废弃 444 与播放时转码（eddce06，决策 19）
  - 生成页输出/输入分辨率下拉并透传 submit 参数（e85828a，决策 20）
  - 文件信息显示仓库内相对路径、生成步骤拆分生成/采用两组（cdb7cdb、b42e4b9）
  - 任务栏每行带提交时间、历史扩到 10 条并分节（995e700）
- [x] gen 简单生成流程（2026-10-19，决策 21）：新增 `flow = "gen"`，向导只有生成一步；
  源视频直接上传，模板 `gen-edit`，采用结果落 `case/result.mp4`；参考图字段已预留。
- [x] gen 流程用 Simple_Anima_Test.mp4 做浏览器操作与 1080p 真实提交验收（2026-10-19）：
  浏览器建 case、填提示词、提交 1080p、采用结果全流程跑通；成片 1944×1066、
  289 帧、12.0 秒，白膜人物被替换为写实人物，背景与编辑器界面保持原样。
  首次提交因个人额度为 0 被拒；改用项目生成会话 `--session-id` 后成功（决策 22）。
- [x] 项目/剧集/会话选择器（2026-10-19，决策 22）：vrgen 新增 `sessions list` 只读命令，
  生成页三层联动下拉框，页面加载与刷新时重新获取会话树；选择结果写 `generation.toml`。
  方案与验收记录见 `docs/session-ui-plan.md`。
- [x] 生成模式可选（2026-10-19，决策 23）：模式下拉框由 `vrgen params show` 的模型能力生成，
  当前提供 videoEdit、allMediaRef、videoExtend；输出比例随模式联动，模式与比例写 `generation.toml`。
- [x] case 与多素材（2026-10-19，决策 24/25）：gen 不再要求源视频，创建时选模式；
  素材步骤管理有序 `[[assets]]`（视频+图片、手动角色、排序、删除、缩略图）；
  `vrgen submit --refs` 接多素材，台账按 `video:v1`/`image:i1` 分组，提交前做角色矩阵与
  限额校验；新增 `gen-multi` 模板与 `asset_list`/`task_rule`/`timeline_rule`。
  向导拆成 partials 与六个脚本；生成页新增免额度“检查提交命令”（`vrgen --dry-run`）。
  同时修复 Windows 管道下 vrgen 中文输出被按 GBK 写入、页面按 UTF-8 解码造成的乱码
  （子进程钉 `PYTHONUTF8`，读旧日志时按 UTF-8 → 本地代码页回退）；命令行 submit
  未显式给比例时不再补 `auto`，避免覆盖 `generation.toml` 里保存的 16:9。
  免额度浏览器验收通过，详见 `docs/multi-asset-plan.md` §10。
- [ ] 多素材真实 allMediaRef 提交与采用（需要平台额度；素材不合格的拒绝路径已用 dry-run 验证）
- 当前测试规模：vrgen 95 个 + vrstudio 258 个（含 web 44 个），合计 353 个，全绿；
  `uv run ruff check .` 两仓库干净（2026-10-19 核对）。
- [ ] fullredraw 向导页真素材浏览器验收（与 M1 配额解决后的真实 submit 一并做）
- 验收：两条流程各跑通一个真实 case，全程不离开浏览器

## M6 生成提交统一化与 patch 时间拼接（2026-10-21 实施完成）

- [x] 契约目标态：`docs/case-model.md` §2/§4/§5 已按统一提交重写，并按决策 33 改为
  「勾选即提交、没有默认集、clip/pad 为候选、mask 自动附带、raw 帧仅工作台、
  无 `derived` 标记」。
- [x] patch 合并产物改名迁移脚本（`scripts/migrate_out_names.py`，决策 31）。
- [x] vrgen：合并 `_prepare_single`/`_prepare_gen`，`submit` 只保留 `--refs`，删除
  `--input`/`--mask`，数量与格式校验切到模型详情 validator（决策 33/34）。
  台账删除 `params.input`/`params.mask`，轮次目录保存 `refs.json` 现场。
- [x] vrstudio：`extract` 产出 `first_frame_raw.png`/`last_frame_raw.png`；生成入口按
  flow 装配候选清单；`[submit] selected` 无默认集；前端空选集与 firstLastFrame 首尾帧
  不足的门禁（决策 33）。
- [x] patch 时间拼接 WP1–WP4：`merge` 输出 `_space.mp4`，新增 `vrstudio assemble`
  输出 `_frame.mp4`，web 两段连续队列，对比页按 `_frame` → `_space` 回退（决策 30–32）。
- 验收：dacne（patch clip + 三视图，mask 自动附带）、ship_01（fullredraw）、
  simple_gen_01（gen）的免额度 dry-run 全部走通；真实提交仍受平台额度限制。
- 测试规模：vrgen 121 个 + vrstudio 320 个，全绿；`uv run ruff check .` 两仓库干净
  （2026-10-21 核对）。

## M7 生成页可读性重构（2026-10-22 实施完成）

方案与最终口径见 `docs/generate-page-plan.md`，决策记录为 37。

- [x] 生成设置与扣费额度的控件整体迁入 fixed 底栏，页面主体不再出现这两个区域；
  主体只保留最近成片、素材、关键帧、提示词与外部成片。
- [x] 删除「生成记录与选用」，改为「最近成片」：有可用未采用轮次时给
  `[选用成片]`，已采用或只有预演轮次时不显示，最近一次失败时显示失败提示。
  采用仍走现有 `adopt` op，显式传轮次目录。
- [x] 提示词占位符改成 `{键|显示名|填写说明}`：vrgen 渲染时去掉后两段，
  `prompt show/save` 下发 `labels` 与 `help`；模板测试强制每个可编辑占位符
  都有显示名和说明。
- [x] 提示词卡片只保留显示名、键名与填写说明；输入框随内容增高；变量改防抖保存，
  提交与预演前先 flush，避免改完立刻提交发旧值。
- [x] 预演状态用页面输入快照判断是否过期（素材、参数、提示词、额度四组）；
  复用仍由 vrgen 的 `run_key` 在台账层保证，重复预演不新增轮次。
- [x] 删除生成页的 `log_tail` 输出与“自动填入”键列表；过程日志由任务面板承担。
- 验收：dacne（patch）、ship_01（fullredraw）、simple_gen_01（gen）页面手测；
  重复预演命中已有轮次；pytest 与 ruff 两侧全绿。
- 测试规模：vrgen 137 个 + vrstudio 320 个，合计 457 个，全绿；
  `uv run ruff check .` 两仓库干净（2026-10-22 核对）。
- 数据实验（不入库）：ship_01 提示词改为写实奇幻风暴，5 个白膜替换为船员
  idle/扶栏/炮位待命；情节、动作、允许变化三处已对齐。

## M8 首尾帧步骤（patch 实施完成；gen 待接）

方案见 `docs/keyframe-workbench-plan.md`，实施记录见其 §10。

- [x] 素材库与视频提交集拆分：图片步输入由 `keyframe.toml` 与原始帧解析，
  不读 `[submit] selected`；一个三视图可以同时服务两步，但两份输入声明互不影响。
- [x] patch 新增可选步骤「首尾帧」，插在抽取与生成之间；两帧大图、四个变量卡、
  分步候选与当前定稿标记。
- [x] 挑首帧后自动排队尾帧批次，尾帧用刚选的首帧作 图3；换首帧时旧尾帧指针清空、
  从视频提交集里取消勾选，旧素材保留。
- [x] 交接：写 `firstLastFrame` 模式与恰好一对提交集，跳到生成步骤；时长按 clip 推导。
- [x] vrgen：`keyframe-first`/`keyframe-last` 模板、`--vars-file`、
  `image submit --template/--step/--image-role`；`params.step` 进台账。
- [x] 图片任务走项目会话；修掉原先不传 `--session-id` 与尾帧默认参考图不指向实际素材的两个缺陷。
- [ ] gen 入口：需要上传两张原始帧的入口与存放位置。
- [ ] 真实图片提交与 firstLastFrame 提交（需额度）；首次提交后回填 R2/R7。
- 测试：vrgen 149 + vrstudio 342 = 491 个，全绿；两侧 ruff 干净（2026-10-23）。

## M9 前端重构（方案已确认，实施中）

方案与论证见 `docs/key-issues/20261023-frontend-stack-selection.md`，实施计划见 `docs/plan/frontend-refactor-plan.md`，决策为 38。

2026-10-23 进展：Phase 0 原型、设计令牌与 `/next` 托管已提交；Phase 1 的 case 列表、昵称身份、任务中心与会话选择器已接真实接口。

- [ ] Phase 0：需求卡、信息架构、设计令牌、case 列表与生成页原型、三项技术验证。
- [ ] Phase 1：新前端壳、case 列表、向导壳、任务中心只读，挂在 `/next`。
- [ ] Phase 2：生成页迁移、上传、提示词编辑、预演与提交，形成最小可用版本。
- [ ] Phase 3：选区、抽取、首尾帧、合并、对比迁移，WebGL 对比器包成组件。
- [ ] Phase 4：身份与归属、任务视图、版本检查、case 占用、扣费归属，切换默认入口。
- [ ] Phase 5：日志分层与索引，旧日志淘汰，任务原始输出与事件关联，见计划第 10 节。
- 验收：两位同事同时通过局域网使用，各自 case 与任务不串；旧前端可回退；pytest、ruff 与新增前端门禁全绿。

## M5 收尾

- [ ] 两仓库 README 交接规范（输入/输出/必须保留/规矩，沿用 vrpad 风格）
- [ ] 知识文档随迁归位；旧仓库（E:\360AIGC\vrpatch、vrpad）冻结归档并加指向
- 验收：新人（或 AI）只凭新仓库 README + AGENTS.md 能跑通两条流程
