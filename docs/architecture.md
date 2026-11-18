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

   patchimg（360 图片局部重绘）：extract 视口 clip.png + clip_mask.png + image.json
                    ──▶ vrgen image submit ──▶ adopt --index ──▶ merge（只写 inner）
   fullRedrawImg（360 图片全幅重绘）：extract padded.png + padded_mask.png + image_pad.json
                    ──▶ vrgen image submit ──▶ adopt --index ──▶ merge（stitch 还原 2:1）

   relight（重打光）：assets/ 的 GT + 氛围图 ──▶ vrstudio relight（不调 vrgen、不花额度）
                    ──▶ out/ 成片（视频整段或单帧）+ 报告 JSON

   共享底座(vrstudio): media/(ffmpeg 发现+probe+16-bit 统一帧泵, 单一 HEVC Main10 10-bit delivery 档)
     · 分层 config · progress 日志
   契约原样冻结: clip.json(单段) · _pad.json · index_map 唯一时间重采样 · 像素基线测试
```

**正交性**：六条流程互斥（一个 case 只选一条）。前五条流程给 vrgen 的都是同一份提交
清单：用户勾选的素材 + patch 的 clip / fullredraw 的 pad / 两条图片流程自动附带的
基图与 mask + 装配器附带的 mask（编辑区域控制图，不参与编号）；gen 的清单就是勾选
的 `[[assets]]`。补丁类流程归一到同一份 `InputPackage`，差异全部由 vrstudio 在"组装
候选与几何"时消解；没有默认提交集，勾选才提交。`relight` 是唯一不产提交清单的一条：
它只把 GT 与氛围图交给本地重打光引擎，不调用 vrgen。

`flow = patchimg`（360 图片局部重绘）与 patch 同构：extract 裁出 16:9 透视视口
`clip.png` + `clip_mask.png` + `image.json`，图片模型（`vrgen image submit`）只重绘
视口，merge 用 `patch/projection` 与 `patch/composite` 的 `SegmentMaps` 贴回并只写
inner；没有 pad/recompose。

`flow = fullRedrawImg`（360 图片全幅重绘）走整幅 pad/stitch：extract 把 2:1 源图 pad
成 21:9 冗余画布（`padded.png` + `padded_mask.png` + `image_pad.json`），图片模型一次
重绘整幅并带 X 张 `lighting_ref`，merge 用 `stitch_image` 还原 2:1，接缝闸门拒绝重构
图候选。两条图片路线的根本差别是 4K 预算摊在多宽的画布上（视口约 2.2× 过采样、全幅
约 0.47×），评测见 `docs/plan/360-img-ab-routes-plan.md`。

8K 图片还有一条待定路线：分段局部链式（多个 `patchimg` case 沿 360 分段、上一段输出
作下一段源图），需要 case 子文件夹分组，尚未开始开发（ab-routes WP1/WP2）。两条图片
流程的前端接入计划见 `docs/plan/img-flows-frontend-plan.md`。

`flow = relight`（重打光）把一张 AI 氛围图的光照搬到真 GT 上：GT 提供结构与细节，
氛围图只提供低频光照、色温与遮挡，输出每个像素落在 GT 的原始网格上。建 case 不绑源
文件，GT 与氛围图由用户在素材步用两个固定槽位选定（`relight_gt` / `relight_atmo`）；
GT 是视频时整段逐帧复用同一份对齐与光照场，是图片时走单帧。它不调用 vrgen、不花额度、
不需要项目会话，因此没有提交集、adopt 与会话门。前端接入计划见
`docs/plan/relight-frontend-plan.md`。

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
      relight.py           # ★新增：两张图进一张图出（GT + 氛围图 → 重打光图，决策 48）；
                           #        relight-video 同文件注册（一段 GT 视频 + 一张氛围图，决策 56）
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
      videoio.py           #    统一帧泵（bgr48le 流式；输出恒为 HEVC Main10 yuv420p10le）
    relight/               # ★新增：重打光（GT 持结构，AI 氛围图只提供低频光照，决策 48）
      align.py             #    相似变换唯一权威（SIFT+RANSAC、相位相关回退、水平 wrap warp）
      fields.py  compose.py  report.py   # 引导滤波/亮度增益/可见度/白点、合成与软裁切、报告
      #                     relight-video 在进帧前对齐、估一次光照场，整段复用（决策 56）
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
  ├─ 图片两条链:  patchimg  pick → extract → generate(图片档) → merge(贴回) → 对比图
  │               fullRedrawImg  extract → generate(图片档) → merge(拼接) → 对比图
  ├─ relight:     素材(GT + 氛围图两个固定槽位) → 重打光(参数 + 视频小样/整段) → 对比图
  └─ gen:         素材(多选/角色/排序/删除/缩略图) → generate(模式/比例/分辨率/
                  提示词/Session/免额度检查) → adopt
                  （没有对比页；patch/fullredraw 的单视频入口保持不变）
```

vrpatch 的 ai-clip 注册端点改为调 `vrgen register`；extract/merge 仍 subprocess 跑 CLI。

前端界面层正在按决策 38 重建：旧前端保留在 `/`，新前端使用 Vue 3 + TypeScript + Vite + Element Plus，构建产物挂在 `/next`，按页面迁移后切换默认入口。需求与论证见 `docs/key-issues/20261023-frontend-stack-selection.md`，实施计划见 `docs/plan/frontend-refactor-plan.md`。后端接口、CLI 契约以及 `erp360.js` 与 `pick.js` 的数学逻辑不随界面层重写。

日志分层按决策 39 执行：事件日志在 `logs/serve/`，任务原始输出在 `logs/tasks/`，`vrgen` 轮次日志留在 `vrgen_runs/<job>/<round>/` 作为审计产物；新代码不再把日志写进 `cases/`。当前规则与目标规则见 `docs/plan/frontend-refactor-plan.md` 第 10 节。

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
- **M4 web 控制台**（基本完成）：patch 流程已浏览器验收；fullredraw 向导页、提示词面板（决策 18）、360° 对比页与统一播放控制、单一 10-bit 编码档（决策 99）、输出/输入分辨率下拉与生成参数草稿（决策 20）均已落地。剩余 fullredraw 真素材验收，与 M1 的真实提交一并做。
- **gen 简单生成流程**（完成，决策 21/22）：最初的单源视频版本把源视频直接作为输入包（canvas=source=源实际像素），模板 `gen-edit`，`adopt` 落 `case/result.mp4`；项目额度通过 `generation.toml` 的 `session_id` 传给 mglc。
- **gen 多素材**（完成，决策 24/25）：case 改为有序 `[[assets]]`（视频/图片 + 角色 + 哈希），新建时选模式且不再要求源视频；旧 gen case 读取时自动迁移。向导拆成 `素材 → 生成` 两步，素材复制进 `cases/<name>/assets/`。vrgen 新增 `submit --refs`：角色矩阵与限额校验、每段视频独立缩放、台账按 `video:v1`/`image:i1` 分组；提示词模板换成 `gen-multi`，素材清单与模式语义由 `asset_list`/`task_rule`/`timeline_rule` 自动生成。生成页提供免额度 `--check`（真正执行 `vrgen submit --dry-run`）。真实 allMediaRef 提交待额度。
- **首尾帧管线**（2026-10-20 批准，WP1–WP4 代码已实现，真实提交待额度，决策 26）：`[[assets]]` 从 gen 专用扩展为三条流程通用；gen 与 patch 生成页增加素材侧边栏，patch 另有关键帧工作台与 firstLastFrame 模式；首期全链路固定 16:9。vrgen 侧已新增 firstLastFrame 模式、`image submit` 与任务种类注册表。设计与计划见 `docs/first-last-frame-pipeline.md`、`docs/firstlast-dev-plan.md`。
- **当前测试规模**（2026-10-19 核对）：vrgen 95 个 + vrstudio 258 个（含 web 44 个），合计 353 个全绿；两仓库 `uv run ruff check .` 干净。
- **待办**：M1/M4 的真实素材验收（需 mglc 配额）、决策 17 的多用户分层（已登记未实现）、统一提交改造（决策 33：勾选即提交、clip/pad 为候选、mask 自动附带、raw 帧仅工作台、extract 产出首尾原始帧）、patch 时间拼接 WP1–WP4（决策 30–32）、M5（README 交接规范 + 旧仓库归档）。
- 无 CD：本地工具无部署物；CI 的 test job 即提交门禁。

## 6. 数据位置与整仓搬迁

工作区由三个仓库并排组成，运行时数据全部落在各自仓库目录内，不进 git：

```
<父目录>/
  docs 仓库（AGENTS.md + docs/）
  vrgen/       runs/  logs/  （台账树）
  vrstudio/    cases/  sources/  vrgen_runs/  logs/  bin/
```

- **路径锚点**：`case.toml` 的 `[source] path` 相对仓库根，`[[assets]] path` 相对
  case 目录，`REPO_ROOT` 由 `vrstudio/src/vrstudio/config.py` 的文件位置推导。
  因此整仓搬到别的盘符或父目录后，代码与 case 都不需要改配置；仓库外的源文件
  （绝对路径）是例外，搬迁后要人工改回可解析的路径。
- **数据不能挪出仓库**：`sources/`、`logs/`、`bin/` 没有配置开关，路径都按
  `REPO_ROOT` 拼；只有 `cases/`（`serve --cases-dir`）与 vrgen 台账
  （`[generate] workdir`）能指到别处。把数据放到仓库外等于要求新增数据根配置键，
  与决策 101 的取舍冲突。跨设备迁移的做法是：三个仓库并排搬走，运行时数据按
  同样的相对位置还原。
- **旧数据迁移**：`vrstudio` 的 `scripts/migrate_source_paths.py` 把 `case.toml`
  里落在仓库内的绝对路径改写成仓库根相对写法；默认 dry-run，`--apply` 落盘，
  重复执行报 0 个。历史产物 JSON（`extracts/*/report.json`、`derived/*.json`）
  里的绝对路径只用于显示，不参与几何解析，不迁移。

