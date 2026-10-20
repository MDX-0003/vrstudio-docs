# 决策记录

合并设计阶段（2026-10）与用户逐项对齐的结论。改动任何一条都应回到本表登记。

## 已拍板（问答确认）

| # | 决策点 | 结论 | 理由摘要 |
|---|---|---|---|
| 1 | 交互形态 | Web 控制台为总入口；CLI 与 web 共享同一执行路径（web 队列 subprocess 跑 CLI） | 直接解决"两套流程交缠难用"；vrpatch web 骨架可复用 |
| 2 | 生成后端 | 双后端：mglc(Seedance) 子进程 + 手动注册本地文件，写同构台账 | 没额度/换账号/用外部工具时流程不断；vrpatch 现有手动路径不丢 |
| 3 | 仓库拓扑 | 两个新仓库（vrgen + vrstudio），旧仓库冻结归档 | 职责清晰；生成服务独立演进 |
| 4 | 服务接入 | CLI 子进程（argv + 退出码 + 台账文件） | 与 vrpatch web 队列、mglc 用法同构；零版本耦合 |
| 5 | 多段选区 | 维持单段；同源多角色 = 多 case 串行 merge | 冻结契约不动；merge 对 footprint 外逐位不变，天然可串行 |
| 6 | 历史数据 | 不迁移，新仓库从新 case 开始 | 重头实现，不为旧格式背负荷 |
| 7 | case 模型 | 修订版：case 只放静态事实；生成调用信息（台账/提示词/task_id）全住 vrgen | 回应"干净精简 + 不混杂"：case→vrgen 只有一行 adopt 指针 |
| 8 | 术语 | vrpad 的 **brief 更名 prompt-vars**（提示词可变块 + 模板选择）；job 级草稿落 `runs/<job>/prompt-vars.toml`；`--template` 首次 submit 后记入草稿 | "brief"与 vrpatch 网页选区草稿（viewport/inner）撞心智；pad/extract 等流程模块保持零提示词知识，prompt 知识只住 vrgen（用户审查提出） |
| 9 | --set 语义 | 键集合自适应于草稿 `[vars]`（新增字段零代码、禁止逐变量固定分支）；未知键退出码 2 并列出可用键；临时覆盖不写回草稿 | 用户提出；与"fail loud"哲学一致 |
| 10 | case 补字段 | patch 的 case.toml 增加 `[extract] current`（当前抽取版本指针，generate/merge 认它） | 审查 generate 设计时发现的遗漏；vrpatch 已有同款先例，避免"最新时间戳"隐式约定 |
| 11 | M4 顺序 | 先 patch 后端接线（pick/extract/merge/restore 接统一 case.py、ai-clip 改调 `vrgen register`），CLI 全绿后再做 web；web 技术栈（沿用 Starlette+原生 JS / HTMX / 前后端分离）先出对比文档单独讨论再定 | 后端是 web 的地基；技术栈选择值得独立论证（2026-10-16 问答确认） |
| 12 | 页面形态 | 向导式（wizard）+ **软向导**：步骤可自由切换查看，"下一步"在验收未达成（mask 未定/无返回件等）时置灰并提示原因 | 强引导与调试自由兼顾 |
| 13 | pick 草稿归属 | 视口/inner 草稿统一写 case.toml（vrstudio case.py 唯一权威），CLI 与 web 都是调用方；不再用 vrpatch 私有 ai_clip.json 草稿体系 | 与决策 7/10 同源：case 模型是三方（CLI/generate/web）共用的唯一事实 |
| 14 | restore 接入深度 | merge 前自动检测返回件合规（帧数/fps/分辨率），不合规自动跑 restore+RIFE+scalefit，浏览器内全通 | 返回片时间契约修复不留给用户手动 CLI |
| 15 | generate 页展示 | 轮询任务状态（轮次列表/run.json）+ mglc.log tail + 断点续跑提示 | 与台账契约对齐 |
| 16 | 对比图 | 同步播放 + 滑动对比（原片 vs 成片），两条流程末尾共用 | 帧级检查接缝需要 |
| 17 | 多用户形态 | 服务以 `--host 0.0.0.0` 开放到局域网、免登录 + 自报昵称；重计算任务进单队列先进先出串行；同一 case 用 case 级独占锁互斥（锁住期间他人全只读，退出或超时自动释放）；浏览/轮询/对比播放直接并发不排队。本轮只记录，web 仍按单人用先跑通，多用户开关后续迭代打开 | 2026-10-16 问答确认（分析过程见下方"多用户分层设计"） |
| 18 | 提示词编辑 | web 生成页完整展示模板正文（只读）+ 变量值（输入框，改动即存）；新增 `vrgen prompt show / save` 两条只读/写草稿命令（JSON 输出，契约 case-model.md §4）；变量草稿单一权威仍按方案 A 留在 vrgen（`runs/<job>/prompt-vars.toml`，job=case 名，打开 case 即经 CLI 读回——用户要的"下次打开还在"由此满足，且不破坏决策 7"提示词不进 case"）；模板自带的变量（正文引用的非几何键）只能改值不能删，自定义变量可增删 | 2026-10-16 用户点名处理提示词显示问题；存储方案按 frontend-feedback 拆解时的倾向（方案 A）执行，任务队列同时把显示条数扩到 10 并加提交时间 |
| 19 | 编码档 | 全流程只产出一个视频编码档：H.264 8-bit yuv420p（默认 crf 18，preset veryfast）；4:4:4 档整体废弃，不再保留"播放时转码"或双档并存。像素基线测试需要精确往返时显式钉 `video.crf=0`，不依赖生产默认值 | 2026-10-19 用户验收 fullredraw 时发现对比页右侧全黑：Seedance 返回本身是 4:2:0，444 是 recompose 重新编码出来的，文件大数倍且 Chrome 的 H.264 解码器解不了 4:4:4。用户明确否决"播放时再转 420"，要求文件落盘时就是可播的 420 |
| 20 | 生成参数与提示词 | 生成页把"输出分辨率"（mglc `--resolution`，480p/720p/1080p，显示 21:9 标称宽高）与"输入分辨率"（vrgen `--scale`，仅 auto/full/half，显示当前 case 的实际宽高）分成两个下拉框；模型 37/videoEdit/21:9/时长/数量固定展示，数量暂锁 1（vrgen 只取第一个结果）。`vrgen submit` 增加显式参数：`--model-id`/`--mode`/`--duration`/`--num`/`--aspect-ratio` 分别对应 mglc 同名/同义 flag，`--scale` 是 vrgen 自有上传缩放；新增 `vrgen params show/save`，参数按 job 存 `runs/<job>/generation.toml`。提示词模板直接改 `templates/360-closure.md`（项目未批量使用），新增【情节与动作】和【允许变化】两节，变量为 `plot`/`action`/`allowed_changes`；输出画布措辞改为"保持相同 21:9 构图与覆盖范围"，不再声称输出像素等于输入文件 | 2026-10-19 用户确认：输入端只保留 auto/full/half；页面必须能直接指定必要参数并看到具体宽高；提示词要能约束情节/动作，并设计"哪些允许变化"，允许通过前端临时编辑 |
| 21 | gen 流程与参考图预留 | 新增 `flow = "gen"`：case 只放源视频（sha256 创建时钉死），向导只有"生成"一步，复用现有生成面板；generate 直接把源视频作为输入包（canvas = source = 源实际像素，无 mask），模板用 `gen-edit`，adopt 结果落 `case/result.mp4`。视频编辑模式不指定输出比例：`--aspect-ratio auto` 表示不向 mglc 传该 flag（videoEdit 的 ratios 为空，输出跟随输入）；`params show --aspect-ratio auto` 把 fixed 显示为 auto，页面写"跟随输入"。未来参考图功能预留 `case.toml [gen] reference_images`（本地图片路径列表）：当前只保存不生效，非空时 generate 明确拒绝；接入时由 vrgen submit 增加 `--ref-image`，逐张配 SD 素材 id 以 mglc `--image`/`--asset-id` 发出 | 2026-10-19 用户提出"只做简单生成、不要前后流程"的新模式；要求先用它在 Simple_Anima_Test 上跑通 1080p，并预先留出参考图接口而不开发 |
| 22 | 项目额度 | 个人额度为 0 时，把项目生成会话 ID 通过 `vrgen submit --session-id`（或 `params save --session-id` 写入 `generation.toml`）传给 mglc `video generate --session-id`，提交即落在该项目下、计费走项目余额。会话 ID 的发现路径是 `mglc project list` → `mglc episode list --project-id` → `mglc session list --project-id --episode`。不传 session-id 时保留 `generation.toml` 已有值；0 表示个人额度。层级与边界详见 `docs/sessions.md` | 2026-10-19 用户指出额度分个人与项目；同日实测：同一提交命令不带 session-id 返回 400403，带 `--session-id 2060150528006080` 后任务提交成功并出片 |
| 23 | 生成模式可选 | 生成页新增模式下拉框，选项由 `vrgen params show` 从模型能力的 `referenceModes` 中筛出“接受输入视频”的模式（当前为 videoEdit、allMediaRef、videoExtend）；模式与输出比例写入 `generation.toml`，submit 从草稿或命令行读取。没有比例列表的模式显示“跟随输入”（`auto`），有比例列表的模式（如 allMediaRef）从平台列表选择比例；`params show` 同时返回 `modes`、`current.mode`、`current.aspect_ratio`（2026-10-20 由决策 26 扩展：firstLastFrame 不吃视频但进入模式列表） | 2026-10-19 用户确认 VideoEdit 动作实验失败，需要切换到 allMediaRef 等模式；用户要求后续多素材与 case 创建流程另行出方案审查 |
| 24 | case 与多素材 | gen case 创建不再要求源视频，但必须选择模式；模式唯一权威仍为 `runs/<case>/generation.toml`，创建后立即写入，`case.toml` 不保存模式。gen 增加有序 `[[assets]]`，视频与图片复制进 `cases/<name>/assets/` 并记录相对路径与哈希；角色由用户手动选择（edit_master/motion_ref/scene_ref/subject_ref）。本期只支持 videoEdit、allMediaRef、videoExtend，不做 firstFrame/firstLastFrame/text2video 与音频。gen 页面只有素材与生成两步，不做对比页；素材合格性只在 vrgen 提交前校验，失败原因从任务日志显示。patch 与 fullredraw 保持现状（firstLastFrame 已由决策 26 扩展；素材步骤并入生成页侧边栏） | 2026-10-19 用户逐项确认，详见 `docs/multi-asset-plan.md` |
| 25 | 多素材契约细节 | 素材以独立 JSON 清单传给 vrgen（`submit --refs refs.json`），每项含 id/kind/path/role/sha256；gen 不再传 `--input`/`--mask`，`--canvas`/`--source` 可省略并由母版视频推导。台账 `assets` 用 `video:v1`/`image:i1` 分组键，`params.refs` 记录缩放件与顺序。角色矩阵：videoEdit/videoExtend 恰好 1 个视频 edit_master（排第一）、图片只能 subject_ref；allMediaRef 至少 1 个视频（2026-10-20 由决策 26 改为视频可为 0，并扩展首尾帧角色），视频可用 edit_master/motion_ref/scene_ref（至多 1 个 edit_master 且排第一），图片可用 subject_ref/scene_ref。母版定提示词几何与上传基准，其余视频各自缩放；时长 videoEdit/videoExtend 取母版、allMediaRef 取最长视频；超限图片也缩放后上传。gen 统一切到新模板 `gen-multi`，用 `asset_list`/`task_rule`/`timeline_rule` 三个只读计算变量承载素材清单与模式语义。`vrstudio case new --mode` 在创建后调用 vrgen 写模式；gen 给了源视频就复制为 v1/edit_master。旧 gen case 在 load 时自动迁移落盘。页面按共享 partials + 拆分脚本重构；本期不真实提交，网页提供免额度检查入口（`generate submit --check` 真正执行 `vrgen submit --dry-run`，校验素材与提示词但不发请求） | 2026-10-19 用户逐项拍板；本机开发与验收不消耗平台额度 |
| 26 | 首尾帧管线与图片生成 | 批准 firstLastFrame 两段式管线：图片模型生成首尾关键帧，视频模型 firstLastFrame 补中间动作。关键帧工作台是 case 内页面，入口在 gen 与 patch 生成页侧边栏，fullredraw 不接入；`[[assets]]` 三条流程通用，源视频与流程产物作为派生条目只读展示；新增 `[submit] selected` 提交集，角色词表增加 first_frame / last_frame / mid_frame / first_frame_raw / last_frame_raw；gen 与 patch 增加 firstLastFrame 模式，patch 以 clip.json viewport 为几何权威并走既有 merge；首期全链路固定 16:9（patch viewport 1920×1080、gen 图片 16:9、firstLastFrame 1080p、merge 目标 1920×1080），比例不一致报错、不静默拉伸；时长为 CLI 参数，显式值 > 最长视频 > 4，不做持久化；新增 `vrgen image submit` 与任务种类注册表 | 2026-10-20 用户批准整体方案；设计见 `docs/first-last-frame-pipeline.md`，实施计划见 `docs/firstlast-dev-plan.md` |

## 多用户分层设计（第 17 条的展开）

用户的复述原文与判定：

> 用户复述：机器只有一台，所以要么放弃这个方案，要么就得做需求队列。
>
> 判定：两头都对，中间漏了第三种情况——"放弃"和"全队列"不是仅有的两个选项，正确形态是按操作类型分流。"机器只有一台"成立：重计算（extract/merge/recompose/restore/RIFE 都是 ffmpeg 级别的单机满载任务）确实只有一份算力，同时跑两个会互相拖慢且内存翻倍。"要么放弃"不成立：浏览、看轮次台账、看对比图、填提示词变量这类操作不占算力，多人同时用没有冲突。"要么就得做需求队列"对重计算成立。修正日期：2026-10-16。

- **并发层（不排队）**：页面浏览、台账/状态轮询、对比图播放、prompt-vars 填写——多人同时用，直接并发响应。
- **串行层（任务队列）**：extract、merge、recompose、restore、vrgen submit——全部进 web 骨架自带的 `tasks.py` 单 worker 队列（旧 vrpatch 已有，迁入继承而非新造），前端显示排队位置与进度；mglc 提交受配额限制且一次渲染约五分钟，天然走同一队列，vrgen 台账的断点续跑保证排队中途重提不重复扣额度。
- **互斥层（case 锁）**：排队解决算力争用，不解决数据争用——两个人同时在同一个 case 的 pick 页拖框、或一个在 pick 一个在 merge，case.toml 会互相覆盖；进入向导编辑（pick 草稿、触发任务）前先拿这个 case 的占用标记，拿不到则整体只读并提示占用者昵称。
- **身份**：免登录，自报昵称仅用于显示任务归属与占用者，不做账号体系。
- **技术栈影响**：无。路线 A（Starlette + 原生 JS）完全承载；`serve` 加 `--host 0.0.0.0` 即可开放。

## case 模型修订细节（第 7 条的展开）

| 质疑点 | 处置 |
|---|---|
| `[fullredraw] target_aspect` | 移出 case → vrstudio 项目配置（平台 bucket 参数，非视频事实） |
| `[patch] viewport/inner/frames` | 保留，角色 = 选区草稿。pick 是迭代动作，草稿（case.toml 可变）与契约（clip.json 冻结）分离，避免版本爆炸 |
| `sha256` | patch 必留（merge 重读源，防"几何配错视频"）；fullredraw 可省（pad 后源不再被读，manifest 已含源身份） |

## 默认决策（设计时替用户定的，仍可否决）

| # | 默认 | 状态 |
|---|---|---|
| D1 | 命名：`vrgen`（生成服务）/ `vrstudio`（流程仓库）；工作区根 `E:\VRAIGC` | 已被采纳为目录名 |
| D2 | mglc 仍为外部 CLI，vrgen 子进程调用；登录态/素材库/限额归 vrgen | 待确认 |
| D3 | 闸门分层：vrgen 只做通用检查（解码/帧数/分辨率）；几何闸门（配准 r、wrap、scalefit）留在 vrstudio 各流程 | 待确认 |
| D4 | 音频照搬现状：patch 成片 remux 源音轨；fullredraw 无音轨（平台 videoEdit 不回音轨，已知限制） | 待确认 |
| D5 | 旧仓库处置：冻结归档，README 顶部加一行指向新仓库 | 待确认 |
| D6 | ffmpeg 封装合并为多 profile 单模块（lossless444 / ai14 / delivery），旧回归测试随迁守护 | 已被决策 19 取代：不再保留 444 档，全流程单一 420 delivery |
| D7 | CI 仅 test + lint；无 CD（本地工具，无部署物） | 已按此搭建脚手架 |

## 命名说明

- `AGENT.md` 请求已按业界标准名落地为 `AGENTS.md`（工具识别的标准文件名）。
- 正式产品名如需更改，改目录名 + pyproject `name` + 文档即可，脚手架不锁死命名。
