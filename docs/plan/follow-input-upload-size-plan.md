# 跟随输入改为按上传件自身尺寸派生（决策 90）

状态：2026-11-05 用户确认两条口径（输出按上传件尺寸派生、平台配准曲线时 d* 归零），开始实施。
关联：决策 79（被本方案取代的旧口径）、决策 78（拼接输入）、`docs/plan/follow-input-resolution-plan.md`、
`docs/case-model.md` 的 `[merge]` 段与目录布局。

## 1. 问题

`cases/110503`（fullredraw，源 1440×720）把一份 2206×946 的 21:9 画布视频作为拼接输入交给 `recompose`：

- 报告写 `output_mode: "case"`、`output_size: [1440, 720]`、「裁回原尺寸」页上的输出尺寸下拉框整条不显示，
  只剩案例分辨率。
- 成片右侧多出一条 43 px 的重复内容，硬接缝落在输出第 1397 列。

两处根因互相独立：

1. `geometry.follow_input_plan` 用 `input_width >= plan.W`（输入宽对**源宽** 1440）判定「跟随无收益」。
   但输入件是画布，宽度里含着两侧冗余；它的内容区实际是 `2206 × 1440/1680 = 1891` px，比源宽大。
   判成「没有新信息」后 `_output_options` 只返回一个选项，前端 `showOutputMode = options.length > 1`
   于是把下拉框藏起来。
2. 同一函数按 `s = input_w / 画布宽` 缩放并保留案例的目标比例。上传件的宽高比与案例画布不一致时，
   冗余带宽按案例的 `L` 切，切完仍会留下上传件自己的冗余。这违背了用户要的「无视 canvas 数据」。
3. 配准代价曲线平坦时（`gate_registration` 判 `warn`，`quality = 1.0016`）仍然应用 `d* = -43`。
   滚动混合带会在带内产生 43 列的重复内容；同一帧按 `d* = 0` 混合则干净。

## 2. 规则（唯一权威点仍是 `redraw/geometry.py`）

输入件尺寸 `(iw, ih)`，源宽高 `(W, H)`：

- 输出高 `out_h = round_even(ih)`；输出宽 `out_w = round_even(out_h × W/H)`。
  源为精确 2:1 时把 `out_w` 对齐到 4 的倍数（半宽也为偶数），与决策 79 的 ERP 特例相同。
- 缩放后的几何由 `plan_pad(PadSpec((out_w, out_h), Fraction(iw, ih)), pre_roll="none")` 派生。
  输入件是偶数尺寸时 `Wc == iw`、`canvas H == out_h`，还原步骤不产生重采样；冗余带宽 `P` 由
  `(iw - out_w)/2` 得出，即完全由输入件自己的宽高比决定。
- 案例的 `target_aspect` 与 `L` 不参与计算。这是与决策 79 的唯一实质差别。
- 不提供选项（返回 `None`）的条件只剩三条：输入尺寸非法或退化；派生后 `P < 1` 或 `L < 8`
  （冗余带太窄，闭合不可靠）；派生结果与案例分辨率完全相同（没有可选的第二种尺寸）。
  删掉 `input_width >= plan.W` 这条闸门，因此输入比案例分辨率大时输出也会更大。

## 3. 配准：平台曲线时不滚动混合带

`gate_registration` 已经用 `quality = mae_second / mae_min` 判断代价曲线是否可信：`< warn_quality`
说明最佳位移与次佳位移几乎一样，`d*` 是巧合匹配。此时：

- 渲染用 `d* = 0`，报告的 `d_star` 记 0（报告字段集不变），日志打出检测值与被归零的原因。
- 判定为 `ok` 时照常应用 `d*`；判定为 `fail` 时仍然中止（`--force` 时才继续，继续时应用 `d*`）。
- `--d-star` 是人工显式覆盖，仍然优先，不被归零。
- 视频 `recompose` 与图片 `stitch_image` 共用同一条判定，规则写在 `registration.py` 一处。

## 4. 两条流程

### 视频 recompose

- `vrstudio recompose --follow-input` 用 `probe` 拿到的 `(w, h)` 派生缩放 plan，后续画布还原、闸门
  搜索半径、端点锁、输出尺寸全部来自派生 plan。
- 输出写 `out/<轮次>_<W>x<H>.mp4`（带后缀），报告记录 `output_mode: "input"`、`output_size` 与
  `restored_canvas`；不带该 flag 时路径与现在完全一致。

### 图片 merge

- `stitch_image(..., follow_input=True)` 用生成图的 `shape` 派生同一个 plan，输出尺寸断言跟着派生 plan 走。
- 输出写 `out/<extract>_image_<W>x<H>.png`。

## 5. web 与前端

- `web/app.py` 的 `_output_options` 传入输入件的宽与高（视频与图片都从 `_media_meta` 取），
  选项仍由后端用同一个 `follow_input_plan` 计算；输入件比案例大时现在会多出「跟随输入」一项，
  下拉框因此恢复显示。前端不改逻辑，只改 `OutputOption` 的注释（原来是「输入更小时」）。
- 「跟随输入」的尺寸既可能小于也可能大于案例分辨率，文案不变（`跟随输入 W×H`）。

## 6. 验收

1. 几何单测：8192×4096 案例 + 1000×428 输入仍是 856×428；2206×946 输入得到 1892×946，`Wc == 2206`，
   `assert_closure` 通过；与案例同尺寸的输入返回 `None`；过窄输入返回 `None`。
2. 视频缩放闭合恒等式：派生尺寸上 pad 后 recompose 输出仍是纯旋转（沿用现有测试，补一条大于源尺寸的）。
3. 配准：构造一条 `quality < warn_quality` 的输入，断言渲染用 `d* = 0`、报告 `d_star = 0`、
   日志含检测值；`--d-star` 覆盖不被归零。
4. web：`output_options` 在输入大于案例时返回两项；`recompose`/`merge` op 透传 `--follow-input`。
5. 实测 `cases/110503`：两种模式各跑一次，确认「跟随输入」写出 `result_1892x946.mp4`，右侧 43 px
   重复内容消失（与 `d*=0` 的对照帧一致）。
6. 门禁：vrstudio `uv run pytest`、`uv run ruff check .`；前端 `lint`、`format:check`、`test`、`build`。

## 7. 提交

1. 根仓库文档一笔：决策 90、本文、`case-model.md`、旧计划状态说明、`AGENTS.md` 索引。
2. vrstudio 代码一笔：geometry、registration、recompose/merge/image、web、测试与前端注释。
