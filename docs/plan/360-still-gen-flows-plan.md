# 360 静图的两条生成流程（审查稿，待批）

状态：按「凡是生成模型产出 360 画布，前后都必须有左右冗余与左右拼接」的原则重写，并把图→视频的三种首尾帧组合收敛成一条 `img2video`。上一版把图→图做成视口裁剪加贴回，缺少 pad/recompose；本版改为全幅 21:9 冗余画布 + 拼接。文末列出仍然需要你确认的取值。

## 0. 结论

- 新增两条 flow：`patchimg`（360 图片局部重绘）与 `img2video`（360 图片→首尾帧→视频）。两条都是独立流程，视频 patch 保持不动。
- 两条流程共用同一套「360 生成辅助」：生成前 `pad`（2:1 ERP 循环冗余到 21:9 画布 + mask + 几何 manifest），生成后 `stitch`（配准、冗余带融合、还原 2:1、接缝闸门）。这套辅助的几何与融合核心在现有 fullredraw 里已经是单帧函数，可以直接复用；需要新写的是静图 I/O、静图 manifest 与两条流程的步骤编排。
- `patchimg` 在全幅拼接之后再按选区做局部贴回，保证选区外与源图逐位一致。`img2video` 不贴回，输出整幅 360 视频，接缝由拼接步骤负责闭合。
- `img2video` 用「槽位 + 绑定」统一三种首尾帧组合：两张源图各重绘一次、一张源图重绘一次首尾复用、一张源图分别重绘两次。链上的中间关键帧保持在 padded 域，不做 recompose；只有最终视频（以及要作为 2:1 交付或预览的关键帧）才 recompose。
- 现有 patch 的视频局部重绘不套用这套辅助：它的生成输入是透视视口裁剪，不是 360 画布；ERP 的左右接缝在 footprint 外，贴回时逐位保留。这一点在 3.5 节单独说明。
- gen 流程里对整幅 360 视频做 `videoEdit` 的路径目前没有 pad/stitch，按这条原则是一个既有缺口。它需要区分 360 与扁平视频，建议单独立项，不塞进本文。

## 0.1 实施状态（2026-10-29）

- WP1 完成：静图 pad/stitch 核心与 `still_pad.json`（vrstudio `755ed2d`）。
- WP2 完成：`patchimg` 的 case/pad、提交、adopt 与贴回（vrstudio `4b34d86`、`9f1dd88`）。
- WP5 完成：vrgen 的 `edit_master`/`mask` 角色文本、`still360-local` 模板与输入限额（vrgen `eb7d6ec`）。
- 真实 8K 验收（2026-10-29）：8192x4096 源、session 2062569522605504、4 张候选；`adopt --index 4` + `merge` 输出 8192x4096 ERP，选区外 `maxdiff 0`，接缝 `wrap 0.437 / percentile 48.1 → ok`。期间补了上传副本降采样（长边 4096）、冗余带守卫与 `changed_inside` 按像素统计。
- WP3（`img2video`）、WP4（前端 `patchimg`）、WP6（gen 整幅 360 缺口）未开始。
- 验证：vrstudio 与 vrgen 的全量 pytest、ruff 通过；真实 `vrgen image submit --dry-run` 生成 `img-` 轮次并打出 `--ratio 21:9 --resolution 4K --num 4`；`patchimg merge` 的选区外 maxdiff 为 0。

## 1. 设计原则与适用边界

原则：**凡是交给生成模型、由模型输出 360 画布（整幅 ERP，或包含 ERP 横向环绕的宽画布）的步骤，前后都必须走「左右冗余—左右拼接」**。

这条原则解决的是同一个问题：模型不知道画布最左与最右是同一圈 360 度，直接生成必然在接缝处出现物体、纹理、光照或运动的不连续。pad 把接缝两侧的真实内容作为冗余带一起交给模型，让它看到完整的环绕邻域；stitch 再用冗余带做配准与融合，把接缝落到模型自己栅格里的相邻列上。

适用边界：

- 生成输入是整幅 ERP 或包含 ERP wrap 的宽画布：适用。fullredraw 已经在做；两条新流程按本文做。
- 生成输入是透视视口裁剪：不适用。视口是普通透视图像，没有 wrap；如果视口跨过 ERP 接缝，投影模块在裁剪前已经把环绕拼好了。现有 patch 属于这一类。
- 生成输入是首尾帧视口图（keyframe 工作台的 16:9）：不适用，理由同上。
- 生成输入是整幅 360 视频且直接 `videoEdit`：适用，但 gen 流程目前没有做。见 3.5 节。

## 2. 需求卡

### 角色与场景

内部制作人员在本机工作站上，通过 CLI 或浏览器处理 VR 360 静图。输入可能是 4K 或 8K 的 2:1 ERP 图。两条流程都不涉及并发、权限与多人协作。

### 任务与失败路径

`patchimg` 的主任务：当我要修一张 360 全景图里的某个人或物体时，我想框选局部、写提示词、生成 N 张候选、挑一张，以便得到一张接缝闭合、选区外完全没变的完整 ERP 图。

`img2video` 的主任务：当我要把一张或两张 360 全景图变成一段 360 视频时，我想按三种首尾帧组合之一生成关键帧、写情节提示词、生成视频，以便得到一段接缝闭合的完整 ERP 视频。

失败路径：

- 源图不是 2:1 时，新建 case 拒绝并报出实际宽高；不静默拉伸或裁切。
- `img2video` 的两张源图尺寸不一致时，拒绝并报出两边尺寸；不静默缩放，因为两张图的 pad 几何必须一致。
- 生成结果的比例与画布不一致时，拼接步骤先按画布宽度还原，比例漂移超过阈值时告警；模型把画布裁掉或重新构图时，冗余带相关性低于阈值，拼接步骤拒绝出片。
- `patchimg` 贴回后选区外出现任何像素差异时，pytest 基线失败；CLI 打印差异像素数。
- 候选没有人工挑选时，adopt 拒绝，要求显式给下标。
- `img2video` 的首帧或尾帧没有定稿时，视频提交拒绝。

### 约束

- 两仓库分离，跨仓库只走 CLI、退出码与台账。
- `clip.json`、`_pad.json`、`runs/<轮次>/run.json` 是冻结契约；两条新流程用新的 `still_pad.json`，不改这三个文件。
- 图像按单帧处理；视频按帧流式处理，不整片驻留内存。
- 平台图片命令只有 `--ratio` 与 `1K/2K/4K`，每轮候选 1..4，没有 mask/inpaint 参数；平台视频命令的模式里没有单图生视频。
- 提交门禁是 `pytest` 全绿与 `ruff` 干净。

### 验收

- `patchimg`：CLI 五步跑通，输出完整 ERP PNG；选区外与源图 `np.array_equal`；接缝闸门通过；N 张候选可人工挑。
- `img2video`：三种 mode 都能在 CLI 跑通，输出 2:1 ERP 视频；接缝指标通过；链上关键帧不做 recompose。
- 两条都不依赖真实平台额度也能跑通：图片走 `image submit --dry-run`，视频走 `submit --dry-run`，拼接用注入的合成结果验证。
- 现有 patch、fullredraw、gen 的测试保持绿色。

### 范围三栏

现在必须做：

- 共用静图 pad/stitch 核心与 `still_pad.json`。
- `patchimg` 的 case、pad、图片提交、adopt、拼接、局部贴回、像素基线。
- `img2video` 的 case、pad、三种槽位组合、首尾帧生成与挑选、firstLastFrame 提交、adopt、视频拼接。
- 两条流程的 CLI 端到端测试。
- 两条流程的 web 与前端步骤链。

以后可以做：

- 8K 源图的分块或局部条带生成，缓解全幅 4K 输出带来的局部细节损失。
- 多区域依次重绘。
- `gen` 的整幅 360 视频补 pad/stitch。

明确不做：

- 单图生视频的图片模型模式：平台没有。
- 把两条新流程塞进现有 patch：会污染视频契约，也会让 if 分支扩散到所有步骤。
- 改造 fullredraw：它已经符合原则。
- 本轮修 gen 的整幅 360 缺口：需要单独决策，因为它要区分 360 与扁平视频，并影响现有 case。

### 优先级

CLI 可行性第一。先做共用辅助与 `patchimg`，把 pad/stitch、局部贴回与像素基线钉死；`img2video` 复用同一套辅助，排在第二；前端两条都排在 CLI 之后。

## 3. 共用辅助：pad 与 stitch

### 3.1 现有 fullredraw 机制

`redraw/geometry.py` 是纯几何，没有 I/O：

- `plan_pad(PadSpec, ...)` 从源尺寸与目标比例推导画布宽度 `Wc`、每侧冗余 `P`、带宽 `L = 2P`、三块区域 `G/R/B`、wrap 对、预滚量 `preroll`，并在返回前调用 `assert_closure` 断言接缝闭合不变量。
- 2:1 源到 21:9 目标时 `P = W/12`；画布保持源高度，只横向加宽。
- `restore_height` 与 `restore_canvas` 负责把模型返回的任意分辨率强制回画布宽度，让区域边界落在整数列上。

`redraw/padding.py` 与 `redraw/pipeline.py` 负责真正的像素变换：

- `pad_horizontal(frame, P)` 用取模索引把左右各 `P` 列环绕复制到对面。
- `pre_roll` 取消 recompose 必然引入的整体旋转，保证交付图保持源图的正前方。
- `apply_chain(frame, chain, ctx)` 对一帧依次执行 `pre_roll` 与 `pad_h`。

`redraw/mask.py` 生成给模型的几何提示图；`recompose` 的几何只从 manifest 读，不读 mask，所以模型忽略或涂改 mask 不会让几何出错。

`redraw/recompose_core.py` 是拼接的几何主体，全部是单帧函数：

- `slice_regions(canvas, spec)` 切出 `G`、`R`、`B`。
- `recompose(canvas, spec)` 用 `blend_block` 把左右冗余带融合成一个宽度为 `L` 的块，拼在 `R` 后面，得到宽度 `W` 的输出。
- `finalize(out)` 只做一次 float64 到 uint8 的量化。
- `restore_canvas(frame, canvas_size, interp)` 把模型返回的帧强制到画布尺寸。

`redraw/registration.py` 的 `circular_translate(G, B, ...)` 估计冗余带的相对位移 `d*` 与相关性；`redraw/verify_core.py` 的 `verdict` 把接缝指标变成 ok/warn/fail。fullredraw 的 `recompose` CLI 只是这些单帧函数外面套了一层视频读写与报告。

### 3.2 静图变体

静图不需要新的几何或新的融合算法，需要的是四件事：

1. 读图与写图的 I/O，按 8-bit BGR、PNG 无损写出。
2. 一个静图 manifest `still_pad.json`，复用 `redraw/manifest.py` 里的 `CanvasInfo`、`PadInfo`、`MaskInfo`、`RestoreInfo` 数据类，去掉 `VideoSettings` 与帧率/帧数字段，增加源图哈希与局部选区。
3. 一个 `pad_still` 步骤：对源图执行 `apply_chain`，得到 21:9 画布；按流程生成 mask；写 manifest。
4. 一个 `stitch_still` 步骤：对生成图执行 `restore_canvas`、`circular_translate`、`recompose`、`finalize`，跑接缝闸门，写报告。

这两步都是单帧，内存占用是一张画布加一张生成图；8K 源大约各 100 MB 量级，可以接受。

### 3.3 视频变体

`img2video` 的视频拼接不需要新算法，直接复用 fullredraw 的 `recompose` 视频路径：

- 逐帧 `restore_canvas`，逐帧 `slice_regions`。
- 在闸门 pass 中用 `circular_translate` 估计一个全局 `d*`（与 fullredraw 一样，不做逐帧抖动）。
- 渲染 pass 用同一个 `d*` 做 `blend_block`，输出宽度 `W` 的 2:1 视频。
- 复用 `FrameReader`/`FrameWriter` 与 `verify_core` 的接缝报告。

差别只在 manifest：`img2video` 的视频阶段没有源视频，manifest 里的源信息换成"首尾帧 + 画布几何"，不写 `_pad.json`。可以在新 manifest 里复用同一组几何字段，让拼接 CLI 不依赖源视频。

### 3.4 复用矩阵

直接复用，不改：

- `redraw/geometry.py`：`plan_pad`、`assert_closure`、`restore_height`。
- `redraw/padding.py`：`pad_horizontal`、`canvas_column_index`。
- `redraw/preroll.py`：`pre_roll`。
- `redraw/pipeline.py`：`TransformContext`、`build_chain`、`apply_chain`。
- `redraw/mask.py`：`redundant_white` 等策略，用于整幅关键帧。
- `redraw/recompose_core.py`：`slice_regions`、`recompose`、`finalize`、`restore_canvas`。
- `redraw/registration.py`：`circular_translate`、`to_gray`。
- `redraw/verify_core.py`：`SeamAccumulator`、`verdict`。
- `redraw/blend.py`：`blend_block`、`weights`。
- `media/videoio.py`：视频拼接的帧读写。

需要新写：

- 静图读写：`cv2.imread`/`cv2.imwrite` 的小封装，固定 8-bit BGR、PNG 无损。
- `still_pad.json` 的读写与校验。
- `pad_still` 与 `stitch_still` 两个单帧步骤。
- `patchimg` 的局部 mask（ERP 空间）与局部贴回。
- `img2video` 的槽位状态机与 firstLastFrame 提交装配。
- 两条流程的 CLI 与 web 步骤。

不复制：

- 时间重采样只在 `patch/framealign.index_map`；两条新流程不涉及时间重采样，视频拼接保持生成视频自己的帧率与帧数。
- ERP 与透视的投影只在 `patch/projection`；`patchimg` 的局部选区到 ERP 掩码仍走这里。
- 画布与源图映射只在 manifest；`patchimg` 的贴回也以 manifest 为准。

### 3.5 适用边界审计

- fullredraw：已符合。pad/recompose 是现有主路径。
- patch（视频局部重绘）：不适用。生成输入是 `extract` 出来的透视视口裁剪，不是 360 画布；视口跨 ERP 接缝时由 `build_view_map`/`build_paste_map` 的环绕采样处理。最终 ERP 的左右接缝在视口 footprint 之外，`composite_frame` 原样复制，逐位保留。如果为了统一而给视口也加冗余带，不但没有收益，还会改变现有像素基线。
- keyframe 工作台（16:9 视口首尾帧）：不适用，理由同上。
- gen 的整幅 360 `videoEdit`/`allMediaRef`：**缺口**。源视频是整幅 ERP 时，模型输出也是整幅 360 视频，但没有 pad/recompose。按原则应当补，但需要先区分 360 源与扁平源，且会影响现有 gen case。建议单独立项，本文只登记。
- 新的 `patchimg` 与 `img2video`：按本文执行。

## 4. Flow A：patchimg（360 图片局部重绘）

### 4.1 步骤链

```text
case new（源 ERP 图）
  → pick（视口 + inner，定义局部区域）
  → extract / pad（全幅 21:9 冗余画布 + 局部 mask + still_pad.json）
  → generate（vrgen image submit，N 张候选）
  → adopt --index（挑一张 21:9 生成图）
  → merge / stitch（配准 + 冗余带融合 + 还原 2:1 + 局部贴回）
  → compare（源图 vs 结果）
```

没有 keyframe，没有 assemble。`extract` 在本流程里做的是 pad，不是视频抽帧；命令名复用是为了让 web 的 op 注册表与用户习惯不变，文档里写明语义。

### 4.2 生成画布、mask 与局部区域

生成输入是整幅 21:9 冗余画布，不是视口裁剪。这样模型能看到 ERP 接缝两侧的真实内容，局部编辑在接缝附近也能保持连续。

`pick` 仍然用视口加 inner 定义"要改哪里"，但它只用于两件事：

- 生成 mask：mask 全白，局部区域涂黑。白色表示保持，黑色表示重绘；左右两条冗余带保持白色。这个极性与现有视频 mask 一致，图片模型是否按同样方式理解需要一次单帧 A/B 确认，见第 9 节。
- 拼接后的局部贴回：把 inner 反投影成 ERP 空间掩码，只在这个掩码内用拼接结果覆盖源图。

局部区域必须落在干净主内容 `[P, W-2P)` 内，不能压到左右冗余带。压到带上时 `pad_h` 会把黑区复制到另一侧，mask 变成横贯画布的宽条；`extract` 现在直接拒绝并提示把视口移离接缝或缩小 inner。跨接缝的局部编辑需要专门方案，本期不做。

### 4.3 拼接与像素保证

`merge` 分支做三件事：

1. 读 `still_pad.json`，对 adopted 的 21:9 结果做 `restore_canvas`。
2. 用 `circular_translate` 估计 `d*` 与冗余带相关性，跑闸门；`recompose` 得到宽度 `W` 的 2:1 完整图，`finalize` 量化一次。
3. 局部贴回：把 inner 反投影成 ERP 空间掩码，向内羽化；用 `multiband_blend(源图, 拼接图, 掩码)` 融合，然后把掩码支撑之外的像素从源图原样复制，保证逐位一致。

验收写成：

- `np.array_equal(out[~local_support], src[~local_support])` 为真。
- `local_support` 内至少有一部分像素发生变化。
- 接缝闸门的相关性不低于阈值；低于阈值时拒绝出片并提示"模型裁掉了画布或重新构图"。

### 4.4 数据与产物

```text
cases/<名>/
  case.toml
  extracts/<版本>/
    padded.png            # 21:9 冗余画布，交给模型
    padded_mask.png       # 局部 mask（黑=重绘，白=保持）
    still_pad.json        # 几何、源图哈希、局部选区、mask 信息
    result.png            # adopted 的 21:9 生成图
    closed.png            # 拼接后的 2:1 完整图
    local.png             # 局部贴回后的最终图
    report.json           # d*、相关性、接缝指标、选区外差异
  derived/                # padded.png、padded_mask.png、still_pad.json 的副本
  out/<版本>_still.png    # 交付图
```

`case.toml` 与 patch 共用 `[viewport]`、`[inner]`、`[extract]`、`[submit]`、`[adopt]`，不写 `[frames]`。`[adopt]` 增加可选的 `index`，只对 `patchimg` 有意义。

`still_pad.json` 复用 `CanvasInfo`、`PadInfo`、`MaskInfo`、`RestoreInfo`，另外记录：

- `source.path`、`source.size`、`source.sha256_16`。
- `local.viewport`、`local.inner`。
- `output.width`、`output.height`（等于源图 2:1 尺寸）。

### 4.5 CLI

```text
vrstudio case new <名> --flow patchimg --source <erp.png>
vrstudio case draft --case <名> --file <draft.json>     # 视口与 inner，可手填
vrstudio extract name --case <名>
vrstudio generate submit --case <名> [--check] [--num 4] [--resolution 4K]
vrstudio generate adopt --case <名> [--round latest] --index <1..N>
vrstudio merge --case <名>
```

`case draft` 是为了 CLI 先行而加的薄命令：web 的 pick 与它共用 `case_mod.set_draft`，不新增几何逻辑。

`generate submit` 组装 `vrgen image submit`：

```text
--job <case 名>
--template still360-local
--vars-file <job>/prompt-vars.toml
--image extracts/<版本>/padded.png       --image-role edit_master
--image extracts/<版本>/padded_mask.png  --image-role mask
--ratio 21:9
--resolution 4K
--num 4
--session-id <项目会话 ID>
--workdir <vrgen workdir>
```

`--check` 对应 `vrgen image submit --dry-run`。不传视频参数。

### 4.6 分辨率取舍

全幅 21:9 画布的总宽度是按源图高度与 21:9 算出来的。2:1 的 4K 源（4096×2048）对应画布约 4780×2048；2:1 的 8K 源（8192×4096）对应画布约 9558×4096。平台图片生成最高档是 4K，返回图的像素预算由平台决定；如果 4K 档的长边约 4096，那么全幅画布会被模型显著降采样，局部区域的细节密度随之下降。

量级：

- 4K 源：画布 4780 宽，模型 4K 输出约 4096 宽，比例约 0.86，局部细节损失约一成多，通常可接受。
- 8K 源：画布 9558 宽，比例约 0.43，局部细节损失过半，生成的人脸或物体在贴回后可能显得糊。

本版默认支持 4K ERP 源，8K 源的细节补救放到后续：分块生成、以视口为中心的局部宽条生成、或等平台提供更高输出档。这个取舍必须在方案里写明，避免上线后才发现 8K 素材的效果不达预期。

平台上传接口对超大 PNG 返回通用 403：117.6 MB 的 9558x4096 `padded.png` 在真实提交时被拒，缩到长边 4096 的 `upload.png`/`upload_mask.png` 后成功。`assemble_still` 现在自动生成这两个提交副本（`generate.image_upload_max_side`，默认 4096），canonical pad 与最终 ERP 仍是源分辨率；模型输出 3840x1648，贴回 8192x4096 后局部偏软，这是 8K 源的预期上限。

已确认：`patchimg` 提交给图片模型的输入图使用全幅 21:9 冗余画布。局部宽条保留为后续优化，只在 8K 源细节不达预期时再评估；它不改变本文的几何与拼接主路径。

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

这是对你"是否可以少做一次 recompose"的回答。

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

三个预设的提示词由三份新模板承载：`still360-first.md` 描述首帧的构图与主体；`still360-last.md` 描述尾帧相对首帧的变化；`still360-motion.md` 描述首帧到尾帧之间的动作与运镜。图片模板使用 `{image_roles}` 展开底图、mask 与参考图；视频模板使用 firstLastFrame 的模式变量。

### 5.4 视频提交与唯一一次拼接

1. 取两个绑定的 padded 关键帧。组合二是同一个文件两次。
2. 用 `vrgen submit --refs` 提交：两个图片素材，角色 `first_frame` 与 `last_frame`，`--mode firstLastFrame`，`--canvas`/`--source` 用 ERP 尺寸，`--duration` 与情节提示词按用户输入。
3. adopt 生成的 21:9 视频。
4. 视频拼接：逐帧 `restore_canvas`、`circular_translate` 估一个全局 `d*`、`recompose`、`finalize`，输出 2:1 视频；接缝闸门与 fullredraw 相同。

关键帧的 pad 几何与视频拼接的几何必须来自同一个 `still_pad.json`：`P`、`L`、`preroll`、画布尺寸任何一项不一致，接缝都会错位。视频拼接复用现有 `cli/recompose.py` 的核心与 `media/videoio.py`，只换 manifest 与入口。

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
    still_pad.json            # 统一几何；两张源必须同尺寸
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
- `one_reuse` 的视频提交里，首帧与尾帧是同一个 padded 文件。
- `one_two_pass` 的尾帧生成 argv 里包含首帧 padded 作为参考图，且首帧没有被 recompose。
- 最终视频拼接通过接缝闸门，输出 2:1；关键帧预览（如果生成）也能通过。
- 现有 keyframe web 测试不回退。

## 6. 两条流程的复用与顺序

- 共用：`case.py`、`redraw/geometry.py`、`redraw/padding.py`、`redraw/pipeline.py`、`redraw/recompose_core.py`、`redraw/registration.py`、`redraw/verify_core.py`、`redraw/blend.py`、`media/videoio.py`、`vrgen image submit`、`vrgen submit`（firstLastFrame）。
- 分叉：`patchimg` 有视口/inner 与局部贴回；`img2video` 有槽位状态机与视频提交。
- 顺序：先做共用静图 pad/stitch 与 `patchimg`，它把几何、manifest、拼接闸门、像素基线全部钉死；再做 `img2video`，它复用这些产物，只多一层槽位与视频提交。反过来做会让 `img2video` 先造一套临时 I/O，后面还要改。

## 7. 契约与不动的东西

- 新增 `still_pad.json`；字段与 `_pad.json` 的几何部分同构，但没有视频属性。两条新流程的拼接都以它为准。
- `clip.json`、`_pad.json`、`run.json` 不动。图片轮次的 `run.json` 已经能表达 `params.images`、`results`、`gate`；首尾帧的角色由顺序与模板固定，不新增字段。
- `roles.json` 不动。底图、mask、首尾帧都是流程产物，不进入 `[submit]` 的角色校验；`vrgen image submit --image-role` 是自由文本，只需在 `IMAGE_ROLE_TEXT` 里补 `edit_master` 与 `mask` 两条文本。
- case.toml 只增加两个 `FLOWS` 值与可选的 `[adopt] index`；不新增 `target` 字段，目标种类由 flow 值编码。`img2video` 的 `two_source` 需要第二个源图字段，放在 `[source]` 旁边，具体形状在 WP0 定。

## 8. 工作包

### WP0：文档与契约

改动：`docs/case-model.md` 增加两条 flow、`still_pad.json`、`[adopt] index`、`img2video` 的三种 mode、CLI 示例；`docs/decisions.md` 增加决策记录（含排除方案与验证方式）；`docs/architecture.md` 的流程总图补两条；本文转为正式计划。

验收：文档索引可追溯；排除方案的理由写在决策记录里。

### WP1：共用静图 pad/stitch 核心

改动：新增静图 I/O；新增 `still_pad.json` 读写；新增 `pad_still`/`stitch_still`；复用 `redraw` 的单帧函数。

验收：2:1 → 21:9 → 2:1 的恒等往返在合成图上前提下闭合；`P`、`L`、`regions`、`wrap_pair` 与 `plan_pad` 一致；剪裁或重新构图的生成图被闸门拒绝。

### WP2：patchimg（CLI）

改动：case 模型、`case draft`、`extract` 的 pad 分支、图片提交、adopt `--index`、`merge` 的拼接与局部贴回。

验收：五步跑通；选区外 `np.array_equal`；接缝闸门通过；候选下标显式；无额度路径（`--check` + 注入结果）通过。

### WP3：img2video（CLI）

改动：keyframe 逻辑从 web 抽到共享模块并加 CLI；`img2video` case 与两种源的 pad；三种 mode 的槽位状态机；首尾帧生成/挑选；firstLastFrame 提交；视频拼接。

验收：三种 mode 都能跑通；`one_reuse` 的首尾是同一 padded 文件，同一路径提交两次不报错且台账能区分 first/last 两条角色；`one_two_pass` 的尾帧参考首帧 padded 且首帧未 recompose；最终视频 2:1 闭合；无额度路径（图片与视频各 `--check` + 注入结果）通过；现有 keyframe web 测试不回退。

### WP4：web 与前端（patchimg）

改动：flow 类型、步骤表、静图 pick、pad 产物展示、候选网格、拼接与局部贴回展示、静图对比、候选结果接口、源图入口。

验收：Playwright 跑通新建→pick→pad→生成→挑选→拼接→对比；现有 patch 页面不回退。

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

- 图片模型没有 mask/inpaint 通道。mask 只是提示，模型可能重绘整幅画布；局部保证来自贴回，不来自模型。生成页与文档必须写清楚。
- 图片模型的 mask 极性未知。现有约定是黑=重绘、白=保持；需要在真实模型上做一次单帧 A/B。极性错误只影响模型是否听话，不影响贴回的像素保证。
- 全幅 21:9 画布与 4K 输出的分辨率矛盾。4K 源可接受，8K 源细节损失过半；缓解手段是分块、局部宽条或更高输出档。真实 8K 验收确认：模型输出 3840x1648，贴回 8192x4096 后局部偏软；并且 117.6 MB 的全幅上传被平台 403，已改为 4096 长边上传副本。
- 局部 inner 必须覆盖完整主体。第一轮 inner 只到腰部，贴回会在腰线切断；CLI 用户应先看 `padded_mask.png` 或预览，web pick 页要画出 inner 边界。
- 局部选区压到冗余带会让 `pad_h` 复制黑区，mask 变成横贯画布的宽条；`extract` 已拒绝并提示移开接缝或缩小 inner。
- 模型可能裁掉画布或重新构图。拼接的冗余带相关性闸门会拒绝出片；错误信息要指向"模型改动了画布构图"，而不是笼统的失败。
- 首帧身份漂移。`one_two_pass` 的尾帧生成以首帧为参考，仍可能在长动作后漂移；需要在提示词与参考图上约束，并在验收里目测。
- 视频拼接的 `d*` 是全局值。与 fullredraw 一样，不做逐帧抖动；如果生成视频的接缝缓慢漂移，需要后续加逐帧模式，但会引入呼吸感。
- 8K 源图的单帧内存约 100 MB 量级，可以接受；但 PNG 写出慢，且 16-bit 输入会被降到 8-bit。本期要求源图已经是摆正的 8-bit sRGB ERP。
- 关键帧与视频共用一组 pad 几何。`P`、`L`、preroll、画布尺寸任何一项不一致都会让接缝错位；`still_pad.json` 必须是唯一权威，两层都从它读。
- 中间关键帧不 recompose 意味着它的 canonical 形态是带有冗余带的 21:9 图。如果后续有别的流程直接消费这张图并把它当 2:1 用，会出错；状态文件必须记录每个产物的域（padded 还是 2:1），消费方按域处理。
- `one_reuse` 把同一个 padded 文件同时作为首帧与尾帧提交。已确认平台接受同文件做首尾帧；WP3 仍加一条 argv 与台账测试，防止上传与台账因哈希相同而回归。
- `firstLastFrame` 的 21:9 输入已确认可用，pad 的 `P` 与画布几何不需要为首尾帧模式单独调整。

## 10. 已确认与待确认

已确认：

- `patchimg` 提交给图片模型的输入图使用全幅 21:9 冗余画布。
- `firstLastFrame` 接受 21:9 输入。
- `one_reuse` 可以用同一个 padded 文件同时做首尾帧。

下面几项还没有你的明确回答。本文采用的默认值写在括号里；你纠正哪一项，我改哪一项。

1. `one_two_pass` 的尾帧底图用 padded 源图（默认，参考图为首帧），还是直接用首帧的 padded 结果？前者更保场景，后者更保首帧构图。
2. `img2video` 的输出是全幅 360 视频（默认），还是视口视频？本文按你的意见取全幅，因为新流程不需要记录视口。
3. gen 的整幅 360 `videoEdit` 缺口本轮修不修？默认单独立项，因为它要区分 360 与扁平源，并影响现有 case。
4. flow 值用 `patchimg` 与 `img2video`（默认）。备选是 `imgpatch`/`imgvideo`；只影响标识符。
5. `two_source` 的两张源图是否强制同尺寸（默认强制，避免两套 pad 几何）？如果允许不同尺寸，需要先约定归一到谁的尺寸。
