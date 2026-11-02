# 重打光前端的接入方案（relight）

状态：已实施（2026-10-30）。验收见 `docs/test-runs/20261030-relight-frontend.md`；
§10 的三条待确认已在实施中定案，§11 记录与本文的三处实质差异。上游：决策 48（图像版
`vrstudio relight`）与决策 56（视频版 `vrstudio relight-video`），
两者的方案与验收分别见 `docs/plan/relight-video-plan.md`、`docs/test-runs/20261030-relight-video.md`。

本文把两条 CLI 收成前端的一条 flow，并回答三个问题：relight 现在有什么能力、放到前端需要几个子页、
氛围图如何由用户手动指定并由美术加工后上传。

## 0. 结论

- **一条 flow，不是两条。** `FLOWS` 新增 `relight`，媒体类型由用户在素材步选定的 GT 文件决定，不新增
  `relightimg` / `relightvideo`。理由是一旦拆成两条，输入区、参数面板、结果区与对比页要各维护两份，
  而它们的差别只有参考帧、编码与小样三处。
- **建 case 时不绑源文件。** 照 `gen` 的既有模式：`case.create` 对 `relight` 允许 `source=None`，
  进入 case 后在素材步选定 GT 与氛围图。这条路径不需要新机制，`gen` 从 2026-10-19 起就是这么跑的
  （`docs/multi-asset-plan.md` §3.1、§10）。
- **CLI 合并成一个 `vrstudio relight`。** 按 GT 的文件类型内部派发到单帧路径或整段路径；视频专属参数在
  GT 是图片时按参数错拒绝，反之亦然。新增 `--sample N` 只渲染采样帧，供前端做小样预览。
  `relight-video` 退役，不保留别名。
- **子页清单：3 个向导步骤 + 2 处改动，0 个新独立路由。** 三个步骤是「素材」「重打光」「对比」，
  分别复用现有的素材选择/上传弹窗、任务队列与进度组件、360 A/B 对比器。两处改动是新建 case 弹窗的
  flow 选项、列表与任务页的标签。
- **氛围图只在本 case 内产生。** 两个固定槽位由 flow 钉死，用户可以从本 case 的素材库选已上传文件，
  也可以上传。美术对 fullRedrawImg 结果的手工加工在外部工具完成，上传时系统只记文件与哈希，
  不提供任何浏览器内改像素的入口，也不自动记录跨 case 的来源。
- **relight 不调平台、不花额度、不需要项目会话。** 因此生成页的会话门、配额提示与 adopt 语义都不适用于
  本流程，这是它与前五条 flow 最大的差别。

## 1. CLI 现在有什么（本方案直接复用）

`vrstudio relight`（图像版）与 `vrstudio relight-video`（视频版）都是「文件进、文件出」，不认 case、
不碰 vrgen。共同点与差异如下。

共同能力。

- 输入是 2:1 ERP 的 GT 加一张与 GT 同尺寸的氛围图；输出是同一网格上的重打光结果。
- 三道硬校验：GT 必须 2:1；氛围图必须逐像素同尺寸；对齐后结构重合度低于 0.15 时退出 1 且不出产物。
- 参数：`--scene night|day` 预设、`--strength 0..1`、`--local-shading 0..1`，缺省值来自场景预设
  （夜 1.0/0.35、日 0.8/0.2）。
- 高光软裁切：`--highlight-clip` 配合 `--clip-knee 0.72`、`--clip-max 0.98`。
- 台账：`--report` 写 JSON，含 `params` / `align` / `clip` / `light`。

只存在于图像版。

- `--dump-light` 额外出 light、gain、visibility 与六联对比四份诊断图。

只存在于视频版。

- `--ref-frame N` 指定对齐与估光照场用的帧；缺省时扫前 90 帧自动选与氛围图结构最相关的一帧。
- 一张氛围图只估一次对齐与光照场，整段逐帧复用；同位检查在最低重合度低于 0.94 时警告但不中断。
- `--crf 0..51` 覆盖编码质量；`--config` / `--set` / `--quiet`；音频用 `-c copy` 从 GT 带过来。
- 成本：8K 单帧约 3–4 秒，1 分钟成片约 30 分钟。

共同边界：氛围图只有一张且全程不变；不做超分、内容回填与补帧；机位移动时只警告，不逐帧重估。

## 2. 需求卡

### 2.1 角色与场景

内部制作与美术在本机工作站的浏览器里使用，单人本地工具，沿用现有的 case 归属与加锁，不引入并发与权限需求。
图像重打光要在十分钟内跑完一轮并反复调参；视频重打光一轮约半小时，必须在正式跑之前先看到效果。

### 2.2 任务与失败路径

主任务：当我要把 AI 氛围图的光照搬到真 GT 上时，我想在一个 case 里选定 GT 与氛围图、调好强度、先看小样
再出成片，以便不离开浏览器完成一次重打光，并让美术的加工结果能被同一套流程直接使用。

失败路径。

- GT 或氛围图任一槽位为空：重打光步禁用，并说明缺哪一项。
- GT 不是 2:1，或氛围图与 GT 尺寸不一致：任务失败，日志给出实际宽高。
- 对齐不可信：退出 1 且不产出文件，页面显示结构重合度与「换一个参考帧」的建议。
- 参考帧越界或选到黑场：给出可读原因，参考帧输入框保留用户填的值。
- 视频机位在动：仍然出片，页面显示同位检查的最低值并标注「适用于固定机位」。
- 上传中断：沿用现有分片上传的百分比与续传，不新做一套。

### 2.3 约束

- relight 不调平台、不花额度、不需要项目会话。生成页已有的会话门与配额提示必须对本流程不生效，
  否则会出现「没选会话就不能重打光」的假门。
- 8K 单帧 3–4 秒、1 分钟成片约 30 分钟，执行必须走现有任务队列并给进度，不能占住请求。
- 视频逐帧流式处理，不整片驻留内存（硬规则 5）。
- 不得把投影、几何或时间重采样的规则复制到 web 或前端（硬规则 3）。
- 不改 `clip.json`、`_pad.json`、`run.json` 三个冻结契约的字段集（硬规则 2）。
- 提交门禁是两仓库 `uv run pytest` 全绿加 `ruff` 干净；前端 `typecheck` / `lint` / `test` / `build` 全绿。

### 2.4 验收

以下每条都能在浏览器、日志或测试里观察到。

- 新建一个不带源文件的 relight case，进入后选图片 GT 与视频 GT 各一次，两次都能走到出片。
- 素材步显示两个槽位；槽位内容显示文件名、宽高，视频另显示帧数与时长。
- 参数面板在图片 GT 下不出现参考帧、小样与编码项，在视频 GT 下出现。
- 图像：跑出 PNG；对比页并排显示 GT 与成片。
- 视频：先小样后整段；小样条显示 N 张缩略图，整段出 MP4 且 GT 的音轨保留。
- 三条失败（GT 非 2:1、尺寸不一致、对齐不可信）各给出可读原因，且不留下半成品文件。
- 现有五条 flow 的步骤链与页面快照不回退。

### 2.5 范围三栏

现在必须做。

- `relight` flow 与不带源文件的建 case。
- 素材步的两个固定槽位，含从素材库选与上传两条入口。
- 参数面板、视频参考帧、N 帧小样预览、整段执行与进度。
- 对比页（视频复用 360 播放器，图片走静图对比）。
- 后端：`FLOWS`、建 case 分支、op 装配、门控链、产物表、当前成片指针。
- CLI：合并成一个 `relight`，新增 `--sample N`。

以后可以做。

- 同位检查结果的可视化报告（逐帧重合度曲线）。
- 逐帧重估与时间平滑，从而支持机位移动。
- 多张氛围图随时间切换。
- 跨 case 导入氛围图并自动记录来源。
- 成片重新作为素材，做二次迭代重打光。

明确不做。

- 浏览器内编辑氛围图像素：美术在 Photoshop 一类的外部工具里加工，本方案只负责接收上传结果。
- 氛围图的全局资产库、版本管理与「正式版」标记。
- relight 走 vrgen 或消耗平台额度。
- 超分、内容回填、补帧。
- 机位移动场景的处理。

### 2.6 优先级

第一优先是把图像版全链路跑通：它一次落地 flow 新增、空 case、两个槽位、参数面板、产物指针与对比页，
而且几秒一轮，可以反复验证。视频版只在其上补参考帧、小样与整段执行三处，不重复以上任何一件。

## 3. 子页清单

三个步骤都是现有向导里的步骤，不是新的独立路由；路由仍只有 `/case/:name/:step` 一条。

### 3.1 子页一：素材（`RelightAssetsStep.vue`）

这是用户的第一站，也承担「决定氛围图」的职责。

- 两个固定槽位，没有角色下拉：「重打光底版 GT」接受视频或图片，「氛围图」只接受图片。
  槽位由 flow 钉死，用户不能改角色，因此配错的状态无法构造。
- 每个槽位两个入口：从本 case 素材库选（复用 `AssetPickerDialog.vue`）、上传（复用
  `AssetUploadDialog.vue` 与现有分片上传会话）。
- 选完 GT 后显示媒体类型、宽高，视频另显示帧数与时长；页面按类型提示下游会多出参考帧与小样。
- 氛围图槽位旁显示与 GT 的尺寸是否一致；不一致只提示，真正的拒绝仍在 CLI。
- 空槽位不阻塞保存，只阻塞下一步。两个槽位都填好才允许进入「重打光」。

### 3.2 子页二：重打光（`RelightStep.vue`）

公共参数区。

- 场景预设（night / day）、strength、local-shading、高光软裁切三件套（开关 + knee + max）。
- 参数在上次运行后回填（来源是 case.toml 的 `[relight]` 段）。

视频专属区，仅在 GT 是视频时出现。

- 参考帧：默认「自动选取」，可切开成手填，0 起计。
- 小样预览按钮与帧数 N（默认 5，均匀采样）。
- 编码质量（crf），缺省留空表示用配置默认值。

执行区。

- 视频先出「预览 N 帧」，结果在小样条里并列展示，点击看大图；确认后才启用「开始重打光（整段）」。
- 图像没有小样环节，直接「开始重打光」。
- 两个动作都走现有任务队列与进度组件，日志尾部沿用任务详情页。

结果区。

- 成片打开入口（走 `/file` 白名单路由）。
- 报告数字：对齐内点数、结构重合度、缩放与旋转、增益均值与 p05/p95、可见度均值；视频另显参考帧号与
  同位检查最低值。

### 3.3 子页三：对比（`RelightCompareStep.vue`）

- 视频：复用现有 360 A/B 播放对比器，左 GT 右成片。
- 图片：静图并排；差异视图作为可选开关，不做进本轮必须项。
- 顶部显示报告摘要与「机位是否在动」的结论，让用户知道成片的前提是否成立。

### 3.4 两处改动，不新增页面

- 新建 case 弹窗：flow 下拉加「重打光」，选中后隐藏源文件选择（`gen` 已有这套分支）。默认 case 名不能
  再从源文件名推导，与 `gen` 一致。
- 列表与任务：case 列表的 flow 筛选与标签加一项；任务页的 op 标签加 `relight`。

## 4. CLI 对齐方案

目标是一个参数集合，web 与前端不需要按媒体维护两套组合。合并后的签名：

```text
vrstudio relight --case NAME [--sample N] [--ref-frame N] [--crf 0..51]
  [--scene night|day] [--strength 0..1] [--local-shading 0..1]
  [--highlight-clip] [--clip-knee 0.72] [--clip-max 0.98]
  [--report JSON] [--config TOML] [--set key=value]... [--quiet]

# 或者不吃 case 的文件模式（脚本、临时验证用）
vrstudio relight --gt GT --atmo ATMO --out OUT [同上]
```

- 派发依据是 GT 的扩展名（`case.kind_of` 的视频集合，其余按图片处理），不按内容探测：改名后的
  文件走错分支会被对应的读图/解流路径按真实原因报出来，代价比每次多探一次内容小。
- 类型专属参数用错时按参数错退出 2，错误文案指名哪个参数只适用于哪种 GT。这样错误状态在入口就被挡住，
  不靠文档提醒。
- `--sample N` 的行为：把 `--out` 当作目录（不存在则创建），写 `sample_<帧号>.png`，不写视频，并按
  时间点 seek 只解被采样的那几帧。小样默认跳过整段同位检查，因为那要解码全片，预览的目的就是快；
  给了 `--report` 时写一份带 `sample` 键的报告。
- `--case NAME` 以 case 为单位：GT 与氛围图取自两个槽位，产物写 case 的 `out/`，成功后回写
  `[relight] current`。它与 `--gt/--atmo/--out` 只能选一种——一份文件两个来源会让「case 里记的是
  哪张」变得含糊；产物命名因此也只有一个来源。
- `relight-video` 退役，不保留别名：保留别名会让 Help、文档与错误信息长期出现两套名字。
- 校验函数、报告构造器与参数解析继续共用现有实现（`resolve_params`、`_check_video`、`_check_inputs`、
  `build_report`），合并不重写引擎。

## 5. case 模型与后端改动

case 模型（`vrstudio/case.py`）。

- `FLOWS` 加 `relight`。
- `create` 对 `relight` 拒绝 `--source` 并且不写 `[source]`；`gen` 是「可选源」，relight 是「不接受源」，
  因为它的两份输入是槽位而不是母版。
- 素材库与槽位分离：`[[assets]]` 是同角色可多条的候选池（美术每改一版氛围图多一条），
  `[relight]` 的 `gt`/`atmo` 是用素材 id 表示的两把指针。角色固定为 `relight_gt`（视频或图片）与
  `relight_atmo`（只图片），在词表里是 `open=false`、`modes=[]`、`reserved=false`；标 `reserved`
  会被 `_add_assets_to` 拒绝，上传管线就走不通。指针指向不存在或角色不符的素材时，`load` 与 `save`
  都按真实原因拒绝。
- `master()` 增加 relight 分支：底版优先。现有回退链在「图片底版 + 图片氛围图」时会先取到氛围图，
  预览几何会错。
- 新增 `[relight]` 段：`gt` / `atmo`（槽位指针）、`current`（当前成片的相对路径）、上次的 `scene` /
  `strength` / `local_shading` / `highlight_clip` / `clip_knee` / `clip_max` / `ref_frame`。
  这是 flow 的唯一草稿段，键集合是一个常量，越界写入按真实原因拒绝。
- `add_relight_candidate`（加候选并选中，同 sha256 复用已有条目）与 `set_relight_pick`（只改指针）
  是 web 与 CLI 共用的两个入口。

后端（`vrstudio/web/app.py`）。

- `_op_argv` 加一个 op `relight`，body 里用 `sample` 布尔值区分小样与整段，不新增第二个 op。
  它只把面板参数翻成 flag 并带上 `--case`：槽位解析、产物命名与 `current` 回写都在 CLI 一处。
- `_gates` 加 relight 链：素材齐 → 可跑；有当前成片 → 可进对比。不加会话门、配额提示与 adopt 判据。
  现有 `_gates` 的 else 兜底在图片流程那一轮已经去掉，relight 必须显式登记，否则会落到未知 flow 的报错。
- `_step_files` / `_outputs` 按 flow 给 relight 的条目：两个槽位、当前成片；`_outputs` 同时收 mp4 与 png。
- `_selection_store` 对 relight 返回「该流程没有选区草稿」，与 `fullRedrawImg` 同一处理。
- `api_assets` 加 `op: slot`（`asset_id` 只改指针；`upload_ids`/`path` 加候选并选中）；
  `_case_info` 下发 `relight`（两个槽位、草稿、当前成片与报告、最近一次小样）；新增
  `POST /api/case/{name}/relight` 写草稿。
- `_prompt` 与 `_generation_params` 对 relight 中央短路：它不调 vrgen、也没有模板，逐个调用方加判断
  会漏（第一次就漏成了 500）。
- `video_source` 对 relight 发底版视频；`api_proxy` 对 relight 明确拒绝（没有 `[source]`，也就没有源片代理），
  对比页因此按原分辨率播放。
- 产物目录沿用 `out/`：整段写 `out/<时间戳>_relit.mp4` 或 `_relit.png`，报告写同名 `.json`，
  小样写 `out/samples/<时间戳>/sample_<帧号>.png`。

## 6. 前端改动

- `types/case.ts` 的 `Flow` 加 `'relight'`；`constants/steps.ts` 的 `FLOW_STEPS` 加
  `[素材, 重打光, 对比]`；`constants/flow.ts` 的 `flowMeta` 加「重打光」（`Record<Flow, …>` 会强制补齐，
  漏写编译不过）。
- 新增两个步骤组件：`RelightAssetsStep.vue`、`RelightStep.vue`；对比步不新写组件，按底版媒体
  扩展 `CompareStep.vue`（图片底版走静态并排、视频底版走 360 对比器，左路从「源片」改成指底版）。
- 复用而不重写：素材库选择与上传用 `components/assets` 与 `components/upload` 下现有弹窗
  （选择器新增 `title/hint/confirmText` 三个可选文案、上传弹窗新增 `destination="slot"`）；
  进度与日志用现有任务组件。
- 步骤页不出现任何 2:1、尺寸或强度范围的本地校验：错误由 CLI 按真实原因返回，前端只负责展示。

## 7. 工作包

### WP0：文档与契约立项

改动：`docs/case-model.md` 补 `relight` flow 的建 case 参数（不绑源）、两个素材角色、`[relight]`
草稿段与成片指针、产物清单；`docs/decisions.md` 登记三条决策（一条 flow 按媒体派发、CLI 合并、
氛围图只在本 case 内产生）；`AGENTS.md` 索引加本文；若 §10 待确认 1 选择新增角色，则 `docs/roles.json`、
`vrgen/src/vrgen/roles.json`、`vrstudio/src/vrstudio/roles.json` 三份同步改，并更新两仓库
`tests/test_roles_contract.py` 的 SHA256。

验收：文档能逐条对上代码现状；`uv run pytest` 全绿、`ruff` 干净。

### WP1：CLI 合并与 `--sample`

改动：`cli/relight.py` 的 `relight` 改为按 GT 类型派发；`relight-video` 退役；新增 `--sample N`；
视频专属参数在图片 GT 下按参数错拒绝；`cli/__init__.py` 的注册同步。

验收：原来图像版与视频版的全部断言在新命令下仍然通过（含 `--strength 0` 与光场复用的逐位一致）；
`--sample 5` 在 8K 素材上出 5 张 PNG 且不写视频；`--ref-frame` 配图片 GT 退出 2 且文案指出参数与类型；
`relight-video` 调用报未知命令。

### WP2：case 模型

改动：`FLOWS` 加 `relight`；`create` 允许无源；`master()` 加 relight 分支；`[relight]` 段读写与
`_RELIGHT_SECTIONS` 常量；两个固定素材角色的校验。

验收：`case new --flow relight` 不带 `--source` 成功且 `case.toml` 无 `[source]`；素材角色填错时被拒且
原因可读；`[relight]` 写入未知键被拒；旧 case 加载不受影响。

### WP3：web 后端

改动：`_op_argv` 的 `relight` op；`_gates` 门链；`_step_files` 与产物表；`_selection_store` 拒绝；
`api_assets` 放行；`_case_info` 下发结果与小样。

验收：pytest 对 `relight` 的 argv 快照（图片 GT 与视频 GT 各一份、小样与整段各一份）；门控在无素材 /
素材齐 / 有成片三种状态下的 reason 与 evidence 正确；未知 flow 仍报错；relight 不进会话门。

### WP4：前端页面

改动：`Flow` / `FLOW_STEPS` / `flowMeta`；新建弹窗；三个步骤组件；对比页媒体分支；列表与任务标签。

验收：§2.4 的验收项逐条通过；现有五条 flow 的页面快照不回退；`typecheck` / `lint` / `test` / `build` 全绿。

### WP5：真实素材端到端

改动：用现有的 8K GT 与一张 AI 氛围图跑通图片与视频各一轮，视频先小样后整段；结论写进
`docs/test-runs/`。

验收：图像成片的观感与 CLI 单跑一致；视频成片没有引入帧间闪烁（沿用 `20261030-relight-video.md` 的
帧间跳变口径）；耗时记录完整。relight 不花额度，这一步不受平台限制。

## 8. 契约与不动的东西

- 三条冻结契约（`clip.json`、`_pad.json`、`run.json`）不改。
- 唯一权威点不新增：重打光的对齐仍在 `relight/align.py`，光照场仍在 `relight/fields.py`，
  web 只做装配与展示。
- 现有五条 flow 的 case.toml 结构、步骤链与页面行为不动，只加标签。
- relight 不接 vrgen：不新增 vrgen 命令、模板或角色文本。
- op 集合只加 `relight` 一个；小样与整段共用，不拆成两个 op。

## 9. 风险

- CLI 合并触碰两条已验证的路径。图像版的逐位一致基线与视频版的强度 0 基线都必须在新命令下重跑，
  不能只跑新功能。
- 视频小样如果仍做整段同位检查，8K 一分钟素材的预览要等几分钟，预览就失去意义。WP1 必须让小样跳过
  全片检查，并把这个取舍写进 help。
- `master()` 的回退链是多个流程共用的，加分支时必须确认 patch / fullredraw / gen 的取值不变。
- 角色词表若选择新增，三份 `roles.json` 与两处 SHA256 任何一处漏改都会让契约测试红；改的时候一次改完。
- 半小时一次的视频重打光没有取消入口的话，参数调错只能等。任务队列的取消能力要在 WP3 一并确认。

## 10. 待确认（已在实施中定案）

1. **两个槽位的角色名。** 结论：新增 `relight_gt`（接受视频或图片）与 `relight_atmo`（只接受图片），
   但 `reserved=false` 而不是方案里写的 `true`——`_add_assets_to` 会拒绝用户给文件素材指定保留角色，
   上传管线就走不通。改为 `open=false` + `modes=[]`，同样不进任何生成页下拉与提交清单。
2. **当前成片指针的位置。** 结论：case.toml 新增 `[relight] current`，与抽取版本指针同构；
   不复用 `adopt_round`（语义是 vrgen 台账轮次）。
3. **小样的默认帧数。** 结论：5 帧，面板可改。实测 20 帧 8K 素材出 5 帧小样约 30 秒。

## 11. 实施记录（2026-10-30）

方案批准后一次做完，验收明细见 `docs/test-runs/20261030-relight-frontend.md`。与方案的三处实质差异：

- **槽位不再是角色本身。** 初版让「一个角色只能一条素材」，做到前端素材步时发现「从素材库选」永远
  没有候选——case 里除了槽位不许有别的东西。改成「`[[assets]]` 是候选池、`[relight]` 的
  `gt`/`atmo` 是两把 id 指针」，美术迭代氛围图才有地方放，也才对应用户「case 素材库里的已上传
  文件就是候选」的原话。
- **web 不再自己拼产物路径。** 增加 `relight --case`，槽位解析、时间戳命名与 `current` 回写全在
  CLI 一处，`_op_argv` 只翻 flag。
- **对比步没有新写组件。** 复用 `CompareStep.vue`：图片底版走静态并排，视频底版走 360 对比器，
  左路从「源片」改成指底版（`video_source` 对 relight 发底版视频）；relight 没有源片代理，
  右路标注「原始分辨率」。

实施中还修掉两个由本次改动引出的缺陷，细节见验收记录 §3：`POST /api/case/{name}/relight` 因
`template_for` 缺模板而 500（改为在 `_prompt`/`_generation_params` 中央短路），以及素材选择器把
生成流程的文案带进 relight 槽位选择。
