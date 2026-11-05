# 跟随输入按上传件尺寸派生：实施与 110503 实测

日期：2026-11-05
关联：决策 90，`docs/plan/follow-input-upload-size-plan.md`，被测 case `vrstudio/cases/110503`。

## 1. 起因

`cases/110503`（fullredraw，源 `sources/02.mp4` 1440×720，扩容画布 1680×720，L=240）把
`assets/v1_视频_-_正片__1.mp4`（2206×946，21:9 画布）设为拼接输入后，「裁回原尺寸」的输出尺寸
下拉框消失，成片是 1440×720，且右侧第 1397 列起有一条 43 px 的重复内容。

## 2. 两处根因与改法

### 2.1 下拉框消失

`geometry.follow_input_plan` 原来用 `input_width >= plan.W` 判定「跟随无收益」。输入件是画布，
它的宽度里含着两侧冗余：2206×946 的内容区是 `2206 × 1440/1680 = 1891` px，比源宽 1440 大，
于是被判成没有新信息，`_output_options` 只剩一个选项，前端 `showOutputMode = options.length > 1`
把下拉框整条藏起来。

改为只用输入件自身的宽高派生：

- 输出高 `round_even(输入高)`，输出宽 `round_even(输出高 × 源宽/源高)`（2:1 源对齐到 4 的倍数）。
- 缩放 plan 由 `plan_pad(PadSpec((out_w, out_h), Fraction(输入宽, 输入高)), pre_roll="none")`
  派生，画布尺寸因此等于输入件尺寸，带宽 `P = (输入宽 − out_w)/2` 由输入件自己的宽高比决定，
  案例的 `target_aspect` 与 `L` 不参与。
- 取消「输入不小于源宽就不跟随」的闸门；只在尺寸非法、`P < 1`、`L < 8`、或派生结果与案例
  分辨率完全相同时返回 `None`。

本 case 的结果：`follow_input_plan` 给出 1892×946（画布 2206×946，L=314），
`_output_options` 返回 `[{case, 1440, 720}, {input, 1892, 946}]`，下拉框恢复。

### 2.2 右侧 43 px 残影

同一份报告里 `quality = 1.0016`、`d* = -43`：最佳位移与次佳位移的误差几乎一样，`d*` 是巧合匹配。
滚动混合带会在带内产生 43 列的重复内容，硬接缝落在输出第 1397 列。同一帧按 `d* = 0` 混合则干净。

改为 `registration.applied_shift(reg, gate)`：`gate == "warn"`（代价曲线平坦）时渲染用 0，
报告 `d_star` 记 0，检测值与被归零的原因写日志；`ok` 照常应用，`fail` 仍中止；
`--d-star` 是人工显式覆盖，不被归零。视频 `recompose` 与图片 `stitch_image` 共用这一处判定。

## 3. 实测

### 3.1 跟随输入（`--follow-input`）

```
gate analysed 48 of 721 frames
d* = -57 (clip_median), band correlation 0.650, cost-curve quality 1.00 -> warn
配准代价曲线平坦（quality 1.00），d* = -57 是巧合匹配：按 0 混合，报告记 0
canvas restore 2206x946 -> 2206x946   (lanczos4, aspect 2.3319)
output         1892x946   regions G/R/B = 314 / 1578 / 314   (follow input)
wrap pair      canvas columns 313, 314
blend          smoothstep, endpoint lock 6 columns
final    out\result_1892x946.mp4   1892x946   721 frames
wrap     2.506 (percentile 90.2); interior worst 3.170
```

- 画布还原与输入件尺寸一致（2206×946），不产生重采样。
- 截帧检查：右侧无重复内容、无硬接缝（改动前同位置有 43 px 重复带）。
- 报告 `out/result_1892x946_recompose.json` 写 `output_mode: "input"`、`output_size: [1892, 946]`、
  `restored_canvas: [2206, 946]`、`registration.d_star: 0`。

### 3.2 案例分辨率（不带 flag）

```
d* = -43 (clip_median), band correlation 0.650, cost-curve quality 1.00  -> warn
canvas restore 2206x946 -> 1680x720
output         1440x720   regions G/R/B = 240 / 1200 / 240
wrap     3.231 at percentile 91.0; worst interior pair 4.022
```

`out/result.mp4` 已重跑覆盖：右侧 43 px 重复内容消失，其余指标与改动前同量级。

## 4. 自动化

- `tests/test_follow_input.py`：1000×428 输入仍是 856×428；12000×5142 输入得到大于源尺寸的
  plan 且 `Wc == 12000`；与案例画布同尺寸返回 `None`；过窄/0/比源窄的输入返回 `None`；
  `applied_shift` 在 warn/ok/fail 三种判定下的取值；web `output_options` 在输入大于案例时
  返回两项（384×192 与 768×384）。
- `uv run pytest`：全绿（185 项前端单测另跑）；`uv run ruff check .` 干净。
- 前端 `npm run lint`、`npm run test`（29 个文件 185 项）通过；`npm run format:check` 在
  `src/api/relight.ts` 等 7 个本次未触碰的文件上报格式问题，属既有状态，未在本轮改动。

## 5. 未做

- `recompose.d_star_mode = per_frame` 的逐帧位移仍按每帧自己的配准结果 EMA，不经过 `warn`
  归零；这条模式是实验开关，本轮不改。
- 浏览器端的下拉框点击与出片未走 Playwright；后端 `_output_options` 已直接调用验证，
  前端只改了类型注释，渲染条件未动。
