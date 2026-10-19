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

### flow = "gen"（简单生成：源视频直接送生成，前后不加流程）

```toml
flow = "gen"

[source]
path = "../sources/Simple_Anima_Test.mp4"
sha256 = "…"            # 每次 submit 都重读源并上传，创建时钉死身份

# [gen]                 # 预留：参考图功能，当前未实现
# reference_images = []

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
- flow = gen 的 case 只有源视频一段静态事实：generate 直接把 `[source] path` 上传，
  画布尺寸与源尺寸都取源视频的实际像素；没有 mask、pad 产物或抽取版本。
- `[gen] reference_images` 是给未来参考图功能预留的字段：值是一个本地图片路径列表。
  当前 vrstudio 只读写并原样保存，`generate` 发现列表非空时明确报"参考图还没接入"，
  不会静默忽略。未来接入时由 vrgen submit 增加 `--ref-image`，逐个配 SD 素材 id
  以 mglc `--image` / `--asset-id` 发出（videoEdit 的 refImageValidator 允许最多 30 张）。

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
  result.mp4                     # 被采用的那轮结果（源视频不复制，直接上传）
  # [gen] reference_images 里的图片原地引用，不复制
```

## 4. vrgen CLI 契约

```
vrgen login [--check]                      # 登录态管理（透传 mglc）
vrgen models [--refresh]                   # 平台模型清单
vrgen submit --job <名> --input <视频> --mask <mask> \
           [--template <id>] [--set theme=…,style=…] \
           [--model-id 37] [--mode videoEdit] [--resolution 1080p] \
           [--duration <秒>] [--num <1..4>] [--aspect-ratio 21:9] \
           [--scale auto|full|half] [--session-id <项目生成会话>] [--workdir <dir>]
                                           # 断点续跑、task_id 防重发
vrgen status --job <名> [--watch]          # 轮询；--watch 阻塞到终态
vrgen register --job <名> --file <本地路径>            # 手动后端：写同格式台账
vrgen result --job <名> --round <key> --out <路径>     # 导出结果（adopt 时调用）
vrgen peek <task-id>                       # 零额度查平台侧状态
vrgen prompt show --job <名> [--template <id>] [--workdir <dir>]   # 读提示词模板+变量草稿
vrgen prompt save --job <名> [--set k=v]… [--unset k]… [--template <id>] [--workdir <dir>]
vrgen params show --job <名> --input <视频> --canvas WxH --source WxH [--aspect-ratio auto] [--workdir <dir>]
vrgen params save --job <名> --resolution <480p|720p|1080p> --scale <auto|full|half> [--session-id <id>] [--project-id <id>] [--episode <n>] [--workdir <dir>]
vrgen sessions list [--project-id <id>] [--episode <n>]   # 只读：项目/剧集/会话树，JSON 输出
```

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
 "current": {"resolution": "720p", "scale": "auto"},
 "fixed": {"model_id": 37, "mode": "videoEdit", "aspect_ratio": "21:9",
           "duration_s": 8, "num": 1},
 "saved": true}
```

- `output` 是平台输出档位及标称宽高；`input` 是当前 case 的输入文件在三种 `scale` 下的实际宽高，`ok/reason` 由平台模型的像素/体积限制计算。
- `current` 优先读 `runs/<job>/generation.toml`，没有则回退配置默认值；`saved` 表示草稿是否存在。`current` 里的 `session_id` 是项目生成会话（0 表示个人额度）。
- 项目额度的接法：`mglc project list` 拿项目 ID，`mglc episode list --project-id <id>` 拿剧集序号，`mglc session list --project-id <id> --episode <n>` 拿 `sessionId`；把 `sessionId` 写进 `generation.toml`（`params save --session-id`）后，所有 submit 都走项目额度。不传 `--session-id` 时 `params save` 保留已有会话。层级、额度行为与失败边界详见 `docs/sessions.md`。
- `params show --aspect-ratio auto` 把 `fixed.aspect_ratio` 显示为 `auto`，页面据此写“跟随输入”；不传时沿用配置默认值。fullredraw 传 `21:9`，gen 传 `auto`。
- `params save` 只接受 `480p|720p|1080p` 与 `auto|full|half`，写 `runs/<job>/generation.toml`，回显 `{"resolution": …, "scale": …, "session_id": …, "project_id": …, "episode": …}`。
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
{"template": "360-closure",        // 生效模板 id：草稿 > --template > 配置默认；都没有则 null
 "available": ["360-closure", "gen-edit"],  // templates/ 下全部可选模板
 "template_text": "…",             // 模板正文原样（含 {占位符}）
 "placeholders": ["canvas_w", "theme"],  // 模板正文引用的全部 {键}
 "geometry_keys": ["canvas_w"],    // submit 时由几何自动填充的只读键
 "vars": {"theme": "黄昏"}}         // prompt-vars.toml [vars] 当前值
```

- `show`：只读。模板解析顺序 `--template` > 草稿 > 配置默认；找不到模板时退出码 2 并列出 `available`。
- `save`：写草稿并回显保存后的同一 JSON。`--set` 新增或覆盖（这里是草稿编辑器，
  **允许新键**，与 submit `--set` 只认已有键不同）；`--unset` 删除键，模板正文引用的键
  拒绝删除（退出码 2 列出哪些删不了）；`--template` 切换模板（必须存在于 templates/）。
- 变量的展示与增删规则（web 侧消费）：模板引用的非几何键（如 theme/style/plot/action/
  allowed_changes）永远展示、不可删除、值可改；草稿里的自定义键可改可删；`geometry_keys`
  是只读占位符，页面只提示不出现输入框。

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
  generation.toml       # job 级草稿：resolution/scale/session_id/project_id/episode（决策 20/22）
  <轮次key>/
    run.json            # 台账：stage/params/prompt/assets/task_id/result/gate/notes
    prompt.txt          # 实际发出的提示词（模板展开后）
    command.txt         # 实际发出的 argv
    progress.log        # 过程叙事（含等待轮询），每次调用追加
    mglc.log            # 外部调用的 argv/返回码/错误消息
    upload_<w>x<h>.mp4  # 缩档后真正上传的（仅 mglc 后端）
    result.mp4          # 生成/注册的结果
```

关键机制（随 vrpad aigc/round 迁入）：task_id 防重发（断点续跑从台账断点继续）、
换账号后素材自愈、gate 数字留档、models.json 清单 24h 缓存。

手动注册后端（`register`）写同样的 run.json（backend = "manual"，无 upload 件与
task_id），保证下游 `result` / adopt 逻辑对两种后端无差别。
