# case 与多素材模型方案

本文记录“新建 case 不再依赖单个视频、首个步骤选定多个素材”的改造方案。它针对当前 `simple_gen_01` 这类“从单个视频出发”的 case 模型；多素材生成、参考图和模式切换需要新的数据结构与页面流程。状态：已实施（2026-10-19），免额度验收通过；真实 allMediaRef 提交待额度。

## 1. 问题来源

当前 gen 流程默认一个 case 只对应一个源视频：

- 创建 case 时必须指定一个视频，`case.toml` 的 `[source]` 只有一条路径。
- `generate` 把这条路径直接作为唯一输入上传。
- 模板里只有 `<视频1>`，没有 `@Video2`、`@Image1` 这样的多素材指代。
- 模式切换后，`allMediaRef` 理论上可以接收多个视频、图片和音频，但现有接口只能给一个视频和一张 mask。

这在结构上把“项目”绑死在一个视频上。实际上项目是一组素材与生成意图，视频、图片、角色参考和场景参考都只是素材。VideoEdit 实验失败后要切换到 `allMediaRef`，这个限制就变成了硬阻塞。

## 2. 目标

- 新建 gen case 时不再要求视频；创建时必须选择生成模式，模式决定需要哪些素材。
- gen 的第一个步骤是“素材”，可以添加多个视频与图片，并为每个素材手动指定角色。
- 素材复制进 `cases/<name>/assets/`，case 自带所需文件，不依赖外部路径长期存在。
- 生成参数、提示词、会话选择、任务队列继续复用现有能力。
- gen 页面与 patch/fullredraw 页面分开设计，公共部分抽出来复用，不维护两份相同逻辑。
- gen 页面只有“素材”和“生成”两步，不包含对比页。
- 旧 case 与旧流程保持可用；patch 与 fullredraw 仍然以单个源视频为起点。

## 3. case 模型改造

### 3.1 创建参数

新建 case 的参数改为：

- `flow`：必填，`gen` / `patch` / `fullredraw`。
- `mode`：`flow = gen` 时必填，表示这个 case 计划使用的生成模式；patch 与 fullredraw 的模式由流程固定，不需要用户选择。
- 源视频：`flow = gen` 时可以为空；`flow = patch` 与 `flow = fullredraw` 仍然必填，因为这两个流程的几何与合成都围绕单个源视频。

gen case 创建成功后，页面立即调用 `vrgen params save --job <case名> --mode <模式>`，把模式写进 `runs/<case名>/generation.toml`。`case.toml` 不保存模式；模式的唯一权威仍然是 `generation.toml`。素材步骤通过 `vrgen params show` 读回模式，再按模型能力决定需要哪些素材。

为此，`params save` 的分辨率与缩放在新建 case 阶段需要允许缺省，未提供时保留已有值或使用配置默认值；`params show` 也需要允许在没有视频、没有画布尺寸时只返回模式列表与当前模式。输入尺寸、输出档位这些依赖素材的字段，等素材步骤选好后再计算。

如果写模式失败，页面要明确提示，不能让用户以为模式已经保存。此时 case 目录已经创建，可以重试写模式，不需要重建 case。

### 3.2 case.toml 结构

gen case 只增加素材列表，不增加模式字段：

```toml
flow = "gen"

[[assets]]
id = "v1"
kind = "video"
path = "assets/v1_main.mp4"
role = "edit_master"
sha256 = "…"

[[assets]]
id = "v2"
kind = "video"
path = "assets/v2_motion_ref.mp4"
role = "motion_ref"

[[assets]]
id = "i1"
kind = "image"
path = "assets/i1_character.png"
role = "subject_ref"
```

字段说明：

- `assets` 是有序数组；顺序决定提示词里的 `@Video1`、`@Video2`、`@Image1` 编号。
- `id` 在 case 内唯一，用于前端引用、文件校验与台账映射。
- `kind` 只允许 `video` 与 `image`；本期不支持音频。
- `role` 使用受控词表：`edit_master`（编辑母版）、`motion_ref`（动作参考）、`scene_ref`（场景参考）、`subject_ref`（主体参考）。角色由用户在素材步骤手动选择，不按顺序自动推断。
- 素材文件复制进 `cases/<name>/assets/`，`path` 相对 case 目录；文件名建议带素材 `id` 前缀，避免同名覆盖。
- `sha256` 可选；添加素材时计算，提交前校验，防止素材被替换后仍按旧配置生成。
- 旧 gen case 的单视频加载时自动映射为一条 `assets`，`role = "edit_master"`；首次迁移时把源视频复制进 `cases/<name>/assets/` 并改写 `path`。`[gen] reference_images` 预留字段迁移为 `kind = "image"` 的素材。

### 3.3 本期支持的生成模式

本期只做三种与视频素材相关的模式：

- `videoEdit`：至少 1 个视频，第一个是编辑母版；可附加图片作为主体参考。动作与时间轴跟随输入。
- `allMediaRef`：多个视频与图片，具体数量上限来自模型能力；每个素材必须指定角色。输出不锁定输入的时间轴，可以重新生成动作。
- `videoExtend`：1 个视频作为延长母版；可附加图片参考。

本期不做 `firstFrame`、`firstLastFrame`、`text2video`，也不做音频素材。这些模式留到多素材模型稳定之后。

模式要求来自模型能力，不在前端写死：

- 从 `vrgen params show` 的 `modes` 列表取可用模式、比例、数量上限。
- 从 `mglc model` 的参考素材校验字段取视频/图片的格式、时长、帧率、像素与体积限制。
- 页面按当前模式显示“需要哪些角色、最多几个素材”，但不在前端判定素材是否合格。

## 4. 前端交互

### 4.1 创建 case

新建 case 面板改为：

- 选择流程；选择 `gen` 时出现模式下拉框，选项来自模型能力。
- gen 不再要求选择视频；patch/fullredraw 保留素材选择。
- gen 创建成功后立即写模式到 `generation.toml`，成功后进入 case 的素材步骤。
- case 名缺省仍可由用户填写；没有视频时不能再用视频文件名做默认名。

### 4.2 gen 的“素材”步骤

素材步骤包含：

- 添加按钮：一次可以选择多个视频或图片。
- 复制：选中的文件复制到 `cases/<name>/assets/`，case.toml 记录相对路径与哈希。
- 素材卡片：显示文件名、类型、尺寸、时长、首帧缩略图、角色下拉框、删除按钮。
- 角色选择：用户手动选择 `edit_master`、`motion_ref`、`scene_ref`、`subject_ref`；页面只列出当前模式允许的角色。
- 排序：拖动调整顺序，编号与 `@VideoN` / `@ImageN` 实时对应。
- 提示词联动：素材列表上方显示可复制的 `@Video1`、`@Image1` 标记；提示词编辑器提供素材清单，避免用户手动记编号。
- 删除：从 case.toml 删除记录，并删除 `assets/` 下的文件；删除前确认。

前端不做素材合格性校验。视频与图片是否符合格式、时长、帧率、像素、体积限制，由 vrgen 在提交前权威检查；检查不通过时，错误写入该轮的过程记录，页面从任务日志里显示失败原因。这样校验规则只有一份，避免前端与 vrgen 各维护一套限制。

### 4.3 页面拆分与复用

gen 页面与旧流程的步骤不同，需要分开设计：

- gen：素材 → 生成。
- patch：选区 → 抽取 → 生成 → 合并 → 对比。
- fullredraw：扩充画面 → 生成 → 裁回原尺寸 → 对比。

gen 不包含对比页。普通视频不能复用 360° ERP 对比器，本期也不新增对比组件。

共同部分抽成共享组件：

- 生成参数（模式、比例、输出/输入分辨率）。
- 提示词面板（模板正文、变量编辑、素材标记）。
- 会话选择（项目、剧集、会话）。
- Session 列表与选用。
- 任务队列与日志。
- 文件列表渲染。

实现建议：

- 服务端用 Jinja `include` 把生成参数、提示词、会话、任务面板拆成 partials；wizard 模板只负责步骤条与各步骤容器。
- 前端把 `wizard.js` 中与步骤无关的函数拆成独立脚本（参数、提示词、会话、任务），按页面加载。
- 步骤定义改为数据驱动：每个 flow 提供步骤列表与面板 id，不再用三元表达式堆在 `STEPS` 常量里。
- 后端仍然只有一套 `/api/case` 与 `/api/run`；新增 `/api/case/<name>/assets` 负责素材增删改排序。

## 5. vrgen 接口改造

### 5.1 提交参数

`vrgen submit` 增加重复参数：

```text
--ref-video <路径>:<角色>
--ref-image <路径>:<角色>
```

旧的 `--input` 与 `--mask` 保留给 patch/fullredraw；gen 多素材走新参数。两种入口最终都转换成同一份 `InputPackage`，提示词几何仍由 canvas/source 决定。

### 5.2 素材登记

每个视频与图片都要登记到 SD 合规素材库：

- 视频按 `--video` + `--video-asset-id` 成对出现，可重复。
- 图片按 `--image` + `--asset-id` 成对出现，可重复。
- 台账的 `assets` 字段从单一 map 扩展为按素材 id 分组，例如 `{"video:v1": 123, "image:i1": 456}`。
- 断点续跑按素材内容哈希判断是否已登记，避免重复审核。

### 5.3 提交前校验

素材校验只在 vrgen 阶段做。校验内容来自模型能力：

- 视频：格式、时长、帧率、像素、体积、数量上限。
- 图片：格式、尺寸、像素、体积、数量上限。
- 模式与素材角色：当前模式是否接受视频或图片，必填角色是否齐全。

校验失败时，vrgen 返回非零退出码，把具体原因写进该轮的过程记录与台账；vrstudio 的任务队列把日志尾部显示在页面上。前端不重复实现这些限制，也不在提交前给出“可以/不可以”的本地判断。

### 5.4 提示词变量

提示词模板增加素材清单变量：

```text
【素材清单】
@Video1：编辑母版，负责时间轴、构图与动作基准。
@Video2：动作参考，只提供动作节奏与路径。
@Image1：主体参考，只定义角色外观。
```

素材编号与 role 由 vrstudio 根据 case.toml 的素材顺序与用户选择的角色生成，作为模板变量传入；模板不自行猜测哪个素材是什么。

## 6. 与现有流程的关系

- patch 与 fullredraw 保持现状，仍然要求一个源视频；它们的 `[source]` 与几何契约不变。
- gen 的 `[source]` 变为可选；旧 gen case 加载时自动映射为单素材。
- 模式的唯一权威仍然是 `runs/<job>/generation.toml`。`case.toml` 不保存模式；打开 case 时通过 `params show` 读回，切换模式时更新 `generation.toml`。
- `[adopt]` 指针、结果文件位置、台账结构保持兼容。

## 7. 实施阶段

1. case 模型：`assets` 数组、无源视频的 gen case、素材复制到 `cases/<name>/assets/`、旧 case 迁移、校验与测试。
2. vrgen：`params save` 允许只写模式、`params show` 允许无视频调用；多素材 submit、素材登记、台账分组、提交前校验、提示词素材变量与测试。
3. 前端：创建面板去掉 gen 的视频要求并写入模式、新增素材步骤、素材 API、提示词联动。
4. 页面重构：抽共享 partials 与脚本，gen 页面与旧流程分离；gen 只有素材与生成两步。
5. 浏览器验收：新建无视频 gen case，添加 2 个视频与 1 张图片，手动指定角色，填提示词，提交 `allMediaRef` 并采用结果；素材不合格时从任务日志确认错误。

每一步单独提交，保持可回退。

## 8. 已确认的结论

1. 模式唯一权威是 `runs/<case名>/generation.toml`；`case.toml` 不保存模式。新建 gen case 后立即写模式，素材步骤通过 `params show` 读回。
2. gen case 的素材复制进 `cases/<name>/assets/`，`case.toml` 记录相对路径与哈希。
3. 素材角色由用户手动选择，不按顺序自动推断。
4. 本期只支持 `videoEdit`、`allMediaRef`、`videoExtend`；`firstFrame`、`firstLastFrame`、`text2video` 与音频素材暂不实现。
5. gen 页面只有素材与生成两步，不包含对比页。
6. patch 与 fullredraw 保持现状，仍以单个源视频为起点。
7. 素材校验只在 vrgen 阶段做；前端不在提交前判定合格性，失败原因通过任务日志显示。

## 9. 相关文档

- `docs/case-model.md`：case 与 CLI 契约。
- `docs/sessions.md`：项目会话与额度。
- `docs/prompt-rules.md`：多素材在提示词里的角色声明规则。
- `docs/video-edit-motion-issue.md`：VideoEdit 动作问题与 A/B 路线。

## 10. 实施与验收记录（2026-10-19）

已落地的契约与代码：

- `case.toml`：gen 改为有序 `[[assets]]`，不再写 `[source]`；素材复制进 `assets/`，
  记录相对路径与哈希。旧 gen case 在 `load` 时自动迁移并落盘。
- `vrstudio case new`：gen 的 `--mode` 必填，创建后调 `vrgen params save` 写模式；
  `--source` 可选，给了就复制为 `v1/edit_master`。
- `vrgen submit --refs`：素材清单 JSON；gen 不传 `--input`/`--mask`，canvas/source
  可省略。角色矩阵、数量上限、视频/图片限额在 vrgen 提交前校验；每段视频独立缩放，
  超限图片也缩放后上传。
- 台账：`assets` 使用 `video:v1`/`image:i1` 分组键；`params.refs` 记录素材顺序、
  角色与缩放件；轮次目录保存 `refs.json`。
- 提示词：新增 `templates/gen-multi.md`，`asset_list`/`task_rule`/`timeline_rule`
  由模式与素材顺序生成；`prompt show` 新增 `computed_keys`。
- 前端：新建面板支持 gen 无视频创建；向导拆成 Jinja partials 与
  common/assets/params/prompt/tasks/wizard 六个脚本；素材步骤支持本地多选、
  手动角色、拖动/按钮排序、删除与缩略图；生成页新增免额度“检查提交命令”
  （`generate submit --check`，内部执行 `vrgen submit --dry-run`）。

浏览器验收（临时 cases 目录，未消耗额度）：

- 新建无视频 gen case `multi-demo`，模式 `allMediaRef`，素材步骤添加 2 个视频
  （其中一个先设为编辑母版并排到第一）与 1 张图片，角色分别为
  `edit_master` / `motion_ref` / `subject_ref`。
- 素材不合格时（256×128、10fps、0.8s 的视频），“检查提交命令”任务失败，
  页面直接显示 `FAIL pixels / FAIL fps / FAIL duration` 与 `vrgen: 素材 v1 不合约`。
- 换成两个合格视频后，检查任务成功；`prompt.txt` 依次出现 `@Video1` /
  `@Video2` / `@Image1`，mglc argv 含两条 `--video`+`--video-asset-id` 与
  一条 `--image`+`--asset-id`。
- 旧 `simple_gen_01` 的 case.toml 复制到临时目录后 `load` 迁移成功：
  生成 `assets/v1_Simple_Anima_Test.mp4` 与一条 `edit_master` 素材。

测试规模：vrgen 95 个、vrstudio 258 个，合计 353 个全绿；两仓库
`uv run ruff check .` 干净。

未做：真实 `allMediaRef` 提交与采用（本期明确不消耗平台额度）；素材不合格
的拒绝路径已用 dry-run 验证，但 SD 合规素材登记与真实任务轮询仍待下一轮额度。

### allMediaRef 尾帧占位实验（2026-10-19）

对 `simple_gen_allMediaRef` 的源片尾帧做了测量（1920×1052）：

- 白膜 bbox 约 `(1022, 369) – (1135, 686)`。
- 中心 x ≈ 56.2%（画面中央、略偏右，不是中左）。
- 头顶 y ≈ 35.1%，脚底 y ≈ 65.2%，站姿高度 ≈ 30.1%。
- 终点在中景成排矮案前的红毯上；左下角前景矮案只是近景物体，不是终点地标。

据此修正了提示词里的三处误导：

- 删除“画面中左”“前景矮案的右后方”“走近镜头/向左前方”等措辞。
- 路径改为“从画面右侧中景向画面中央横向移动，前进幅度很小，变大主要来自站直”。
- 终点明确为“中心约 56%、头顶约 35%、脚底约 65%、高度约 30%，不得越过中线进入左半区”。

实验结论：

- 让源视频与首/尾帧都当 `scene_ref` 时，模型可能保留画面里的白膜，同时把高官作为
  新前景角色加入（`gen-multi-a46163aa` 即此现象）；`allMediaRef` 不执行“遮罩式原地替换”。
- 首尾帧可以作为空间提示，但不能强制移除白膜；若要单人结果，参考帧里的白膜区域
  需要先处理掉，或改用无白膜的空镜/位置标记。
- 平台模型 37 支持 `firstFrame` 与 `firstLastFrame`（mglc `--first-image` /
  `--last-image`），但本期 CLI/契约未接入；它是锁尾帧的结构化候选，前提是尾帧
  已经是目标高官在目标位置/尺度的画面，而不是白膜尾帧。
- 提示词采用“位置与姿势分离”：首/尾帧只锁屏幕占位（脚底、头顶、左右边界）；
  白膜的姿势、关节角度和动作不是模板，起始坐姿与结束站姿按剧情重演；
  同时明确成片只能有高官一人、白膜必须完全消失。

