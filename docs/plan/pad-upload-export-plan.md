# 扩充件的上传副本：提前到扩充步生成并支持下载

## 1. 背景

用户把 `cases/1105-01/seedance_input.mp4`（4480×1920 = 8,601,600 像素）直接交给 mglc，被平台挡下：

```
当前参考视频像素为8601600，超过最大允许像素8295044
```

同一套流程里 `cases/vf_dance_walk_02` 却能提交，原因不在流程，而在于交给 mglc 的**不是** `seedance_input.mp4` 本身：

- `vf_dance_walk_02` 的 pad 件是 9558×4096（39,149,568 像素），远超上限；vrgen 在 prepare 阶段按模型 37 的 `refVideoValidator.maxPixel = 8295044` 把它重编码成 `upload_pad_4398x1884.mp4`（8,285,832 像素），上传的是这份副本，提示词里写的也是 4398×1884。
- `1105-01` 没有跑过 vrgen 的提交准备（`vrgen_runs/1105-01/` 里没有轮次目录），交出去的是全尺寸 pad 件，于是撞上限。

结论：平台能接受的输入尺寸只在 vrgen 的 prepare 阶段算出来。用户不走我们的平台生成、只想要 pad 与原尺寸拼接时，拿不到这份"被正确缩放过的输入"。

## 2. 要解决的问题

1. 把 vrgen 里"按平台限额算上传尺寸并重编码"这段抽成可复用函数，并提供独立 CLI，脱离提交也能产出上传副本。
2. 在「扩充画面」步骤就把上传副本生成出来，作为第二组文件展示，支持下载，供外部工具直接使用。
3. 顺带把「视频全幅重绘」页的扩充与裁回拆成两个步骤各自的面板，消除共用 UI 与按钮堆积。

## 3. 两组文件的区别

pad 步骤之后，case 里有两种尺寸体系，页面上分组展示，不混在同一个列表：

- **扩充产物（全尺寸）**：`seedance_input.mp4`、`seedance_input_mask.png`、`seedance_input_pad.json`。画布尺寸与几何契约，`recompose` 只认这一组；其中 manifest 没有缩放版本。
- **上传件（送平台的文件）**：`derived/upload_pad_<W>x<H>.mp4`、`derived/upload_pad_mask_<W>x<H>.png`、`derived/upload_pad_<W>x<H>.json`。前两个是重编码后的同尺寸副本（视频 crf 16、mask 灰度 PNG），第三个记录画布、源尺寸、上传尺寸、缩放比例、冗余带列号与平台上限。

上传件的文件名与轮次目录里的 `upload_<id>_<W>x<H>.mp4` 保持一致，因此用户拿到的文件与平台实际收到的是同一份（同参数、同命名）。

## 4. 生成时机

扩充画面任务成功后自动排队一个导出任务，不额外占一次点击；日常走内部生成路线的人也能提前看到缩放到多大。用户改了生成参数（模型、模式、`scale`）后，已有的上传件不再对应当前设置，页面显示「当前生成参数已变」并给一次「按当前参数重新生成」。

不选择"每次 pad 都顺手转码"以外的做法（点按钮才生成、单独手填尺寸）：前者的代价是每次 pad 多一次重编码，后者让用户自己算平台上限，都会把已知规则推给用户。

## 5. vrgen 侧

### 5.1 抽出可复用函数

新增 `vrgen/src/vrgen/prep/uploads.py`，把 `round/pipeline.py` 内联的三段搬出来，`_prepare_refs` 改为调用：

- `plan_video(asset_id, path, *, conf, validator, explicit)`：对应现 `pipeline.py` 里"probe → check_input → 失败才 `choose_upload_size`"。
- `plan_image(...)`、`plan_mask(..., canvas_size, image_validator)`。
- `materialize(plan, out_dir, *, conf, log, image_validator, video_validator)`：按 role/kind 选 `scale_video` / `scale_image` / `scale_reference_image`，缩放后重新 probe 并复核限额，失败抛 `BudgetError`。

`UploadPlan` 是纯数据（`asset_id`、`src`、`spec`、`size`、`needs_scale`、`kind`、`role`），不建轮次、不写台账。重构以字节一致为验收：同一输入的两条路径产出的上传件 sha256 相同。

### 5.2 新 CLI

```
vrgen prep --video <路径> [--mask <路径>] --canvas WxH --source WxH --out <目录>
           [--scale auto|full|half|WxH] [--video-model-id 37] [--mode videoEdit]
           [--workdir <dir>] [--dry-run]
```

- 模型清单走 `load_models` / `find_model`（缓存仍落 workdir），限额取该 mode 的 `refVideoValidator`。
- 视频固定 id `pad`、mask 固定 id `pad_mask`，与 `--refs` 契约的流程产物命名一致。
- 写 `upload_pad_<W>x<H>.mp4`、`upload_pad_mask_<W>x<H>.png`、`upload_pad_<W>x<H>.json` 到 `--out`。
- `--dry-run` 只打印规划（尺寸、比例、冗余带、上限），不写文件。
- 退出码沿用 0 / 2 / 1；缩放后仍超限按 `BudgetError` 以 1 结束（与 `submit` 的判定和退出码一致，不另立规则）。
- JSON 字段：`canvas`、`source`、`upload{path,width,height,pixels}`、`scale`、`scale_percent`、`band{P,L,regions}`、`limit{max_pixel,max_bytes}`、`video_model_id`、`mode`、`created_utc`、`tool`。

## 6. vrstudio 侧

- 新命令 `vrstudio export-upload --case <名> [--cases-dir] [--scale] [--dry-run]`：从唯一 manifest 取 canvas/source（`_manifest` + `to_pad_plan`），从 `_flow_candidate` / `_flow_mask` 取 pad 与 mask，输出目录固定 `cases/<名>/derived/`，组 argv 调 `vrgen prep` 并透传退出码。
- web 的 op 注册表加 `export_upload`；`pad` 成功后的 follow-up 在 `flow == fullredraw` 且 manifest 存在时自动排队同一命令，机制与 `merge → assemble` 相同。
- `_fullredraw_step_files` 的 `pad` 组增加 `uploads` 列表与 `pad_upload` 摘要（读上传件 JSON；文件不存在时为空），供页面区分两组文件。

## 7. 前端

- `MergeStep` 增加 `step` prop（由 `WizardView` 传入当前步骤），fullredraw 分支按步骤渲染两个独立面板；patch / patchimg / fullRedrawImg 分支不变。
- 扩充步：主按钮「扩充画面/重新扩充」、pad 门控提示、扩充产物、上传件两组文件；右列只留最近任务。
- 裁回步：拼接输入控件、输出模式、主按钮「裁回原尺寸」、门控提示、裁回产物；右列成片与最近任务。
- 上传件组头写清来源与上限（`model 37 · videoEdit · scale auto`，上限 8,295,044 像素），每行在原有播放/打开之外加「下载」。
- `FileRow` 增加可选 `#actions` 插槽，props 仍只有 `{ entry }`，现有调用零改动。

## 8. 工作包

1. WP0 原型：`.tmp_prototype/merge-step.html`，现状 + 方案两个标签，覆盖上传件的已有/未生成/生成中/参数已变四态与两个步骤，1280 与 1440 两个宽度。
2. WP1 文档：本文、`case-model.md` §4、`decisions.md` 决策 87、`frontend-decisions.md` 条目 29。
3. WP2 vrgen：`prep/uploads.py`、`pipeline.py` 复用、`vrgen prep`、测试（规划算术、CLI、字节一致）。
4. WP3 vrstudio CLI：`export-upload` 与 `--dry-run`。
5. WP4 web：`export_upload` op、pad follow-up、`uploads` 与侧车摘要。
6. WP5 前端：`MergeStep` 拆分、上传件分组、`FileRow` 插槽、类型与 `RunOperation`。
7. WP6 验收：见下。

## 9. 验收

- 字节一致：对 `1105-01` 的真文件跑 `vrgen prep`（4398×1884），与同一 case 的 `vrgen submit --dry-run` 产出的 `upload_pad_4398x1884.mp4` 比 sha256。
- CLI：`--dry-run` 不写文件；`--scale full` 超限时退出码 2；mask 与视频同尺寸。
- 后端：两侧 `uv run pytest` 全绿、`uv run ruff check .` 干净。
- 前端：`npm run lint`、`format:check`、`test`、`build` 全过；新增用例覆盖按步骤渲染、上传件空态按钮、下载链接带 `download=1`、`FileRow` 插槽。
- 浏览器：用 `1105-01` 走扩充步看到两组文件 → 重新扩充后上传件出现 → 下载得到 4398×1884 的 mp4 与 mask → 切到裁回步只见拼接输入与裁回按钮。

## 10. 非目标

- 不改 `_pad.json`、`run.json`、`clip.json` 的字段集与轮次目录命名。
- `vrgen submit` 仍在轮次目录里自行生成上传件，不改台账；导出件是 case 侧的另一份。
- 不新增 config 键与提示词变量。
- 不在生成时自动触发浏览器下载。

## 11. 后续修订（决策 96，2026-11-09）

「上传件」这个内部叫法在页面上看不懂，且导出失败只留下任务报错。修订：

- 组名改为「生成平台合规分辨率副本」，tag 改「外部工具用这组」；说明写清全尺寸件超过
  8,295,044 像素上限、副本已按限额缩到同一尺寸、mask 同宽高、JSON 记录画布/缩放/冗余带。
  按钮文案改为「生成合规副本」。
- `/api/case` 新增 `upload_gate = {ready, reason}`（`_apply_upload_gate`，与
  `_apply_mode_gate` 同一处计算）：扩充件未生成时沿用 pad 门控原因；源片时长不在当前
  模式区间时显示「源片 1.9 秒，videoEdit 要求 2–30 秒」并置灰导出按钮。
- 不放宽 vrgen 的时长校验（副本必须与内部提交是同一份），也不做循环补帧。
