# 360 静图的两条生成流程

状态：已定稿（决策 46，2026-10-29）。按「局部重绘走视口局部、整幅 360 画布生成才走左右冗余与拼接」重写：上一版把 `patchimg` 做成全幅 21:9 画布，8K 实测暴露局部细节被摊薄，本版把它改回与视频 patch 同构的视口局部，`img2video` 继续使用全幅 pad/stitch。文末列出仍然需要确认的取值。

## 0. 结论

- 新增两条 flow：`patchimg`（360 图片局部重绘）与 `img2video`（360 图片→首尾帧→视频）。两条都是独立流程，视频 patch 保持不动。
- `patchimg` 走**视口局部**：`extract` 从 ERP 裁出 16:9 视口图与 inner mask，图片模型只重绘这张视口图，`merge` 归一化后贴回 ERP，并只写 inner 区域。它与视频 patch 同构，复用 `patch/projection`、`patch/composite`、`patch/scalefit`；不需要全幅 pad/recompose。
- `img2video` 走**全幅 360 画布**：源图与关键帧 pad 成 21:9 冗余画布，图片模型重绘关键帧，视频模型 firstLastFrame 出 21:9 视频，最后逐帧拼接回 2:1。它复用静图 pad/stitch 核心与 fullredraw 的 recompose。
- 「所有 360 画布生成都要左右冗余与拼接」的原则保留，但适用对象是**模型输出为 360 画布**的步骤。视口裁剪是透视图像，不是 360 画布；视口跨 ERP 接缝时投影先拼好环绕，模型看到的仍是连续透视图。视频 patch 属于这一类，`patchimg` 也属于。
- 8K 的 `patchimg` 全幅实测暴露两个问题：全幅 4K 输出摊到 9558 宽后局部偏软；117.6 MB 的全幅 PNG 被平台上传接口 403。视口局部同时解决这两点：输入是 1920×1080（或 4K 视口）的裁剪图，局部拿到完整 4K 输出，上传尺寸也远低于限制。
- `img2video` 的关键帧仍是整幅 360 图，仍受 4K 输出与上传尺寸限制；它的上传副本降采样与 pad/stitch 继续保留。

## 0.1 实施状态（2026-10-29）

- WP1 完成：静图 pad/stitch 核心与 `image_pad.json`（vrstudio `755ed2d`）。该核心现在服务 `img2video`，不再服务 `patchimg`。
- WP2 曾以全幅实现（vrstudio `4b34d86`、`9f1dd88`、`6927d58`）并用 8192×4096 源做过真实 4 张候选验收：接缝 `wrap 0.437 / percentile 48.1 → ok`，选区外 `maxdiff 0`。验收同时证明全幅方案让局部细节偏软，因此 `patchimg` 改为视口局部：extract 只写 `clip.png` + `clip_mask.png` + `image.json`，merge 走 `SegmentMaps.from_geometry` + `composite_frame` + 只写 inner；全幅的 `patch/still.py`（ERP 空间局部 mask + 局部融合）随之下线，`redraw/image.py` 与上传副本降采样保留给 `img2video`。
- 模板与角色文本完成：vrgen 的 `edit_master`/`mask` 角色文本、`img360-local` 模板与输入限额（vrgen `eb7d6ec`）。
- WP2 真实额度验收完成（8K 源、4 张候选、选区外 `maxdiff 0`、局部锐度约为全幅方案的 1.7 倍）：见 `docs/test-runs/20261029-patchimg-viewport-local.md`。
- WP3（`img2video`）、WP4（前端 `patchimg`）、WP5（前端 `img2video`）、WP6（gen 整幅 360 缺口）未开始。

## 1. 设计原则与适用边界

原则：**凡是交给生成模型、由模型输出 360 画布（整幅 ERP，或包含 ERP 横向环绕的宽画布）的步骤，前后都必须走「左右冗余—左右拼接」**。

原因：模型不知道画布最左与最右是同一圈 360 度，直接生成会在接缝处出现物体、纹理、光照或运动的不连续。pad 把接缝两侧的真实内容作为冗余带交给模型；stitch 用冗余带做配准与融合，把接缝落到模型自己栅格里的相邻列上。

适用边界：

- 模型输出是整幅 ERP 或包含 ERP wrap 的宽画布：适用。fullredraw 已经在做；`img2video` 的关键帧与视频按本版做。
- 模型输出是透视视口裁剪：不适用。视口是普通透视图像；视口跨 ERP 接缝时，`build_view_map` 的环绕采样在裁剪前已经把接缝拼成连续图像。现有视频 patch 与新的 `patchimg` 都属于这一类。
- 模型输出是整幅 360 视频且直接 `videoEdit`：适用，但 gen 流程目前没有做。见 3.4 节。
- 模型输出是首尾帧视口图（keyframe 工作台的 16:9）：不适用，理由同视口裁剪。

因此两条新流程的归档是：`patchimg` 与视频 patch 同构，走视口局部；`img2video` 的关键帧与视频走全幅 pad/stitch。

## 2. 需求卡

### 角色与场景

内部制作人员在本机工作站上，通过 CLI 或浏览器处理 VR 360 静图。输入可能是 4K 或 8K 的 2:1 ERP 图。两条流程都不涉及并发、权限与多人协作。

### 任务与失败路径

`patchimg` 的主任务：当我要修一张 360 全景图里的某个人或物体时，我想框选视口与内部区域、写提示词、生成 N 张视口候选、挑一张贴回，以便得到一张接缝保持、选区外完全没变的完整 ERP 图。

`img2video` 的主任务：当我要把一张或两张 360 全景图变成一段 360 视频时，我想按三种首尾帧组合之一生成关键帧、写情节提示词、生成视频，以便得到一段接缝闭合的完整 ERP 视频。

失败路径：

- 源图不是 2:1 时，新建 case 拒绝并报出实际宽高；不静默拉伸或裁切。
- `patchimg` 的 inner 超出视口时，extract 拒绝；inner 没有覆盖完整主体时，贴回会在主体内部切断，CLI 先看 mask 预览再提交。
- 视口比例与图片模型支持的比例不一致时，submit 拒绝；本期视口固定 16:9，图片模型支持 16:9。
- `img2video` 的两张源图尺寸不一致时，拒绝并报出两边尺寸；不静默缩放，因为两张图的 pad 几何必须一致。
- 生成结果的比例与画布/视口不一致时，拼接或贴回先按目标尺寸还原，比例漂移超过阈值时告警；模型把画布裁掉或重新构图时，冗余带相关性低于阈值，拼接步骤拒绝出片。
- `patchimg` 贴回后选区外出现任何像素差异时，pytest 基线失败；CLI 打印差异像素数。
- 候选没有人工挑选时，adopt 拒绝，要求显式给下标。
- `img2video` 的首帧或尾帧没有定稿时，视频提交拒绝。

### 约束

- 两仓库分离，跨仓库只走 CLI、退出码与台账。
- `clip.json`、`_pad.json`、`runs/<轮次>/run.json` 是冻结契约；两条新流程不改这三个文件。`patchimg` 用新的 `image.json`，`img2video` 用新的 `image_pad.json`。
- 图像按单帧处理；视频按帧流式处理，不整片驻留内存。
- 平台图片命令只有 `--ratio` 与 `1K/2K/4K`，每轮候选 1..4，没有 mask/inpaint 参数；平台视频命令的模式里没有单图生视频。
- 提交门禁是 `pytest` 全绿与 `ruff` 干净。

### 验收

- `patchimg`：CLI 五步跑通，输出完整 ERP PNG；选区外与源图 `np.array_equal`；N 张候选可人工挑；8K 源的局部细节来自 4K 视口输出，不再被全幅画布摊薄。
- `img2video`：三种 mode 都能在 CLI 跑通，输出 2:1 ERP 视频；接缝指标通过；链上关键帧不做 recompose。
- 两条都不依赖真实平台额度也能跑通：图片走 `image submit --dry-run`，视频走 `submit --dry-run`，贴回/拼接用注入的合成结果验证；真实额度验收按 8K 源补一次。
- 现有 patch、fullredraw、gen 的测试保持绿色。

### 范围三栏

现在必须做：

- `patchimg` 的视口局部链路：case、extract（视口图 + inner mask + `image.json`）、图片提交、adopt、贴回、像素基线。
- `img2video` 的全幅链路：静图 pad/stitch 核心、三种槽位组合、firstLastFrame 提交、视频拼接。
- 两条流程的 CLI 端到端测试。
- 两条流程的 web 与前端步骤链。

以后可以做：

- 跨 ERP 接缝的局部编辑专门方案（视口加宽、21:9 宽条或全幅路径）。
- 8K 源的分块或局部条带生成，用于 `img2video` 的关键帧。
- 多区域依次重绘。
- `gen` 的整幅 360 视频补 pad/stitch。

明确不做：

- 单图生视频的图片模型模式：平台没有。
- 把两条新流程塞进现有 patch：会污染视频契约，也会让 if 分支扩散到所有步骤。
- 改造 fullredraw：它已经符合原则。
- 本轮修 gen 的整幅 360 缺口：需要单独决策，因为它要区分 360 与扁平视频，并影响现有 case。

### 优先级

CLI 可行性第一。先做 `patchimg` 的视口局部链路（它与视频 patch 同构，复用现成投影与合成，风险最低），再做 `img2video` 的全幅链路；前端两条都排在 CLI 之后。

## 3. 两条生成路径

### 3.1 视口局部（patchimg 与视频 patch）

视口局部不新建几何规则，直接复用视频 patch 的权威模块：

- `patch/projection`：`build_view_map` / `remap_viewport` 把 ERP 重采样成透视视口；`build_paste_map` / `rect_to_erp_bbox` 把视口反投影回 ERP。视口跨 ERP 接缝时，`BORDER_WRAP` 先把环绕拼好。
- `patch/extract`：`extract_viewport_frame(erp, viewport)` 裁视口；`make_mask_image(viewport, inner)` 生成黑内白外的 mask。mask 极性是黑=重绘、白=保持，图片模板按这个极性写。
- `patch/composite`：`SegmentMaps` 构建一次 view/paste 采样图与 inner mask；`composite_frame(erp, ai_viewport)` 把 AI 视口多频带融合后贴回 ERP；`normalize_ai_frame` 把模型返回的任意尺寸归一到视口尺寸。
- `patch/scalefit`：可选的单对帧全局缩放/平移纠偏；图片模型返回漂移时再开，首版可先关闭。
- `patch/blend`：多频带融合；`patch/sidecar`：`Viewport` / `InnerRect` 数据类。

视口局部的数据流：

```text
源 ERP 图
  → extract：clip.png（视口裁剪）+ clip_mask.png（inner mask）+ image.json（冻结几何）
  → 图片模型：只重绘 clip.png，mask 为提示
  → adopt：挑一张视口结果 result.png
  → merge：normalize → 可选 scalefit → SegmentMaps.composite_frame → 只写 inner
  → out/<版本>_image.png（完整 ERP）
```

接缝性质：

- 视口不跨 ERP 接缝：接缝在视口 footprint 之外，贴回时逐位保留。
- 视口跨 ERP 接缝：投影把接缝拼成连续透视图，模型看到的是正常图像；贴回后靠视口的透视连续性保持，不需要冗余带。
- 最终 ERP 的左右接缝要么是源图的（footprint 外），要么在视口内部由投影与 AI 内容连续承接；不存在“全幅画布被模型重绘后接缝错位”的问题。

### 3.2 全幅 pad/stitch（img2video）

全幅路径解决的是整幅 360 画布的生成接缝，`img2video` 的关键帧与视频使用它。几何与融合来自 fullredraw 的单帧核心：

- `redraw/geometry.py`：`plan_pad` 从源尺寸与目标比例推导 `Wc`、`P`、`L=2P`、`G/R/B`、wrap 对、preroll，并 `assert_closure`。
- `redraw/padding.py` / `pipeline.py`：`pad_horizontal` 环绕复制，`pre_roll` 抵消整体旋转，`apply_chain` 对单帧执行。
- `redraw/recompose_core.py`：`slice_regions`、`recompose`、`finalize`、`restore_canvas`。
- `redraw/registration.py` / `verify_core.py`：`circular_translate` 估 `d*` 与相关性，`verdict` 出接缝判定。
- `redraw/image.py` / `manifest.py`：`plan_image`、`pad_image`、`stitch_image`、`image_pad.json`。这是 `img2video` 的静图变体；`patchimg` 不再使用。

全幅路径的性质：

- 模型输出必须是 21:9 画布；拼接用冗余带闭合接缝。
- 4K 图片输出被摊到画布宽度（2:1 8K 源约 9558 宽），关键帧的局部细节受 4K 上限限制。
- 全幅 PNG 可能超过平台上传限制；`assemble_still` 的上传副本降采样（长边 4096）继续用于 `img2video` 的关键帧提交。

### 3.3 复用矩阵

`patchimg` 直接复用，不改：

- `patch/projection`：`build_view_map`、`remap_viewport`、`build_paste_map`、`rect_to_erp_bbox`。
- `patch/extract`：`extract_viewport_frame`、`make_mask_image`。
- `patch/composite`：`SegmentMaps`、`composite_frame`、`normalize_ai_frame`。为 still 增加一个 `SegmentMaps.from_geometry(viewport, inner, erp_w, erp_h)` 类构造，避免为了构造 `SegmentMaps` 伪造一个 `Segment`。
- `patch/scalefit`：`fit_core` 的单对帧用法（可选）。
- `patch/blend`：`multiband_blend`（视口内的融合由 `composite_frame` 调用）。
- `case.py`、`cli/case.py`、`cli/generate.py`、`cli/merge.py` 的流程分支。

`img2video` 直接复用，不改：

- `redraw/geometry.py`、`redraw/padding.py`、`redraw/preroll.py`、`redraw/pipeline.py`。
- `redraw/recompose_core.py`、`redraw/registration.py`、`redraw/verify_core.py`、`redraw/blend.py`。
- `redraw/image.py` 的 `plan_image`、`pad_image`、`stitch_image`、`map_erp_mask_to_canvas`（最后一项目前只被全幅局部 mask 用，保留给未来整幅/跨接缝方案）。
- `media/videoio.py` 的视频拼接帧读写。
- `vrgen image submit`、`vrgen submit`（firstLastFrame）。

需要新写：

- `patchimg` 的 `image.json` sidecar（version、erp_w/h、viewport、inner；没有 fps/时间）。
- `patchimg` 的 extract 分支：视口裁剪 + mask + `image.json`。
- `patchimg` 的图片提交分支：`vrgen image submit`，视口图 + mask。
- `patchimg` 的贴回分支：`SegmentMaps.from_geometry` + `composite_frame` + 只写 inner。
- `img2video` 的槽位状态机与 firstLastFrame 提交装配。
- 两条流程的 CLI 与 web 步骤。

不复制：

- 时间重采样只在 `patch/framealign.index_map`；`patchimg` 是单帧，`img2video` 的视频拼接保持生成视频自己的帧率与帧数。
- ERP 与透视的投影只在 `patch/projection`。
- 画布与源图映射只在 manifest；`patchimg` 的 `image.json` 与 `img2video` 的 `image_pad.json` 各自是唯一权威。

### 3.4 适用边界审计

- fullredraw：已符合。pad/recompose 是现有主路径。
- 视频 patch：不适用。视口裁剪不是 360 画布；视口跨接缝时投影处理，footprint 外逐位保留。
- `patchimg`：不适用。与视频 patch 同构，视口局部。
- keyframe 工作台（16:9 视口首尾帧）：不适用，理由同上。
- `img2video`：适用。关键帧与视频都是整幅 360 画布，走 pad/stitch。
- gen 的整幅 360 `videoEdit`/`allMediaRef`：**缺口**。源视频是整幅 ERP 时，模型输出也是整幅 360 视频，但没有 pad/recompose。按原则应当补，但需要先区分 360 源与扁平源，且会影响现有 gen case。建议单独立项，本文只登记。

## 4. Flow A：patchimg（360 图片局部重绘）

### 4.1 步骤链

```text
case new（源 ERP 图）
  → pick（视口 + inner，定义局部区域）
  → extract（视口裁剪 clip.png + inner mask + image.json）
  → generate（vrgen image submit，N 张视口候选）
  → adopt --index（挑一张视口结果 result.png）
  → merge（normalize + 可选 scalefit + composite_frame + 只写 inner）
  → compare（源图 vs 结果）
```

没有 pad/recompose，没有 keyframe，没有 assemble。`extract` 在本流程里做的是**视口裁剪**，不是时间抽帧，也不是全幅 pad。

### 4.2 生成输入与选区

生成输入是透视视口图 `clip.png`，不是全幅 21:9 画布。视口用 `pick` 的 yaw/pitch/fov/宽高定义；inner 用视口坐标定义要改的区域。`make_mask_image` 生成黑内白外的 mask，图片模板说明“黑色区域需要重绘，白色区域保持原样”。

视口宽高：

- 默认 1920×1080（16:9），与视频 patch 的默认视口一致。
- 图片模型支持 16:9 与 4K；8K 源可以把视口设到 3840×2160，让局部拿到完整的 4K 输出，再贴回 ERP。视口宽高只是 case 草稿字段，不需要新增枚举。
- 视口比例必须是图片模型支持的 ratio；本期固定 16:9，非 16:9 在 extract/submit 拒绝并说明原因。

视口跨 ERP 接缝时，投影会先把环绕拼成连续透视图；模型看到的是正常透视图像，不需要冗余带。视口不跨接缝时，ERP 接缝在 footprint 之外，贴回时逐位保留。

inner 必须覆盖完整主体。inner 只到腰部时，模型可能把整身改掉，但贴回只写 inner，腰线以下会切断；CLI 用户要先看 `clip_mask.png` 或 extract 的预览，web pick 页要画出 inner 边界。

### 4.3 贴回与像素保证

`merge` 分支：

1. 读 `image.json` 的视口/inner 与 ERP 尺寸，读源 ERP、`result.png`（视口结果）。
2. 用 `normalize_ai_frame` 把结果归一到视口尺寸；比例不一致时默认拒绝，显式 `--allow-crop` 才居中裁切。
3. 可选 `scalefit.fit_core`：用单对 `(clip, result)` 估计全局缩放/平移；环带 NCC 低于阈值时跳过并记日志。首版可以先关闭。
4. `SegmentMaps.from_geometry(viewport, inner, erp_w, erp_h, feather_px)`，`composite_frame(source_erp, ai_viewport)` 得到贴回后的 ERP。
5. 只写 inner：用 `local_erp_mask` 的 support，把 `composited[support]` 覆盖到源图，其他像素从源图原样复制。

验收：

- `np.array_equal(out[~support], src[~support])` 为真。
- `support` 内至少有一部分像素变化。
- 不要求 `maxdiff_outside` 之外的近似阈值；`composite_frame` 的视口融合已经处理 inner 边界的颜色差，只写 inner 保证选区外严格不变。

### 4.4 数据与产物

```text
cases/<名>/
  case.toml
  extracts/<版本>/
    clip.png              # 视口裁剪图（16:9，8-bit BGR）
    clip_mask.png         # inner mask（黑=重绘，白=保持）
    image.json            # 冻结几何：erp_w/h、viewport、inner
    result.png            # adopted 的视口结果
    report.json           # 归一化、可选 scalefit、差异统计
  derived/                # clip.png、clip_mask.png、image.json 的副本
  out/<版本>_image.png    # 交付图
```

`image.json`：

```json
{
  "version": 1,
  "erp_width": 8192,
  "erp_height": 4096,
  "viewport": {"yaw_deg": -101.0, "pitch_deg": 0.0, "fov_h_deg": 70.0,
               "width": 1920, "height": 1080},
  "inner": {"x": 420, "y": 280, "width": 1080, "height": 800}
}
```

不复用 `clip.json`：`clip.json` 的字段集冻结，`fps`、`frame_start`、`frame_end` 对静图没有意义；`image.json` 只放静图需要的几何。`image_pad.json` 属于 `img2video` 的全幅路径，`patchimg` 不写它。

### 4.5 CLI

```text
vrstudio case new <名> --flow patchimg --source <erp.png>
vrstudio case draft --case <名> --file <draft.json>
vrstudio extract name --case <名>
vrstudio generate submit --case <名> [--check] [--num 4] [--resolution 4K]
vrstudio generate adopt --case <名> [--round latest] --index <1..N>
vrstudio merge --case <名>
```

`generate submit` 组装 `vrgen image submit`：

```text
--job <case 名>
--template img360-local
--vars-file <job>/prompt-vars.toml
--image extracts/<版本>/clip.png       --image-role edit_master
--image extracts/<版本>/clip_mask.png  --image-role mask
--ratio 16:9
--resolution 4K
--num 4
--session-id <项目会话 ID>
--workdir <vrgen workdir>
```

视口图默认 1920×1080，上传尺寸远低于平台限制；不需要全幅上传副本降采样。`--check` 走 `vrgen image submit --dry-run`。

### 4.6 分辨率与 8K 源

视口局部把模型输出集中在视口上：

- 视口 1920×1080，图片模型 4K 输出约 3840×2160，贴回时降采样到 1920×1080，局部细节来自完整的 4K 输出。
- 视口 3840×2160，模型 4K 输出约 1:1，局部细节最高；ERP 仍是 8K，贴回由投影重采样。
- 全幅方案把 4K 输出摊到 9558 宽，局部只剩约 0.4 倍密度；这是本版改回视口局部的原因。

8K 源的 ERP 只在 extract 时读一次并裁视口；不整幅驻留到提交。`img2video` 的关键帧仍是全幅 4K 输出，8K 细节上限问题保留在那里。

## 5. Flow B：img2video（360 图片→首尾帧→视频）

### 5.1 三种组合与统一模型

你提出的三种组合是：

- 组合一：一开始就有两张图片，分别重绘成首帧与尾帧。
- 组合二：只有一张图片，只重绘一次，首帧与尾帧复用同一张结果。
- 组合三：只有一张图片，但分别重绘两次，首帧的重绘结果作为尾帧重绘的输入。

这三种组合可以收敛成同一个模型：**槽位（slot）+ 绑定（binding）**。

- 一个槽位代表一次关键帧生成：它有源图、可选的参考图、一次图片模型调用，以及一个保留下来的 21:9 padded 结果。
- 绑定决定哪个槽位的 padded 结果当首帧、哪个当尾帧。
- 组合一是两个槽位，各自绑定 first/last。
- 组合二是一个槽位，同时绑定 first 与 last；视频提交时同一个 padded 文件用两次。
- 组合三是两个槽位，第二个槽位的参考图指向第一个槽位的 padded 结果。

因此只需要一条 flow=`img2video`，用 `keyframes.toml` 的 `mode` 表达三种预设，不需要三条流程或三个页面。

### 5.2 padded 域与 recompose 规则

规则可以写成三句话：

1. **每次调用图片模型之前，输入必须处于 padded 域。** 2:1 的源图先 pad 成 21:9；已经是 padded 的中间关键帧直接传入，不重复 pad。
2. **链上的中间关键帧不 recompose。** 它下一步还要作为 padded 输入（组合三的尾帧重绘）或作为 padded 首尾帧提交给视频模型（三种组合都是）；此时做 recompose 再 pad 回来会多一次重采样与量化，并把模型自己生成的冗余带换成拼接后的带，而链上本来就需要 padded 输入。
3. **只有离开 padded 域的产物才 recompose。** 最终交付的 360 视频必须 recompose；要把某张关键帧作为 2:1 图片交付或给用户看 2:1 预览时，才对它做一次 recompose。

所以组合三生成首帧后确实不需要 recompose：首帧的 padded 结果直接作为尾帧重绘的参考图，尾帧的 padded 结果直接和首帧一起提交给视频模型；唯一强制的 recompose 在视频输出上。组合一与组合二同理，链上都不 recompose。

需要区分"canonical 产物"与"预览"：

- canonical 的关键帧是 21:9 padded 图，链上只用它。
- 如果前端要给用户看 2:1 的候选，可以对每个候选生成一张 2:1 的预览图；预览只用于显示，不替换 canonical，也不影响后续调用。
- 如果某个关键帧要作为独立资产交付（例如交给别的流程），再对它做一次正式 recompose。

### 5.3 三种预设的具体行为

组合一 `two_source`：

- `case new` 时给两张 2:1 ERP 图；两张图必须同尺寸，或先归一到同一 ERP 尺寸。
- 两张图各自 pad 成同一组几何的 21:9 画布。
- 首帧槽位用第一张 padded 图生成；尾帧槽位用第二张 padded 图生成。
- 两个 padded 结果直接提交给视频模型。

组合二 `one_reuse`：

- 一张 2:1 源图，pad 一次，生成一次。
- 同一个 padded 结果同时作为首帧与尾帧；视频提交时同一个路径传两次。
- 视频的动作完全由情节提示词驱动；首尾相同意味着模型要回到同一构图。

组合三 `one_two_pass`：

- 一张 2:1 源图，pad 一次。
- 首帧槽位：底图是 padded 源图，mask 用 `redundant_white`（冗余带保持、主内容可重绘），生成 N 张候选，挑一张，保留 padded 结果。
- 尾帧槽位：底图仍是 padded 源图，参考图是首帧的 padded 结果（角色 `first_frame` 或 `subject_ref`），生成 N 张候选，挑一张，保留 padded 结果。
- 两个 padded 结果直接提交给视频模型；首帧不做 recompose。

尾帧的底图也可以改成首帧的 padded 结果，而不是 padded 源图。两种做法的差别是：底图用源图更保场景，参考图用首帧更保人物；底图用首帧则更保首帧的整体构图，但可能把首帧的瑕疵带进尾帧。本文默认前者，列在待确认。

三个预设的提示词由三份新模板承载：`img360-first.md` 描述首帧的构图与主体；`img360-last.md` 描述尾帧相对首帧的变化；`img360-motion.md` 描述首帧到尾帧之间的动作与运镜。图片模板使用 `{image_roles}` 展开底图、mask 与参考图；视频模板使用 firstLastFrame 的模式变量。

### 5.4 视频提交与唯一一次拼接

1. 取两个绑定的 padded 关键帧。组合二是同一个文件两次。
2. 用 `vrgen submit --refs` 提交：两个图片素材，角色 `first_frame` 与 `last_frame`，`--mode firstLastFrame`，`--canvas`/`--source` 用 ERP 尺寸，`--duration` 与情节提示词按用户输入。
3. adopt 生成的 21:9 视频。
4. 视频拼接：逐帧 `restore_canvas`、`circular_translate` 估一个全局 `d*`、`recompose`、`finalize`，输出 2:1 视频；接缝闸门与 fullredraw 相同。

关键帧的 pad 几何与视频拼接的几何必须来自同一个 `image_pad.json`：`P`、`L`、`preroll`、画布尺寸任何一项不一致，接缝都会错位。视频拼接复用现有 `cli/recompose.py` 的核心与 `media/videoio.py`，只换 manifest 与入口。

### 5.5 数据与产物

```text
cases/<名>/
  case.toml
  keyframes.toml              # mode、源图、槽位的轮次/下标/padded 路径
  extracts/<版本>/
    first/padded.png          # 第一张源的 21:9 画布
    last/padded.png           # 第二张源的 21:9 画布（仅 two_source）
    first/padded_mask.png
    last/padded_mask.png
    image_pad.json            # 统一几何；两张源必须同尺寸
  keyframes/
    first_padded.png          # canonical 首帧（21:9）
    last_padded.png           # canonical 尾帧（21:9）；one_reuse 指向 first
    first_preview.png         # 可选，2:1 显示副本
    last_preview.png
  video/
    result.mp4                # adopted 的 21:9 生成视频
  out/<版本>_360.mp4          # 拼接后的 2:1 交付视频
```

`keyframes.toml` 复用现有 `keyframe.toml` 的读写模式，把 `[extract]` 换成 `[pad] version`，记录：

- `mode`：`two_source`、`one_reuse` 或 `one_two_pass`。
- 每个槽位的 `source`、`reference`、`round`、`index`、`padded`。
- `one_reuse` 的尾帧绑定指向首帧，不重复生成。

### 5.6 CLI

```text
vrstudio case new <名> --flow img2video --source <erp.png> [--source-last <erp2.png>]
vrstudio keyframe plan --case <名> --mode two_source|one_reuse|one_two_pass
vrstudio extract name --case <名>
vrstudio keyframe run --case <名> --slot first [--check] [--num 4]
vrstudio keyframe pick --case <名> --slot first --index <1..N>
vrstudio keyframe run --case <名> --slot last [--check] [--num 4]   # one_reuse 跳过
vrstudio keyframe pick --case <名> --slot last --index <1..N>       # one_reuse 跳过
vrstudio generate submit --case <名> [--check] [--duration 4]
vrstudio generate adopt --case <名>
vrstudio merge --case <名>
```

`keyframe` 目前只有 web 接口，没有 CLI。CLI 先行要求把它从 `web/app.py` 抽到共享模块（`keyframe.py` 或新的 `keyframe_flow.py`），web 端点改为调用共享函数。这是重构，不是新逻辑；现有 keyframe 测试可以守护。

### 5.7 验收

- 三种 mode 都能在无额度路径上跑通：图片 `--check`、视频 `--check`、拼接用注入结果。
- `one_reuse` 的视频提交里，首帧与尾帧是同一个 padded 文件，同一路径提交两次不报错且台账能区分 first/last 两条角色。
- `one_two_pass` 的尾帧生成 argv 里包含首帧 padded 作为参考图，且首帧没有被 recompose。
- 最终视频拼接通过接缝闸门，输出 2:1；关键帧预览（如果生成）也能通过。
- 现有 keyframe web 测试不回退。

## 6. 两条流程的复用与顺序

- `patchimg` 共用：`case.py`、`patch/projection`、`patch/extract`、`patch/composite`、`patch/blend`、`patch/scalefit`、`vrgen image submit`。
- `img2video` 共用：`case.py`、`redraw/geometry`、`redraw/padding`、`redraw/preroll`、`redraw/pipeline`、`redraw/recompose_core`、`redraw/registration`、`redraw/verify_core`、`redraw/blend`、`redraw/still`、`media/videoio`、`vrgen image submit`、`vrgen submit`（firstLastFrame）。
- 顺序：先做 `patchimg` 的视口局部，它复用现成视频 patch 模块，风险最低；再做 `img2video` 的全幅 pad/stitch。全幅 `image_pad.json`/`stitch_image` 已在 WP1 完成，保留给 `img2video`。
- 全幅 patchimg 的代码（`padded.png`、`image_pad.json`、`stitch_image` 的 patchimg 分支、上传副本、冗余带守卫）不直接删除，而是从 `patchimg` 路径撤出，转为 `img2video` 的 keyframe 全幅路径与未来整幅重绘的基础；移除 `patchimg` 专用的分支与测试。

## 7. 契约与不动的东西

- 新增 `image.json`（`patchimg` 的视口局部几何）：version、erp_w/h、viewport、inner；没有 fps/时间。
- 新增 `image_pad.json`（`img2video` 的全幅几何）：字段与 `_pad.json` 的几何部分同构，但没有视频属性。
- `clip.json`、`_pad.json`、`run.json` 不动。图片轮次的 `run.json` 已经能表达 `params.images`、`results`、`gate`；首尾帧的角色由顺序与模板固定，不新增字段。
- `roles.json` 不动。底图、mask、首尾帧都是流程产物，不进入 `[submit]` 的角色校验；`vrgen image submit --image-role` 是自由文本，只需在 `IMAGE_ROLE_TEXT` 里补 `edit_master` 与 `mask` 两条文本（已完成）。
- case.toml 增加两个 `FLOWS` 值与可选的 `[adopt] index`；`img2video` 的 `two_source` 需要第二个源图字段，放在 `[source]` 旁边，具体形状在 WP0 定。

## 8. 工作包

### WP0：文档与契约

改动：`docs/case-model.md` 增加两条 flow、`image.json`、`image_pad.json`、`[adopt] index`、`img2video` 的三种 mode、CLI 示例；`docs/decisions.md` 更新决策 46（patchimg 视口局部、img2video 全幅）；`docs/architecture.md` 的流程总图补两条；本文转为正式计划。

验收：文档索引可追溯；排除方案的理由写在决策记录里。

### WP1：静图 pad/stitch 核心（img2video 全幅）

改动：静图 I/O；`image_pad.json` 读写；`pad_image`/`stitch_image`；复用 `redraw` 的单帧函数。

验收：2:1 → 21:9 → 2:1 的恒等往返在合成图上前提下闭合；`P`、`L`、`regions`、`wrap_pair` 与 `plan_pad` 一致；剪裁或重新构图的生成图被闸门拒绝。（已完成，`755ed2d`）

### WP2：patchimg 视口局部（CLI）

改动：
- `case.py` 的 patchimg case/draft（保留）。
- `patch/sidecar.py` 新增 `StillGeometry`（构造即校验 2:1、16:9、inner 在视口内）与 `image.json` 读写。
- `patch/composite.py` 新增 `SegmentMaps.from_geometry`（不伪造 `Segment`）与 `paste_inner`（composite 后只写 inner）；`inner_support`/`inner_bbox` 是唯一的贴回支撑区。
- `extract` 的 patchimg 分支改为视口裁剪 + `make_mask_image` + `image.json`；移除全幅 pad、`padded.png`/`image_pad.json`、冗余带守卫。
- `generate submit` 的 patchimg 分支改为 `vrgen image submit`，输入 `clip.png` + `clip_mask.png`，ratio 16:9、4K、N；`_upload_inputs` 从 patchimg 路径撤出，留给 `img2video` 的关键帧提交。
- `generate adopt --index`（保留），落 `result.png`（视口结果）。
- `merge` 的 patchimg 分支改为 `SegmentMaps.from_geometry` + `composite_frame` + 只写 inner；移除全幅 stitch/local composite 的分支，`patch/still.py` 下线。
- 测试：视口 extract、mask 极性、非 16:9 与 inner 越界拒绝、submit argv、adopt index、贴回选区外逐位不变、跨 ERP 接缝视口的两半支撑与环绕连续。

验收：五步跑通；选区外 `np.array_equal`；8K 源的局部细节来自 4K 视口输出；真实额度验收一次；无额度路径（`--check` + 注入结果）通过。

### WP3：img2video（CLI）

改动：keyframe 逻辑从 web 抽到共享模块并加 CLI；`img2video` case 与两种源的 pad；三种 mode 的槽位状态机；首尾帧生成/挑选；firstLastFrame 提交；视频拼接。

验收：三种 mode 都能跑通；`one_reuse` 的首尾是同一 padded 文件，同一路径提交两次不报错且台账能区分 first/last；`one_two_pass` 的尾帧参考首帧 padded 且首帧未 recompose；最终视频 2:1 闭合；无额度路径（图片与视频各 `--check` + 注入结果）通过；现有 keyframe web 测试不回退。

### WP4：web 与前端（patchimg）

改动：flow 类型、步骤表、静图 pick、视口 extract 产物展示、候选网格、贴回展示、静图对比、候选结果接口、源图入口；pick 页画出 inner 边界并提示覆盖完整主体。

验收：Playwright 跑通新建→pick→extract→生成→挑选→贴回→对比；现有 patch 页面不回退。

### WP5：web 与前端（img2video）

改动：`img2video` 步骤链、三种 mode 的槽位配置、首尾帧候选与挑选、视频提交、视频拼接展示、视频对比；关键帧 2:1 预览按需生成。

验收：Playwright 三种 mode 各跑通一条；现有 patch 页面不回退。

### WP6：gen 整幅 360 缺口（单独立项）

改动：给 gen 的整幅 360 视频增加条件式 pad/stitch；区分 360 与扁平源。

验收：360 源走 pad/stitch，扁平源保持原路径；现有 gen 测试全绿。

### WP7：总验收

改动：无。

验收：两仓库 `pytest` 全绿、`ruff` 干净；两条 CLI 端到端脚本各产出一份交付物并打印接缝与逐位一致结论；真实平台提交在额度可用时补一次人工验收。

## 9. 风险

`patchimg`：

- 视口局部复用了视频 patch 的投影与合成；跨 ERP 接缝的视口依赖 `build_view_map` 的 `BORDER_WRAP`，已有投影基线测试守护。
- inner 必须覆盖完整主体。上一轮全幅验收中，inner 960×540 只到腰部，贴回会在腰线切断；CLI 用户应先看 `clip_mask.png` 或预览，web pick 页要画出 inner 边界。
- 图片模型没有 mask/inpaint 通道。mask 只是提示，模型可能重绘整个视口；选区外保证来自贴回，不来自模型。
- 视口比例必须是模型支持的 ratio；本期固定 16:9，图片模型支持 16:9 与 4K。
- 8K 源的局部细节来自视口图与 4K 输出；视口 1920×1080 时贴回 ERP 后仍是 1920 级细节，要更高细节把视口设为 3840×2160。

`img2video`：

- 全幅 21:9 画布与 4K 输出的分辨率矛盾。4K 源可接受，8K 源细节损失过半；真实 8K 验收确认模型输出 3840×1648，贴回 8192×4096 后局部偏软。
- 117.6 MB 的全幅 PNG 被平台上传接口 403；`assemble_still` 的上传副本降采样（长边 4096）继续用于 `img2video` 的关键帧提交。
- 模型可能裁掉画布或重新构图。拼接的冗余带相关性闸门会拒绝出片；错误信息要指向"模型改动了画布构图"。
- 首帧身份漂移。`one_two_pass` 的尾帧生成以首帧为参考，仍可能在长动作后漂移；需要在提示词与参考图上约束，并在验收里目测。
- 视频拼接的 `d*` 是全局值。与 fullredraw 一样，不做逐帧抖动；如果生成视频的接缝缓慢漂移，需要后续加逐帧模式，但会引入呼吸感。
- 关键帧与视频共用一组 pad 几何。`P`、`L`、preroll、画布尺寸任何一项不一致都会让接缝错位；`image_pad.json` 必须是唯一权威，两层都从它读。
- 中间关键帧不 recompose 意味着它的 canonical 形态是带有冗余带的 21:9 图。如果后续有别的流程直接消费这张图并把它当 2:1 用，会出错；状态文件必须记录每个产物的域（padded 还是 2:1）。
- `one_reuse` 把同一个 padded 文件同时作为首帧与尾帧提交。已确认平台接受同文件做首尾帧；WP3 仍加一条 argv 与台账测试。

## 10. 已确认与待确认

已确认：

- `patchimg` 走视口局部（本版修订，取代上一版的“全幅 21:9”）。理由：与视频 patch 同构；8K 实测证明全幅 4K 输出摊到 9558 宽后局部偏软，且 117.6 MB 全幅 PNG 被平台 403。
- `img2video` 的关键帧与视频走全幅 21:9 pad/stitch。
- `firstLastFrame` 接受 21:9 输入。
- `one_reuse` 可以用同一个 padded 文件同时做首尾帧。

下面几项还没有你的明确回答。本文采用的默认值写在括号里；你纠正哪一项，我改哪一项。

1. `one_two_pass` 的尾帧底图用 padded 源图（默认，参考图为首帧），还是直接用首帧的 padded 结果？前者更保场景，后者更保首帧构图。
2. `img2video` 的输出是全幅 360 视频（默认），还是视口视频？本文按你的意见取全幅，因为新流程不需要记录视口。
3. gen 的整幅 360 `videoEdit` 缺口本轮修不修？默认单独立项，因为它要区分 360 与扁平源，并影响现有 case。
4. flow 值用 `patchimg` 与 `img2video`（默认）。备选是 `imgpatch`/`imgvideo`；只影响标识符。
5. `two_source` 的两张源图是否强制同尺寸（默认强制，避免两套 pad 几何）？如果允许不同尺寸，需要先约定归一到谁的尺寸。
6. `patchimg` 的默认视口宽高用 1920×1080（默认，与视频 patch 一致），还是 3840×2160（8K 源局部细节更高，但上传和生成成本更高）？
