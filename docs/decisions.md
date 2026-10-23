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
