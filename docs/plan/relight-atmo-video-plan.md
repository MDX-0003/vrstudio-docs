# 视频氛围重打光（relight atmo video）方案

状态：已批准（2026-11-04）。WP0–WP3 实施中；WP4 等用户的氛围视频测试素材就位后再做，
WP5 视实测决定。四项关键选择已确认：逐帧光场、允许不同分辨率并按进度对齐、接受 1080p
氛围视频、fullredraw 成片复制/上传进 relight case。

上游：决策 56（视频重打光）、59（relight 只有一条 flow）、64（删除同位检查、缓存变换）、
65（报告计时）。相关文档：`docs/plan/relight-video-plan.md`、
`docs/plan/relight-frontend-plan.md`、`docs/plan/relight-decode-cache-plan.md`。

## 0. 结论

- **新能力只加一条：视频 GT + 视频氛围。** 相似变换仍只估一次（固定机位前提），
  光场改为逐帧从对应时刻的氛围帧重估；图片氛围的固定光场路径不动。
- **氛围源按媒体类型自动分派，不新增 CLI 开关。** 氛围是图片时沿用现在的「一张图整段复用」；
  氛围是视频时自动走逐帧光场。图片 GT 不接受视频氛围。
- **氛围视频只要求 2:1 ERP，不要求与 GT 同分辨率、同帧率。** 光场在 2K 工作尺度估计，
  1080p 氛围已经够用；GT 继续提供 8K 结构。
- **上游 video fullredraw 不需要新 flow。** 它已经存在（pad → generate(videoEdit) → recompose
  → compare）；本轮补的是真素材验收与「成片如何进入 relight case」的操作顺序，不是重写流程。
- **不做跨 case 路径引用。** fullredraw 成片按现有 `[[assets]]` 语义复制/上传进 relight case。

## 1. 现状与已有规划

### 1.1 已实现

- `vrstudio relight`：图片 GT 出单帧 PNG，视频 GT 出整段 MP4；`--ref-frame`、`--sample N`、
  `--crf`、`--report` 已就绪；`relight-video` 已退役。
- 视频路径：一张氛围图只估一次对齐与光照场，整段逐帧只做乘算（`src/vrstudio/cli/relight.py:593`）；
  参考帧与相似变换缓存在 `cases/<case>/derived/relight/fixed.json`。
- 前端：`relight` 一条 flow，「素材 → 重打光 → 对比」三步；两个槽位、素材库候选、小样、
  整段、报告时间戳、360 对比都已落地。
- 上游 `fullredraw`：`FLOWS` 已含该 flow，步骤为 pad → generate → recompose → compare
  （`frontend/src/constants/steps.ts:21`）；生成模式固定 `videoEdit`（`docs/case-model.md:577`），
  模板 `360-closure`（`src/vrstudio/cli/generate.py:45`）。

### 1.2 氛围依据当前只允许图片的三处

- 角色契约：`relight_atmo.kinds = ["image"]`（`src/vrstudio/roles.json:136`）；
  `docs/case-model.md:286` 明确写「只接受图片」。
- CLI：`_relight_video` 用 `read_image(inputs.atmo)` 读氛围源，并要求与 GT 逐像素同尺寸
  （`src/vrstudio/cli/relight.py:512`、`:522`）。
- 前端：氛围槽位选择器固定 `mode='image'`（`frontend/src/views/wizard/RelightAssetsStep.vue:30`）；
  上传弹窗只对 `relight_gt` 接受视频（`frontend/src/components/upload/AssetUploadDialog.vue:57`）。

### 1.3 已有规划里没有视频氛围

- `docs/plan/relight-frontend-plan.md:56` 把「氛围图只有一张且全程不变」写成共同边界；
  `:116` 把「多张氛围图随时间切换」列为以后可做。
- `docs/plan/relight-video-plan.md` §8 同样把「多张氛围图随时间切换」列为不做。
- 因此本次是新立项，不是续做已有工作包。

### 1.4 两个必须写进方案的事实

- **按现有能力表，videoEdit 最高 1080p。** 4K 只在 Seedance 2.0 的 `allMediaRef` /
  `firstLastFrame`，而 2.0 没有 videoEdit（`docs/case-model.md:579`、
  `docs/plan/patch-4k-region-plan.md:10`）。若平台已放开 4K videoEdit，这条要先更新能力表。
- **fullredraw 的 recompose 输出是 2:1、源尺寸，但帧率与帧数跟随 AI 返回。** 平台可能把
  30fps 重采样为 24fps，时长也会略变。所以 relight 不能按帧号硬配，必须按时间/进度对齐。
- **fullredraw 真素材浏览器验收仍未完成**（`docs/roadmap.md:84`）。本轮 WP5 一并补。

## 2. 需求卡

### 2.1 主任务

当我要把一段 AI 重绘后的氛围视频的光照搬到 8K 真 GT 视频上时，我想在 relight case 里把
氛围槽位选成视频、先看小样再出整段，以便光照随时间变化也能跟着走，同时 GT 的结构与细节
一点不丢。

### 2.2 失败路径

- 图片 GT + 视频氛围：参数错退出 2，文案说明视频氛围只适用于视频 GT。
- 氛围视频不是 2:1：参数错退出 2，给出实际宽高。
- 氛围视频比 GT 短：仍然出片，复用最后一帧并警告；报告记录实际映射到的帧号。
- 氛围视频读不出帧、或参考帧对不可用：运行失败退出 1，不留下半成品。
- 对齐不可信：退出 1 且不出片，与现有视频路径一致。
- 时间映射后结构相关过低：只警告并写进报告，不中断（证据，不是闸门）。

### 2.3 约束

- 固定机位前提不变；不做逐帧 SIFT，不做机位移动。
- 视频逐帧流式处理，不整片驻留内存（硬规则 5）。
- 相似变换的唯一权威点仍是 `vrstudio/relight/align.py`；时间映射新增一处权威点，
  不得在 web 或前端复制。
- 不改 `clip.json`、`_pad.json`、`run.json` 三个冻结契约。
- 图片氛围路径的像素基线保持不变。

### 2.4 验收

以下每条都能在 CLI、报告、测试或浏览器里观察到。

- 8K GT + 1080p 氛围视频：小样与整段都能出片，帧数/帧率/音轨与 GT 一致。
- 合成「移动光源」氛围视频：输出画面的亮区随时间移动，证明逐帧光场生效。
- `strength 0`：引擎层逐位等于 GT；视频文件层在 crf 0 的编码往返误差内。
- 不同帧率/帧数的氛围视频：按归一化进度配对，报告写出映射方式与氛围帧数。
- 图片 GT + 视频氛围被拒绝，退出 2；氛围视频非 2:1 被拒绝，退出 2。
- 图片氛围的现有测试与像素基线全部不改地通过。
- 浏览器：氛围槽位能上传/选择视频，门控文案、报告「逐帧光场」、小样与整段都正确。
- fullredraw 真素材验收：patch 成片 → fullredraw → recompose 出 2:1 成片，再进入 relight。

## 3. 设计

### 3.1 输入与校验

- `--atmo` 接受图片或视频，由 `kind_of()` 判类型。
- 允许的组合只有三种：
  - 图片 GT + 图片氛围：现有单帧路径，不变。
  - 视频 GT + 图片氛围：现有整段固定光场路径，不变。
  - 视频 GT + 视频氛围：新增逐帧光场路径。
- 图片 GT + 视频氛围：参数错退出 2。
- 视频氛围校验：必须是 2:1 ERP；不要求与 GT 同分辨率、同帧率、同帧数。
- 图片氛围校验保持现状：必须与 GT 逐像素同尺寸。
- 视频 GT 的 2:1、偶数宽高校验保持不变。

### 3.2 时间映射

- 映射规则按归一化进度：GT 第 `i` 帧（共 `G` 帧）对应氛围第
  `round(i × (A − 1) / max(G − 1, 1))` 帧（共 `A` 帧）。
- 两路顺序读，氛围读得慢时向前跳到目标帧，读得快时复用上一帧；不逐帧 seek。
- `A` 未知时回退按时间：`t = i / gt_fps`，用氛围 fps 换算目标帧。
- 氛围短于 GT：复用最后一帧，警告一次，报告写 `atmo_short=true`。
- 该规则落在一个新模块 `src/vrstudio/relight/atmo.py`，CLI、web、前端都只读它的结果；
  web 与前端不实现第二套。

### 3.3 参考帧与对齐

- 显式 `--ref-frame N`：取 GT 第 N 帧与它按 3.2 映射到的氛围帧，成对估计相似变换。
- 自动选帧：两路顺序打开，扫前 `MAX_REFERENCE_SCAN` 帧；GT 帧灰度标准差低于
  `MIN_REFERENCE_STRUCTURE` 的跳过；对每一对在 2K 上算结构相关，取最高的一对。
- 相似变换仍只估一次，整段复用；`_check_alignment` 的判据不变。
- 缓存命中时跳过成对扫描与 SIFT，只按缓存的参考帧号继续；缓存键里的氛围身份改成视频的
  sha/size/mtime，失效规则不变。
- 报告新增参考帧对：GT 帧号、氛围帧号、映射方式、`ref_matched`。

### 3.4 逐帧光场

对每一帧 GT：

1. GT 帧降到 2K 工作尺度：`gt_small = resize(frame, (work_w, work_h), INTER_AREA)`。
2. 取映射到的氛围帧，同样降到 2K：`atmo_small`。
3. 用固定变换在 2K 上 warp：`warp_with_matrix(atmo_small, alignment.matrix,
   (work_w, work_h))`；不在 8K 上逐帧 warp。
4. `fields = estimate_fields(gt_small, aligned_small)`；因为输入已经是 2K，
   `estimate_fields` 内部的 resize 是 no-op。
5. `light = light_compose(fields, (gt_w, gt_h), strength, local_shading)`。
6. `out = light.apply(frame)`。

这样每帧多的是「一次 2K 引导滤波 + 一次光场放大」，不是逐帧 SIFT。`strength 0` 时
`light_compose` 仍退化为单位变换，输出与 GT 逐位一致。

**为什么 1080p 氛围在性能上可接受。** 光场的估计尺度本来就是 2K（2048 宽）；1080p 氛围
（1920 宽）只比工作尺度小 6%，降到 2K 时几乎不放大，解码与缩放的代价都低于 2K/4K 输入。
真正贵的部分是每帧一次 2K 引导滤波和一次 8K 光场放大，与氛围视频分辨率关系不大；1080p
不会成为新的瓶颈。

图片氛围路径完全不进这个循环，继续用现有的 `FixedLight` + 一次 `light_compose`。

### 3.5 CLI 契约

```text
vrstudio relight --gt GT.mp4 --atmo ATMO.mp4 --out OUT.mp4
  [--ref-frame N] [--sample N] [--crf 0..51]
  [--scene night|day] [--strength 0..1] [--local-shading 0..1]
  [--highlight-clip] [--clip-knee 0.72] [--clip-max 0.98]
  [--report JSON] [--config TOML] [--set key=value]...
```

- 不新增开关：氛围类型决定光场模式。
- `--atmo` 帮助改成「AI 氛围源：图片（固定光场）或视频（逐帧光场）；视频按时间与 GT 对齐」。
- `--ref-frame` 帮助补一句「氛围是视频时同时决定参考帧对」。
- 小样与整段、退出码语义、图片专属/视频专属参数的拒绝规则全部保持现状。

### 3.6 case 模型与角色

- `relight_atmo.kinds` 改为 `["image", "video"]`；三份 `roles.json`
  （`docs/roles.json`、`vrstudio/src/vrstudio/roles.json`、`vrgen/src/vrgen/roles.json`）
  逐字节同步，更新 `vrstudio/tests/test_roles_contract.py` 的 `CONTRACT_SHA256`。
- 新增配对规则：两个槽位都在时，氛围是视频而 GT 是图片才拒绝；GT 还没选时允许先把
  视频氛围候选放进素材库并选中（门控只提示缺底版）。GT 从视频改成图片、而氛围指针仍指向
  视频时，在 `set_relight_pick`、`load` 与 `relight --case` 入口按真实原因拒绝。
  前端选择器在 GT 未选时两种都收，选定后按 GT 类型过滤；错误的组合不会由 UI 产生。
- `[relight]` 键集合不变；不新增 `atmo_mode`、不新增 `atmo_kind` 字段，类型由指针素材的
  `kind` 决定。
- `add_relight_candidate` 的上传/复制管线不变；视频文件按普通素材复制进 `assets/`。

### 3.7 web 与前端

web（`src/vrstudio/web/app.py`）：

- `_relight_payload` 已有 `atmo.kind`；门控文案从「氛围图」改为「氛围依据（图或视频）」。
- `_gates` 增加配对判断：GT 是图片但氛围是视频时，`assets` 步不通过并给出原因。
- `api_assets` 的 slot 分支不需要新端点；角色 kinds 放宽后上传管线原样可用。
- `_op_argv` 的 `relight` op 不变。

前端：

- `RelightAssetsStep.vue`：氛围槽位在 GT 是视频或还没选时用 `pickerMode='video'`
  （这个模式本身同时收视频与图片），GT 是图片时仍用 `'image'`；文案改成「氛围依据」。
- `AssetUploadDialog.vue`：新增一个由父组件传入的「该槽位是否接受视频」属性；氛围槽位在
  GT 是视频时为真。
- `RelightStep.vue`：报告类型增加 `atmo_kind`、`atmo_frames`、`atmo_fps`、`fields_mode`
  与可选的 `atmo_match`；面板显示「氛围：视频 · 逐帧光场」。
- 对比页与步骤链不变。

### 3.8 报告与缓存

报告新增（都不是跨仓库契约）：

- `atmo_kind`：`image` / `video`。
- `atmo_frames` / `atmo_fps`：氛围视频的帧数与帧率；图片氛围不写。
- `atmo_mapping`：`normalized_progress`（或回退的 `time`）。
- `atmo_ref_frame`：与 GT 参考帧配对的氛围帧号。
- `fields_mode`：`fixed` / `per_frame`。
- `atmo_match`：可选，逐帧 GT 与对齐后氛围帧的结构相关 `{min, mean}`；只作证据。
- `timing` 增加 `render_decode_atmo`、`render_fields`；小样增加对应三项。

缓存：

- `fixed.json` 字段集不变，仍只缓存参考帧号与相似变换。
- 缓存键的氛围身份来自视频文件的 sha/size/mtime；换氛围视频自动 miss。
- 逐帧光场不缓存，与决策 64「只缓存变换」一致。

### 3.9 上游 fullredraw 的 SOP

1. 用 patch 成片建 `fullredraw` case。Web 建 case 的源文件只从 `sources/` 选或上传，
   所以先把 patch 成片放进 `sources/` 或在上传入口传一次。
2. `pad` 生成 21:9 冗余画布。
3. `generate`：模式固定 `videoEdit`，模板 `360-closure`；【允许变化】只写光影、色温、
   空气质感，不写物体与动作；分辨率按平台能力选 1080p（4K 只在没有 videoEdit 的模型上）。
4. `adopt` 后 `recompose` 裁回 2:1；检查几何闸门通过、输出宽高为源尺寸。
5. 记录成片的帧数、帧率、时长；与 GT 不同不影响 relight，但要在报告里能看到映射结果。
6. 把成片作为 `relight_atmo` 候选加入 relight case：CLI
   `vrstudio case relight --case R --atmo <成片>`，或前端素材步上传。

## 4. 工作包

本轮做到 WP3：CLI、case/web、前端全部可跑，用合成素材与单测验收；WP4 需要用户先用
fullredraw 手动生成氛围视频，作为下一轮的起点。

### WP0：文档、契约与角色词表

改动：`docs/case-model.md` 的 relight 段改成「氛围依据可为图片或视频」并写配对规则；
`docs/decisions.md` 登记本次决策；三份 `roles.json` 同步；`tests/test_roles_contract.py`
更新 SHA；`AGENTS.md` 索引加本文。

验收：文档与代码现状逐条对得上；`uv run pytest` 全绿、`ruff` 干净。

### WP1：CLI 与引擎

改动：新增 `src/vrstudio/relight/atmo.py`（时间映射、成对读取、氛围帧提供者）；
`cli/relight.py` 增加视频氛围分支；`resolve_reference` 拆出成对参考帧解析；
逐帧光场循环、小样、报告、缓存身份；`estimate_fields` / `light_compose` 的调用方式。

验收：

- 合成移动光源氛围视频：输出亮区随时间移动。
- 不同帧率/帧数的氛围视频：映射正确，报告写出 `atmo_mapping` 与实际帧号。
- `strength 0` 引擎层逐位一致；20 帧 crf 0 视频的 maxdiff 与现有视频基线同口径。
- 图片氛围的所有现有测试不改地通过。
- 三种非法组合（图片 GT + 视频氛围、氛围非 2:1、氛围读不出帧）各自退出 2 / 1，
  且不留下半成品。

### WP2：case 模型与门控

改动：`relight_atmo` kinds；配对校验；`[relight]` 读写不变；web `_gates` 文案与配对判断。

验收：`case relight --atmo <视频>` 能加入并选中；图片 GT + 视频氛围被 `load` / 门控拒绝；
旧 relight case 加载不受影响；`test_web_relight.py` 增补配对用例。

### WP3：前端

改动：素材步的选择器/上传/文案；重打光步的报告类型与展示；类型定义。

验收：浏览器里 GT 选视频后，氛围槽位能上传与选择视频；GT 选图片时仍只收图片；
报告显示「逐帧光场」与氛围帧数；现有图片/视频氛围路径页面不回退；`typecheck` /
`lint` / `test` / `build` 全绿。

### WP4：真实素材端到端

改动：用 patch 成片跑一次 fullredraw（真实额度），再用它的成片跑 relight 的冷/热各一轮；
结论写 `docs/test-runs/`。

验收：fullredraw 的 recompose 几何闸门通过；relight 小样能看到光照随时间变化；
整段无异常闪烁；记录每帧耗时、峰值内存、帧间亮度跳变；与固定光场版本做一次 A/B。

### WP5：性能与稳定性收尾

只在 WP4 的实测不达标时做：

- 2K 光场的时间平滑（EMA），只在测得闪烁时启用。
- 8K 光场放大的分条处理或复用缓冲，压低峰值内存。
- 若逐帧成本过高，评估「每隔 N 帧估一次 + 2K 插值」的折中，但不改默认语义。

## 5. 验收指标

- 功能：视频氛围能出片；逐帧光照随时间变化；图片氛围与现有基线不回退。
- 时间：氛围与 GT 帧率/帧数不同也能正确配对；报告可复查。
- 质量：整段帧间亮度跳变不高于现有视频重打光的口径；无可见闪烁。
- 性能：记录 8K GT + 1080p 氛围的秒/帧与总时长；以此决定是否进 WP5。
- 上游：fullredraw 真素材一轮通过并留下验收记录。

## 6. 风险

- **逐帧光场可能闪烁。** 氛围视频的压缩噪声会让 2K 光场逐帧抖动；先实测，必要时加时间平滑。
- **8K 内存峰值。** 每帧放大 gain/visibility 会反复分配大数组；实测峰值，必要时复用缓冲。
- **时间映射漂移。** 平台重采样会让时长略变；按归一化进度是最稳的近似，报告给出证据；
  若漂移明显，再考虑按场景切点对齐。
- **1080p 氛围的细节不足。** 光场在 2K 估计，1080p 已接近工作尺度；用真实素材确认观感。
- **videoEdit 改变内容而非只改光照。** 若结构变化过大，对齐闸门会拒绝；此时回到提示词
  收紧允许变化，或改用图片氛围。
- **三份 roles.json 与 SHA。** 任何一处漏改都会让契约测试红；WP0 一次改完。

## 7. 不做

- 跨 case 路径引用氛围视频（复制/上传优先）。
- 图片 GT 使用视频氛围。
- 逐帧 SIFT / 逐帧重估相似变换 / 机位移动支持。
- 4K videoEdit（平台能力未提供时）。
- 缓存逐帧光场。
- 氛围视频与 GT 的自动场景切点对齐。

## 8. 依赖与待确认

- 用户正在制作的 CLI 氛围视频测试素材；就位后先跑 WP4 的冷/热两轮。
- 平台是否已放开 4K videoEdit；若已放开，更新 `docs/case-model.md` 的能力表后再决定
  氛围视频分辨率。
- fullredraw 真素材验收的额度窗口。
