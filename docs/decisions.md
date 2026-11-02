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
| 26 | 首尾帧管线与图片生成 | 批准 firstLastFrame 两段式管线：图片模型生成首尾关键帧，视频模型 firstLastFrame 补中间动作。关键帧工作台是 case 内页面，入口在 gen 与 patch 生成页侧边栏，fullredraw 不接入；`[[assets]]` 三条流程通用，源视频与流程产物作为派生条目只读展示（2026-10-21 由决策 33 修订：clip/pad 改为可勾选候选，mask 自动附带，raw 帧只进工作台）；新增 `[submit] selected` 提交集，角色词表增加 first_frame / last_frame / mid_frame / first_frame_raw / last_frame_raw；gen 与 patch 增加 firstLastFrame 模式，patch 以 clip.json viewport 为几何权威并走既有 merge；首期全链路固定 16:9（patch viewport 1920×1080、gen 图片 16:9、firstLastFrame 1080p、merge 目标 1920×1080），比例不一致报错、不静默拉伸；时长为 CLI 参数，显式值 > 最长视频 > 4，不做持久化；新增 `vrgen image submit` 与任务种类注册表 | 2026-10-20 用户批准整体方案；设计见 `docs/first-last-frame-pipeline.md`，实施计划见 `docs/firstlast-dev-plan.md` |
| 27 | pick 预览红框 | 红框只由页面 `#innerBox` 画：拖拽中虚线、保存后实线；`vp.png` 不再叠加 inner 红框，预览 URL 和帧缓存不随 inner 失效；`/inner` 写盘后保留 PreviewStore（同步缓存的 mtime），不丢已解码的 ERP 帧 | 消除双红框和松手后 0.5–1.1 秒重画；拖 inner 不改变视口投影，重画是无用功；红框是页面状态，不应由服务端图片承载 | 2026-10-21 用户认可方案 |
| 28 | web 日志 | 服务日志与前端错误日志分成两个 JSONL 文件：`logs/serve/service-YYYYMMDD.jsonl` 记录启动、请求、预览耗时、几何变更、任务生命周期；`logs/serve/client-YYYYMMDD.jsonl` 记录浏览器经 `POST /api/client-log` 上报的脚本与媒体错误。访问日志跳过 `/api/task` 轮询和静态资源；按天轮转，默认保留 14 天；`serve` 增加 `--log-dir`/`--log-level`/`--log-keep-days` | 上次 8760 的运行日志只留在终端，事后无法复查；服务日志要能直接回答慢请求、500、任务失败和预览冷解码，前端错误必须单独归档，不能混进服务文件 | 2026-10-21 用户确认先做服务日志，前端错误只留独立入口，JSON 输出，不记录轮询 |
| 29 | pick 播放与预览代理 | Chrome 优先：滑块和上/下一帧同时 seek 顶部视频并请求同一帧的下方预览；播放中滑块跟随视频但不逐帧请求，暂停/seek 时更新下方；滑块标注帧号、总帧数、当前秒和总秒。预览代理是源片的 4K H.264 8-bit yuv420p 副本（按源宽最多 4096，同 fps/帧数，无音频），首次打开 pick 发现缺文件时由后台生成，顶部播放器与服务端预览共用；源片已是浏览器可播的 H.264 yuv420p MP4 时跳过生成。 | 8K HEVC 每帧 1.5–6.7 秒，逐帧和播放联动都不可用；4K 代理把冷帧降到约 0.3 秒、缓存命中约 12 毫秒；播放中 60fps 跟随不在本轮范围 | 2026-10-21 用户确认 |
| 30 | patch 时间拼接 | `frames` 精确等于 AIGC 重绘范围，切出 x 帧、完整重绘 x 帧、再在时间和空间上恢复，不做前后余量；空间合并与时间合并拆成两个独立 CLI，前端把空间合并的输出路径作为时间合并的输入参数；编码统一 H.264 8-bit yuv420p。空间合并输出已经是 `n_seg @ 抽取 fps`（AI 24fps 在空间合并前由 restore 转回），时间合并只做帧数/fps/sha256 校验后直接拼接，不再次改帧率；完整成片保持源片帧数、fps 和音频 | 中间段重绘与整片交付分开；独立 CLI 让空间合并和时间合并可单独测试、失败可保留中间段；帧数契约已在空间合并阶段建立，时间合并不需要额外帧率转换 | 2026-10-21 用户确认 |
| 31 | patch 合并输出命名与回退 | 空间合并入口 `vrstudio merge` 输出 `out/<版本>_space.mp4`；时间合并入口 `vrstudio assemble` 输出 `out/<版本>_frame.mp4`。`clip.json` 区间等于整片时不调用 assemble，只保留 `_space.mp4`。下游（对比页、输出选择）优先读 `_frame.mp4`，读不到再读 `_space.mp4`；非整片且只有 `_space.mp4` 时标注“仅中间段”。旧 `out/<版本>.mp4` 不进入新回退链，由一次性迁移脚本改名为 `<版本>_space.mp4`，目标已存在时跳过不覆盖 | 两种合并需要可区分的产物；整片抽取再做时间合并是重复劳动；下游按 `_frame` → `_space` 回退，整片和中间段都能找到可用文件 | 2026-10-21 用户确认 |
| 32 | patch 合并串联 | 空间合并和时间合并作为两个连续队列任务：`vrstudio merge` 成功后自动提交 `vrstudio assemble`；两步独立日志、独立重试，空间合并失败不进入时间合并 | 保持两个 CLI 独立，同时让页面自动完成两步；失败时能定位在空间合并还是时间合并 | 2026-10-21 用户确认 |
| 33 | 提交集与流程产物 | 生成提交只认用户勾选：`[submit] selected` 就是本次提交集，不做默认集，也不按模式自动补素材；缺省等于空集；可勾选候选 = `[[assets]]` 文件素材 + patch 的 `clip` / fullredraw 的 `pad`；mask 由装配器自动附带，不出现在候选、不写进 `selected`、不占 `@ImageN`；首尾原始帧只进工作台输入区，`--refs` 清单拒绝 `*_raw` 角色；`--refs` 不再有 `derived` 标记，id 统一为大小写字母开头的字符串（用户素材仍用 `v1`/`i1`，进入 refs 的流程产物用 `clip`/`mask`/`pad`/`pad_mask`；raw 帧的 `first_raw`/`last_raw` 只用于工作台）；firstLastFrame 只取勾选里恰好一张 `first_frame` 加一张 `last_frame`，其余勾选项不参与，也不附带 mask；前端在点击生成时检查这一对，不足或超出就弹错、不发请求，vrgen 保留同样的提交前校验；patch 的 extract 同时产出 `clip.mp4` 与 clip 的首尾原始帧 `first_frame_raw.png`/`last_frame_raw.png`，供工作台直接使用，不再依赖单独的抽帧动作 | 用户 2026-10-21 拍板：前置流程只决定哪些素材可见，提交什么由用户决定；mask 是编辑区域控制图而不是画面参考，拿出来避免用户素材编号顺延；raw 帧靠角色校验挡住，不靠用户自觉；首尾帧的准备工作在 extract 阶段一次完成 |
| 34 | 参数查询与能力缓存 | `vrgen params show` 的 `--input` 改为 `--refs`，从清单里的母版计算输入档位；母版是图片时 `input` 为空。模型详情缓存缺失、过期或刷新失败时直接报配置错，提示 `vrgen models --refresh`；提交时不在本地回退内置限额。CI 与免额度测试用固定的 `models.json` fixture | 提交面统一后参数查询也读同一份清单；模型详情是数量/格式限制的唯一来源，缓存失效时继续提交会把未校验的素材发给平台 | 2026-10-21 用户确认 |
| 35 | 8K 成片播放与 seek | `FfmpegSink` 固定 0.5 秒关键帧间隔（`KEYFRAME_INTERVAL_S`，按 fps 换算成 `-g`/`-keyint_min`），extract、restore、merge、assemble 的输出统一按此编码；对比页的纹理上传在 `video.seeking` 期间跳过，等 seek 完成后再上传，不再把目标时间提前记成已上传 | 2026-10-22 对比页实测：合并片 GOP 250 帧（4.17 秒），源片 30 帧（0.5 秒）；8K 成片 seek 一次要解上百帧，叠加对比页进度校正的反复 seek，表现为播放卡顿、拖进度条不刷新、必须播放/暂停两次才更新。短 GOP 只改关键帧位置，不改变解码像素 | 2026-10-22 用户确认先做编码与前端两项 |
| 36 | pick 与对比页统一用 4K 代理 | pick 页沿用源片代理（`derived/pick/proxy.mp4`，patch 与 fullredraw 都可生成）；对比页左路用同一个源片代理、右路用成片代理（`derived/preview/<stem>_proxy.mp4` + 侧车，记录源路径/字节数/mtime，文件被覆盖后自动重建）。`/api/case/<名>/proxy` 用 `file` 参数选择成片，`/video/outproxy/...` 提供代理；代理未就绪时先播原片并在后台生成，就绪后前端切到代理并保留进度。代理与源文件同 fps、同帧数、无音频，宽度最多 4096；交付文件仍是 8K 原件 | 8K 成片在页面里解码与纹理上传都过重，短 GOP 只解决 seek 成本；预览改为 4K 后左右两路解码量降到约 1/4，代理只生成一次并按源文件身份失效。实测 dacne 的 145 MB 成片代理为 4096×2048、60fps、590 帧、7.1 MB | 2026-10-22 用户确认 |
| 37 | 生成页按主题折叠、控件进底栏、模板内别名 | 生成设置与扣费额度的控件整体迁入 fixed 底栏，页面主体不再出现这两个区域；素材/关键帧/提示词/外部成片各自折叠，摘要行显示当前值。删除「生成记录与选用」，改为「最近成片」一行：有可用未采用轮次时给 `[选用成片]`，已采用或只有预览轮次时不显示，最近一次失败时显示失败提示。提示词占位符写成 `{键\|显示名\|填写说明}`，vrgen `prompt show/save` 增发 `labels` 与 `help`；提示词变量改为防抖保存，提交与预演前先 flush。预演状态用页面输入快照判断是否过期；复用仍由 `run_key` 在台账层保证。 | 非技术用户无法在长页面里核对提交内容，预演轮次和失败轮次混在列表里造成信息污染；把与提交强相关的控件固定在一个位置，能减少上下滚动。别名写在模板里，避免第二份映射文件与漂移；模板测试强制覆盖。 | 2026-10-22 用户确认方案与实施 |
| 38 | 前端技术栈 | 前端界面层改用 Vue 3 + TypeScript + Vite + Element Plus 独立工程重建；旧前端保留在 `/`，新前端挂在 `/next`，按页面迁移、功能对齐后切换；后端同步补浏览器上传、身份与 case 归属、任务归属与只读任务列表、并发写入版本检查、扣费归属。账号与密码暂缓，身份按决策 17 免登录自报昵称；任务先用单队列。身份、队列与 case 占用都通过接口隔离，后续换账号体系或多 worker 不改页面与接口。 | 同时要解决"改不动""套用成熟设计系统""新旧并行"三项要求；Element Plus 正式版活跃，Ant Design Vue 正式版停在 2024-11-11；局域网多人需要后端补五项。 | 2026-10-23 用户确认；论证见 `docs/key-issues/20261023-frontend-stack-selection.md`，实施计划见 `docs/plan/frontend-refactor-plan.md` |
| 39 | 日志分层与索引 | 事件层继续用 `logs/serve/service-YYYYMMDD.jsonl` 与 `client-YYYYMMDD.jsonl`（决策 28）；新增任务原始层 `logs/tasks/YYYYMMDD/<task_id>_<kind>_<case>.log`，短操作不再单独建文件；vrgen 轮次日志保留在 `vrgen_runs/<job>/<round>/mglc.log` 与 `progress.log`，作为轮次审计产物，事件日志用 `round_id` 与 `log_ref` 指向它；`cases/` 与 `logs/` 根目录不再写日志。旧前缀文件不迁移，Phase 5 上线时先输出清理清单，确认后删除。事件保留 14 天，任务原始日志默认 30 天可配置；请求、任务、轮次与用户用 `request_id`/`task_id`/`round_id`/`user_id` 关联；前端只经 `/api/tasks` 与 `/api/tasks/{id}/log` 读取。 | 用户指出每个操作一个日志文件、logs 与另一棵树分散，管理混乱；核对现状：`logs/` 根目录有大量 `extract_`/`merge_`/`assemble_`/`restore_`/`web_`/`proxy_` 文件，`vrgen_runs/` 有 88 个轮次日志，`cases/` 为 0，测试日志混入生产 `logs/`。 | 2026-10-23 用户确认旧日志淘汰；实施见 `docs/plan/frontend-refactor-plan.md` Phase 5。 |
| 40 | 前端迁移的并发与入口 | 新前端写请求带 `X-Case-Revision`；`case-meta.json` 保存负责人、revision 与更新时间，冲突返回 409 `revision_conflict`；旧前端不传 revision 时允许写入并递增。case 占用锁用 `cases/<name>/.web-lock.json`，页面 30 秒心跳，2 分钟无心跳可接管；锁只提示、不阻断写入。任务记录扣费归属 `project_id`/`episode_id`/`session_id`。默认入口切到 `/next/`；旧前端仍由 `/case/{name}` 提供服务，配置 `web.default_frontend=legacy` 可把 `/` 切回旧列表（入口与旧前端回退由决策 42 退役）。 | 局域网多人需要避免静默覆盖与任务归属串号；同时保留旧前端一个版本周期作回退。 | 2026-10-23 用户要求继续完成迁移计划；实施见 `docs/plan/frontend-refactor-plan.md` Phase 4。 |
| 41 | 分支策略 | 根仓库、vrgen、vrstudio 只维护 `main` 分支；不创建长期功能分支，不为阶段性工作保留旁支；临时实验分支验收后合并或删除；提交、文档与验收记录都落在 `main`；不新增长期远程分支。 | 用户 2026-10-25 要求所有进度只在 main 维护。检查时根仓库与 vrstudio 各有一个 `frontend/complete-migration`，两者 `main..branch` 都为空，没有独有提交，已安全删除；vrgen 原本只有 main，保留其未提交工作不动。 | 2026-10-25 用户确认，硬规则 8 同步登记。 |
| 42 | 旧版控制台退役 | 前端只维护 Vue `/next` 一套：删除设置页「旧版入口」、Jinja2 模板与旧静态脚本、`GET /case/{name}` 的页面渲染与 `web.default_frontend` 配置；`/` 固定 307 到 `/next/`，`/case/{name}` 保留 307 到 `/next/case/{name}`（旧书签不 404）。同批删除三个旧版兼容点：`keyframe.sheet`/`sheet_candidates` 派生字段、`GET/PUT /api/case/{name}/keyframe/sheet`、`set_asset_role` 对 `[submit.roles]` 的同步。`/api/*`、`/img/{name}/vp.png`、`/file`、`/video/*` 全部保留。 | 用户 2026-10-27 明确只维护这一版前端；旧版入口在默认配置下本就打不开旧版（`/` 已 307 到 `/next/`），保留只会误导。 | 2026-10-27 用户确认整体退役；实施与验收见 `docs/test-runs/20261027-legacy-console-retirement.md`。 |
| 43 | 配置在启动时定格 | `serve` 启动时一次加载并校验配置（`config.activate`），web 请求路径只读 `config.active()`，不再逐次读盘与重跑 `_validate`；配置错误在启动期按退出码 2 报告并写明原因。改配置文件要重启 serve 生效，取消原「`proxy_max_w` 即时生效」。同批两项：`_validate` 缺键改报 `ConfigError`；`uvicorn.error` 与 `request.error` 的重复异常日志合并为一条，保留方法与路径。 | 2026-10-27 18:14 旧进程（退役前的代码，`_validate` 仍读 `web.default_frontend`）读到已删除该键的新 `default.toml`，每个走到配置的请求都抛 `KeyError` 变成 500，traceback 还因源码已变而显示成错误的行。根因是配置数据热、Python 代码冷，两者能错开；启动定格让文件与代码一起切换，这类错位无法构造。进程级配置是不可变 `Config`，属应用状态，不是硬规则 5 禁止的模块级可变缓存。 | 2026-10-28 用户认可审查结论并要求修复；实施与验收见 `docs/test-runs/20261028-config-snapshot-and-log-dedup.md`。 |
| 44 | 光照参考角色 | 角色词表新增 `lighting_ref`（光照参考）：素材清单固定文案为“只提供光源位置、色温、明暗对比与空气质感；不提供构图、机位、背景与任何画面内容”，只对图片成立。前端按素材种类给下拉：视频保持 `edit_master`/`subject_ref`/`motion_ref`，图片再加上 `lighting_ref`；vrgen 把它加进 `ROLE_PROMPT`，并在语义校验里拒绝视频使用该角色。 | 2026-10-28 palace_01 实测：把氛围参考图标成 `scene_ref` 提交 fullredraw，素材清单的“只提供构图、背景与光照”被模型当成场景授权，返回画面复刻了参考图的宫殿布局（返回帧与参考图结构相关 0.522，与输入 pad 只有 0.053），两条冗余带不再对应，recompose 的几何闸门按设计拒绝出片。`scene_ref` 与 `space_ref` 都显式授予构图，`subject_ref` 会把参考图里的人物当外观依据，词表里没有只给光照的档位；新增一个角色比反复在提示词里跟角色授权对抗更可靠。 | 2026-10-28 用户要求直接落地该角色并支持下拉选择。 |
| 45 | 角色词表单一化 | 角色词表固化为 `docs/roles.json`（name/label/help/prompt/kinds/modes/open/reserved），vrgen 与 vrstudio 各存一份逐字节相同的副本，两侧各有一条契约测试断言本地词表与快照一致并用 SHA256 钉住快照。两侧的 kind 限制改为读同一张表（`check_kinds`）：vrstudio 的添加素材、改角色、`[submit].roles` 读写四处都校验，vrgen 的 `validate_mode` 用同一张表替代逐角色 `if`。`/api/case` 下发 `roles`，前端删掉 `VIDEO_ROLE_OPTIONS`/`IMAGE_ROLE_OPTIONS`/`ASSET_ROLE_LABELS`/`LEGACY_HELP`，下拉只按服务端角色做 `open + kinds + modes` 过滤，旧值由服务端词表补「旧角色」。 | 2026-10-28 加 `lighting_ref` 时同一份词表要在 6 个文件、3 个仓库手工同步，说明还要抄两遍；kind 限制有三种写法（vrgen 两个 `if`、前端两个数组、vrstudio 没有），导致接口直调能把视频存成光照参考、直到提交才报错。角色数量上双后这种手抄会开始付维护成本，且漏改不一定立刻红。 | 2026-10-28 用户要求落地三项：服务端驱动、kind 规则数据化、共享契约快照。 |
| 46 | 360 静图两条流程：patchimg 视口局部、img2video 全幅拼接 | 新增 `flow=patchimg`（360 图片局部重绘）与 `flow=img2video`（360 图片→首尾帧→视频）。`patchimg` 与视频 patch 同构：extract 视口裁剪 `clip.png` + inner mask + `image.json`，图片模型只重绘视口，merge 用 `SegmentMaps`/`composite_frame` 贴回并只写 inner；不走全幅 pad/recompose。`img2video` 的关键帧与视频是整幅 360 画布，走「pad 2:1→21:9 冗余画布 + stitch 还原 2:1」，几何与融合复用 fullredraw 的单帧核心；槽位+绑定统一三种首尾帧组合，链上关键帧留在 padded 域不 recompose，只拼最终视频。 | 视口裁剪是透视图像，不是 360 画布；视口跨接缝时投影先拼好环绕，不需要冗余带。全幅 21:9 会把 4K 输出摊到 9558 宽，8K 实测局部细节明显偏软；117.6 MB 全幅 PNG 还被平台 403。img2video 的关键帧/视频确实是 360 画布，必须 pad/stitch。 | 2026-10-29 用户修正：`patchimg` 改走视口局部；`img2video` 保留全幅 21:9；`firstLastFrame` 接受 21:9；`one_reuse` 可用同一文件做首尾帧。排除：`patchimg` 继续全幅 21:9（8K 局部细节与上传 403 两项实测不支持）；改造现有 patch 双源（污染 `clip.json` 冻结契约、if 分支扩散）；gen 的整幅 360 `videoEdit` 缺口（单独立项）。验证：全幅 patchimg 的 8K 验收证明局部偏软并留下接缝/贴回基线；视口局部的 CLI 重做按 `docs/plan/360-img-gen-flows-plan.md` WP2 执行。 |
| 47 | 8K 静图重绘的两条路线先 CLI 实测 | 对同一张 8192×4096 ERP 与同一张氛围参考图，分别跑「分段局部链式」（多个 `patchimg` case 沿 360 分段、上一段输出作下一段源图、每段带 `lighting_ref`）与「全幅 4K + 关键区块参考」（一次提交整幅 21:9 基图 + 10 张自动切片的关键区块 + `lighting_ref`，`stitch_image` 还原 2:1 到源图尺寸），用同一组指标评测后选型。本轮只在 CLI 层开发，前端接入等选型结论。 | 两条路线的差别是 4K 输出摊在多宽的画布上：分段局部让模型 4K 只服务约 0.7 Mpx 的 inner（约 2.2× 过采样，8K 保真），全幅让 4K 覆盖整幅（约 0.47×，细节上限为 4K）。这个取舍要用真实成片与观感判断，不能只靠算术。分段路线必须先支持 case 子文件夹分组；模型 44 的平台上限已查：13 张参考图、比例表没有 2:1（最宽 21:9）、输出最高 4K，因此 B 必走 pad/stitch，细节图最多 10 张、按真实投影覆盖 84.9% 的 ERP。 | 2026-10-29 用户提出两条路线都要测，并要求先写清开发前置。计划见 `docs/plan/360-img-ab-routes-plan.md`。 |
| 48 | 重打光（relight） | 新增 `vrstudio relight` 子命令：一张真 8K GT 加一张 AI 4K 氛围图进，一张与 GT 同网格的 8K 图出。定位是「光照搬运」——GT 给结构与细节，氛围图只给低频光照、色温与遮挡；不做超分、不做内容回填。算法固定为单一 v2 引擎，线性光下 `out = GT_lin × Ws × gY^strength × V^(local_shading×strength)`：`gY` 是以 GT 亮度为引导的联合引导滤波求出的亮度比，`V` 是 AI 局部亮度与其自身低频之比，`Ws` 是按 strength 插值的 LMS von Kries 白点矩阵。几何（SIFT + RANSAC 相似变换、匹配不足回退相位相关、水平 wrap 的 warp）只住 `src/vrstudio/relight/align.py`，是该相似变换的唯一权威点，不进 `redraw/`；旋转保留、不钳制。参数：`--gt/--atmo/--out` 必填，`--strength` 默认 1.0，`--local-shading` 默认 0.35，`--highlight-clip`（knee 0.72 / max 0.98），`--dump-light`，`--report`；场景预设 night = 1.0/0.35、day = 0.8/0.2。只接受 2:1、同尺寸、8-bit 的输入，不支持 21:9 padded 域。退出码 0/2/1；对齐不可信时必须失败且不出图，判据只有一条：把氛围图按拟合出的变换 warp 到 GT 坐标后，两张图在 2–6 像素尺度上的结构重合度（带通后的归一化相关，0 表示完全无关、1 表示完全重合）低于 0.15。 | AI 图生模型的上传与输出都卡在 4K，而 8K 交付的细节不能来自模型：4K→8K 纯插值 PSNR 上限 44.9 dB、高频只恢复到 86%，中量 USM 即出白边。实测 GT 与重绘是同一场景的两次渲染（4–16 px 带通相关 0.48，8–32 px 0.59），结构能对上、微纹理对不上，因此只能以 GT 为底做低频乘算，不能把重绘当细节来源。乘算模型的三项各自挡住一个已实测的失败：引导滤波挡「烛光低频把人脸整体点亮」，可见度项挡「模型画的阴影压不下去」，全局白点挡「逐通道比值在日光下放大 GT 的红色」。实测：夜戏 4 张候选对齐内点 15–53、2K 带通相关 0.38–0.44，v2 人脸均值 12.0–25.5（v1 为 29.2–54.9，GT 34.7）而全局均值基本不变，说明是光照重分配不是整体压暗；日光 2 张内点 38/41、相关 0.439/0.371，`strength=1.0` 过曝 8.9%、0.7 时 0.8%。 | 2026-10-29 用户确认按 `upscale_lab/docs/cli-integration-plan.md` 的工作包接入，算法不再重新设计。排除方案：加法差值（接缝 0.91 合格但对比度塌陷）、纯超分或锐化（补不出 4K 里不存在的细节，中量以上锐化用白边冒充清晰）、GT 高频嫁接（分频段替换只有 22.9% 区域过一致性判定，输出高频能量 0.99 倍，等于没做）、v1 的 A/B/C/E/F/G/H 比率模式（共用高斯低频逐通道比值，看不到遮挡，已退役只留 `ratio_variants.py` 作历史对照）、球谐 SH（方向光与多光源污染时再启动的后备路线，本期不做）、21:9 padded 域输入（padded 域的画布↔源映射权威在 `_pad.json`，重打光只吃 recompose 后的 2:1）。展开见下节。 |
| 49 | patch 4K 大区域重绘 | patch 支持 3840×2160 视口与 4K 输出档；fov 决定覆盖、分辨率决定密度，页面同时提供 fov 滑杆与视口/输出档；4K 生成走 Seedance 2.0 的 firstLastFrame 或 allMediaRef（4–15 秒），videoEdit 仍固定 1080p；模型按 job 存 generation.toml（P2）；不做多视口/分块、4K 21:9、自动 fov 推荐、时间切分。 | 角色移动范围超过单块 1080p 的覆盖；动作只是示意，不需要结构锁定；2.0 有 4K 但没有 videoEdit，4K 只能用不锁结构的两种模式；两条 4K 路线都是 15 秒上限，19 秒全片需时间切分（另立）。另：patch + allMediaRef 的模板要从 character-repaint 改到 gen-multi。 | 2026-10-30 用户批准方案并要求完整全流程 plan，同时确认 allMediaRef 也可能使用。详见 `docs/plan/patch-4k-region-plan.md`。 |
| 56 | 视频重打光（relight-video） | 新增 `vrstudio relight-video` 子命令：一段 2:1 ERP 真 GT 视频加一张同尺寸 AI 氛围图进，一段同分辨率、同帧数、同帧率的重打光视频出。引擎与参数完全复用决策 48 的图像版：一张氛围图只估一次对齐与光照场（参考帧缺省在整段前 90 帧里自动选，`--ref-frame` 可显式指定），整段逐帧只做光场乘算，编码走 `media/videoio`（H.264 8-bit yuv420p，音频从 GT 视频 `-c copy`）。「固定变换是否仍适用」的判据不是逐帧跟踪位移，而是其余帧与参考帧按同一坐标的结构重合度，全段最低值低于 0.94 时警告、不中断。不提供 `--dump-light`；报告字段 `{gt, atmo, size, frames, fps, ref_frame, ref_matched, frames_checked, min_hold, params, align, clip, light, seconds}`。只适用于固定机位、光照不随时间变化的镜头；运动物体与机位移动的时间一致性作为已知限制登记。 | 逐帧重估相似变换会让相邻帧的缩放/旋转各跳一点（候选之间旋转 −0.14° 到 −0.33°、缩放 0.995–1.015），光照场随之低频闪烁，且每帧一次 SIFT 的代价接近单帧打光本身；固定一次估计恰好把「相机没动」变成显式前提。相位相关在这类 2K 带通图上测不准小位移（合成素材平移 4 像素只测出 0.5–0.7 像素），而判据只需要知道「还在不在同一坐标」，直接比重合度更准也少一个误差源。8K 真实素材 20 帧实测约 3 秒/帧、帧间亮度跳变 0.022（GT 自身 0.035）。 | 2026-10-30 用户认可「第一帧估计几何与光照场、整段复用」的思路并要求先按最小方案试跑再开发。方案见 `docs/plan/relight-video-plan.md`，验收见 `docs/test-runs/20261030-relight-video.md`。 |
| 50 | 首尾帧图片步提示词改为槽位架构 | `keyframe-first.md` 与 `keyframe-last.md` 改为槽位展开：共用 `target` / `preserve` / `cleanup`，首帧 `source_first` / `figure` / `pose_first`，尾帧 `source_last` / `subject_last` / `pose_last`；删除写死的「白色占位人形」与「界面清理」，底图对象是否继承姿态改由 `source_*` 明说；模板新增槽位时 web 端按 `prompt show` 的 placeholders 差集补默认值，旧草稿不需要手工迁移。 | 用户 2026-10-30 指出旧案例约束残留：dance_move 是真人原片，模板却要求「不继承占位人形站姿」，人物被重画成站姿、尺寸偏大；同一底图两套提示词各 4 张的对照实验证明文字保不住姿态。方案与 dance_move 取值见 `docs/keyframe-workbench-plan.md` §3.3、§5.3.1。 |
| 51 | 模板渲染清理空的可选段 | `prep/prompt.py` 的 `render()` 逐行展开后，删除「本行含占位符、这些占位符的值全为空、且渲染后只剩 `【…】` 或空白」的行；本行没有占位符的独立标题行不动，`gen-multi` 的「标题一行、内容下一行」写法不受影响。清理放在渲染这一步，`prompt show` 预览、`image/video submit` 与台账 `prompt.txt` 是同一份文本；过滤 vars 不可行，模板展开仍要求每个占位符有定义。多行可选块（标题一行、占位符下一行）暂不处理，出现时改用显式 `{#key}…{/key}` 语法。 | 用户 2026-10-30 要求提交前自动清理空模块：空槽位会以裸标题 `【清理】`、`【尾帧位置与姿态】` 的形式进入模型；把清理放进 `render()` 而不是 vrstudio 或提交前一刻，预览与提交不会分叉。 |
| 52 | 生成页模型下拉与首尾帧共用图片模型 | 生成页底栏新增「视频模型」「图片模型」两个下拉，选项来自 `params show` 的 `models` / `image_models`，保存走 `params save` 的 `video_model_id` / `image_model_id`；保存的 id 不在当前清单时补一条「模型 #id」占位项，避免下拉框空白。首尾帧工作台不单独选模型，直接用 `generation.toml` 的 `image_model_id`，只在候选区显示当前模型名；4K / 1080p 预设改用 `video_model_id`。 | 模型 id 只在类型内唯一（22 既是视频 Seedance 2.0 也是图片 Seedream 4.0），必须按类型分开存；首尾帧两步共用同一个图片模型，避免每步各选一次。前端改动见 `frontend/src/components/generate/GenerateSubmitBar.vue` 与 `GenerateStep.vue`，验收见浏览器实测：视频 Seedance 2.0 / 图片 专业图片-2.5。 |
| 53 | 移除生成页的 4K / 1080p 快捷预设 | 删除底栏「切到 4K」「切回 1080p」两个按钮及其 `applyPreset` 逻辑。模型、输出分辨率、模式都已有独立下拉，预设只是把三者打包，模型下拉上线后成为重复入口。 | 用户 2026-10-30 要求删除；预设附带的「视口宽度与 4K 不匹配」提示一并移除，若 4K 路线需要该提示，改为在输出分辨率变化时提示。 |
| 54 | 图片流程的 still 命名统一为 image/img | 契约文件 `still.json` → `image.json`、`still_pad.json` → `image_pad.json`、产物 `out/<版本>_still.png` → `out/<版本>_image.png`、vrgen 模板 `still360-local` → `img360-local`、manifest 的 `kind` 值 `"still"` → `"image"`；代码侧 `redraw/still.py` → `redraw/image.py`、`plan_still`/`pad_still`/`stitch_still` → `plan_image`/`pad_image`/`stitch_image`、`StillGeometry`/`StillManifest` → `ImageGeometry`/`ImageManifest`、`StillError` → `ImageFlowError`。`flow` 值不变：`patchimg` 与 `fullRedrawImg` 是用户拍定的对外名字。规则是「媒体类型做前缀」：视频链保持现名，图片链统一 `image`/`img`。已有 extract 目录用一次性脚本改名，不做双读 | `still` 是「静帧」的行话，中文读者要多一次映射；而且现名没有统一规则（`patch`/`patchimg`、`fullredraw`/`fullRedrawImg` 只差大小写、`still_pad` 与 `img2video` 混用），计划 §6 已登记「代码里容易写混」的风险。改名在前端接入前最便宜：真实用户为 0、测试覆盖完整。`still_pad.json` 在 `redraw/manifest.py` 里被标为 frozen external contract，按硬规则 2 先立项再两侧同改。`StillError` 不能叫 `ImageError`——`media.imageio.ImageError`（读图失败）已占用，两个异常在 `extract` 的同一个 `except` 子句里都要用，故取 `ImageFlowError`。排除：flow 值一并改名（磁盘上的 case.toml 要迁移，收益不抵成本）；只改展示层与文档（代码可读性问题原样保留） | 2026-10-30 用户认可方案 A，并指定 flow 值按 `patchimg` / `fullRedrawImg` 写 |
| 55 | 360 图片两条流程前端接入 | 把 `patchimg`（图片·局部重绘）与 `fullRedrawImg`（图片·全幅重绘）开放到 web，作为与 patch/fullredraw 并列的可选 flow：前端 flow 下拉 5 项，两条链都是单张 2:1 ERP 图进、同尺寸 2:1 图出。工作包 WP0–WP7：命名与契约、fullRedrawImg 真实格式验证（1K×1，前移为门槛）、web 建案例接受图片源、op 装配与会话门与门控（去掉 `_gates` 的 else 兜底）、草稿段单一判定、素材挂载与 `/img/keyframe` → `/img/round`、前端页面、真实额度端到端。不做 img2video、A 路线分段链式、gen 的整幅 360 缺口 | CLI 五步已就绪（extract / generate submit / adopt --index / merge 都以 case 为单位，`--check` 可零额度演练），缺口集中在 web 装配与前端页面。评审发现四件必须先改的事：图片提交缺 `--image-model-id` 与会话门、`_gates` 的 else 兜底会把图片 case 静默送进 gen 门链、草稿段判定分散在多个端点（几何端点根本不校验 flow）、`--num`/`--resolution` 只有 help 文案没有值域断言。真实额度轮必须在开放前跑，否则第一条用户链路就是首次平台验证 | 2026-10-30 用户认可方案并要求开始开发；计划见 `docs/plan/img-flows-frontend-plan.md` |
| 57 | 首尾帧可「直接用原始帧」定稿 | 首尾帧工作台每步增加「直接用原始帧」：把当前抽取的 `first_frame_raw.png` / `last_frame_raw.png` 复制进 `[[assets]]`，角色写 `first_frame` / `last_frame`，指针写进 `keyframe.toml`（`round = "extract"`、`index = 1`），不提交生成、不花额度。落成普通素材角色后，交接视频与提交清单走常规路径，`--refs` 里仍然不出现 `*_raw`（决策 33 的「原始帧只进工作台输入区」不破）。首帧同时是这一对定稿的版本锚：落首帧会把 `extract` 记成当前版本并清掉旧尾帧；过期状态下不允许只落尾帧（会拼出跨版本的一对）。原始帧不再作为独立的 ``[[assets]]`` 条目在 extract 时预置 | 用户 2026-10-30 提出：原始首尾帧没有进素材库、无法被选，希望能「做首尾帧重绘」与「直接用原始截图」二选一。直接给 `*_raw` 角色开放提交会污染 `--refs` 契约（保留角色），所以改成「按需落成 first_frame/last_frame」；同时修掉尾帧宽高比对的参照物错误（原来比 assets 里最早的首帧稿，多轮之后必然误判）与「接受尾帧也改写版本锚点」的隐患 | 2026-10-30 用户提出；实现见 `vrstudio/web/app.py` 的 `_keyframe_use_raw` 与 `KeyframeStep.vue` |
| 58 | fullRedrawImg 提示词"只写光、不写物体" | fullRedrawImg 的 `edit` 变量只描述光影、色调、空气与材质响应，不点名原图没有的照明装置或道具；唯一光源必须落在图1 已有的实物上（灯笼、灯架、窗洞），并写明没有其他光源。氛围参考图必须用 `lighting_ref` 角色，其固定文案与模板【禁止】都明确"不取场景与画面内容"，防止参考图的场景被复刻。取值落在 `vrgen_runs/<case>/prompt-vars.toml`，模板不复制 | 2026-10-30 为 `relight_ref_gen_01` 填提示词时发现：初稿在 `edit` 里点名"案几矮烛台与落地连枝灯"，是把原图没有的照明装置当成要新增的物体，与 `preserve` 的"不新增任何物体"自相矛盾，模型最终偏向哪边不可控；同一模板第一句已声明整幅重绘，`edit` 里的任一具名物体都会被当成新增授权。决策 44 的 `scene_ref` 事故说明"参考图内容混入"的风险仍在，`lighting_ref` 文案缺少"场景"一项，模板也只在 `preserve` 里泛泛禁止 | 2026-10-30 用户要求按模板为 relight_ref_gen_01 补提示词；计划与取值见 `docs/plan/fullredraw-img-prompt-vars.md` |
| 59 | 重打光在前端只有一条 flow | `FLOWS` 新增 `relight`，不拆 `relightimg` / `relightvideo`。媒体类型由素材步选定的 GT 文件决定，CLI 也按 GT 的实际探测结果派发到单帧或整段路径。步骤链只有一条：素材 → 重打光 → 对比；视频专属的参考帧、N 帧小样与编码项在同一页里按 GT 类型出现。建 case 不绑源文件（照 gen 的「无源 + `[[assets]]`」模式），GT 与氛围图在素材步选定。素材库是同角色可多条的候选池，两个槽位是 `[relight]` 里用素材 id 表示的两把指针，不是角色本身——美术每改一版氛围图就多一条候选，来回切换不必重新上传。relight 不调 vrgen、不花额度、不需要项目会话，因此没有提交集、adopt 与会话门，`/api/case` 对这条流程不下发 prompt 与 generation_params | 拆成两条 flow 会让输入区、参数面板（scene/strength/local-shading/highlight-clip）、结果区与对比页各维护两份，而它们的差别只有参考帧、小样与编码三处，违反「共用优先」。relight 与 patchimg/fullRedrawImg 的形状不同：那两条以 case 为单位跑五步链并提交平台，relight 是拿两个现成文件直接算，所以不能照抄它们的门控。槽位若直接等同于角色并限一条，素材库就没有候选可挑，「从素材库选」形同虚设 | 2026-10-30 用户认可「只做一个 flow、由 GT 格式决定调哪条 CLI」，并要求先对齐 CLI 接口以免维护两套参数；计划见 `docs/plan/relight-frontend-plan.md`，子页清单为 3 个向导步骤 + 2 处改动、0 个新独立路由；实施与验收见 `docs/test-runs/20261030-relight-frontend.md` |
| 60 | relight CLI 合并与 `--sample` | `vrstudio relight-video` 退役，`vrstudio relight` 改为按 GT 类型派发：图片走 `read_image` 之后单帧重打光，视频走 `probe` 之后整段执行。类型专属参数用错时按参数错退出 2 并指名哪个参数只适用于哪种 GT（`--ref-frame`/`--sample`/`--crf` 仅视频，`--dump-light` 仅图片）。新增 `--sample N`：把 `--out` 当目录，只渲染 N 帧均匀采样的 PNG、不编码视频，并默认跳过整段同位检查。不保留旧命令名做别名 | 保留别名会让 help、文档与错误信息长期出现两套名字，新人更容易用错；合并成一个参数集合是「不维护不同参数组合」的唯一做法。小样必须跳过全片同位检查，否则 8K 一分钟素材的预览要等几分钟，而预览的全部意义就是快——这个取舍写进 help，不留给用户猜 | 2026-10-30 用户批准合并方案；验收要求原有图像版逐位一致基线与视频版强度 0 基线在新命令下重跑 |
| 61 | 氛围图只在本 case 内产生 | 氛围图由用户在 relight case 的素材步上传或从本 case 素材库选择，角色固定为 `relight_atmo`；底版固定为 `relight_gt`。库里同角色可多条，槽位指针 `[relight] atmo` / `gt` 决定用哪一条。两个角色在词表里是 `open = false`、`modes = []`、`reserved = false`。美术对 fullRedrawImg 结果的加工在外部工具完成，本方案只负责接收上传结果，不提供任何浏览器内改像素的入口；不记录跨 case 的来源，也不建氛围图的全局资产库与版本标记 | 美术的加工循环确实是「导出 → 外部改 → 上传」，浏览器内再给一套曝光/色温/对比滑块会与 relight 自己的 strength/local-shading 职责重叠，出现两处都能改亮度。两个角色由 flow 钉死、用户不能改角色，配错的状态因此无法构造。标 `reserved = true` 看起来更贴切，但 `_add_assets_to` 会明确拒绝用户给文件素材指定保留角色，上传管线就走不通 | 2026-10-30 用户确认「只在本 case 内选 + 上传」；实现见 `vrstudio/src/vrstudio/case.py` 与 `vrgen/src/vrgen/roles.json` |
| 62 | 提示词冗余带宽度对齐 mask；重打光选帧只保留一条闸门 | vrgen `prep/prompt.py::geometry_from_sizes` 的带宽从 `(canvas_w - source_w) // 2`（=P）改为 `canvas_w - source_w`（=L），与 `redundant_white` 的 mask 白带同宽：8192×4096 源在 9558×4096 画布上是每侧 1366（白带列 0–1365、8192–9557，主内容 1366–8191 共 6826）。`band_half` 仍是 P=683。同步改写 vrgen 两条断言（`test_full_redraw_img_template_renders`）并新增 `test_geometry_band_matches_the_mask_band`、`test_geometry_band_is_zero_without_redundancy`。vrstudio `relight` 视频路径：删掉「参考帧与氛围图的未对齐带通相关 < 0.15 就退出 1」这条前置闸门，改为只警告；黑场由自动选帧的灰度标准差（`MIN_REFERENCE_STRUCTURE=12`）跳过，可用性只由对齐后的 `correlation_after ≥ 0.15` 判定。 | 提示词与 mask 对不上时，模型看到的白带是 1366 列、文字却说 683 列，把外侧 683 列真实内容误标成可重绘区，可能产生风格断层；而拼接只看 manifest，几何结果不会错，所以只影响观感与稳定性。未对齐相关对几像素平移极其敏感：实测拼接后的氛围图有 −9 px 位移，同一对图的未对齐相关从 0.55 掉到 −0.013，前置闸门直接拒掉了可用素材。去掉后判据回到决策 48 的「对齐后重合度」一条，黑场仍然被排除（GТ 侧灰度标准差、以及对齐后相关必然为 0）。 | 2026-10-30 用户在闭环验收中发现提示词列号与 mask 不符，要求先修 CLI 再提交生成。验收见 `docs/test-runs/20261030-relight-space-e2e.md`。 |
| 63 | case 列表的流程筛选与 case 删除 | 筛选下拉的选项由 `frontend/src/constants/flow.ts` 的 `flowMeta` 生成（派生 `flowOptions`），与表格 tag 同源，新增流程不再单独维护选项。新增 `DELETE /api/case/{name}`：删 `cases/<name>/` 与 `generate.workdir/<name>/`（默认 `vrgen_runs/<name>/`），`sources/`、`logs/` 与共享上传池不动；不可恢复，前端用普通确认弹窗。拒绝条件两条：case 被其他用户持有且锁心跳有效（409，报占用者昵称）；该 case 有运行中或排队任务（409）。`case_mod.delete` 先直接 `rmtree`，Windows 句柄占用时改名进 `cases/.trash/` 再删，仍失败则报出残留路径 | 筛选选项与 tag 各维护一份，是「新增了 relight case 却选不到」的直接原因；改为同源后漏改会被 `Flow` 联合类型挡住。删除范围带上 vrgen 台账，避免同名重建时读到旧轮次；`sources/` 是共享池，跟着删会误伤其他 case。占用与任务检查放在删除前，避免删到一半留下半状态 | 2026-11-02 用户确认；实现见 `vrstudio/src/vrstudio/case.py::delete`、`web/app.py::_delete_case` 与 `frontend/src/views/CaseListView.vue` |
| 64 | 重打光去掉同位检查并缓存参考帧与相似变换 | 视频重打光只支持固定机位：删除整片同位检查及 `frame_hold`/`MIN_FRAME_HOLD`，报告去掉 `frames_checked`/`min_hold`；扫描时保留最佳参考帧的原分辨率图，光照场不再为取参考帧二次解码；显式 `--ref-frame` 改为按帧号 seek，小样也接受该参数。`--case` 模式在 `cases/<case>/derived/relight/fixed.json` 缓存解析后的参考帧号与全精度 `AlignResult`，键为 GT/氛围图身份（case 素材 sha256，缺失时 size + mtime_ns）、请求的 `ref_frame`（auto 或整数）与缓存版本；命中时跳过 91 帧扫描与 SIFT，只按参考帧 seek 一帧重算光照场；氛围图一换即 miss 并重新选帧。缓存损坏或写入失败静默重算，不新增 CLI 开关；报告的计时与时间戳见决策 65。 | 378 帧 8K 素材的小样实测 128.1 秒，约 100 秒花在“扫描 91 帧 + 顺序解到第 80 帧”这 172 次解码；`docs/test-runs/20261030-relight-space-e2e.md` 也记录了整段多遍读片（约 87 GB）。重打光素材都是固定机位，同位检查只警告不阻断，却要额外读一遍全片；参考帧与相似变换在输入不变时是纯函数，缓存后热跑只做一帧解码与光照场。 | 2026-11-02 用户确认：优先消除重复解码；氛围图变化时重新选参考帧；只缓存变换，不缓存光照场。方案见 `docs/plan/relight-decode-cache-plan.md`。 |
| 65 | 重打光报告增加运行时间与分段计时 | 视频重打光的小样与整段报告新增 `kind`（sample/full）、`started_at`/`finished_at`（本地时区 ISO 8601）、`cache`（enabled/hit/load）与 `timing`：准备阶段 `cache_load`/`scan`/`read`/`align`/`fields`；小样 `sample_decode`/`sample_compose`/`sample_write`；整段 `render_decode`/`render_compose`/`render_write`/`render_flush`/`render_total`；`total` 与 `seconds` 相同。产物文件名的时间戳取自同一个 `started_at`。`/api/case` 的 relight 负载新增 `sample_report`，前端在“上次运行”标题与小样标题上直接显示运行时间，分段耗时作为次要信息；老报告没有时间戳时回退到产物文件 mtime。 | 用户看不到“上次运行”到底是什么时候发生的；报告只有总 `seconds`，无法确认选帧、匹配、光照场、出帧各占多少。整段渲染里 `render_write` 是写 ffmpeg 管道的耗时，编码在 ffmpeg 进程里并行进行，收尾等待记在 `render_flush`。 | 2026-11-02 用户确认以时间戳为前端重点，分段计时为次要信息。方案见 `docs/plan/relight-decode-cache-plan.md`。 |
| 66 | fullRedrawImg 的拼接输入可指向素材库 | case.toml 新增可选段 `[merge] input = "<素材 id>"`：不写时仍用 `extracts/<current>/result.png`（adopt 落点）；写了就只认本 case 里 `kind = image` 的素材，load 时校验素材存在与种类，删除被指向的素材时清空指针并回退到采用结果。`vrstudio merge --case` 不新增参数，fullRedrawImg 分支先解析 `[merge] input`，没有才读 `result.png`。拼接前按 manifest 的 `canvas.size` 校验输入宽高比，不符时以退出码 2 报「拼接输入必须是 21:9 画布图」，不再让 `restore_canvas` 把 2:1 源图拉伸后靠冗余带相关性兜底。report.json 增记输入的素材 id 与 sha256。Web 的 `merge.ready` 改为「extract 完成且（指针可解析或采用结果存在）」，`step_files.merge.inputs` 显示实际输入，MergeStep 增加「从素材库选择 / 用回生成结果」。只放开 fullRedrawImg；patchimg 的贴回仍只接受 adopt 结果 | 外部工具改完的 21:9 稿回传后，目前必须先 `generate adopt` 才能拼接，而 adopt 的语义是「采用这一轮生成的候选」：把外部文件塞进去要么伪造 round/index，要么覆盖 `result.png`，`[adopt]` 与页面上的「已采用第 N 张」都会变成假话。美术的加工循环本来就是导出→外部改→上传（决策 61），拼接输入是独立问题，不该借道 adopt。指针与 relight 的槽位同构，是这套 case 模型里已验证过的写法；选择落盘后，刷新、CLI 复跑与他人接手看到的输入一致，report 也能追溯 | 2026-11-02 用户确认只开放拼接操作的素材来源，并要求先同步文档再开发；本轮不放开 patchimg。 |
| 67 | 拼接输入一键上传入库 | 角色词表新增 `merge_input`（label「拼接输入」，`kinds = ["image"]`，`modes = []`，`open = false`，`reserved = false`）。merge 页提供「上传并用作拼接输入」：走现有分片上传，再由 `POST /api/case/{name}/assets` 的 `op: "merge-input"` 一次完成入库与设置指针；同一 sha256 的图片已在本 case 时直接指向已有素材，不重复拷贝。指针仍可指向任意图片素材，素材库的「从素材库选择」保持不变。`modes: []` 使这一角色不出现在任何生成下拉，避免被当成参考图提交；上传入口只收 png/jpg/webp。按既有角色流程同步 `docs/roles.json` 与两个仓库的副本、更新两处 `CONTRACT_SHA256` | 用户指出「先去素材库上传、再回拼接页选择」反直觉，一次点击应同时完成「入库 + 选作拼接目标」。素材库仍是 case 文件的唯一副本（可复用、可去重、有 sha256），所以不能绕开它另建目录；而 `[[assets]]` 必须带角色，复用 `lighting_ref` 等生成角色会把拼接输入误标成参考图，并可能被勾进提交。用 `open = false` + `modes = []` 钉住它只用于拼接 | 2026-11-02 用户要求用一个按钮同时解决上传与选择；上传入库后素材库可见，指针与拼接门控沿用决策 66。 |
| 68 | 拼接报告的非有限数值写 null | `vrstudio.jsonio.json_safe` 在落盘与下发前把 `NaN`/`Infinity` 递归换成 `null`：merge 的两条图片报告写出时使用它并加 `allow_nan=False`；`_image_report` 读取旧报告时也清理一遍，老文件不必重跑 merge。`registration.quality` 是「次优比最优」的比值，逐位相同时为 `inf`，报告里改为 `null`，前端按「无该指标」处理（类型改为 `number \| null`）。 | 浏览器实测用 `padded.png` 做恒等拼接后，报告里出现 `"quality": Infinity`；Python 的 `json.dumps` 默认允许它，`json.loads` 也能读回，但 Starlette 的 `JSONResponse` 用 `allow_nan=False`，整个 `GET /api/case/<name>` 抛 `ValueError` 变成 500，页面刷新失败、任务完成后的自动刷新也拿不到新成片。只改前端无法兜住，必须在写出与读入两处清理。 | 2026-11-02 用户在验收拼接输入时发现；回归测试见 `tests/test_jsonio.py` 与 `tests/test_fullredraw_img.py::test_merge_returns_the_source_bit_exactly`。 |
| 69 | 冗余带相关性闸门默认降到 0.60 | `recompose.min_band_correlation` 的出厂默认从 0.80 改为 0.60：改 `config/default.toml` 与 `config.py` 的 builtin 默认，以及 `merge` / `recompose` / `calib` 三处取值回退与 `stitch_image` / `gate_registration` 的函数默认值，不留下任何仍按 0.80 判定的路径。其余判据不变：`quality < 1.15` 仍判 warn，切片后的 `verdict` 仍由接缝指标（wrap 分位、interior 差异）决定。0.80 的论证与那组失败实验（0.777 / 0.642 / 0.841 / 0.574，0.841 过闸仍有重影）保留在 `docs/plan/360-img-ab-routes-plan.md` §3.3，不删除、不改写。回退方式：把上述默认值改回 0.80，或在本机 `vrstudio/vrstudio.toml` 写 `[recompose] min_band_correlation = 0.80` 只恢复本机行为。 | 用户要求放宽到 0.60，让 AIGC 重绘后两端冗余带发生轻微分岔的候选（实测 `i1` 0.731、`i5` 0.784）仍能出片。实测这两张在 0.70/0.60 下都能 stitch，`verdict = ok`，接缝指标 wrap 0.35、分位 26.5 / 13.4。代价必须写清楚：闸门从此只证明“两条带足够像”，不再证明“是同一段内容”；高对比区域可能出现两份重绘叠加的重影（0.841 的历史案例已出现过），需要人工看片。 | 2026-11-02 用户明确要求改为 0.6，并要求独立提交与文档记录以便回退。 |


## 重打光（第 48 条的展开）

**定位。** `relight` 解决的是一个已确认的物理约束：AI 图生模型的上传与输出都卡在 4K，8K 交付的细节不能来自模型。真 8K GT 提供结构与细节，AI 重绘结果只提供低频光照、色温与遮挡关系；输出每个像素都落在 GT 的原始网格上，所以不存在「把 4K 重绘的细节贴回 8K」这类拼接问题，也不需要对重绘的高频做任何处理。

它明确不负责两件事：超分（4K→8K 的细节是编的），内容回填（氛围图里新增的窗格、天空、发光体传不过来，需要单独立项）。

**乘算模型（单一 v2 引擎，在线性光下计算）。**

```text
Lg = guided(guide=Y(GT_lin), src=GT_lin, r=12@2K, eps=300)
La = guided(guide=Y(GT_lin), src=AI_lin,  r=12@2K, eps=300)
gY = Y(La) / Y(Lg)
W  = vonKries(LMS(La), LMS(Lg))，归一化为保亮度
V  = clamp(Y(AI_lin) / Y(La), 0, 2)
Ws = (1 - strength) × I + strength × W
out_lin = GT_lin × Ws × gY^strength × V^(local_shading × strength)
```

三项各承担一类失败，删任何一项都会退回已实测的问题：

- `gY` 必须用 GT 亮度引导的联合引导滤波，不能用高斯低频。夜戏 AI 原图人脸是 10–14，但脸旁烛光在 σ=48 的低频里约 40，比值看不到遮挡，v1 把人脸点亮到 29.2–54.9；引导滤波让光照不跨 GT 的遮挡边界，v2 降到 12.0–25.5（GT 34.7）。
- `V` 让模型画出的阴影能压暗 GT，是脸不再被整体提亮的主要原因；`local-shading=0` 时退化为纯低频打光。
- `W` 只做全局白点、不做逐通道比值：逐通道比值在日光下把 GT 木材的高饱和红一起放大成偏色。

低频在 2K 上算完再放大到原尺寸，8K 单张约 4–5 秒。

**几何权威点。** 对齐 = 2K 灰度 + SIFT（最近邻比值 0.75）+ `estimateAffinePartial2D` RANSAC（重投影阈值 3 px）估计相似变换；匹配数或内点不足 12 时退回相位相关只求平移，并在报告里标 `fallback`；平移量按原尺寸/2K 的比例放大，缩放与旋转按相似变换定义不变；最后用 `BORDER_WRAP` 的 `warpAffine` 把氛围图变换到 GT 坐标。以上全部只住 `src/vrstudio/relight/align.py`，是该相似变换的唯一权威点，`redraw/` 与 `patch/projection` 都不再实现第二套。

旋转保留、不钳制：实测 −0.14° 到 −0.33°，钳到 0 反而离真实变换更远。

**参数与默认值。**

| 参数 | 默认 | 语义 |
|---|---|---|
| `--gt` / `--atmo` / `--out` | 必填 | GT 图、氛围图、输出 PNG |
| `--strength` | 1.0 | 整体施加量，同时作用于增益、白点与可见度；0 时输出与 GT 逐位一致 |
| `--local-shading` | 0.35 | 可见度项权重；0 只用低频光场，1 完全跟随 AI 的局部明暗 |
| `--highlight-clip` | 关闭 | 高光软裁切 |
| `--clip-knee` / `--clip-max` | 0.72 / 0.98 | 软裁切的拐点与上限 |
| `--dump-light` | 关闭 | 额外输出 light / gain / visibility / 六联四份诊断图 |
| `--report` | 无 | 写 JSON 报告 |

场景预设只给默认值，显式传参优先：`--scene night` = 1.0/0.35，`--scene day` = 0.8/0.2。日光把 strength 降到 0.8 是因为 1.0 时过曝 8.9%、0.7 时 0.8%，而 `local-shading` 在 0.2–0.5 之间对人脸和过曝的影响都很小。

**输入限制与退出码。**

- 0：成功。
- 2：参数错——比例不是 2:1、两张图尺寸不一致、strength 或 local-shading 越界、输出路径缺失、输入不是 8-bit 单通道/三通道的普通位图。
- 1：运行失败——读图失败、对齐不可信、写出失败。

对齐不可信判据只有一条：把氛围图按拟合出的变换 warp 到 GT 坐标后，两张图在 2–6 像素尺度上的结构重合度低于 0.15 就判错位。这个重合度是这么算的：两张图先各做一次 2 像素与 6 像素的高斯模糊并相减，得到只保留粗结构的带通图像（整体明暗和细纹理都被去掉），再算归一化相关，0 表示两张图在这些尺度上完全无关，1 表示完全重合。实测对齐后夜戏 4 张为 0.376–0.437、日光 2 张为 0.439/0.371，对齐前约 0（cand1 是 −0.00，cand3 是 −0.02），0.15 夹在中间，两侧都有大余量。

只看这一条、不看内点数，理由是内点数只说明「有多少对特征被这个变换解释了」，不说明变换对不对：360 室内到处是重复的窗格与梁柱花纹，SIFT 完全可能配上相邻两根柱子、拿到十几个内点而几何错位一个窗格，这种情形下结构重合度是唯一能拆穿的证据（cand3 不对齐时 8K 重合度是 −0.0155，正是错位的样子）。代价是模型把画面改得很厉害、但几何其实对的候选也会被拒；这种情形下光照落在哪里本来就无法核对，拒绝优于错贴。判据在对齐本身用的 2K 尺度上算，不在 8K 上算：8K 带通要多花数秒，且不改变判定结论（对齐后 8K 重合度 0.21–0.29，与 2K 的排序一致）。

错位的光照比不重打光更糟，所以这一项失败必须中断，不提供「忽略对齐失败」的公开开关。

**已知缺陷（本期接受，不靠改算法结构解决）。**

- 日光下输出比 AI 更红、更饱和，因为增益放大了 GT 原有的高饱和色。
- 窗格、天空这类内容变化传不过来：那是内容变化不是光照变化，v2 与球谐都补不了。
- 对齐后 8K 带通相关只有 0.21–0.29（模型重画了细节）；这只影响逐像素比对，不影响低频增益的可用性。

**未决。** 逆光素材未验证；多候选批量是逐张输出还是先排序；16-bit 输入（当前只做 8-bit sRGB）；日光饱和度是否需要「向 AI 低频色度靠拢」的约束。

**验收。** `--strength 0` 与 GT 逐位一致（maxdiff 0）；同一输入重复运行结果一致（RANSAC 种子固定）；6 张既有候选的输出与原型逐位一致（maxdiff ≤ 1）；对齐后的结构重合度不低于 0.30 且比不对齐至少高 0.10；8K 单张不超过 30 秒；尺寸/比例不一致、参数越界、对齐不可信三类失败都给出具体原因。

## 日志分层（第 39 条的展开）

当前规则与目标规则的全文写在 `docs/plan/frontend-refactor-plan.md` 第 10 节。决策要点如下。

- 事件层只写按天的 JSONL，短操作不再建文件。
- 任务原始层一任务一文件，只放子进程输出。
- 轮次日志留在轮次目录，作为审计产物，不搬进 `logs/`。
- `cases/` 与 `logs/` 根目录不再写日志。
- 旧前缀文件不迁移，Phase 5 先输出清理清单，确认后删除。
- 前端通过任务与日志接口读取，不直接读文件路径。

## 前端技术栈（第 38 条的展开）

决策 11 的前提是单人本地工具，该前提已被半年内局域网 2–5 人取代。决策 11 的原文保留，本节记录取代它的选型结论。

- 替换的范围：两个 HTML 模板、6 个 partial、10 个静态脚本里的绘制与状态部分、两份内联 CSS。
- 不替换的范围：Starlette 路由、Jinja2 页面壳、`tasks.py` 队列、`app.py` 业务、`erp360.js` 的 WebGL 投影与双路同步、`pick.js` 的拖框坐标计算、`docs/case-model.md` 的 CLI 契约。
- 前端工程：Vue 3 + TypeScript + Vite + Element Plus，独立目录 `vrstudio/frontend/`，构建产物由 Starlette 挂在 `/next`。
- 旧前端保留在 `/`，按页面迁移，功能对齐后切换默认入口；旧前端在一个版本周期后删除。
- 后端同步补齐：浏览器上传、身份与 case 归属、任务归属与只读任务列表、并发写入版本检查、扣费归属。
- 身份与并发按决策 17 的分层执行，账号密码暂缓，任务先用单队列；两者通过接口隔离，后续替换实现时页面与接口不变。
- 论证见 `docs/key-issues/20261023-frontend-stack-selection.md`，实施计划见 `docs/plan/frontend-refactor-plan.md`。

## 多用户分层设计（第 17 条的展开）

用户的复述原文与判定：

> 用户复述：机器只有一台，所以要么放弃这个方案，要么就得做需求队列。
>
> 判定：两头都对，中间漏了第三种情况——"放弃"和"全队列"不是仅有的两个选项，正确形态是按操作类型分流。"机器只有一台"成立：重计算（extract/merge/recompose/restore/RIFE 都是 ffmpeg 级别的单机满载任务）确实只有一份算力，同时跑两个会互相拖慢且内存翻倍。"要么放弃"不成立：浏览、看轮次台账、看对比图、填提示词变量这类操作不占算力，多人同时用没有冲突。"要么就得做需求队列"对重计算成立。修正日期：2026-10-16。

- **并发层（不排队）**：页面浏览、台账/状态轮询、对比图播放、prompt-vars 填写——多人同时用，直接并发响应。
- **串行层（任务队列）**：extract、merge、recompose、restore、vrgen submit——全部进 web 骨架自带的 `tasks.py` 单 worker 队列（旧 vrpatch 已有，迁入继承而非新造），前端显示排队位置与进度；mglc 提交受配额限制且一次渲染约五分钟，天然走同一队列，vrgen 台账的断点续跑保证排队中途重提不重复扣额度。
- **互斥层（case 锁）**：排队解决算力争用，不解决数据争用——两个人同时在同一个 case 的 pick 页拖框、或一个在 pick 一个在 merge，case.toml 会互相覆盖；进入向导编辑（pick 草稿、触发任务）前先拿这个 case 的占用标记，拿不到则整体只读并提示占用者昵称。
- **身份**：免登录，自报昵称仅用于显示任务归属与占用者，不做账号体系。账号与密码暂缓，昵称通过 `IdentityProvider` 隔离，当前实现为 `NicknameProvider`，将来换账号体系时只替换实现。
- **队列扩展**：当前是单 worker 的 `SingleChannelQueue`；任务记录带 `owner`、`queue_position`、`created_at`、`started_at`、`finished_at`。将来换多 worker 或按人公平调度时替换 `TaskQueue` 实现，任务中心读取的字段不变。
- **占用扩展**：当前用文件锁实现 `CaseLock`；将来换数据库锁或分布式锁时只替换实现，页面与接口不变。
- **技术栈影响**：前端界面层由决策 38 改为 Vue 3 + TypeScript + Vite + Element Plus，旧前端并行保留；后端与 CLI 契约不变。`serve` 加 `--host 0.0.0.0` 即可开放。

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
