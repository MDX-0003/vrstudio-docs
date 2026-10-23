# 总架构：vrgen（生成服务）+ vrstudio（流程仓库）

权威版本。旧设计稿（E:\360AIGC\vrpad\docs\knowledge\two-repo-architecture.md）已被本文取代。

## 1. 职责切分与数据流总图

```
            ┌───────────────── vrgen（生成服务，独立仓库）─────────────────┐
            │ CLI: login/models/submit/status/register/result/peek          │
            │      prompt/params（提示词草稿与生成参数草稿，JSON 输出）        │
            │ 台账: runs/<job>/<轮次key>/  run.json 五件套（断点续跑/防重发）  │
            │ 双后端: mglc(Seedance) 子进程 ─┐                              │
            │         手动注册本地文件 ───────┴─ 同构台账                     │
            │ 迁自: vrpad aigc/{platform,prep,round} 原样                    │
            └──────▲─────────────────────────────────────▲────┘
                   │ CLI 子进程（argv+退出码+台账）           │
            ┌──────┴─────────────────────────────────────┴────┐
            │            vrstudio · Web 控制台（总入口）                   │
            │        新建 case → 选 flow → 编排 → 采用 → 出片 → 对比图        │
            └──────┬─────────────────────────────────────┬────┘
                   │ flow = patch（局部重绘）             │ flow = fullredraw（全景重绘）
   pick(视口/inner 草稿→case.toml)                    pad(循环冗余画布 21:9 + mask
        │                                            + _pad.json 契约)
   extract(冻结 clip.json + clip.mp4 + clip_mask.png     │
     + 首尾原始帧)  ──候选清单──▶ vrgen              pad 画布 ──候选清单──▶ vrgen
        │                                                │
   adopt(结果拷入 case, 记轮次 key)                   adopt(同左)
        │                                                │
   restore/rife + scalefit 对齐                      recompose(整数配准+smoothstep
        │                                            混合+还源宽+闸门)
   merge(多频带融合, footprint 外逐位不变)                 │
        │                                                │
      out/ 成片                                       out/ 成片

   gen（多素材生成）：assets/ 素材清单 ──refs.json──▶ vrgen → adopt → case/result.mp4
                    （素材并入生成页侧边栏；没有 pad/extract/recompose/merge 等前后步骤）

   共享底座(vrstudio): media/(ffmpeg 发现+probe+统一帧泵, 单一 H.264 420 delivery 档)
     · 分层 config · progress 日志
   契约原样冻结: clip.json(单段) · _pad.json · index_map 唯一时间重采样 · 像素基线测试
```

**正交性**：三条流程互斥（一个 case 只选一条）。三流程给 vrgen 的都是同一份提交
清单：用户勾选的素材 + patch 的 clip / fullredraw 的 pad + 装配器自动附带的 mask
（编辑区域控制图，不参与编号）；gen 的清单就是勾选的 `[[assets]]`。三者归一到同一
份 `InputPackage`，差异全部由 vrstudio 在"组装候选与几何"时消解；没有默认提交集，
勾选才提交。

## 2. vrgen 模块树（目标态）

```
vrgen/
  src/vrgen/
    cli.py                 # 单入口多子命令（契约见 docs/case-model.md）
    platform/              # ← vrpad aigc/platform 原样：binpath(mglc发现) client media models
    prep/                  # ← vrpad aigc/prep 原样：budget prompt scale
                           #   params.py ★新增：生成参数（输出档位/输入缩放）草稿
    round/                 # ← vrpad aigc/round 原样：assets gate ledger pipeline task
    manual.py              # ★新增：手动注册后端（本地文件 → 同格式台账）
    sessions.py            # ★新增：项目/剧集/生成会话树（只读，web 会话选择器用）
    jobs.py                # ★重写：job(=case名) 分组与 prompt-vars / generation.toml 草稿
                           #   （提示词可变块+模板选择，替代 vrpad 的 brief 术语；
                           #    并替代 aigc/case.py 的"自己找 *_pad.json"逻辑，改显式入参）
  config/default.toml      # 平台参数：模型/模式/分辨率档/超时/登录态路径
  templates/               # 提示词模板：360闭环（vrpad 迁入）、人物重绘（新增）
  runs/                    # 台账树（服务自有数据，gitignore）
```

## 3. vrstudio 模块树（目标态）

```
vrstudio/
  src/vrstudio/
    cli/
      case.py              # ★新增：new/list/show（薄封装，写 case.toml）
      generate.py          # ★新增：组装输入包 → subprocess 调 vrgen → adopt 落 case
      extract.py           # ← vrpatch cli/extract 原样
      merge.py             # ← vrpatch cli/merge 原样
      restore.py           # ← vrpatch cli/restore 原样
      pad.py               # ← vrpad cli/pad 原样
      recompose.py         # ← vrpad cli/recompose 原样
      calib.py / verify.py / seam_center.py / plan.py   # ← vrpad 辅助命令原样
    patch/                 # ← vrpatch 核心库原样（局部重绘域）
      projection.py        #    ERP↔rectilinear 唯一权威
      extract.py  composite.py  sidecar.py  case.py
      framealign.py        #    时间重采样唯一权威（index_map）
      restore.py  scalefit.py  rife.py  detect.py  blend.py
    redraw/                # ← vrpad 核心库原样（全景重绘域，目录改名避开 blend 撞名）
      geometry.py  padding.py  blend.py  manifest.py  mask.py
      registration.py  recompose_core.py  verify_core.py  framefit.py
    media/                 # ★合并：vrpad videoio/binres + vrpatch media.py
      ffmpeg.py            #    发现（bin/ > PATH）+ probe
      videoio.py           #    统一帧泵（bgr24 流式；输出恒为 H.264 8-bit yuv420p）
    case.py               # ★新增：case.toml 读写/校验的唯一权威（CLI / generate / web 三方共用）
    config.py              # ← vrpad 分层 toml（default + 本机覆盖 + --set）
    progress.py            # 日志/RateMeter（两边合并为一份）
    web/                   # ← vrpatch web 骨架扩展：app tasks render templates static
  cases/  sources/  logs/  bin/    config/default.toml
```

### Web 控制台页面流

```
case 列表（flow 徽标）
  ├─ patch case:  pick(全景点击定视口/拖框定 inner/逐帧浏览) → extract → generate
  │               (vrgen 任务队列+日志 tail+轮次列表) → adopt → merge(进度) → 对比图
  ├─ fullredraw:  pad(几何预览) → generate(输出/输入分辨率下拉) → adopt → recompose(进度+闸门) → 对比图
  └─ gen:         素材(多选/角色/排序/删除/缩略图) → generate(模式/比例/分辨率/
                  提示词/Session/免额度检查) → adopt
                  （没有对比页；patch/fullredraw 的单视频入口保持不变）
```

vrpatch 的 ai-clip 注册端点改为调 `vrgen register`；extract/merge 仍 subprocess 跑 CLI。

前端界面层正在按决策 38 重建：旧前端保留在 `/`，新前端使用 Vue 3 + TypeScript + Vite + Element Plus，构建产物挂在 `/next`，按页面迁移后切换默认入口。需求与论证见 `docs/key-issues/20261023-frontend-stack-selection.md`，实施计划见 `docs/plan/frontend-refactor-plan.md`。后端接口、CLI 契约以及 `erp360.js` 与 `pick.js` 的数学逻辑不随界面层重写。

## 4. 拷贝映射表（旧 → 新）

| 旧 | → 新 | 动作 |
|---|---|---|
| vrpad `aigc/platform/` `aigc/prep/` `aigc/round/` | vrgen | 原样 |
| vrpad `aigc/case.py`（自动找 `*_pad.json`） | — | 不拷；输入包改显式入参（vrgen `jobs.py` 重写） |
| vrpad `aigc/cli` 单入口 + config `[aigc]` 段 + 提示词模板 | vrgen | 迁入并去 vrpad 化 |
| vrpad pad/recompose 命令 + geometry/padding/blend/manifest/mask/registration/recompose_core/verify_core/framefit | vrstudio `cli/` + `redraw/` | 原样（连同各自契约测试） |
| vrpad videoio/binres、vrpatch media.py | vrstudio `media/` | 合并为多 profile 单模块，回归测试随迁守护 |
| vrpad config.py 分层 toml、progress.py | vrstudio | 合并（两边实现近似） |
| vrpatch 全部核心库 + web/ + cli/extract,merge,restore | vrstudio `patch/` + `web/` + `cli/` | 原样（契约/守卫/基线不动） |
| vrpatch `ai_clip.json` 注册路径 | vrgen `manual.py` | 语义升级为台账记录 |
| 两边知识文档（geometry-contract、projection-contract、aigc-handoff-prompt 等） | 各自所属仓库 docs/ | 随迁 |

## 5. 实施现状

- **M0 脚手架**（完成）：两仓库 git init（main）、uv 工程（3.11 + src layout）、pytest + ruff、GitHub Actions CI（windows/ubuntu 矩阵）。
- **M2 契约搬运**（完成，vrstudio e2032f1）：`redraw/` ← vrpad、`patch/` ← vrpatch、`media/` 合并、CLI 装配（迁入命令 9 个 + 新增 case/generate + serve stub），随迁测试 170 绿。
- **M3 generate 接线**（完成，vrgen c07b327 + vrstudio 4d1452c）：vrgen manual 后端全链路（register/status/result，17 测试）；vrstudio 统一 case 模型 + generate 三命令；合成 e2e + ship_01 真实复现（指标与 vrpad 历史逐位一致），共 186 测试绿。
- **M1 平台链路**（代码完成，vrgen a35ee41）：mglc 登录/模型清单/提交/轮询/下载/零额度查询全部接入真实调用，断点续跑与防重发有回归测试；受配额限制，真实素材的一轮完整提交尚未验收。
- **M4 web 控制台**（基本完成）：patch 流程已浏览器验收；fullredraw 向导页、提示词面板（决策 18）、360° 对比页与统一播放控制、单一 420 编码档（决策 19）、输出/输入分辨率下拉与生成参数草稿（决策 20）均已落地。剩余 fullredraw 真素材验收，与 M1 的真实提交一并做。
- **gen 简单生成流程**（完成，决策 21/22）：最初的单源视频版本把源视频直接作为输入包（canvas=source=源实际像素），模板 `gen-edit`，`adopt` 落 `case/result.mp4`；项目额度通过 `generation.toml` 的 `session_id` 传给 mglc。
- **gen 多素材**（完成，决策 24/25）：case 改为有序 `[[assets]]`（视频/图片 + 角色 + 哈希），新建时选模式且不再要求源视频；旧 gen case 读取时自动迁移。向导拆成 `素材 → 生成` 两步，素材复制进 `cases/<name>/assets/`。vrgen 新增 `submit --refs`：角色矩阵与限额校验、每段视频独立缩放、台账按 `video:v1`/`image:i1` 分组；提示词模板换成 `gen-multi`，素材清单与模式语义由 `asset_list`/`task_rule`/`timeline_rule` 自动生成。生成页提供免额度 `--check`（真正执行 `vrgen submit --dry-run`）。真实 allMediaRef 提交待额度。
- **首尾帧管线**（2026-10-20 批准，WP1–WP4 代码已实现，真实提交待额度，决策 26）：`[[assets]]` 从 gen 专用扩展为三条流程通用；gen 与 patch 生成页增加素材侧边栏，patch 另有关键帧工作台与 firstLastFrame 模式；首期全链路固定 16:9。vrgen 侧已新增 firstLastFrame 模式、`image submit` 与任务种类注册表。设计与计划见 `docs/first-last-frame-pipeline.md`、`docs/firstlast-dev-plan.md`。
- **当前测试规模**（2026-10-19 核对）：vrgen 95 个 + vrstudio 258 个（含 web 44 个），合计 353 个全绿；两仓库 `uv run ruff check .` 干净。
- **待办**：M1/M4 的真实素材验收（需 mglc 配额）、决策 17 的多用户分层（已登记未实现）、统一提交改造（决策 33：勾选即提交、clip/pad 为候选、mask 自动附带、raw 帧仅工作台、extract 产出首尾原始帧）、patch 时间拼接 WP1–WP4（决策 30–32）、M5（README 交接规范 + 旧仓库归档）。
- 无 CD：本地工具无部署物；CI 的 test job 即提交门禁。
