# patchimg 视口局部：8K 真实额度验收记录

记录时间：2026-10-29。
背景：`docs/plan/360-still-gen-flows-plan.md` 的 WP2 把 `patchimg` 从全幅 21:9 改回视口局部（vrstudio `e2e3553`）。本文按 WP2 的验收条款，用真实额度跑完一轮 CLI 全流程。
结论：五步（case → draft → extract → submit/adopt → merge）全部跑通；选区外 `maxdiff 0` 且与源图逐位相等；同一主体区域的局部细节明显高于旧全幅方案。`compare` 还没有 CLI，本文的对比图由外部脚本生成。

## 1. 环境

- vrstudio `main` `e2e3553`（patchimg 视口局部）；vrgen `main` `e46082e`（修掉 `still360-local` 里全幅冗余带的残留说明）。
- 源图：`vrstudio/sources/360erp_test.png`，8192×4096，2:1 ERP。
- case：`vrstudio/cases/wp2_live`（新建，不复用旧 `erp_test` 的全幅版本目录）。
- 视口：`yaw -101.0 / pitch 0.0 / fov_h 70.0`，1920×1080；inner `420,280,1080×800`（覆盖坐着的文官整身）。
- 模型与额度：`vrgen image submit`，model 44，`--ratio 16:9 --resolution 4K --num 4`，session `2062569522605504`（cli会话_测试）。
- 提示词：`vrgen_runs/wp2_live/prompt-vars.toml`，`edit` = 把红框内坐着的文官换成穿金色长袍的年轻武将、保持坐姿朝向大小与位置；`preserve` = 柱子、地面、烛台、背景与其他人物保持原样，光照色调构图不变。

## 2. 步骤与证据

### T1 case 与 pick 草稿

- `vrstudio case new wp2_live --flow patchimg --source sources\360erp_test.png` 通过，源图 2:1 校验在创建时执行。
- `vrstudio case draft --case wp2_live --file draft.json` 写入上表视口与 inner；`case show` 回读一致。

### T2 extract：只产视口图与几何

- 版本目录 `extracts/20261029-110142/` 只有 `clip.png`（1920×1080）、`clip_mask.png`、`still.json`；`derived/` 同三个文件；没有 `padded.png`，没有 `still_pad.json`。
- `still.json`：`version 1`、`erp 8192×4096`、`viewport 1920×1080`、`inner 420,280,1080×800`。

### T3 submit：真实一轮，4 张候选

- `vrstudio generate submit --case wp2_live --num 4 --resolution 4K --session-id 2062569522605504` 发出的 argv 为 `vrgen image submit --template still360-local --image clip.png --image-role edit_master --image clip_mask.png --image-role mask --ratio 16:9 --resolution 4K --num 4`。
- 轮次 `img-2e6d79af`，4 张候选均为 3840×2160，gate `ok`；台账 `params` 记录 ratio `16:9`、model 44、session 同上。
- 候选挑选依据（把候选降采样到 1920×1080 后与 `clip.png` 比，统计 inner 之外）：MAE 分别 6.36 / 4.41 / 6.99 / 6.11，p95 21.0 / 13.7 / 24.3 / 19.0。2 号场景保持最好，边界过渡最稳，采用 2 号。
- 视觉：四张都把文官换成了金色长袍的坐姿武将，位置、朝向与大小保持不变。

### T4 adopt

- `vrstudio generate adopt --case wp2_live --round img-2e6d79af --index 2` 把 2 号拷成 `extracts/20261029-110142/result.png`，并写 `[adopt] round/index`。

### T5 merge：贴回并只写 inner

- `vrstudio merge --case wp2_live`：归一化 3840×2160 → 1920×1080（比例一致，等比缩放），`SegmentMaps.from_geometry` + `composite_frame` + 只写 inner。
- 输出 `out/20261029-110142_still.png`，8192×4096。
- 统计：support 701031 px，changed 698678 px，`outside maxdiff 0`；inner 内 PSNR 21.28 dB，|diff| 中位数 5.0。
- 独立复算（不读 report，直接从 still.json 重建几何）：`np.array_equal(out[~support], src[~support])` 为真；ERP 接缝两端的列（0..2 与 8188..8191）与源图逐位相等。

### T6 前后对比产物

`cases/wp2_live/out/` 下四张（cases/ 不进 git）：

| 文件 | 内容 |
|---|---|
| `cmp_1_viewport_in_vs_out.png` | 模型输入（`clip.png`）与模型输出（`result.png`）并排 |
| `cmp_2_erp_before_after_diff.png` | 视口 footprint 的贴回前 / 贴回后 / 差异热图 |
| `cmp_3_erp_full_before_after.png` | 整张 8192×4096 ERP 的缩略前后对比 |
| `cmp_4_inner_boundary_zoom.png` | inner 左上边界 2× 特写 |

差异热图显示：变化集中在 inner 的投影范围内，范围外为 0；模型在 inner 内重绘了整块背景（mask 只是提示），区域内 |diff| 中位数 5，主体处最大。

## 3. 与旧全幅方案的局部细节对比

同一 case 几何下取同一个 inner bbox（1674×1060 的 ERP 像素），比较 2026-10-29 上午全幅验收的成片与本轮成片：

| 指标 | 旧全幅（`erp_test/out/20261029-103543_still.png`） | 本轮视口局部 |
|---|---|---|
| Laplacian 方差 | 57.0 | 98.5 |
| Sobel 梯度均值 | 17.94 | 24.56 |

视口局部的高频能量约为全幅方案的 1.7 倍，与计划里“4K 输出不再摊到 9558 宽”的判断一致。两组来自不同轮次的候选，指标只作方向性证据，不是受控实验。

## 4. 发现与遗留

- `still360-local` 模板原有一句“画布左右两侧的冗余带是同一条全景接缝的两份拷贝”，在视口局部下不成立，本轮开跑前已删（vrgen `e46082e`）。旧的全幅验收记录不受影响，它当时是正确的。
- `adopt` 依赖真实轮次（`vrgen result`），无额度时只能手工落 `result.png`；单测用 monkeypatch 覆盖 `_capture`，覆盖的是 argv 与指针写入。
- 计划 §4.1 的 `compare` 步骤没有对应 CLI，前端对比页在 WP4；本轮对比图由临时脚本生成。
- `--scale-fit` 纠偏按计划保持关闭：本轮模型返回比例与视口一致（3840×2160），没有触发。
