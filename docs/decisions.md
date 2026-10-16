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
| D6 | ffmpeg 封装合并为多 profile 单模块（lossless444 / ai14 / delivery），旧回归测试随迁守护 | 待确认 |
| D7 | CI 仅 test + lint；无 CD（本地工具，无部署物） | 已按此搭建脚手架 |

## 命名说明

- `AGENT.md` 请求已按业界标准名落地为 `AGENTS.md`（工具识别的标准文件名）。
- 正式产品名如需更改，改目录名 + pyproject `name` + 文档即可，脚手架不锁死命名。
