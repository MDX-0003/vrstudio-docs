# 跟随输入分辨率计划（视频 recompose 与图片 merge）

状态：2026-11-04 用户认可整体方向与三项选择，待实施。
关联：决策 79，`docs/case-model.md` 的 `[merge]` 段与目录布局，`docs/plan/video-merge-input-plan.md`。

## 1. 问题

`recompose` 与 `stitch_image` 的输出尺寸固定等于 case 源分辨率。当 AIGC 工具返回 480p、而 case 源是 8192×4096 时，每一帧都要先放大到 9558×4096 的画布，再做混合、接缝统计与 8K 编码。

实测（`cases/vf_dance_walk_02`，输入 1000×428、297 帧）：

- 放大到画布 38.6 ms/帧，混合 166 ms/帧，接缝统计 74.5 ms/帧，8K 编码 140 ms/帧。
- 渲染段 2.7 fps，闸门段约 6 fps，整条约 165 秒。
- 输入只有 0.43M 像素，输出 33.5M 像素，放大 78 倍；多出来的计算不产生任何新细节。

## 2. 目标

允许用户为一次 recompose/merge 选择「跟随输入的像素密度」输出，低分辨率输入不再被迫放大到 case 分辨率。低分辨率成片用于预览与迭代，不替代源分辨率交付物。

## 3. 规则（唯一权威点：`redraw/geometry.py`）

输入宽度 `input_w`，源宽 `W`，画布宽 `Wc`：

- 缩放比例 `s = input_w / Wc`。
- 输出宽 `out_w = round_even(W × s)`，输出高 `out_h = round_even(H × s)`；`round_even` 与 pad 共用同一实现。
- 缩放后的几何由一个真实的 `plan_pad(PadSpec((out_w, out_h), plan.target_aspect), pre_roll="none")` 派生，而不是逐字段取整；这样 `assert_closure` 仍会验证 `L = 2P`、区域平铺与 wrap 对相邻。
- 端点锁按 `endpoint_lock_pct` 从缩放后的 `L` 重新计算；搜索半径按 `search_pct` 从缩放后的 `L` 重新计算；`d*` 是缩放后画布上的整数列。
- 输入宽度不小于源宽、或缩放后 `L < 8`（冗余带过窄，闭合不可靠）时，不提供跟随输入，回退案例分辨率。

例子：1000/9558 → 输出 856×428，画布 1000×428，L=144，端点锁 3，搜索半径 36。

## 4. 两条流程

### 视频 recompose

- `vrstudio recompose --follow-input`：探测输入宽度后按上面的规则派生缩放后的 plan。
- 输出写 `out/<轮次>_<W>x<H>.mp4`，报告写 `out/<轮次>_<W>x<H>_recompose.json`；不带该 flag 时路径与现在完全一致。
- 报告新增 `output_mode`（`case` / `input`）与 `output_size`，`restored_canvas` 记录缩放后的画布。

### 图片 merge

- `vrstudio merge --case --follow-input`：`stitch_image` 接受 `follow_input` 参数，内部用同一规则选择缩放后的 plan。
- 输出写 `out/<extract>_image_<W>x<H>.png`；不带该 flag 时维持 `out/<extract>_image.png`。
- 最终尺寸断言从「等于源图尺寸」改成「等于缩放后的输出尺寸」；报告新增 `output_size` 与 `output_mode`。
- `stitch_image` 默认 `follow_input=False`，img2video 等现有调用不受影响。

## 5. web 与前端

- `_case_info` 新增只读 `output_options`：由后端用同一个 `follow_input_plan` 计算两种模式的宽高，返回 `[{mode: "case", width, height}, {mode: "input", width, height}]`；输入不满足条件时只给 `case`。
- 视频 `recompose` op 与图片 `merge` op 在 `body.output_mode == "input"` 时透传 `--follow-input`。
- 「拼接」与「裁回原尺寸」页共用一个输出尺寸下拉框；默认案例分辨率，选择只随本次运行提交，不写进 `case.toml`。
- 步骤页的「裁回原尺寸输出」/「拼接输出」显示该轮次真实写出的文件：后端按 adopt 轮次或 extract 版本前缀，加 `<stem>_recompose.json` 配对条件，从 `out/` 里找出实际产物（案例分辨率或 `_<W>x<H>` 后缀）；一个都没找到时才退回案例分辨率的计划路径并标「文件缺失」。
- 「成片」面板按新→旧展示（后端 `_outputs` 仍按 mtime 升序，对比页继续取最后一项作默认）。

## 6. 对比页识别

现有规则不需要改：

- 视频 fullredraw：`_output_files` 收 `out/*.mp4`，条件是旁边存在 `<stem>_recompose.json`；后缀输出与后缀报告成对出现，会被识别。
- 图片流程：`_output_files` 收 `out/*.png`，不要求报告；后缀 PNG 直接进入列表。
- 对比页默认选 mtime 最新的一份；两种分辨率可以来回切。视频代理按文件名读取 `out/`，后缀文件可走代理。
- 已知限制：图片的 `report.json` 每个 extract 版本一份，描述最近一次 merge；切回旧的 8K 成片时，报告面板仍显示最近一次的低分辨率指标。本轮不拆报告。

## 7. 验收

1. `follow_input_plan` 单测：1000/9558 → 856×428、偶数、`assert_closure` 通过；输入不小于源宽与过小输入返回 `None`。
2. 视频缩放闭合恒等式：在小尺寸 plan 上 pad 后 recompose，输出仍是该尺寸的纯旋转。
3. 图片缩放闭合恒等式：`stitch_image(follow_input=True)` 对缩放后的画布输出该尺寸的纯旋转。
4. CLI：两种流程各跑一次带 flag 与不带 flag 的对照，确认文件名、报告字段与尺寸。
5. web：`output_options` 两种模式尺寸正确；两个 op 透传 `--follow-input`；带后缀的 mp4/png 出现在 `_output_files`。
6. 门禁：vrstudio `pytest` 与 `ruff`；前端 `lint`、`format:check`、`test`、`build`。
7. 性能对照：`vf_dance_walk_02` 用案例模式与跟随输入各跑一次，记录耗时与输出尺寸。

## 8. 提交

1. 根仓库文档一笔。
2. vrstudio 后端一笔：几何函数、两条 CLI、web、测试。
3. vrstudio 前端一笔：下拉框、类型与测试。
