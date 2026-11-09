# Case 数据模型与 vrgen CLI 契约

两仓库的唯一接口权威。任何字段或命令面的变更先改本文，再改两侧代码与测试。

迁移状态：§2 的素材角色与校验、§4 的 `vrgen submit` 参数面与 `--refs` 清单、§5 的
台账字段已按 `unified-submit-plan.md`（2026-10-21 立项）重写为统一提交契约；同日按
决策 33/34 修订：提交集只认用户勾选，clip/pad 与文件素材同为候选、mask 自动附带
（fullredraw 视频无前置图片时除外，见 §2）、raw 帧仅工作台、没有 `derived` 标记，
patch 的 extract 同时产出 clip 的首尾原始帧。
vrgen 侧已于 2026-10-21 迁移完成（`submit` 只剩 `--refs`，本地半场一条路径，台账不再写
`params.input`/`params.mask`）；vrstudio 侧按本文目标契约迁移。

## 1. 原则

**case.toml 只放这个视频任务的静态事实。**
生成侧的一切（提示词、分辨率档、task_id、素材 id、调用日志）都不进 case；
它们住在 vrgen 的台账树里。case → vrgen 的唯一耦合是一行 `[adopt]` 指针。

## 2. case.toml 格式

### flow = "patch"（局部重绘：UE 出全景 + 白膜人物）

```toml
flow = "patch"

[source]
path = "../sources/ue_render_03.mp4"
sha256 = "…"            # merge 前校验；防"几何配错视频"

[pick]                  # 当前选中的范围预设；没有 preset 时可以为空
active = "r1"

[[range_preset]]        # 手动保存的选区；可多条，id 递增、删除后不复用
id = "r1"
created_at = "2026-11-09T16:30:00+08:00"
updated_at = "2026-11-09T17:05:00+08:00"

[range_preset.viewport] # 选区角度与视口像素尺寸
yaw_deg = 0.0
pitch_deg = -10.0
fov_h_deg = 90.0
width = 1470
height = 943

[range_preset.inner]    # 白膜子区（视口内坐标）：真正送去重绘的部分
x = 400
y = 200
width = 600
height = 500

[range_preset.frames]
start = 24
end = 168

[extract]               # 当前生效的抽取版本（web extract 时写入）
current = "20260923T073001"   # → extracts/<时间戳>/；generate 与 merge 都以它为准

[adopt]                 # vrgen 台账里被采用的轮次；采用时结果已拷入本 case
round = "dusk-c3a41f90"

[merge]                 # 可选：外部重绘的视口视频；缺省回退 extracts/<current>/result.mp4
input = "v2"            # 本 case 素材库里 kind = video 的一条
```

patch 与 fullredraw 也可以有 `[[assets]]`（三视图、重绘定稿帧等文件素材）和可选的 `[submit] selected`，格式与 gen 示例相同；源视频仍然只放在 `[source]`。流程产物不写进 `[[assets]]`，路径由 `[extract] current` 或 manifest 决定；其中 patch 的 `clip`、fullredraw 的 `pad` 是用户可勾选的候选，mask 是流程自动附带的控制图（fullredraw 视频在没有任何用户图片时不附带，见 §2），首尾原始帧只进工作台输入区（见 §4 `--refs` 清单）。

web pick 的高频操作只写 `derived/pick/draft.toml`；`vrstudio extract name --case X [--preset ID]` 按选中的 preset 抽取，缺省用 `[pick] active`。抽取版本的几何冻结在 `clip.json`，不记录 preset id。

### flow = "patchimg"（360 静图局部重绘：视口局部）

```toml
flow = "patchimg"

[source]
path = "../sources/pano_8k.png"
sha256 = "…"            # merge 前校验；源图必须是 2:1 ERP

[pick]
active = "r1"

[[range_preset]]
id = "r1"
created_at = "2026-11-09T16:30:00+08:00"
updated_at = "2026-11-09T17:05:00+08:00"

[range_preset.viewport]
yaw_deg = -101.0
pitch_deg = 0.0
fov_h_deg = 70.0
width = 1920            # 16:9：图片模型支持的档位
height = 1080

[range_preset.inner]    # 视口内坐标：真正要重绘的区域，必须覆盖完整主体
x = 420
y = 280
width = 1080
height = 800

[extract]
current = "20261029-101500"

[adopt]
round = "img-77c1a0e4"
index = 3               # 图片轮次里被采用的那张（1..N）；patchimg 必填
```

`image.json`（`extracts/<版本>/image.json`，version=1）是 patchimg 的几何唯一权威，与 `clip.json` 同地位但去掉了时间：

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

设计说明：

- 与 patch 同构：extract 只裁出透视图口 `clip.png`，图片模型只重绘这一张，merge 用与视频 patch 相同的投影与 `composite_frame` 贴回，再只写 inner；不做全幅 pad/recompose。视口跨 ERP 接缝时，投影的环绕采样先把它拼成连续图像，因此不需要冗余带。
- 视口比例必须是图片模型支持的 16:9；非 16:9 在 extract 与 submit 两处拒绝。视口宽高只是草稿字段（1920×1080 或 3840×2160），不是枚举。
- inner 必须覆盖完整主体：贴回只写 inner，主体跨出 inner 会在边界被切断。CLI 先看 `clip_mask.png`，web pick 页要画出 inner 边界。
- mask 是提示不是通道：平台图片命令只有 `--ratio` 与 `1K/2K/4K`，没有 inpaint 参数；选区外严格不变的保证来自贴回，不来自模型。
- `clip.json`、`_pad.json`、`image_pad.json` 都不属于 patchimg；`image_pad.json` 留给 `img2video` 的全幅路径。

### flow = "fullRedrawImg"（360 静图全幅重绘：21:9 画布 + 氛围参考）

```toml
flow = "fullRedrawImg"

[source]
path = "../sources/pano_8k.png"
sha256 = "…"            # extract 前校验；源图必须是 2:1 ERP

[[assets]]                     # 氛围参考；可多张，都用 lighting_ref
id = "i1"
kind = "image"
path = "assets/i1_palace_light_ref_01.png"
role = "lighting_ref"

[submit]
selected = ["i1"]

[extract]
current = "20261029-141749"

[adopt]
round = "img-…"
index = 2               # 图片候选下标，必填

[merge]                 # 拼接输入；整段缺省 = extracts/<current>/result.png（adopt 落点）
input = "i2"            # 本 case 素材库里 kind = image 的一条，必须是 21:9 画布图
```

设计说明：

- 没有 `[viewport]/[inner]/[frames]`：几何全部由 extract 决定——整幅 pad 成 21:9。改几何等于换源或改 pad 配置重新 extract，不是改草稿。
- 提交顺序固定为 基图 → mask → `[submit] selected` 里的氛围参考（全部 `lighting_ref`）。基图与 mask 由装配器自动附带，不写进 `selected`。
- **必须提交 mask**：`redundant_white` 把左右两条冗余带标白，它们是同一条全景接缝的两份拷贝，也是 `stitch_image` 的配准锚点。代价是横跨接缝的那条带（源图 `[6826,8192)`，约占 ERP 的 16.7%）保持源图像素、不参与重绘；换来的是接缝稳定闭合。实测不交 mask 时 4 张候选只有 1 张过 band correlation 闸门。
- 参考图总数受模型上限约束（mglc 模型 44 的 `maxReferenceCount = 13`），vrstudio 在装配时按 `generate.image_max_refs` 断言；基图与 mask 占 2 张，所以氛围参考最多 11 张。
- 比例只能是 21:9：模型的比例表里没有 2:1（最宽 21:9）。merge 用 `stitch_image` 还原 2:1 到源图分辨率。
- 最终细节上限是 4K：模型输出 4K 21:9，还原到 8K 是约 2.1 倍上采样；实测区块细节只剩源图的 9%（纯重采样对照组 19%）。这是整幅重绘路线的固有代价。
- 拼接输入不必是本轮生成的候选：`[merge] input` 指向素材库里的一条文件，用于美术在外部工具改完、按 21:9 画布导回的结果。fullRedrawImg 用 `kind = image` 的 21:9 画布图，fullredraw 用 `kind = video` 的 21:9 画布视频；指针只认本 case 的对应种类素材，删除该素材时清空指针并回退到 adopt 结果。图片流程拼接前按 manifest 的 `canvas.size` 校验输入宽高比，2:1 源图或成片会以退出码 2 拒绝，而不是交给 `restore_canvas` 拉伸后靠冗余带相关性兜底；视频流程不新增宽高比硬校验，错比例的输入由 recompose 的冗余带相关性闸门在渲染前拒绝。patchimg 的贴回仍只接受 adopt 结果。拼接页的「上传并用作拼接输入」把文件以 `merge_input` 角色加入素材库并选中它；该角色 `kinds = ["image", "video"]`、`modes = []`、`open = false`，不参与生成提交，也不能在生成页下拉里被选到。

### 图片两条流程的共同契约（web 视角，2026-10-30 起）

- 源与建案例：`[source] path/sha256`，源文件是 2:1 ERP 图片。`vrstudio case new --flow patchimg|fullRedrawImg --source <erp.png>` 与 web 建案例走同一条校验：比例绝对偏差超过 0.001 拒绝并报实际宽高；web 的图片源来自 `sources/` 目录或上传，后缀取 `_IMAGE_EXTS`。patchimg 建好即写入默认 16:9 草稿，fullRedrawImg 没有选区草稿、建完即可 extract。
- 五步以 case 为单位：`case draft`（仅 patchimg）→ `extract name --case [--preset ID]` → `generate submit --case [--num N] [--resolution 1K|2K|4K] [--image-model-id <id>] [--session-id <id>]` → `generate adopt --case --index N` → `merge --case`。web 复用现有 op（extract / submit / dry_run / adopt / merge），不新增 op 或子命令。
- `[adopt] index` 两条流程都必填：`generate adopt` 在缺下标时直接拒绝，web 的 adopt 必须透传下标。
- `[merge] input` 属于 patch、fullRedrawImg 与 fullredraw：patch 的 `merge --case` 按它取外部重绘的视口视频，缺省或清空后回退 `extracts/<current>/result.mp4`；图片流程的 `merge --case` 按它取拼接输入，缺省或清空后回退 `extracts/<current>/result.png`；fullredraw 的 `recompose` 按它取输入，缺省或清空后回退 case 根目录的 `result.mp4`。web 的门控接受这些来源，步骤页显示实际要用的那个文件。
- 输出分辨率默认等于 case 源尺寸；`recompose`（视频）与 `merge`（图片）都接受 `--follow-input`，改由输入件自身的宽高派生输出几何（画布等于输入件尺寸、带宽由输入件的宽高比算出），输入比案例分辨率大时输出也会更大，规则与边界见 `docs/plan/follow-input-upload-size-plan.md`。跟随输入时视频写 `out/<轮次>_<W>x<H>.mp4`、图片写 `out/<extract>_image_<W>x<H>.png`，与案例分辨率的成片并存；该选择只随单次运行，不写进 `case.toml`。配准代价曲线平坦（`warn`）时 `d*` 按 0 混合，报告记 0。
- 产物：patchimg 写 `clip.png`、`clip_mask.png`、`image.json`；fullRedrawImg 写 `padded.png`、`padded_mask.png`、`image_pad.json`，提交时另存 `upload.png`/`upload_mask.png` 副本。两条流程的交付物都是 `out/<版本>_image.png`（不是 mp4）。
- `image.json` 与 `image_pad.json` 的字段集不变；后者 manifest 的 `kind` 值为 `image`。
- 图片提交的提示词变量写在 job 的 `prompt-vars.toml`：`generate submit` 对两条图片流程拒绝 `--var`，也拒绝 `--mode/--duration/--aspect-ratio/--scale`。

### flow = "fullredraw"（全景重绘：AI 重绘整个 360°）

```toml
flow = "fullredraw"

[source]
path = "../sources/stock_pano.mp4"
sha256 = "…"            # 可选：pad 之后源不再被读，manifest 已含源身份

[adopt]
round = "dusk-a9fb11bc"

[merge]                 # 拼接输入；整段缺省 = case 根目录/result.mp4（adopt 落点）
input = "v3"            # 本 case 素材库里 kind = video 的一条，必须是 21:9 画布视频
```

### flow = "gen"（多素材生成：素材自带，模式由 generation.toml 决定）

```toml
flow = "gen"

[[assets]]                     # 有序数组；顺序决定 @VideoN / @ImageN 编号
id = "v1"                      # case 内唯一；前端、文件名校验与台账映射都认它
kind = "video"                 # video | image
path = "assets/v1_main.mp4"    # 相对 case 目录；case 自带文件
role = "edit_master"           # 受控词表见下方“设计说明”；视频与图片共用
sha256 = "…"                   # 可选；添加时计算，提交前校验

[[assets]]
id = "v2"
kind = "video"
path = "assets/v2_motion_ref.mp4"
role = "motion_ref"
sha256 = "…"

[[assets]]
id = "i1"
kind = "image"
path = "assets/i1_character.png"
role = "subject_ref"
sha256 = "…"

[submit]                       # 可选：本次提交的候选 id 列表；缺省为空集
selected = ["v1", "i1"]        # 顺序决定 @VideoN / @ImageN；角色见 [submit.roles]

[submit.roles]                 # 可选：本次提交的逐条角色；缺省回退到 [[assets]] role
v1 = "edit_master"
i1 = "subject_ref"

[adopt]
round = "dusk-3c1a4b2d"
```

设计说明：

- `[[assets]]` 不再是 gen 专属：patch、fullredraw 也可以有文件素材列表（三视图、重绘定稿帧等）。三条流程的既有段（patch/patchimg 的 `[source]/[[range_preset]]`、fullredraw 的 `[source]`、以及 `*_pad.json` manifest）不变。
- 原始源视频与流程产物（patch 的 clip/mask/首尾原始帧、fullredraw 的 pad/mask）不写进 `[[assets]]`，路径由 `[extract] current` 或 manifest 决定，避免与 `[source]` 的哈希契约形成双重真源。其中 clip/pad 作为可勾选候选；mask 由装配器自动附带，不作为用户素材；首尾原始帧只作工作台输入。提交契约不区分来源，也没有 `derived` 标记。merge 成片是流程输出，不作为生成提交候选。
- 源视频为什么不并进 `[[assets]]`（2026-10-27 补充，与 gen 的差异在此说明）：patch 的 `[source] sha256` 是 merge 前的校验契约，同一份视频再记一条素材就是双重真源；fullredraw 的生成母版是 `pad` 产物（候选 id `pad`、角色 `edit_master`），源视频只被 `vrstudio pad` 读一次，并进素材库会让候选里出现两个 `edit_master` 视频，而提交几何由 manifest 决定，选错源会静默错片。此外 `[[assets]]` 的语义是"复制进 `cases/<name>/assets/` 的文件"，源视频是从共享池 `sources/` 直接引用的数 GB 原片，按 case 复制一份没有收益。gen 既没有流程段也没有流程母版，源视频本身就是第一条素材，所以 gen 反过来取消 `[source]`（见本节末尾的迁移说明）。界面上的统一由素材库承担：素材库在 `[[assets]]` 表格上方以只读「流程文件」组显示源视频与流程母版（`info.source_file` 与 `source === 'flow'` 的候选，可查名、查路径、打开原片，母版还标出是否已加入本次提交），不改动以上数据规则。
- 角色词表：`edit_master`、`motion_ref`、`space_ref`、`scene_ref`、`lighting_ref`（光照参考，只给光源位置、色温、明暗对比与空气质感，不给构图与画面内容）、`subject_ref`、`first_frame`（首帧定稿图）、`last_frame`（尾帧定稿图）、`mid_frame`（中间过渡帧，预留）、`first_frame_raw`、`last_frame_raw`（工作台输入底图，由 patch 的 extract 从 clip 首尾导出）、`mask`（编辑区域标注图；由 patch/fullredraw 的流程产物提供，装配器自动附带，不作为用户候选，也不参与 `@ImageN` 编号；fullredraw 视频无前置图片时不附带，见 §2）。机器可读的权威是 `docs/roles.json`（每项含 name/label/help/prompt/kinds/modes/open/reserved），两仓库各存一份逐字节相同的副本。图片步另有 `detail_ref`（细节参考），只存在于 `keyframe.toml` 的 `refs`，不进入视频提交清单。用户素材的角色由用户在引用清单里选择，不按顺序推断；空角色是未完成状态，提交前必须补齐。
- 当前前端开放的角色按素材种类区分：视频为 `edit_master`、`subject_ref`、`motion_ref`；图片在这三个之外增加 `lighting_ref`，因为光照参考只对图片成立。`firstLastFrame` 模式另开 `first_frame` / `last_frame`。`scene_ref`、`space_ref`、`mid_frame` 仍在后端词表里，用于旧 case 与直接调用 CLI 的路径；普通下拉不展示，旧值以「旧角色」标记显示，可改成开放角色。
- `[submit]` 是可选的提交集：`selected` 是本次提交的有序 id 列表，`roles` 是可选的逐 id 角色映射。没有默认集，缺省等于空集，勾选才提交。角色按 `roles[id]` 取；没有该键时回退到 `[[assets]] role`，因此旧 case 不需要迁移。同一份清单里一个素材只出现一次；跨步骤可以重复引用，角色各自记录。clip/pad 用固定 id 也可以出现在 `selected` 里；mask 不写进 `selected`，由装配器在提交时自动追加。写入只发生在 vrstudio，vrgen 只读 refs JSON，不认识这两个字段。删除素材时同步从 `selected` 与 `roles` 移除；重排不改 id，`selected` 不动。旧 case 没有这个字段时按空集处理，升级后首次打开需要重新勾选一次。
- `target_aspect` 不在 case 里——它是平台 bucket 参数，进 vrstudio 项目配置。
- `[[range_preset]]` 是手动保存的选区（可变）；`[pick] active` 指向当前选中的那条。
  preset 不写名字：`created_at` 是首次保存时间，界面用它做标题；`updated_at` 是最近保存时间。
  `保存` 用当前工作草稿覆盖当前条并刷新 `updated_at`，`另存为` 按当前时间新建一条；
  `vrstudio extract name --case X [--preset ID]` 按选中的 preset 抽取，缺省用 active。
- `derived/pick/draft.toml` 是 pick 页的工作草稿：点全景、拖 inner、改 fov、换视口尺寸、
  摇杆、改帧范围都只写它，不写 `case.toml`。它不是契约，CLI 不直接读；带
  `source_sha256`，源片换了就回退 active preset。
- `clip.json` / `image.json` 是抽取时冻结的契约；抽取版本不记录 preset id，也不写
  `meta.json`。preset 可变，id 不是稳定的历史键；版本的真实几何只在冻结文件里。
- 改范围 = 改 preset/draft 后重新 extract = 新版本目录，两者分离避免 pick 迭代造成版本爆炸。
- `[extract] current` 是草稿→契约的"当前生效"指针：generate 与 merge 都认它，
  不采用"最新时间戳"这种在手工复制目录时会出错的隐式约定（vrpatch 先例）。
- 合并页只列抽取记录，不把未抽取的 preset 当成合并项；preset 只在几何匹配时作为标签出现。
- prompt-vars（提示词可变块：theme/style，外加模板选择）在 vrgen 侧按 job（=case 名）
  保存为 `runs/<job>/prompt-vars.toml`，case 不知道提示词的存在。
  **术语**：不用 vrpad 的 "brief"——避免与 vrpatch 网页选区草稿（viewport/inner）混淆。
- gen 的 `[source]` 已取消：源视频只是第一条素材。新建 gen case 时可以给 `--source`，
  vrstudio 把它复制进 `assets/` 并记为 `v1`、`role = "edit_master"`；不给源视频时
  建出来是空素材列表，由素材步骤补齐。
- 旧 gen case（只有 `[source]`）在 `load` 时自动迁移：源视频复制进
  `cases/<name>/assets/v1_<原文件名>`，写成一条 `[assets]`（`role = "edit_master"`），
  哈希保留，`[source]` 段删除。迁移失败（源不存在/复制失败）时报错并保持原文件。
- 旧 `[gen] reference_images` 同样迁移为 `kind = "image"`、`role = "subject_ref"` 的素材；
  不再作为独立字段读写。
- 模式**不在 case.toml**。唯一权威是 `runs/<job>/generation.toml` 的 `mode`；新建 gen
  case 时由 `vrstudio case new --mode` 或网页创建面板立即写入，之后通过
  `vrgen params show` 读回、`params save` 切换。
- 素材 `id` 按类型独立递增：视频 `v1`、`v2`…，图片 `i1`、`i2`…；删除后不复用。
- `kind` 只允许 `video` / `image`；本期不支持音频。
- `role` 的取值见下方「素材角色与校验」；用户素材的角色由用户手动选择，不按顺序推断，空角色是未完成状态。数量、格式、时长等上限交给模型详情 validator 校验，本地不再维护按模式的角色数量矩阵。
- 数值限制（格式、时长、帧率、像素、体积、数量上限）只在 vrgen 提交前校验；
  vrstudio 前端不重复实现。视频与超限图片在 vrgen 内缩放到限额内再上传。

### flow = "relight"（重打光：图片或视频氛围依据打到真 GT 上，不调平台）

```toml
flow = "relight"

[[assets]]                     # 素材库：同角色可以有多条候选，顺序无关
id = "v1"
kind = "video"                 # 底版可以是视频或图片；决定走整段还是单帧
path = "assets/v1_dance_move.mp4"
role = "relight_gt"            # 重打光底版：结构与细节的来源
sha256 = "…"

[[assets]]                     # 氛围依据候选一：美术上传的第一版图片
id = "i1"
kind = "image"
path = "assets/i1_atmo_v1.png"
role = "relight_atmo"
sha256 = "…"

[[assets]]                     # 氛围依据候选二：fullredraw 重绘后的视频
id = "v2"
kind = "video"                 # 视频只允许配视频底版
path = "assets/v2_atmo_redraw.mp4"
role = "relight_atmo"
sha256 = "…"

[relight]                      # 唯一草稿段：两把槽位指针 + 成片指针 + 上次参数
gt = "v1"                      # 槽位指向哪一条候选
atmo = "v2"                    # 图片或视频；视频要求 gt 也是视频
current = "out/20261030-171530_relit.mp4"
scene = "night"
strength = 1.0
local_shading = 0.35
highlight_clip = false
clip_knee = 0.72
clip_max = 0.98
ref_frame = 12
regions = "relight/regions.json"   # 可选：区域覆盖定义；不写表示没有区域
```

设计说明：

- 建 case 不绑源文件：`vrstudio case new --flow relight` 可以不给 `--source`，`case.toml` 不写 `[source]`。
  这和 gen 同构（gen 从 2026-10-19 起就是「无源 + `[[assets]]`」），GT 与氛围图由用户在素材步选定。
  不给源时 case 名必须由用户填写，不能再从文件名推导。
- **素材库与槽位分离**：`[[assets]]` 是候选池，同一角色可以有多条（美术每改一版氛围图就多一条，
  便于来回切换）；`[relight]` 的 `gt`/`atmo` 是两把指针，用素材 id 指向当前选中的那一条。
  早期实现把「槽位」直接等同于角色、限制每种角色只能一条，结果是「从素材库选」永远没有候选可挑。
- 角色由 flow 钉死，用户不能改：`relight_gt` 接受视频或图片，`relight_atmo` 接受图片或视频。
  两个角色在词表里是 `open = false`、`modes = []`、`reserved = false`——不进任何生成页下拉、不进任何
  提交清单，但因为是普通角色，`add_assets` 的上传与复制管线原样可用（`reserved = true` 会被
  `_add_assets_to` 明确拒绝，所以这两个角色不能标 reserved）。
- 指针必须指对角色：`gt` 指向的素材角色必须是 `relight_gt`，`atmo` 必须是 `relight_atmo`；
  指向不存在的素材或角色不符时在 `load`/`save` 两处按真实原因拒绝。
- **氛围类型配对**：两个槽位都在时，氛围是视频而底版是图片才拒绝；底版还没选时允许先把
  视频氛围候选放进素材库并选中，门控只提示缺底版。底版从视频改成图片、而氛围指针仍指向
  视频时按真实原因拒绝。
- 媒体类型由指针指向的底版决定，不写进 case.toml：底版是图片走单帧路径，是视频走整段路径。
  步骤链因此只有一条：素材 → 重打光 → 对比，视频专属的参考帧与小样在同一页里按底版类型出现。
- **氛围类型决定光场模式，不新增字段或开关**：氛围是图片时，一张图只估一次对齐与光照场、
  整段复用；氛围是视频时，固定相似变换仍只估一次，但每一帧按归一化进度取对应的氛围帧、
  在 2K 工作尺度重估光场。氛围视频只要求 2:1 ERP，允许与底版分辨率、帧率、帧数不同；
  图片氛围仍要求与底版逐像素同尺寸。
- `[relight]` 是 flow 的唯一草稿段。`current` 指向最近一次成片（相对 case 目录），对比步认它；
  其余键是上一次运行的参数，用来回填面板。不复用 `[adopt]`：那两个字段的语义是 vrgen 台账轮次，
  而 relight 没有轮次。写入只发生在 vrstudio，未知键按真实原因拒绝。
- **区域覆盖**：`[relight]` 可选键 `regions` 指向 case 目录内的一个 JSON 文件（相对路径，
  缺省表示没有区域；写入时与其余键一样只接受 case 内的相对路径）。区域是球面多边形，
  顶点为 `[lon, lat]`，单位度，经度允许超出 ±180（不 wrap，跨接缝时由读方平移）。
  可选 `pole` 为 `"north"` / `"south"` 时表示含该极点的盖帽：`verts` 是绕该极点一圈的
  闭环，区域取极点所在的一侧，栅格化时由读方把首个顶点按 ±360 复制成接缝边、再沿
  纬度 ±90 闭合；缺省或 `null` 表示普通闭合多边形。盖帽只能表示含极点的一侧，不能表示
  环带、洞或极点的补集。
  每个区域用稀疏的 `params` 覆盖 `strength` / `local_shading` / `clip`，`null` 或缺失表示
  沿用 `[relight]` 的默认值。`ranges` 缺省或 `null` 表示整段生效；非空时是
  `[{"start": 秒, "end": 秒}, …]` 的区间列表，解析端按 `start` 排序并把重叠或相接的区间
  合并成并集，单区域原始最多 64 条、并集最多 8 段，空数组拒绝（不生效用 `enabled`）。
  区间按 GT 帧率换算成帧并左闭右开，区间外等于该区域不存在；图片底版的 `ranges` 必须为
  `null`，非空按参数错退出 2。区间只随本文件传入，CLI 与 web 都不新增区间参数。
  区域最多 16 个、每个最多 64 个顶点、纬度限制在 ±89.5°，违反按参数错（退出 2）。
  `pole` 非空时边界必须绕该极点恰好一圈；扭转量不是 ±1 或边自交同样按参数错。
  `vrstudio relight --regions FILE` 可直接指定；`--case` 模式缺省读 `[relight] regions`，
  显式文件优先。`--sample-at 12,240,600` 按帧号出小样，与 `--sample N` 互斥。
- **区域文件的字段集**（`version = 1`，与 `[relight]` 一样只认这些键）：

```json
{
  "version": 1,
  "regions": [
    {
      "id": "r1",
      "name": "窗边高光",
      "color": "#f59e0b",
      "enabled": true,
      "verts": [[-24.0, 8.0], [-8.0, 11.0], [-4.0, 1.0], [-18.0, -3.0]],
      "pole": null,
      "feather_deg": 3.0,
      "params": {
        "strength": 0.45,
        "local_shading": null,
        "clip": { "knee": 0.72, "max": 0.98 }
      },
      "ranges": null
    }
  ]
}
```

  重叠按数组顺序处理，后一个盖在前一个上面；羽化只在该区域边界与下方值之间过渡。
  没有区域或所有区域 `enabled = false` 时，引擎走原标量路径，成片与改动前逐位一致。
- relight 不调 vrgen、不花额度、不需要项目会话，所以没有 `[submit]`、`[adopt]`、`generation.toml`
  与提示词；`/api/case` 对这条流程不下发 prompt 与 generation_params。
- 产物目录沿用 `out/`：整段写 `out/<时间戳>_relit.mp4`，单帧写 `out/<时间戳>_relit.png`，
  报告写同名 `.json`，小样写 `out/samples/<时间戳>/sample_<帧号>.png`。产物命名与 `current`
  的回写都在 `vrstudio relight --case` 一处，web 只把面板参数翻成 flag。

### 素材角色与校验

角色只承载提示词里的职责声明，不再承载按模式的数量限制；数量、格式、时长、帧率、
像素、体积的上限以模型详情的 validator 为唯一依据（`refVideoValidator` /
`refImageValidator` / 模式 `maxCount`），提交前由 vrgen 校验，超限时按 validator
返回的具体项报参数错。本地只保留平台接不住的语义规则：firstLastFrame 恰好一张
首帧加一张尾帧、至多一个 `edit_master` 且必须是第一条视频、`*_raw` 不能进入
`--refs` 清单，以及角色与素材种类的限制（`mask`、`lighting_ref`、首尾帧与
`*_raw` 只能是图片）。角色词表、职责句、种类限制、模式归属与下拉可见性固化在
`docs/roles.json`：vrgen 与 vrstudio 各存一份逐字节相同的副本，两侧各有一条契约
测试断言本地词表与快照一致并用 SHA256 钉住快照；前端不再自带词表，`/api/case`
下发 `roles`（name/label/help/kinds/modes/open/reserved）。模型详情缓存
（`runs/<job>/models.json`）缺失、过期或刷新失败时直接报配置错，提示先运行
`vrgen models --refresh`；需要模型能力的命令（submit、params show、prompt show）
一律按此报错，不在本地回退内置限额，也不静默放行。

- 角色职责声明（进入提示词素材清单的固定文案）：
  - `edit_master`：编辑母版，负责时间轴、构图与动作基准。
  - `motion_ref`：动作参考，只提供动作节奏与路径。
  - `space_ref`：空间参考，只提供机位、构图、起点与终点位置；不提供人物动作。
  - `scene_ref`：场景参考，只提供构图、背景与光照。
  - `lighting_ref`：光照参考，只提供光源位置、色温、明暗对比与空气质感；不提供构图、机位、背景与任何画面内容。只对图片成立，用于"按参考图改氛围、不改场景"的重绘。
  - `subject_ref`：主体参考，只定义角色外观。
  - `mask`：编辑区域标注，不作为画面内容参考。
  - `first_frame` / `last_frame`：首帧/尾帧定稿图，锁定起点/终点构图与人物外观。
  - `mid_frame`：中间过渡帧，仅在首尾间距过大时补充。
  - `first_frame_raw` / `last_frame_raw`：工作台输入底图（原始抽取帧），由 patch 的
    extract 从 clip 首尾导出，只提供场景与占位。它们只在关键帧工作台输入区出现，
    不是提交候选；`--refs` 清单拒绝 `*_raw` 角色，因此不能靠手动勾选或直接调 CLI
    把它们当首尾帧提交。
- 首尾帧工作台的当前状态存于 case 目录的 `keyframe.toml`（vrstudio 自有，不是
  case.toml 的段，也不是 vrgen 的契约）：`extract`（定稿基于哪个抽取版本）、
  `refs`（图片步的有序参考图清单，每项含 `asset`、`role`、`note`；`role` 为
  `subject_ref` 或 `detail_ref`，恰好一张 `subject_ref`）、`[first]` / `[last]`
  （轮次、候选序号、素材 id）。旧格式的单值 `sheet` 读取时视为只有一项
  `subject_ref` 的清单。图片步的参考图由这份文件与原始帧解析，不读 `[submit]`；
  视频提交清单只由生成页的引用条目决定，两者互不影响。
- 每帧的定稿有两条路：从生成候选里挑（`[first].round` 是轮次目录名），或
  「直接用原始帧」——把当前抽取的 `*_frame_raw.png` 复制进 `[[assets]]`、角色
  写 `first_frame` / `last_frame`，`round` 记为 `extract`、`index` 为 1。
  两条路写出的都是普通素材角色，所以交接与 `--refs` 的行为完全一致；
  `first_frame_raw` / `last_frame_raw` 这两个保留角色仍然不进提交清单。

`space_ref` 与 `motion_ref` 的分工是“空间”和“身体动作”的分工：`space_ref` 只提供机位、构图、起点与终点位置，不提供人物动作；`motion_ref` 提供动作节奏与路径。白模视频只锁空间时用 `space_ref`，需要继承动作节奏时用 `motion_ref`。

- 通道映射只有两条规则，除此之外全部勾选素材走 `--video` / `--image` 通道：
  - 仅当模式为 `firstLastFrame` 时，勾选里恰好一张 `first_frame` 与一张
    `last_frame` 映射到 mglc 的 `--first-image` / `--last-image`（首帧在前）；
    不足、超出或混入其他素材即报参数错。其他模式下这两个角色按普通图片走
    `--image`。
  - `mask` 由装配器自动附带，不是用户候选；追加在所有用户图片之后，不参与
    `@ImageN` 编号。缩放规则是强制缩放到母版的上传画布，不按图片预算 fit，
    宽高、比例与体积仍按图片 validator 校验。模板用固定文案说明最后一张图是
    区域标注，不写编号。
  - `fullredraw` 视频例外：`[submit] selected` 里没有任何非 mask 图片时，mask
    不进入清单。mglc 把图片列表第一项当目标 IP 库资产校验，此时 mask 会成为
    唯一图片并被拒绝；`patch` 的内区提示与 `fullRedrawImg` 的接缝锚点不适用
    这条豁免，后者仍有基图排在 mask 前面。模板用计算变量 `mask_note` /
    `mask_ban` 条件渲染区域标注段，没有 mask 时两段都不出现。
- 母版（提示词几何与上传基准）的回退链依次是：第一条 `edit_master` 视频 → 第一条
  视频 → 第一条 `space_ref` 或 `scene_ref` 图片（二者同级，按清单顺序取第一个）→
  第一条 `first_frame` 图片 → 第一条图片。母版为图片时，画布尺寸取图片宽高。
  显式给出 `--canvas`/`--source` 时以显式值为准（fullredraw 的画布来自 manifest）。
- 时长：显式 `--duration` 优先；没有显式值时，`videoEdit` / `videoExtend` 取母版
  时长，`allMediaRef` 取最长视频时长，`firstLastFrame` 及纯图片提交取 4 秒。显式值
  按当前模式的 duration 范围校验（模型 37 的 `firstLastFrame` 为 4–30 秒）。时长
  不写进 `generation.toml`，实际采用值只记在轮次台账的 `params.duration_s`。
- 首期几何基线：`firstLastFrame` 只接受 16:9 的 patch viewport（规范像素
  1920×1080）与 16:9 的 gen 图片；非 16:9 的 patch case 继续用 `videoEdit`，切到
  `firstLastFrame` 时在提交前报参数错。merge 目标为 1920×1080，正常路径是
  identity；比例一致只做等比缩放，比例不一致直接报错，中心裁切只对历史或外部
  导入视频显式开启。

## 3. case 目录

```
cases/<名>/
  case.toml                      # 唯一真源（§2）
  assets/                        # 三流程共用：文件素材副本（三视图、抽取帧、定稿帧、gen 素材）
    v1_main.mp4
    v2_motion_ref.mp4
    i1_character.png
  # --- flow = patch ---
  extracts/<时间戳>/             # 版本化冻结契约（vrpatch 原样）
    clip.json                    #   字段集/version=1 冻结，单段守卫
    clip.mp4                     #   送生成的视口裁剪
    clip_mask.png                #   inner 掩膜
    first_frame_raw.png          #   clip.mp4 首帧原始图（从 clip 读，不从源片抽）
    last_frame_raw.png           #   clip.mp4 末帧原始图（从 clip 读，不从源片抽）
    result.mp4                   #   被采用的那轮结果（adopt 时从 vrgen 拷入）
  derived/                       # 旧 merge 产物 out_<版本>.mp4 + .merge.json + pick/ 预览缓存
    pick/draft.toml              #   pick 页工作草稿（web 私有，不是契约；高频几何写这里）
  out/<版本>_space.mp4           # 空间合并（merge）产物：n_seg 帧中段
  out/<版本>_frame.mp4           # 时间拼接（assemble）产物：整条源片等长
                                 # 整片抽取只有 _space；下游按 _frame → _space 回退
  # --- flow = patchimg ---
  extracts/<时间戳>/             # 版本化冻结（单帧；与 patch 同构，没有时间）
    clip.png                     #   16:9 视口裁剪：送生成的唯一图像
    clip_mask.png                #   inner mask（黑=重绘，白=保持），作为提示附带
    image.json                   #   冻结几何：erp_w/h + viewport + inner（version=1）
    result.png                   #   被采用的那张视口结果（adopt 时拷入）
    report.json                  #   归一化与贴回统计
  derived/                       # clip.png + clip_mask.png + image.json 的副本
  out/<版本>_image.png           # 贴回后的完整 2:1 ERP
  # --- flow = fullRedrawImg ---
  extracts/<时间戳>/             # 版本化冻结（单帧、全幅）
    padded.png                   #   21:9 画布，源分辨率（8K 源约 117 MB）
    padded_mask.png              #   redundant_white：两条冗余带白、主内容黑
    image_pad.json               #   全幅几何唯一权威
    upload.png / upload_mask.png #   提交副本（长边 ≤ generate.image_upload_max_side）
    result.png                   #   被采用的 4K 21:9 结果
    report.json                  #   配准、接缝闸门与 aspect drift
  out/<版本>_image.png           # stitch 还原的 2:1 成片（案例分辨率）
  out/<版本>_image_<W>x<H>.png   # 跟随输入尺寸派生时的成片（可选）
  # --- flow = fullredraw ---
  seedance_input.mp4             # pad 画布（无损）
  seedance_input_mask.png
  seedance_input_pad.json        # recompose 唯一几何权威（契约原样）
  result.mp4                     # 被采用的那轮结果
  out/<轮次key>.mp4 + _recompose.json          # 案例分辨率
  out/<轮次key>_<W>x<H>.mp4 + _recompose.json  # 跟随输入（可选）
  # --- flow = gen ---
  result.mp4                     # 被采用的那轮结果
```

patch/patchimg 的抽取版本不写 `meta.json`：preset 的时间戳与几何都可变，preset id 不是稳定的历史键；版本的真实几何只在 `clip.json` / `image.json` 里。合并页按冻结几何分组，preset 只在几何匹配时按 `created_at` 作为标签出现。

## 4. vrgen CLI 契约

case 创建入口（vrstudio）：

```
vrstudio case new <名> --flow patch|patchimg|fullRedrawImg|fullredraw|gen [--source <文件>] [--mode <模式>]
  # patch/fullredraw：--source 必填（视频），--mode 禁止
  # patchimg：--source 必填（2:1 ERP 图片），--mode 禁止；建好即写入默认 16:9 草稿
  # fullRedrawImg：--source 必填（2:1 ERP 图片），--mode 禁止；没有选区草稿
  # gen：--mode 必填；--source 可选。给了源视频就复制为 assets/v1（edit_master）。
  #      case 写盘后立即以子进程调 vrgen params save --job <名> --mode <模式>；
  #      写模式失败时 case 保留，命令以退出码 2 结束并提示重试。
```

```
vrgen login [--check]                      # 登录态管理（透传 mglc）
vrgen models [--refresh]                   # 平台模型清单
vrgen submit --job <名> --refs <提交资产清单.json> \
           [--canvas WxH] [--source WxH] \
           [--template <id>] [--set theme=…,style=…] \
           [--video-model-id 37] [--mode videoEdit] [--resolution <480p|720p|1080p|4K>] \
           [--duration <秒>] [--num <1..4>] [--aspect-ratio auto|W:H] \
           [--scale auto|full|half] [--audio keep|none] \
           [--session-id <项目生成会话>] [--workdir <dir>] [--dry-run] [--resubmit]
                                           # 三个流程共用的唯一提交入口；断点续跑、task_id 防重发
                                           # --audio none：平台无「不生成声音」参数，结果下载后去音轨
                                           # --resubmit：放弃本轮复用、另开一轮（会重新计费）
vrgen prep --video <路径> [--mask <路径>] --canvas WxH --source WxH --out <目录> \
           [--scale auto|full|half|WxH] [--video-model-id 37] [--mode videoEdit] \
           [--workdir <dir>] [--dry-run]
                                           # 只按平台限额缩放上传件：不建轮次、不碰平台
                                           # 写 upload_pad_<W>x<H>.mp4 / _mask_<W>x<H>.png / .json
vrgen image submit --job <名> (--prompt <文本> | --template <id> [--vars-file <文件名>]) \
           [--image-role <角色>]… [--image-note <说明>]… [--image-model-id <图片模型 id>] \
           --image <路径> [--image <路径>]… \
           --ratio <16:9> --resolution <1K|2K|4K> [--num <1..4>] \
           [--step first|last] \
           [--session-id <项目生成会话>] [--workdir <dir>] [--dry-run] [--resubmit]
                                           # 图片生成；候选全部下载，台账记为 img- 轮次
vrgen status --job <名> [--watch]          # 轮询；--watch 阻塞到终态
vrgen register --job <名> --file <本地路径>            # 手动后端：写同格式台账
vrgen result --job <名> --round <key> [--index <N>] --out <路径>
                                           # 导出结果；图片轮次按 --index 取第 N 张，缺省第一张
vrgen peek <task-id>                       # 零额度查平台侧状态
vrgen prompt show --job <名> [--template <id>] [--vars-file <文件名>] [--refs <json>] \
                 [--mode <模式>] [--image-role <角色>]… [--image-note <说明>]… \
                 [--canvas WxH] [--source WxH] [--workdir <dir>]   # 读模板+草稿；可回展开正文
vrgen prompt save --job <名> [--set k=v]… [--unset k]… [--template <id>] [--vars-file <文件名>] \
                 [--refs <json>] [--mode <模式>] [--image-role <角色>]… [--image-note <说明>]… \
                 [--canvas WxH] [--source WxH] [--workdir <dir>]
vrgen params show --job <名> [--refs <json>] [--canvas WxH] [--source WxH] [--aspect-ratio auto] [--workdir <dir>]
                                           # 只读：output/input 档位与模式列表；refs 只用于取母版算输入尺寸
vrgen params save --job <名> [--video-model-id <id>] [--image-model-id <id>] [--resolution <480p|720p|1080p|4K>] [--scale <auto|full|half>] [--mode <模式>] [--aspect-ratio <auto|W:H>] [--session-id <id>] [--project-id <id>] [--episode <n>] [--workdir <dir>]
vrgen sessions list [--project-id <id>] [--episode <n>]   # 只读：项目/剧集/会话树，JSON 输出
```

提交的输出契约（供 vrstudio 的任务层解析，不要改格式）：命中已有轮次或断点续跑时，`submit` 与 `image submit` 都打印一行

```
reused      <轮次目录>  reason=key|resumed  task=<task id|->  (本次未提交，未花费)
```

`reason=key` 是本地半场按 spend-once key 命中已有轮次，`reason=resumed` 是同一轮已有 `task_id`、本次只继续等待。两种情况都不发请求、不扣额度，退出码仍为 0。需要同一提示词再抽一版时用 `--resubmit`：一次性 token 并入 key 另开一轮，旧轮原样保留并重新计费；上一轮仍在跑（`stage=submitted` 且没有 result）时拒绝。

`patchimg` 的图片提交由 `vrstudio generate submit` 组装成 `vrgen image submit`，视口图与 inner mask 由装配器自动附带（mask 不进 `[submit] selected`、不占编号）：

```
vrgen image submit --job <case 名> --template img360-local --vars-file prompt-vars.toml \
  --image <extract>/clip.png       --image-role edit_master \
  --image <extract>/clip_mask.png  --image-role mask \
  [--image <参考图> --image-role <角色>]… \
  --ratio 16:9 --resolution 4K --num 4 [--session-id <id>] [--workdir <dir>]
```

`fullRedrawImg` 的提交由同一条命令发出，模板与角色不同：基图是 21:9 上传副本，mask 是冗余带掩膜，之后是 `[submit] selected` 里的氛围参考：

```
vrgen image submit --job <case 名> --template fullRedrawImg --vars-file prompt-vars.toml \
  --image <extract>/upload.png       --image-role edit_master \
  --image <extract>/upload_mask.png  --image-role mask \
  [--image <氛围参考图> --image-role lighting_ref]… \
  --ratio 21:9 --resolution 4K --num 4 [--session-id <id>] [--workdir <dir>]
```

`fullRedrawImg` **必须**提交 mask：它把两条冗余带冻成源图像素，作为 `stitch_image` 的配准锚点，接缝因此稳定闭合；代价是横跨接缝的约 16.7% 不参与重绘。

`prompt show` 与 `prompt save` 在提供 `--refs` / `--mode` / `--canvas` / `--source` 时，会额外返回 `rendered`（展开后的完整提示词）和 `render_error`（缺哪个占位符）。展开只读，不建轮次、不碰平台；前端提示词面板默认显示 `rendered`，模板骨架可切换查看。

`--vars-file` 指定草稿文件名（默认 `prompt-vars.toml`），只接受 job 目录下的裸文件名、必须以 `.toml` 结尾；首尾帧工作台用 `keyframe-vars.toml`，与视频提示词草稿互不覆盖。`--image-role` 与 `--image` 一一对应，用于展开模板里的计算键 `image_roles`（图片步的「图1/图2/图3」分工）；它不写进草稿，也不能用 `--set` 修改。

### `--refs` 提交资产清单（三个流程共用的唯一提交入口）

`vrgen submit` 只有一种输入：`--refs` 清单。旧 `--input` / `--mask` 参数与互斥校验
删除。清单 = `[submit] selected` 里的用户素材与 clip/pad，加上装配器自动附带的
mask 控制图：勾选了哪些素材就提交哪些，没有默认集，也没有自动补入的素材；mask
是唯一的自动附带项，因为它不是画面参考，而是编辑区域控制图。patch 的 clip、
fullredraw 的 pad 与 `[[assets]]` 文件素材使用同一套条目格式。vrstudio 是清单的
唯一生产者，vrgen 不读 case.toml。

清单是一个 JSON 文件，以 patch（勾选 clip + 三视图，装配器附带 mask）为例：

```json
{
  "assets": [
    {"id": "clip", "kind": "video", "path": "E:\\…\\cases\\dacne\\extracts\\20261021-140105\\clip.mp4", "role": "edit_master"},
    {"id": "i1", "kind": "image", "path": "E:\\…\\cases\\dacne\\assets\\i1_dancer.jpg", "role": "subject_ref", "sha256": "…"},
    {"id": "mask", "kind": "image", "path": "E:\\…\\cases\\dacne\\extracts\\20261021-140105\\clip_mask.png", "role": "mask"}
  ]
}
```

mask 条目由装配器追加在所有用户图片之后，不在 `[submit] selected` 里，也不参与
提示词编号；它只是编辑区域控制图，不是用户素材。

- 条目字段：`id`、`kind`（`video` | `image`）、`role`、`path`、可选 `sha256`
  （给了就校验）。没有 `derived` 字段；来源只影响面板展示与路径解析，不影响提交
  语义。
- `id` 在清单内唯一，统一为字母开头、其余为字母数字下划线连字符的字符串。用户
  素材沿用 `v1`、`v2`…（视频）与 `i1`、`i2`…（图片）；进入 refs 的流程产物用
  固定名 `clip`、`mask`、`pad`、`pad_mask`；`first_raw`/`last_raw` 只用于工作台
  输入，不进入 refs。
- 清单顺序取 `[submit] selected` 的顺序，mask 固定追加在所有用户图片之后
  （fullredraw 视频在没有任何用户图片时不追加，见 §2）；提示词
  编号与 argv 按视频在前、图片在后分组，组内保持清单顺序，得到 `@VideoN` /
  `@ImageN`。mask 不参与编号，声明顺序与 mglc argv 的 `--video` / `--image` 顺序
  逐一对齐（契约测试点）。
- 提交不再做 SD 合规素材登记（决策 75，2026-11-04 起）：`--video` / `--image`
  只给本地路径，**不伴随** `--video-asset-id` / `--asset-id`；平台在 generate 时
  自动上传登记。此前「先 `virtual-ip upload` 等审核再提交」的流程作废，手动登记
  会导致任务异步失败（第 1 个参考资产不属于目标 IP 库或与文件不匹配）。
- 清单条目的 `role` 由 vrstudio 按 `[submit.roles]` 覆盖 `[[assets]] role` 后写入；
  vrgen 只读清单角色，不读 case.toml，也不知道角色来自哪里。
- 路径可以是绝对路径，也可以相对 JSON 文件所在目录。`[submit] selected` 可以
  引用文件素材与 clip/pad；mask 不出现；缺省为空集，旧 case 需要重新勾选一次。
- 数量、格式、时长、帧率、像素、体积校验以模型详情 validator 为唯一依据，vrgen
  按具体超限项报参数错；本地只保留 §2「素材角色与校验」的四条语义规则。
- `firstLastFrame` 的清单只含勾选里恰好一张 `first_frame` 和一张 `last_frame`，
  顺序固定为首帧在前，映射到 `--first-image` / `--last-image`；其他勾选项不参与，
  视频也不参与，该模式不附带 mask（见 §2「素材角色与校验」）。
- vrgen 在轮次目录里保存一份 `refs.json` 现场，之后断点续跑以它为准。
- `--canvas` / `--source` 省略时，按母版回退链取尺寸；fullredraw 的装配器显式给出
  画布与源尺寸，画布来自 manifest。
- 视频与超限图片各自缩放到模型限额内；mask 由装配器追加在用户图片之后，强制
  缩放到母版的上传画布，不按图片预算 fit；缩放件按素材 id 命名并记入台账。
- `--dry-run` 只做本地半场，不发请求不花钱，用于检查清单、能力校验、提示词与
  argv。
- 首尾图合规性首期按“直接传本地路径、不做 SD 合规素材登记”实现：CLI 的
  `--first-image` / `--last-image` 没有对应的 asset-id 参数。若平台在真实提交时
  拒绝，按 `firstlast-dev-plan.md` 的 R1 回退，不在首期自建登记流程。

### 上传件：轮次目录与 case 侧的两份产物

`submit` 在轮次目录里写下 `upload_<id>_<W>x<H>.<ext>`，这是平台实际收到的文件。同一个文件也可以脱离提交单独产出：
`vrgen prep` 把 pad 视频与 mask 缩放到同一尺寸，写到调用方指定的目录（vrstudio 用 `cases/<名>/derived/`），并以
`upload_pad_<W>x<H>.json` 记录画布、源尺寸、上传尺寸、缩放比例、冗余带列号与平台上限。

- 两处使用同一套规划与编码参数，同一输入下 sha256 相同；轮次目录那份仍由 `submit` 自己生成，台账结构不变。
- 上传件不参与 `recompose`：裁回只认 manifest 与 `seedance_input.mp4`，两组文件不互相替代。
- `--scale full` 在上传件仍超限时按运行失败（退出码 1）结束，与 `submit` 的判定一致。

### 生成参数（web 生成页的数据源，决策 20）

submit 显式参数的来源必须能一一对回 mglc 的 `video generate`，不能自造同名语义：

| vrgen 参数 | 来源 | 语义 |
|---|---|---|
| `--video-model-id` | mglc `--model-id` | 视频模型 ID；fullredraw 固定 37（Seedance 2.5），4K 路线用 22（Seedance 2.0） |
| `--mode` | mglc `--type` | 生成模式；fullredraw 固定 `videoEdit` |
| `--duration` | mglc `--duration` | 整数秒；显式值优先，按当前模式的 duration 范围校验。缺省时 `videoEdit` / `videoExtend` 取母版时长，`allMediaRef` 取最长视频，`firstLastFrame` 与纯图片提交取 4。patch 的 `firstLastFrame` 由 vrstudio 从当前 `clip.json` 的帧范围与帧率推导整秒后显式传 `--duration`，所以 vrgen 的纯图片默认 4 只覆盖 gen。时长不写进 `generation.toml`，实际值只记台账 `params.duration_s` |
| `--resolution` | mglc `--resolution` | **输出档位**，480p / 720p / 1080p / 4K；不是输入文件尺寸。4K 只在模型详情的该模式 `resolutions` 里发布时可用（当前 22 的 `firstLastFrame` / `allMediaRef`；37 的 `videoEdit` 最高 1080p）。图片命令另用 1K / 2K / 4K 词表 |
| `--num` | mglc `--num` | 生成数量 1..4；视频轮次当前只取第一个结果，前端固定 1；图片轮次下载全部候选 |
| `--aspect-ratio` | mglc `--aspect-ratio` | 输出比例；fullredraw 固定 21:9，gen 用 `auto` 表示不传该 flag（videoEdit 的输出比例跟随输入）。`firstLastFrame` 不传该 flag，比例跟随首尾图 |
| `--scale` | **vrgen 自有** | 上传前的输入缩放：`auto`（限额内最大）/ `full`（画布原尺寸）/ `half`（画布一半）；没有对应的 mglc flag |
| `--audio` | **vrgen 自有** | `keep`（默认）保留结果音轨；`none` 在结果下载后去掉音轨。mglc 没有「不生成声音」的参数（`--keep-original-sound` 只控制参考音频），所以只能本地后处理；`none` 时同时不传 `--keep-original-sound` |
| `--session-id` | mglc `--session-id` | 项目生成会话 ID（>0）；提交落在该项目下，计费走项目额度；0/不传 = 个人额度 |

`--scale` 决定上传文件的实际像素，也就决定提示词里的 `{canvas_w}×{canvas_h}` 和冗余带列号；`--resolution` 只决定平台输出档位，**不会改变提示词里的输入像素数字**。

`vrgen image submit` 的参数面：

- `--prompt` 与 `--template` 二选一：直接给正文，或给模板 id 由 vrgen 展开。模板路径读 `--vars-file` 指定草稿（默认 `prompt-vars.toml`），并接受 `--image-role` 生成的 `image_roles`；展开后的正文原样写入轮次的 `prompt.txt`，台账与直接给正文时同构。
- `--image-model-id` 指向图片模型。取值优先级：显式参数 > `generation.toml` 的 `image_model_id` > 配置 `mglc.image_model_id`（首期默认 44 专业图片-2.5，备选 Seedream 4.5 = 25）。
- `--image` 可重复，直接传本地路径；图片模型不需要 SD 合规素材登记。
- `--image-role` 可重复，条数必须与 `--image` 相同，按顺序对应；仅用于 `--template` 渲染，不发给平台。
- `--image-note` 可重复，条数必须与 `--image` 相同，按顺序对应；空字符串表示这张图没有用途。它只用于 `--template`，由 vrgen 展开进 `image_roles`，不发给平台；与 `--prompt` 同用时报参数错。
- `--step first|last` 可选：只写入 `run.json` 的 `params.step`，供首尾帧工作台分组展示，不参与平台请求；缺省不写该字段。
- `--ratio`：首期调用方固定传 `16:9`；vrgen 只校验它属于模型详情声明的比例表，不自行推导。
- `--resolution`：只接受 `1K|2K|4K`；工作台未显式传入时取该模型 `resolutions` 的最高档，允许下调。
- `--num`：1..4；候选全部下载并写入台账 `results`，`vrgen result --index` 逐张取出。
- `--session-id` 与 `--workdir` 的语义与视频命令相同；`--dry-run` 只组装 argv，不发请求、不扣额度。

21:9 下各输出档位的标称尺寸（页面展示用；最终以平台返回并写入 `run.json` 的 gate 为准）：

| 档位 | 标称宽高 | 依据 |
|---|---|---|
| 480p | 992×432 | 平台公开像素表 |
| 720p | 1470×630 | ship_01 实测返回 |
| 1080p | 2206×946 | 平台公开像素表 |

16:9 的 4K 档标称 3840×2160（`prep/params.py` 的 `OUTPUT_SIZES_16_9`）；21:9 4K 没有已核对的标称值，`output_options` 暂不提供这一档，`params show` 也不会列它。

`params show` 输出单个 JSON 对象：

```json
{"job": "ship_01",
 "output": [{"value": "480p", "width": 992, "height": 432},
            {"value": "720p", "width": 1470, "height": 630},
            {"value": "1080p", "width": 2206, "height": 946}],
 "input": [{"value": "auto", "width": 4400, "height": 1884, "ok": true, "reason": ""},
           {"value": "full", "width": 4668, "height": 2000, "ok": false,
            "reason": "9,336,000 px 超过上限 8,295,044"},
           {"value": "half", "width": 2334, "height": 1000, "ok": true, "reason": ""}],
 "current": {"resolution": "720p", "scale": "auto",
             "mode": "videoEdit", "aspect_ratio": "auto",
             "session_id": 0, "project_id": 0, "episode": 0},
 "modes": [{"value": "videoEdit", "label": "VideoEdit · 结构锁定编辑（动作跟随输入）",
            "takes_video": true, "ratios": [], "max_count": 50,
            "max_videos": 10, "max_images": 30,
            "duration": {"type": ""}},
           {"value": "allMediaRef", "label": "AllMediaRef · 多素材参考（可重新生成动作）",
            "takes_video": true, "ratios": ["auto", "16:9", "21:9"], "max_count": 50,
            "max_videos": 10, "max_images": 30,
            "duration": {"type": "range", "min": 4, "max": 30}},
           {"value": "firstLastFrame", "label": "FirstLastFrame · 首尾帧生视频",
            "takes_video": false, "ratios": [], "max_count": 2,
            "max_videos": 0, "max_images": 2,
            "duration": {"type": "range", "min": 4, "max": 30}}],
 "models": [{"id": 22, "name": "Seedance 2.0", "description": "…"},
            {"id": 37, "name": "Seedance 2.5", "description": "…"}],
 "image_models": [{"id": 44, "name": "专业图片-2.5", "description": "…"},
                  {"id": 25, "name": "Seedream 4.5", "description": "…"}],
 "fixed": {"video_model_id": 37, "image_model_id": 44, "duration_s": 8, "num": 1},
 "saved": true}
```

- `output` 是平台输出档位及标称宽高；`input` 是 `--refs` 清单里的母版在三种 `scale` 下的实际宽高，`ok/reason` 由平台模型的像素/体积限制计算。母版是图片时 `input` 为空，因为输入缩放只对视频有意义。
- `input` / `canvas` / `source` 都可省略。省略 `--refs` 时（例如新建 gen case 后还没有素材），
  `output` 与 `input` 返回空数组，页面只使用 `modes` 与 `current`；素材补齐后再次调用
  即恢复完整结果。省略 `--refs` 时若显式给了 `--canvas`/`--source`，只用于计算 `output`。
- `modes` 是模型能力里筛出的、本期支持的模式（`videoEdit` / `allMediaRef` / `videoExtend` / `firstLastFrame`）；筛选不再要求模式“接受视频”，否则纯图片的 `firstLastFrame` 不会出现在列表里。页面用它填充模式下拉框，不在前端写死。`max_videos` / `max_images` 取对应 validator 的 `maxCount`；`takes_video=false` 时 `max_videos` 返回 0。角色选项不在 `modes` 里回显：按模式的角色数量矩阵已退役，本地只保留 §2「素材角色与校验」的四条语义规则；前端从全局角色词表按素材种类渲染。
- `params show` 的 `takes_video` 闸门只拦“`--refs` 清单里有视频、当前模式却不接受视频”的情况：不传 `--refs`、或清单里没有视频时，无论当前模式是什么都返回 `modes` 与 `current`。否则纯图片 case 一旦把当前模式存成 `firstLastFrame`，页面连模式列表和时长范围都读不到。
- `current` 优先读 `runs/<job>/generation.toml`，没有则回退配置默认值；`saved` 表示草稿是否存在。`current` 里的 `session_id` 是项目生成会话（0 表示个人额度）。
- `fixed.video_model_id` 是生效的视频模型：优先 `generation.toml` 的 `video_model_id`，没有则用配置 `mglc.video_model_id`（默认 37）。`fixed.image_model_id` 是生效的图片模型：优先 `generation.toml` 的 `image_model_id`，没有则用配置 `mglc.image_model_id`（默认 44）。旧的 `generation.toml` 键 `model_id` 读取时按视频模型兼容。
- `models` 是视频模型清单（`{id, name, description}`，全部列出、按 id 去重——平台会把同一 id 列成样片/完整两条，取能力多的那条），供生成页模型下拉框使用；来源是 `model_list_url` 的免鉴权 GET，24h 缓存在 `models.json`。`image_models` 是图片模型清单，来源 `mglc model list --type image`（需登录态），24h 缓存在 `models_image.json`；取不到时返回空数组并附 `image_models_error` 说明原因，不影响其余字段。**模型 id 只在类型内唯一**（22 既是视频 Seedance 2.0 也是图片 Seedream 4.0，25 既是视频 Vidu Q3 Turbo 也是图片 Seedream 4.5），任何存储与界面都以 (类型, id) 为准。
- `current.mode` 是本次提交使用的模式；`current.aspect_ratio` 是解析后的比例。没有比例选项的模式显示 `auto`，页面写“跟随输入”；`allMediaRef` 这类有比例列表的模式从列表里选择。
- `fixed.duration_s` 不再表示保存的草稿偏好：页面时长下拉按 `modes[].duration` 渲染，“自动”不传 `--duration`，实际采用值以轮次台账 `params.duration_s` 为准。patch 的 `firstLastFrame` 另下发 `auto_duration_s`（由 clip 帧范围与帧率推导的整秒），页面据此把“自动”显示成“自动（约 N 秒）”；提交仍由 vrstudio 显式传 `--duration`。`fixed.duration_s` 此时回显同一个推导值，只是提示，不是草稿。
- 项目额度的接法：`mglc project list` 拿项目 ID，`mglc episode list --project-id <id>` 拿剧集序号，`mglc session list --project-id <id> --episode <n>` 拿 `sessionId`；把 `sessionId` 写进 `generation.toml`（`params save --session-id`）后，所有 submit 都走项目额度。不传 `--session-id` 时 `params save` 保留已有会话。层级、额度行为与失败边界详见 `docs/sessions.md`。
- `params save` 的 `--video-model-id` / `--image-model-id` / `--resolution` / `--scale` 可省略；省略时保留 `generation.toml` 已有值，
  没有草稿时回退配置默认值（`--image-model-id` 不写 resolution/scale 那些视频草稿键，只改图片模型）。新建 gen case 只传 `--mode`，其余字段等素材选好后再写。
  接受正整数模型 ID、`480p|720p|1080p|4K`、`auto|full|half`、任意模式名与 `auto` 或 `W:H` 比例，写
  `runs/<job>/generation.toml`，回显 `{"video_model_id": …, "image_model_id": …, "resolution": …, "scale": …, "mode": …, "aspect_ratio": …,
  "session_id": …, "project_id": …, "episode": …}`。模式是否被模型支持由 submit 阶段的
  模型能力校验负责；`vrstudio case new` 在创建时只接受本期四种模式。
- submit 的取值优先级：命令行显式参数 > `generation.toml` > `config/default.toml`。`--scale` 的 quarter/显式 WxH 仍保留在 config 里给内部调试；CLI `--scale`、`params save` 与前端只接受 `auto|full|half`。

### sessions 子命令（前端会话选择器的数据源）

`vrgen sessions list` 只读、不消耗额度，输出单个 JSON 对象：

```json
{"fetched_at": "2026-10-19T06:30:00Z",
 "projects": [{"id": 2060150527854528, "name": "2026大秦寻仙VR",
               "episodes": [{"no": 1, "id": 2040714108516707, "name": "秦宫夜宴",
                             "sessions": [{"id": 2060150528006080, "name": "未命名"}]}]}]}
```

- 不带参数展开全部项目；`--project-id` 限定项目；同时给 `--project-id` 与 `--episode` 只返回该集。只给 `--episode` 是参数错误（退出码 2）。
- 任一层的空结果输出空数组。mglc 查询失败按退出码 1 处理，错误写 stderr。
- 查询链路是 `mglc project list` → `mglc episode list --project-id` → `mglc session list --project-id --episode`。

### prompt 子命令（web 提示词编辑界面的数据源，决策 18）

两个命令都输出**单个 JSON 对象**（`ensure_ascii`，机器可读；调用方 `json.loads` 解析）：

```json
{"template": "gen-multi",          // 生效模板 id：草稿 > --template > 配置默认；都没有则 null
 "available": ["360-closure", "gen-edit", "gen-multi"],  // templates/ 下全部可选模板
 "template_text": "…",             // 模板正文原样（含 {键|显示名|填写说明} 或 {键}）
 "placeholders": ["canvas_w", "asset_list", "theme"],  // 模板正文引用的全部键（去掉显示名与说明）
 "geometry_keys": ["canvas_w"],    // submit 时由几何自动填充的只读键
 "computed_keys": ["asset_list", "task_rule", "timeline_rule"],  // 由素材与模式自动填充的只读键
 "labels": {"theme": "主题 / 场景"},  // {键|显示名|说明} 里的显示名；只含写了显示名的键
 "help": {"theme": "写场景主题与氛围；决定重绘后的整体内容方向。"},  // 同上的填写说明
 "vars": {"theme": "黄昏"}}         // prompt-vars.toml [vars] 当前值
```

- 模板占位符可写成 `{键|显示名|填写说明}`。显示名与说明允许中文、空格与斜杠，
  不允许 `{`、`}` 与换行（显示名里也不能出现 `|`）；它们只服务页面展示，
  不进入展开后的提示词。`render()` 先把整个占位符归一成 `{键}` 再展开，
  成片提示词与不带显示名时逐字节一致。只写 `{键|显示名}` 仍然有效。
- `placeholders` 只列键名并按首次出现顺序去重；`labels` 只包含写了显示名的键，
  `help` 只包含写了说明的键，同名键都以第一次为准。没有写显示名的键由页面退回
  键名显示；`help` 用于回答“为什么要填这个字段”，不是发给模型的内容。
- `show`：只读。模板解析顺序 `--template` > 草稿 > 配置默认；找不到模板时退出码 2 并列出 `available`。
- `save`：写草稿并回显保存后的同一 JSON。`--set` 新增或覆盖（这里是草稿编辑器，
  **允许新键**，与 submit `--set` 只认已有键不同）；`--unset` 删除键，模板正文引用的键
  拒绝删除（退出码 2 列出哪些删不了）；`--template` 切换模板（必须存在于 templates/）。
- 变量的展示与增删规则（web 侧消费）：模板引用的非几何键（如 theme/style/plot/action/
  allowed_changes）永远展示、不可删除、值可改；草稿里的自定义键可改可删；`geometry_keys`
  与 `computed_keys` 是只读占位符，页面不生成输入框，也不在主体里单独列一段“自动填入”。
- `labels` 与 `help` 是本次新增的契约字段：出厂模板要求每个非几何、非计算占位符都带
  显示名与填写说明，vrgen 的模板测试会遍历 `templates/*.md` 检查覆盖与一致性。
  旧调用方不认识这两个字段时可以忽略，不影响原有 `placeholders` / `geometry_keys` 行为。
- `computed_keys`：`asset_list`、`task_rule`、`timeline_rule` 由 vrgen 在 submit 时按素材
  顺序与当前模式生成，不允许写进 `prompt-vars.toml`；旧调用方不认识时可以忽略。


### 素材清单与模式规则的计算键（templates/）

gen 流程统一使用 `gen-multi`（旧 `gen-edit` 保留，供历史轮次重放与对照）；
`asset_list` 等计算键对全部模板开放，character-repaint 与 360-closure 增加素材
清单段属于模板内容改动，机制不变：

- `{asset_list}`：按清单顺序生成，例如
  `@Video1：编辑母版，负责时间轴、构图与动作基准。`、
  `@Image1：主体参考，只定义角色外观。`；mask 不参与编号，模板用固定文案说明
  最后一张图是编辑区域标注，声明顺序与 mglc argv 的 `--video` / `--image` 顺序
  逐一对齐。
- `{task_rule}`：按模式生成任务句。`videoEdit` 是“只编辑母版中的指定主体”；`allMediaRef`
  是“按文本分镜重新生成完整表演”；`videoExtend` 是“从母版结尾自然延长”。
- `{timeline_rule}`：`videoEdit` 锁定动作顺序、起止时间、方向与画面位置；`allMediaRef`
  允许重新编排节拍并写整数秒分镜；`videoExtend` 从母版结尾继续，不重演已有时段。
- 其余用户变量（`subject` / `target` / `plot` / `preserve` / `allowed_changes` 等）仍然
  由提示词面板维护，规则同前。

退出码：`0` 成功 / `2` 参数或配置错 / `1` 运行失败（台账里有完整现场）。

`--template` 只需在 job 首次 submit 时指定，之后记入该 job 的 prompt-vars 草稿。

`--set <键>=<值>`（可多次）的键集合**自适应于草稿的 `[vars]`**：在 toml 里新增字段后
立即可用，实现里不允许出现逐变量的固定分支；未知键以退出码 2 失败并列出该 job 的
可用键（fail loud，不静默忽略）。`--set` 是本次调用的临时覆盖，不写回草稿；生效值
由台账留档（command.txt 记 argv、prompt.txt 记展开结果）。

## 5. 台账格式（runs/<job>/）

沿用 vrpad run.json 五件套，两条流程同构；job 级另有一份可变草稿：

```
runs/<job>/
  prompt-vars.toml      # job 级草稿：template 选择 + 提示词可变块（vrgen 侧唯一可写的"当前值"）
  generation.toml       # job 级草稿：video_model_id/image_model_id/mode/aspect_ratio/resolution/scale/session_id/project_id/episode（决策 20/22/23；不含时长；旧键 model_id 读取时按视频模型兼容）
  <轮次key>/              # 视频轮次
    run.json            # 台账：stage/params/prompt/task_id/result/gate/notes（assets 已退役，见下）
    prompt.txt          # 实际发出的提示词（模板展开后）
    command.txt         # 实际发出的 argv
    progress.log        # 过程叙事（含等待轮询），每次调用追加
    mglc.log            # 外部调用的 argv/返回码/错误消息/返回载荷（data 行，紧凑 JSON；URL 截断签名查询串）；时间戳为东八区 +08:00（run.json 的 *_utc 字段仍为 UTC）；`===` 段头是 vrgen 一级命令，其下 mglc 调用与 msg/data 续行逐级缩进
    refs.json           # 本次提交的资产清单现场（含 id/kind/role/path/hash；三流程共用）
    upload_<id>_<w>x<h>.mp4 / .png   # 按素材 id 命名的缩放件（三流程统一；母版缩放件另记 run.json 的 upload 字段）
    result.mp4          # 生成/注册的结果
  keyframe-vars.toml    # 首尾帧图片步的变量草稿（可选；与 prompt-vars.toml 同构、互不覆盖）
  img-<轮次key>/          # 图片轮次：label 固定为 img
    run.json            # params.kind="image"，params.step 可选，results 列出全部候选
    result_1.png … result_N.png
```

gen 多素材与图片轮次的 run.json 字段扩展（其余字段与旧格式相同；以下字段是本次对冻结契约的显式扩展）：

- `params.kind`：`"video"` | `"image"`，缺省视为 `"video"`；`backend` 字段语义不变。轮次类型以它为准，读旧 run.json 缺字段时按 video 处理。
- `results`：可选字符串数组，图片轮次的多候选结果文件清单（`result_1.png` … `result_N.png`）。视频轮次不写该字段，单值 `result` 语义不变。
- `params.step`：可选，`"first"` | `"last"`；图片轮次属于首尾帧工作台的哪一步，供页面分组。缺省表示未标注（旧轮次或非工作台图片轮次）。
- `task_ids`：可选整数数组；图片批次在平台侧对应多个并列任务时，记录全部任务 ID，`task_id` 仍保留第一个以兼容旧读取方。逐个任务的图按 URL 去重后写入 `results`。
- `params.duration_s`：本次实际采用的时长（整数秒），是审计事实，不是偏好；不写 `generation.toml`。
- `params.video_model_id` / `params.image_model_id`：本次实际采用的模型，按轮次类型各记其一（视频轮次记 `video_model_id`，图片轮次记 `image_model_id`）。历史轮次的 `params.model_id` 读取时按轮次类型兼容。
- `assets`：已退役（决策 75）——提交不再手动登记 SD 合规素材，新轮次不写该字段。
  旧轮次的 `assets`（如 `{"video:clip": 123, "image:mask": 456}`）仍可能存在，
  读取方按缺省处理。patch/fullredraw 早期写过的 `"video"` / `"image"` 单键同样只读兼容。
- `params.refs`：本次提交的资产清单，每项含 `id`、`kind`、`role`、`path`、`sha256`、
  `upload`（缩放件路径）、`width`、`height`（上传件的实际宽高）；顺序与 `refs.json`
  一致。没有 `derived` 字段，流程产物与文件素材同构。
  `firstLastFrame` 同样通过该字段记录首尾帧。
- 统一清单后不再写 `params.input` / `params.mask`：母版与 mask 都从 `params.refs`
  里取（`master` 给出母版 id，role=mask 的条目是 mask）。旧轮次的 run.json 仍可能
  带这两个键，读取方按缺省处理。
- `params.master`：母版素材 id（可能是图片）；`params.duration_source`：`master` | `longest` | `none`。
- `run_key`：母版参数从“视频文件哈希”放宽为“任意参考素材”，否则纯图片轮次无法创建。
- `status`：图片轮次带 img 标记；`result --index N` 按 `results` 取第 N 张，缺省第一张；旧轮次没有 `results` 时只取 `result`。
- `upload` 仍记录母版上传件，供旧的通用闸门与人工查看；其余缩放件在 `params.refs`。
- 断点续跑不再按 `assets` 验证素材（决策 75 后没有登记环节）；旧轮次带 `assets`
  的读取方按缺省处理。

关键机制（随 vrpad aigc/round 迁入）：task_id 防重发（断点续跑从台账断点继续）、
gate 数字留档、models.json 清单 24h 缓存。

手动注册后端（`register`）写同样的 run.json（backend = "manual"，无 upload 件与
task_id），保证下游 `result` / adopt 逻辑对两种后端无差别。
