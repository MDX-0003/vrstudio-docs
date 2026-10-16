# 总架构：vrgen（生成服务）+ vrstudio（流程仓库）

权威版本。旧设计稿（E:\360AIGC\vrpad\docs\knowledge\two-repo-architecture.md）已被本文取代。

## 1. 职责切分与数据流总图

```
            ┌───────────────── vrgen（生成服务，独立仓库）─────────────────┐
            │ CLI: login/models/submit/status/register/result/peek          │
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
   extract(冻结 clip.json + clip.mp4                     │
     + clip_mask.png)  ──输入包──▶ vrgen            pad 画布 ──输入包──▶ vrgen
        │                                                │
   adopt(结果拷入 case, 记轮次 key)                   adopt(同左)
        │                                                │
   restore/rife + scalefit 对齐                      recompose(整数配准+smoothstep
        │                                            混合+还源宽+闸门)
   merge(多频带融合, footprint 外逐位不变)                 │
        │                                                │
      out/ 成片                                       out/ 成片

   共享底座(vrstudio): media/(ffmpeg 发现+probe+统一帧泵, 三档编码 profile)
     · 分层 config · progress 日志
   契约原样冻结: clip.json(单段) · _pad.json · index_map 唯一时间重采样 · 像素基线测试
```

**正交性**：两条流程互斥（一个 case 二选一），vrgen 对两边看到的是同一种东西——
一段视频 + 一张 mask + 一份提示词 + 分辨率档。差异全部由 vrstudio 在"组装输入包"时消解。

## 2. vrgen 模块树（目标态）

```
vrgen/
  src/vrgen/
    cli.py                 # 单入口多子命令（契约见 docs/case-model.md）
    platform/              # ← vrpad aigc/platform 原样：binpath(mglc发现) client media models
    prep/                  # ← vrpad aigc/prep 原样：budget prompt scale
    round/                 # ← vrpad aigc/round 原样：assets gate ledger pipeline task
    manual.py              # ★新增：手动注册后端（本地文件 → 同格式台账）
    jobs.py                # ★重写：job(=case名) 分组与 prompt-vars 草稿
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
      writer.py            #    统一帧泵 + 显式编码 profile（lossless444 / ai14 / delivery）
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
  └─ fullredraw:  pad(几何预览) → generate → adopt → recompose(进度+闸门) → 对比图
```

vrpatch 的 ai-clip 注册端点改为调 `vrgen register`；extract/merge 仍 subprocess 跑 CLI。

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

## 5. 脚手架现状（M0，本次交付）

- 两仓库已 `git init`（main 分支）、uv 工程（Python 3.11，src layout）、pytest + ruff、
  GitHub Actions CI（test + lint，windows/ubuntu 矩阵）。
- CLI 骨架已按契约声明全部子命令（stub，退出码 2 + 指向 `docs/case-model.md`），
  冒烟测试断言命令面完整。
- 无 CD：本地工具无部署物；CI 的 test job 即提交门禁。
