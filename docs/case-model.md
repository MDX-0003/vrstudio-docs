# Case 数据模型与 vrgen CLI 契约

两仓库的唯一接口权威。任何字段或命令面的变更先改本文，再改两侧代码与测试。

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

[viewport]              # 选区草稿：web pick 写入，extract 时冻结进 clip.json
yaw_deg = 0.0
pitch_deg = -10.0
fov_h_deg = 90.0
width = 1470
height = 943

[inner]                 # 白膜子区（视口内坐标）：真正送去重绘的部分
x = 400
y = 200
width = 600
height = 500

[frames]
start = 24
end = 168

[extract]               # 当前生效的抽取版本（web extract 时写入）
current = "20260923T073001"   # → extracts/<时间戳>/；generate 与 merge 都以它为准

[adopt]                 # vrgen 台账里被采用的轮次；采用时结果已拷入本 case
round = "dusk-c3a41f90"
```

### flow = "fullredraw"（全景重绘：AI 重绘整个 360°）

```toml
flow = "fullredraw"

[source]
path = "../sources/stock_pano.mp4"
sha256 = "…"            # 可选：pad 之后源不再被读，manifest 已含源身份

[adopt]
round = "dusk-a9fb11bc"
```

### flow = "gen"（多素材生成：素材自带，模式由 generation.toml 决定）

```toml
flow = "gen"

[[assets]]                     # 有序数组；顺序决定 @VideoN / @ImageN 编号
id = "v1"                      # case 内唯一；前端、文件名校验与台账映射都认它
kind = "video"                 # video | image
path = "assets/v1_main.mp4"    # 相对 case 目录；case 自带文件
role = "edit_master"           # edit_master | motion_ref | space_ref | scene_ref | subject_ref
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

[adopt]
round = "dusk-3c1a4b2d"
```

设计说明：

- `target_aspect` 不在 case 里——它是平台 bucket 参数，进 vrstudio 项目配置。
- `[viewport]/[inner]/[frames]` 是**草稿**（可变）；`clip.json` 是**契约**（冻结）。
  改范围 = 改草稿重新 extract = 新版本目录，两者分离避免 pick 迭代造成版本爆炸。
- `[extract] current` 是草稿→契约的"当前生效"指针：generate 与 merge 都认它，
  不采用"最新时间戳"这种在手工复制目录时会出错的隐式约定（vrpatch 先例）。
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
- `role` 由用户手动选择，不按顺序推断；空角色是未完成状态，提交前必须补齐。
- 数值限制（格式、时长、帧率、像素、体积、数量上限）只在 vrgen 提交前校验；
  vrstudio 前端不重复实现。视频与超限图片在 vrgen 内缩放到限额内再上传。

### gen 素材角色与模式矩阵

| 模式 | 视频 | 图片 | 数量与顺序 |
|---|---|---|---|
| `videoEdit` | 恰好 1 个，`role = "edit_master"` | 只能 `subject_ref` | 视频必须排第一条 |
| `allMediaRef` | 至少 1 个；角色 `edit_master` / `motion_ref` / `space_ref` / `scene_ref` | `subject_ref` / `space_ref` / `scene_ref` | 至多 1 个 `edit_master`；若存在，必须排第一条视频 |
| `videoExtend` | 恰好 1 个，`role = "edit_master"` | 只能 `subject_ref` | 视频必须排第一条 |

`space_ref` 与 `motion_ref` 的分工是“空间”和“身体动作”的分工：`space_ref` 只提供机位、构图、起点与终点位置，不提供人物动作；`motion_ref` 提供动作节奏与路径。白模视频只锁空间时用 `space_ref`，需要继承动作节奏时用 `motion_ref`。

- 三种模式都要求至少 1 个视频素材；audio 不在本期范围。
- 视频数量上限取 `refVideoValidator.maxCount`，图片数量上限取
  `refImageValidator.maxCount`，同时不超过模式自身的 `maxCount`。
- 母版（提示词几何与上传基准）取第一条 `edit_master` 视频；`allMediaRef` 没有
  `edit_master` 时取第一条视频。其余视频各自缩放到限额内并保持各自比例。
- 时长：`videoEdit` / `videoExtend` 取母版时长，`allMediaRef` 取最长视频时长；
  显式 `--duration` 仍然优先。

## 3. case 目录

```
cases/<名>/
  case.toml                      # 唯一真源（§2）
  # --- flow = patch ---
  extracts/<时间戳>/             # 版本化冻结契约（vrpatch 原样）
    clip.json                    #   字段集/version=1 冻结，单段守卫
    clip.mp4                     #   送生成的视口裁剪
    clip_mask.png                #   inner 掩膜
    result.mp4                   #   被采用的那轮结果（adopt 时从 vrgen 拷入）
  derived/                       # merge 产物 out_<版本>.mp4 + .merge.json + pick/ 预览缓存
  # --- flow = fullredraw ---
  seedance_input.mp4             # pad 画布（无损）
  seedance_input_mask.png
  seedance_input_pad.json        # recompose 唯一几何权威（契约原样）
  result.mp4                     # 被采用的那轮结果
  out/<轮次key>.mp4 + _recompose.json
  # --- flow = gen ---
  assets/                        # 素材副本（case 自带，不依赖外部路径）
    v1_main.mp4
    v2_motion_ref.mp4
    i1_character.png
  result.mp4                     # 被采用的那轮结果
```

## 4. vrgen CLI 契约

case 创建入口（vrstudio）：

```
vrstudio case new <名> --flow patch|fullredraw|gen [--source <视频>] [--mode <模式>]
  # patch/fullredraw：--source 必填，--mode 禁止
  # gen：--mode 必填；--source 可选。给了源视频就复制为 assets/v1（edit_master）。
  #      case 写盘后立即以子进程调 vrgen params save --job <名> --mode <模式>；
  #      写模式失败时 case 保留，命令以退出码 2 结束并提示重试。
```

```
vrgen login [--check]                      # 登录态管理（透传 mglc）
vrgen models [--refresh]                   # 平台模型清单
vrgen submit --job <名> \
           ( --input <视频> [--mask <mask>] | --refs <素材清单.json> ) \
           [--canvas WxH] [--source WxH] \
           [--template <id>] [--set theme=…,style=…] \
           [--model-id 37] [--mode videoEdit] [--resolution 1080p] \
           [--duration <秒>] [--num <1..4>] [--aspect-ratio 21:9] \
           [--scale auto|full|half] [--session-id <项目生成会话>] [--workdir <dir>]
                                           # 断点续跑、task_id 防重发
vrgen status --job <名> [--watch]          # 轮询；--watch 阻塞到终态
vrgen register --job <名> --file <本地路径>            # 手动后端：写同格式台账
vrgen result --job <名> --round <key> --out <路径>     # 导出结果（adopt 时调用）
vrgen peek <task-id>                       # 零额度查平台侧状态
vrgen prompt show --job <名> [--template <id>] [--refs <json>] [--mode <模式>] \
                 [--canvas WxH] [--source WxH] [--workdir <dir>]   # 读模板+草稿；可回展开正文
vrgen prompt save --job <名> [--set k=v]… [--unset k]… [--template <id>] \
                 [--refs <json>] [--mode <模式>] [--canvas WxH] [--source WxH] [--workdir <dir>]
vrgen params show --job <名> [--input <视频>] [--canvas WxH] [--source WxH] [--aspect-ratio auto] [--workdir <dir>]
vrgen params save --job <名> [--resolution <480p|720p|1080p>] [--scale <auto|full|half>] [--mode <模式>] [--aspect-ratio <auto|W:H>] [--session-id <id>] [--project-id <id>] [--episode <n>] [--workdir <dir>]
vrgen sessions list [--project-id <id>] [--episode <n>]   # 只读：项目/剧集/会话树，JSON 输出
```

`prompt show` 与 `prompt save` 在提供 `--refs` / `--mode` / `--canvas` / `--source` 时，会额外返回 `rendered`（展开后的完整提示词）和 `render_error`（缺哪个占位符）。展开只读，不建轮次、不碰平台；前端提示词面板默认显示 `rendered`，模板骨架可切换查看。

### `--refs` 素材清单（gen 多素材入口）

`vrgen submit` 的两种输入互斥：

- `--input` + `--mask`：patch / fullredraw 的单视频入口，行为不变。
- `--refs`：gen 的多素材入口；不再传 `--input` / `--mask`。`--canvas` / `--source`
  可以省略，由母版视频的实际尺寸推导。

`--refs` 是一个 JSON 文件：

```json
{
  "assets": [
    {"id": "v1", "kind": "video", "path": "E:\\VRAIGC\\vrstudio\\cases\\demo\\assets\\v1_main.mp4", "role": "edit_master", "sha256": "…"},
    {"id": "v2", "kind": "video", "path": "E:\\VRAIGC\\vrstudio\\cases\\demo\\assets\\v2_motion_ref.mp4", "role": "motion_ref"},
    {"id": "i1", "kind": "image", "path": "E:\\VRAIGC\\vrstudio\\cases\\demo\\assets\\i1_character.png", "role": "subject_ref"}
  ]
}
```

- `path` 可以是绝对路径，也可以相对 JSON 文件所在目录；`sha256` 可选，给了就校验。
- `id` 在清单内唯一；`kind` 只允许 `video` / `image`；`role` 只允许四个受控词。
- 顺序就是提示词 `@VideoN` / `@ImageN` 的编号顺序；vrgen 按角色矩阵校验。
- vrgen 在轮次目录里保存一份 `refs.json` 现场，之后断点续跑以它为准。
- `--canvas` / `--source` 省略时，gen 取母版视频的实际像素（母版 = 第一条
  `edit_master`，没有则第一条视频）；显式给出时仍按显式值。
- 视频与超限图片各自缩放到模型限额内；缩放件按素材 id 命名并记入台账。
- `selftest`：`vrgen submit --refs … --dry-run` 只做本地半场，不发请求不花钱，
  用于检查素材清单、角色矩阵、提示词与 argv。

### 生成参数（web 生成页的数据源，决策 20）

submit 显式参数的来源必须能一一对回 mglc 的 `video generate`，不能自造同名语义：

| vrgen 参数 | 来源 | 语义 |
|---|---|---|
| `--model-id` | mglc `--model-id` | 模型 ID；fullredraw 固定 37（Seedance 2.5） |
| `--mode` | mglc `--type` | 生成模式；fullredraw 固定 `videoEdit` |
| `--duration` | mglc `--duration` | 整数秒，CLI 必填；`videoEdit` 的时间轴由输入决定，默认按输入时长向上取整 |
| `--resolution` | mglc `--resolution` | **输出档位**，480p / 720p / 1080p；不是输入文件尺寸 |
| `--num` | mglc `--num` | 生成数量 1..4；当前 vrgen 只取第一个结果，前端固定 1 |
| `--aspect-ratio` | mglc `--aspect-ratio` | 输出比例；fullredraw 固定 21:9，gen 用 `auto` 表示不传该 flag（videoEdit 的输出比例跟随输入） |
| `--scale` | **vrgen 自有** | 上传前的输入缩放：`auto`（限额内最大）/ `full`（画布原尺寸）/ `half`（画布一半）；没有对应的 mglc flag |
| `--session-id` | mglc `--session-id` | 项目生成会话 ID（>0）；提交落在该项目下，计费走项目额度；0/不传 = 个人额度 |

`--scale` 决定上传文件的实际像素，也就决定提示词里的 `{canvas_w}×{canvas_h}` 和冗余带列号；`--resolution` 只决定平台输出档位，**不会改变提示词里的输入像素数字**。

21:9 下各输出档位的标称尺寸（页面展示用；最终以平台返回并写入 `run.json` 的 gate 为准）：

| 档位 | 标称宽高 | 依据 |
|---|---|---|
| 480p | 992×432 | 平台公开像素表 |
| 720p | 1470×630 | ship_01 实测返回 |
| 1080p | 2206×946 | 平台公开像素表 |

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
            "max_videos": 10, "max_images": 30, "video_required": true,
            "roles": {"video": ["edit_master"],
                      "image": ["subject_ref"]},
            "duration": {"type": ""}},
           {"value": "allMediaRef", "label": "AllMediaRef · 多素材参考（可重新生成动作）",
            "takes_video": true, "ratios": ["auto", "16:9", "21:9"], "max_count": 50,
            "max_videos": 10, "max_images": 30, "video_required": true,
            "roles": {"video": ["edit_master", "motion_ref", "space_ref", "scene_ref"],
                      "image": ["subject_ref", "space_ref", "scene_ref"]},
            "duration": {"type": "range", "min": 4, "max": 30}}],
 "fixed": {"model_id": 37, "duration_s": 8, "num": 1},
 "saved": true}
```

- `output` 是平台输出档位及标称宽高；`input` 是当前 case 的输入文件在三种 `scale` 下的实际宽高，`ok/reason` 由平台模型的像素/体积限制计算。
- `input` / `canvas` / `source` 都可省略。省略 `--input` 时（例如新建 gen case 后还没有素材），
  `output` 与 `input` 返回空数组，页面只使用 `modes` 与 `current`；素材补齐后再次调用
  即恢复完整结果。省略 `--input` 时若显式给了 `--canvas`/`--source`，只用于计算 `output`。
- `modes` 是模型能力里筛出的、本期支持的模式（`videoEdit` / `allMediaRef` / `videoExtend`）；
  页面用它填充模式下拉框，不在前端写死。`max_videos` / `max_images` 取对应
  validator 的 `maxCount`，`roles` 与 `video_required` 是本地角色矩阵的只读回显。
- `current` 优先读 `runs/<job>/generation.toml`，没有则回退配置默认值；`saved` 表示草稿是否存在。`current` 里的 `session_id` 是项目生成会话（0 表示个人额度）。
- `current.mode` 是本次提交使用的模式；`current.aspect_ratio` 是解析后的比例。没有比例选项的模式显示 `auto`，页面写“跟随输入”；`allMediaRef` 这类有比例列表的模式从列表里选择。
- 项目额度的接法：`mglc project list` 拿项目 ID，`mglc episode list --project-id <id>` 拿剧集序号，`mglc session list --project-id <id> --episode <n>` 拿 `sessionId`；把 `sessionId` 写进 `generation.toml`（`params save --session-id`）后，所有 submit 都走项目额度。不传 `--session-id` 时 `params save` 保留已有会话。层级、额度行为与失败边界详见 `docs/sessions.md`。
- `params save` 的 `--resolution` / `--scale` 可省略；省略时保留 `generation.toml` 已有值，
  没有草稿时回退配置默认值。新建 gen case 只传 `--mode`，其余字段等素材选好后再写。
  接受 `480p|720p|1080p`、`auto|full|half`、任意模式名与 `auto` 或 `W:H` 比例，写
  `runs/<job>/generation.toml`，回显 `{"resolution": …, "scale": …, "mode": …, "aspect_ratio": …,
  "session_id": …, "project_id": …, "episode": …}`。模式是否被模型支持由 submit 阶段的
  模型能力校验负责；`vrstudio case new` 在创建时只接受本期三种模式。
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
 "template_text": "…",             // 模板正文原样（含 {占位符}）
 "placeholders": ["canvas_w", "asset_list", "theme"],  // 模板正文引用的全部 {键}
 "geometry_keys": ["canvas_w"],    // submit 时由几何自动填充的只读键
 "computed_keys": ["asset_list", "task_rule", "timeline_rule"],  // 由素材与模式自动填充的只读键
 "vars": {"theme": "黄昏"}}         // prompt-vars.toml [vars] 当前值
```

- `show`：只读。模板解析顺序 `--template` > 草稿 > 配置默认；找不到模板时退出码 2 并列出 `available`。
- `save`：写草稿并回显保存后的同一 JSON。`--set` 新增或覆盖（这里是草稿编辑器，
  **允许新键**，与 submit `--set` 只认已有键不同）；`--unset` 删除键，模板正文引用的键
  拒绝删除（退出码 2 列出哪些删不了）；`--template` 切换模板（必须存在于 templates/）。
- 变量的展示与增删规则（web 侧消费）：模板引用的非几何键（如 theme/style/plot/action/
  allowed_changes）永远展示、不可删除、值可改；草稿里的自定义键可改可删；`geometry_keys`
  与 `computed_keys` 是只读占位符，页面只提示不出现输入框。
- `computed_keys` 是本次新增的契约字段：`asset_list`、`task_rule`、`timeline_rule` 由 vrgen
  在 submit 时按素材顺序与当前模式生成，不允许写进 `prompt-vars.toml`。旧调用方不认识
  这个字段时可以忽略它，不影响原有 `geometry_keys` 行为。

### gen 多素材模板（templates/gen-multi.md）

gen 流程统一使用 `gen-multi`（旧 `gen-edit` 保留，供历史轮次重放与对照）：

- `{asset_list}`：按 case.toml 顺序生成，例如
  `@Video1：编辑母版，负责时间轴、构图与动作基准。`、`@Video2：动作参考，只提供动作节奏与路径。`、
  `@Image1：主体参考，只定义角色外观。`
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
  generation.toml       # job 级草稿：mode/aspect_ratio/resolution/scale/session_id/project_id/episode（决策 20/22/23）
  <轮次key>/
    run.json            # 台账：stage/params/prompt/assets/task_id/result/gate/notes
    prompt.txt          # 实际发出的提示词（模板展开后）
    command.txt         # 实际发出的 argv
    progress.log        # 过程叙事（含等待轮询），每次调用追加
    mglc.log            # 外部调用的 argv/返回码/错误消息
    refs.json           # gen 多素材：本次提交的素材清单现场（含 id/kind/role/path/hash）
    upload_<w>x<h>.mp4  # patch/fullredraw：缩档后真正上传的视频（仅 mglc 后端）
    upload_<id>_<w>x<h>.mp4 / .png   # gen：按素材 id 命名的缩放件
    result.mp4          # 生成/注册的结果
```

gen 多素材的 run.json 字段扩展（其余字段与旧格式相同）：

- `assets`：从 `{"video": 123, "image": 456}` 扩展为按素材 id 分组，例如
  `{"video:v1": 123, "video:v2": 124, "image:i1": 456}`。patch/fullredraw 仍用
  `"video"` / `"image"` 两个旧键，两种键集互不混用。
- `params.refs`：本次提交的素材清单，每项含 `id`、`kind`、`role`、`path`、`sha256`、
  `upload`（缩放件路径）、`width`、`height`；顺序与 `refs.json` 一致。
- `params.master`：母版素材 id；`params.duration_source`：`master` 或 `longest`。
- `upload` 仍记录母版上传件，供旧的通用闸门与人工查看；其余缩放件在 `params.refs`。
- 断点续跑按 `assets` 里的 id 键验证素材；同一素材内容哈希相同则复用审核结果。

关键机制（随 vrpad aigc/round 迁入）：task_id 防重发（断点续跑从台账断点继续）、
换账号后素材自愈、gate 数字留档、models.json 清单 24h 缓存。

手动注册后端（`register`）写同样的 run.json（backend = "manual"，无 upload 件与
task_id），保证下游 `result` / adopt 逻辑对两种后端无差别。
