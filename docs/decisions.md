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
