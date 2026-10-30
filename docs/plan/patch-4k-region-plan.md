# patch 4K 大区域重绘：fov 与分辨率、两条 4K 生成路线与全流程操作

状态：已批准（2026-10-30）。P1 代码已实现并全绿；真实额度试点（源片 0–449 帧）待执行；P2 Web 全链路待实施。
关联：决策 49；`docs/case-model.md` §2/§4；决策 26（首尾帧管线）。

## 0. 结论与范围

patch 的重绘区域要覆盖角色移动范围，单块 1080p 不够。区域大小由 fov 决定，输出分辨率只决定采样密度，两者必须一起调。

4K 生成只能走 Seedance 2.0 的 `firstLastFrame` 或 `allMediaRef`：2.0 有 4K，但没有 `videoEdit`；2.5 有 `videoEdit`，最高 1080p。dance_move 的动作只是示意，不需要结构锁定，所以这两条路线成立。

两条 4K 路线都是 4–15 秒。dance_move 是 19 秒（570 帧）；P1 试点固定取源片 0–449 帧（15.0 秒），其余 120 帧保留源片，由 assemble 拼回。4K 全片（19 秒）需要时间切分，本期不做。

本期不做四件事：多视口/分块、4K 21:9、自动 fov 推荐、把 19 秒全片切成多段 4K 生成（现有的单段 assemble 照常使用）。

契约保持不动：`clip.json`、`_pad.json`、`run.json`、`refs.json` 的字段集不变；只增加 vrgen 的 4K 输出档与 `generation.toml` 的 `model_id`（P2）。

### 0.1 实施状态（2026-10-30）

P1 代码已落地并全绿：vrgen 的 4K 档（`OUTPUT_TIERS`、16:9 标称、`output_options` 容错、提交前能力预检）、vrstudio 的 4K 视口与 `/fov` 端点/coverage 读数、`template_for` 对 allMediaRef 的修正、Pick 页 fov 滑杆与读数、Keyframe 的 4K 默认与原始帧体积显示。真实额度试点（0–449 帧、A/B 各一轮）尚未执行；P2 的 `generation.toml model_id` 与 Web 全链路未开始。

## 1. 平台事实

来自 `vrgen_runs/models.json`（2026-10-30 的缓存）与 `vrgen/src/vrgen/platform/models.py` 的实测记录。

| 模型 | 可用模式 | 最高输出 | 时长 | 输入视频上限 | 备注 |
|---|---|---|---|---|---|
| 37 Seedance 2.5 | videoEdit / allMediaRef / firstFrame / firstLastFrame / videoExtend | 1080p | videoEdit 跟随输入；其余 4–30 秒 | 8,295,044 px、210 MB | 唯一结构锁定的 videoEdit |
| 22 Seedance 2.0 | allMediaRef / firstFrame / firstLastFrame | 4K | 4–15 秒 | allMediaRef 2,086,668 px、3 个视频 | 没有 videoEdit |
| 18 Kling 3.0 | firstFrame / firstLastFrame | 4K | 3–15 秒 | — | 4K 首尾帧备选 |
| 19 Kling 3.0-Omni | firstFrame / firstLastFrame | 4K | 3–10 秒 | — | 时长更短 |

由此得到四条约束：

- 4K 16:9 的标称栅格是 3840×2160。
- allMediaRef 的输入视频上限是 2,086,668 px，4K 视口 clip 会被 vrgen 自动缩到 1920×1080 再上传；输出仍是 4K，但输入细节只有 1080p，4K 的细节由模型生成。
- firstLastFrame 只吃两张图，没有输入视频；图片步必须出 4K。
- 19 秒在任何 4K 模型上都超时长，15 秒是硬上限。

## 2. 区域、fov 与分辨率

### 2.1 三个量的分工

- fov 决定覆盖角度。赤道附近 `footprint_w = erp_w × fov / 360`，经度在 ERP 里是线性的，与投影无关。
- 视口栅格决定这段角度用多少像素采样。
- 输出档决定模型返回的栅格。视口栅格与输出档应一致（1080p 对应 1920×1080，4K 对应 3840×2160），否则贴回时会把成片放大或缩小。

只改视口尺寸不会扩大覆盖：前端现在的尺寸下拉保留 fov、按比例缩放 inner，看到的角度一点不变。

### 2.2 密度表（dance_move，8K，22.76 px/度）

| fov | footprint 宽 | 1080p 密度 | 4K 密度 |
|---|---|---|---|
| 59° | 1343 px | 1.43 | 2.86 |
| 84° | 1912 px | 1.00 | 2.01 |
| 100° | 2276 px | 0.84 | 1.69 |
| 110° | 2503 px | 0.77 | 1.53 |
| 120° | 2731 px | 0.70 | 1.41 |

密度是输出宽度除以覆盖宽度：大于 1 表示过采样，贴回时缩小；小于 1 表示贴回时放大、发软。

### 2.3 inner 比例与所需 fov

设 inner 占视口的宽度比例为 r，要覆盖 X 个 ERP 像素：

- 需要的 fov = `X × 360 / (r × erp_w)`
- 1080p 密度 = `1920 × r / X`
- 4K 密度 = `3840 × r / X`

以 r = 0.85 为例：

| 路径宽度 X | 需要的 fov | 1080p 密度 | 4K 密度 | 结论 |
|---|---|---|---|---|
| 1500 px | 78° | 1.09 | 2.18 | 1080p 够 |
| 1800 px | 93° | 0.91 | 1.81 | 1080p 勉强，4K 舒服 |
| 2000 px | 103° | 0.82 | 1.63 | 上 4K |
| 2200 px | 114° | 0.74 | 1.48 | fov 接近上限，边缘开始拉 |
| 2500 px | 129° | 0.65 | 1.31 | 单视口不合适 |

inner 比例不改变密度，只改变“在现有 fov 内重绘多少面积”。角色路径超出当前 fov 时，拉 inner 救不回来。

### 2.4 透视上限

单个透视图像的边缘角放大率约为 `1/cos²(半角)`：fov 110° 时约 3 倍，120° 时约 4 倍。单视口可用 fov 约 100–110°，8K 源、inner 85%–90% 时能覆盖的路径宽度约 1.9K–2.2K ERP px。超过这个范围，加 fov 只换来边缘拉伸，应回到多视口/分块。

## 3. 契约与数据

### 3.1 case.toml

- `[viewport]` 的 width/height 允许 3840×2160；fov 仍是草稿字段；`[inner]` 仍以视口像素表示。
- `[frames]` 在 4K 路线下必须不超过 15 秒（30fps 即 450 帧）。
- 不新增 section；`[adopt]` 不变。
- 在 `notes` 里记录 fov 与覆盖范围的依据，便于复现。

### 3.2 generation.toml（P2）

- 新增 `model_id`；`vrgen params save --model-id` 写入，`params show` 回显，`submit` 读取。
- 目的：同一个 job 在 videoEdit 1080p 与 4K 路线之间切换，不依赖全局 config。
- 切换模型后模式列表会变（22 没有 videoEdit），页面必须重新拉 `params show`，并把当前模式收敛到合法值。

### 3.3 vrgen 的 4K 档

- `OUTPUT_TIERS` 增加 `4K`；`OUTPUT_SIZES_16_9` 增加 `(3840, 2160)`；`output_options` 对表里没有的档位跳过（21:9 的 4K 没有标称值，先不提供）。
- `params show` 已按模型的 `resolutions` 过滤：22 的 firstLastFrame/allMediaRef 会显示 4K，37 不会。
- `cli.py` 两处 `resolution not in OUTPUT_TIERS` 校验随枚举自动接受。可选增加“resolution 不在该模型列表”的提前报错，让失败原因更具体。

### 3.4 不改的契约

- `clip.json`（单段、version=1）、`_pad.json`、`run.json`、`refs.json` 字段集不变。
- adopt 仍是 `vrgen result` 把结果拷进 `extracts/<版本>/result.mp4`；4K 只是文件更大。

### 3.5 模板映射（必须修）

`vrstudio/src/vrstudio/cli/generate.py` 的 `template_for` 现在把 patch + allMediaRef 映射到 `character-repaint`。那份模板写的是 videoEdit 语义：“只编辑 <视频1>”“时间轴与输入一致”，与 allMediaRef 的“按【动作段】重演”冲突。

改为：

- patch + firstLastFrame 或 allMediaRef → `gen-multi`；
- patch + videoEdit → `character-repaint`。

`gen-multi` 需要 `subject` / `target` / `plot` / `preserve` / `allowed_changes` 变量；切换模板后用 `vrgen prompt show` 看缺哪些占位符，并在草稿里补齐。

## 4. 代码改动清单

| 文件 | 改动 | 阶段 |
|---|---|---|
| `vrgen/src/vrgen/prep/params.py` | 4K 档、16:9 标称、`output_options` 容错 | P1 |
| `vrgen/src/vrgen/cli.py` | 4K 校验（随枚举）；可选能力预检 | P1 |
| `vrgen/src/vrgen/jobs.py` | `GenerationParams.model_id` | P2 |
| `vrgen/src/vrgen/cli.py` 的 params show/save | model_id 读写与回显 | P2 |
| `vrgen/tests/` | 4K fixture、model_id 往返 | P1/P2 |
| `docs/case-model.md` | §4 加 4K 行；generation.toml 加 model_id | P1/P2 |
| `vrstudio/src/vrstudio/web/app.py` | `PATCH_VIEWPORT_OPTIONS` 加 4K；`/fov` 路由；coverage 读数；`_op_argv` 透传 model_id；对齐提示 | P1/P2 |
| `vrstudio/src/vrstudio/web/render.py` | `PreviewStore.set_fov` | P1 |
| `vrstudio/src/vrstudio/patch/projection.py` | 公开 footprint 尺寸辅助（唯一权威仍在此） | P1 |
| `vrstudio/src/vrstudio/cli/generate.py` | `template_for` 修 allMediaRef；model_id 读取；时长说明 | P1/P2 |
| `vrstudio/src/vrstudio/cli/merge.py` | 无代码改动；4K 内存/耗时实测；必要时按分辨率缩放 feather/levels | P1 |
| `vrstudio/frontend/.../PickStep.vue` | fov 滑杆、覆盖读数、4K 尺寸档 | P1 |
| `vrstudio/frontend/.../GenerateStep.vue` | 4K 输出档、4K 首尾帧预设、时长与对齐提示 | P2 |
| `vrstudio/frontend/.../KeyframeStep.vue` | 4K 默认、上传体积显示 | P1 |

## 5. 全流程操作

### 5.0 前置

1. 安装环境：`uv sync --extra dev`。
2. 登录与模型清单：`vrgen login --check`；`vrgen models --refresh`，确认 22 的 `firstLastFrame` 与 `allMediaRef` 都有 4K。
3. 选择路线：
   - 需要端点稳定、中间由模型编：firstLastFrame；
   - 需要沿用源片的动作路径与节奏：allMediaRef；
   - 需要结构锁定、作为质量对照：videoEdit 1080p。
4. 准备项目生成会话 ID，避免个人额度为 0 时提交失败。
5. 启动 Web 控制台：`vrstudio serve`，Pick / Keyframe / Generate / Compare 页面都在 `/next/case/<名>` 下。

### 5.1 建 case 或打开已有 case

```text
vrstudio case new <名> --flow patch --source sources\dance_move.mp4
```

已有 case 直接打开。确认 `[source] sha256` 校验能通过。

### 5.2 Pick：fov、视口、inner、帧范围

1. 视口尺寸选 3840×2160。
2. 拉 fov 滑杆，从 59° 开始逐步加大，直到 inner 能盖住角色路径的左右两端。页面读数应同时显示覆盖角度、ERP footprint 宽高、1080p/4K 密度。
3. 目标密度按路线定：1080p 对照路线取 ≥1；4K 路线取 1.5–2.0 或更高。超过 110° 时页面提示边缘拉伸。
4. 拖 inner 覆盖整段移动路径，不只是起始姿势，并留出角色自身的宽度。inner 越接近视口边缘，锚点环越窄。
5. 帧范围固定为 0–449（30fps，15.0 秒）；不要取 0–450，那是 451 帧、15.03 秒，超过模型上限。窗口也可以整体平移，只要帧数是 450；首尾帧最好落在清晰、低运动的姿势上。
6. 保存，检查 `case.toml` 的 `[viewport]` / `[inner]` / `[frames]`。

### 5.3 Extract

```text
vrstudio extract name --case <名>
```

检查四件事：

- `clip.json` 的视口是 3840×2160，帧范围与草稿一致；
- `clip.mp4` 是 4K，帧数正确；
- `clip_mask.png` 黑色区域等于 inner；
- `first_frame_raw.png` / `last_frame_raw.png` 是 4K。

改动 fov 或 inner 后必须重新 extract，工作台会把旧定稿标记为 stale。

### 5.4 路线 A：firstLastFrame 4K

1. 图片步 first：工作台选模型 44、分辨率 4K、候选数 4，填写 figure / pose_first / preserve，提交后挑 1 张定稿。
2. 图片步 last：以首帧定稿为参考（first_frame），同样 4K、候选数 4，填写 pose_last，提交后挑 1 张定稿。
3. Handoff：页面把模式写成 firstLastFrame，提交集写成 `[first, last]`。
4. 视频提交，先零额度校验：

```text
vrstudio generate submit --case <名> --model-id 22 --mode firstLastFrame --resolution 4K --aspect-ratio 16:9 --check
```

去掉 `--check` 后真实提交：

```text
vrstudio generate submit --case <名> --model-id 22 --mode firstLastFrame --resolution 4K --aspect-ratio 16:9
```

`--duration` 省略时，firstLastFrame 由 vrstudio 按 clip 的帧范围取整秒，allMediaRef 由 vrgen 取最长视频；两者都必须不超过 15 秒，`--check` 会显示实际采用值。需要固定某一秒数时再显式传。

5. 采用结果：`vrstudio generate adopt --case <名> --round <轮次>`。
6. 贴回：`vrstudio merge --case <名>`，产物是 `out/<版本>_space.mp4`；Web 队列会自动接 assemble（产物 `out/<版本>_frame.mp4`），CLI 手动执行 `vrstudio assemble --case <名>`。assemble 对从 0 帧开始的段直接支持：前段 0 帧、中段 450 帧、后段 120 帧，输出仍是 570 帧；最终成片的音频从源片复用，AI 段不带音频。整片抽取时只有 `_space`。
7. 检查：result 栅格是 16:9（3840×2160 或 4096×2304）、帧数/fps 合规、merge 报告的边界与静态背景指标。

### 5.5 路线 B：allMediaRef 4K

1. P1 修好 `template_for` 后，装配器对 patch + allMediaRef 会自动用 `gen-multi`；用 `vrgen prompt show` 检查变量，补齐 subject / target / plot / preserve / allowed_changes。
2. 提交集：clip（edit_master）+ 主体参考（subject_ref，可多张）+ 可选 lighting_ref；mask 由装配器自动附带。在 Generate 页把 clip 与参考图勾进提交集、角色按上表设置，模式选 allMediaRef，分辨率 4K，比例 16:9。
3. 视频提交，先校验：

```text
vrstudio generate submit --case <名> --model-id 22 --mode allMediaRef --resolution 4K --aspect-ratio 16:9 --check
```

去掉 `--check` 后真实提交：

```text
vrstudio generate submit --case <名> --model-id 22 --mode allMediaRef --resolution 4K --aspect-ratio 16:9
```

4. 注意 clip 上传会被缩到 1920×1080（输入上限 2.09M px），提示词里的 canvas 数字是上传尺寸，不是输出尺寸；4K 的细节由模型生成。上传缩放保持 `--scale auto`：选 `full` 会把 8.29M px 的 4K clip 原样上传，超过 2.09M 上限，vrgen 会在提交前报预算错误。allMediaRef 的时长由最长视频向上取整；如果 ffprobe 把 450 帧报成 15.0007 秒，会取整成 16 秒并被拒，此时显式传 `--duration 15`。
5. 采用、贴回、时间拼接，步骤同路线 A。
6. 检查重点：模型是否重构了构图或镜头。漂移大的候选直接弃用，不要靠贴回掩盖。

### 5.6 路线 C：videoEdit 1080p 对照

模型 37、视口 1920×1080、fov 与 4K 路线相同、模式 videoEdit、分辨率 1080p。时长跟随输入，结构锁定。它作为质量与边界的基线，用来判断 4K 路线是否真的更清楚。这条路要另做一次 extract（把视口改回 1920×1080、fov 不动），得到同一角度的 1080p clip；旧版本保留。

### 5.7 对比与记录

在对比页看原片与成片，量三个数：inner 边界梯度与内部 p95 的比值、静态背景区域与源片的差异、动作是否始终留在 inner 内。把数字、并排图和额度/壁钟写进 `docs/test-runs/<日期>-patch-4k.md`。

## 6. 验收标准

- 零额度：两条路线的 `--check` 通过；P2 下 `params show` 显示 model 22 与 4K。
- 结构：extract 产物齐全；merge 后视口 footprint 之外逐位相等（footprint 内、inner 外的环是重投影，不做逐位保证）；帧数精确。
- 质量：边界梯度不高于内部 p95；静态背景差异在阈值内；动作不出 inner；比例与时长闸门通过。
- 栅格：返回 16:9、宽度达到 4K 档标称；normalize 为 identity 或等比缩放。
- 成本：图片 2 步各 4 张，视频两条路线各 1 轮；记录额度与壁钟。

## 7. 失败处理与回滚

| 现象 | 检查 | 处理 |
|---|---|---|
| `--duration` 超 15 秒 | vrgen 报“超出模式 firstLastFrame 的合法区间” | 裁帧范围到 ≤15 秒；全片 4K 走时间切分（另立） |
| 4K 不出现或被拒 | `vrgen models --refresh`；22 的 modes/resolutions | 确认模型与模式；退回 1080p |
| 4K 关键帧上传被拒 | 图片体积、平台返回码 | 压缩或降采样图片上传，视频仍 4K；或改用 2K 关键帧 |
| 比例不一致 | generation.toml 的 aspect_ratio；返回栅格 | 设 auto 或 16:9 |
| merge 内存/耗时过高 | 峰值内存、单帧耗时 | 降 levels、降视口到 2880×1620、或分段跑 |
| allMediaRef 重构构图 | 返回帧与源片的空间相关 | 弃用该候选，改 firstLastFrame |
| 结果帧数偏短 | merge 的 short 警告 | 不贴回，重跑 |
| 15 秒处出现外观突变或白模 | 第 449 帧与 450 帧的源片内容；角色是否仍在画面 | 把 15 秒窗口停在动作结束或低运动点；否则走 P3 时间切分 |
| 模型与模式不匹配 | 22 没有 videoEdit | P2 用 `params save --model-id`；P1 用 `--model-id` |

回滚：把模型改回 37、模式 videoEdit、分辨率 1080p、视口 1920×1080。旧 extract 版本仍在，不删。

## 8. 分期

- P0（本文）：决策 49、case-model 的 4K 行随 P1 一起落地。
- P1 CLI 试点：vrgen 4K 档；视口 4K；fov 端点/滑杆/读数；keyframe 4K；CLI 视频提交；4K merge；在源片 0–449 帧上按 A、B 各跑一次。
- P2 Web 全链路：generation.toml 的 model_id；params show/save；4K 首尾帧预设；对齐与时长守卫。
- P3 条件项：把 19 秒全片切成多段 4K 生成；多视口/分块。

## 9. 风险与待确认

- 4K 档的 firstLastFrame 与 allMediaRef 从未真实跑过（现有 firstLastFrame 轮次都是 1080p），平台返回的栅格、时长与额度都未知。
- allMediaRef 的 1080p 输入到 4K 输出，细节是生成的，实际锐度可能不如 1080p 基线；以指标判定，不看档位标称。
- 15 秒上限对 19 秒素材的约束。
- 15 秒后的 120 帧保留源片，时间拼接处是硬切；如果角色在 15 秒后仍在画面里，成片会出现从重绘角色跳回白模的外观突变。
- 大 inner 的背景由模型编，边界漂移是主要质量风险。
- 4K merge 的内存与耗时。
- AI 返回的帧率或帧数不合规时，merge 会走 restore/RIFE；4K 下这一步明显变慢，先用 720p 或 1080p 验通流程再上 4K。
- P2 的 model_id 契约与切换模型后的模式收敛。
- 4K 关键帧的上传体积。

## 10. 明确不做

- 多视口/分块：movement 超过约 110° fov（8K、inner 85%–90% 时约 2K ERP px）才回来。
- 4K 21:9：没有平台标称值。
- 自动 fov 推荐：先手动滑杆加读数，用几轮真实素材再谈。
- 把 19 秒全片切成多段 4K 生成：另立工作包；现有的单段空间+时间拼接不受影响。
