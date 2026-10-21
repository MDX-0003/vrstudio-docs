# Patch + videoEdit：只重绘中间动作段的例子

本文用一个具体例子说明 patch 流程如何只抽取源片中间的一段、选一个视角交给 videoEdit 重绘，以及位置和时间为什么能按抽取记录复现。这里记录的是当前实现的行为和一致性原理，不是操作手册的简写版；当前 `merge` 只输出中间段成片，整片时间拼接尚未实现，见 `docs/patch-time-assembly-plan.md`（草案）。

## 例子设定

- 源片：600 帧，60fps，ERP 8000×4000（示例数字，不代表某个真实素材）。
- 动作：白膜骨骼只在第 100–300 帧出现，其他帧没有需要重绘的内容。
- viewport：选择一个固定的 yaw/pitch/fov，画布 1920×1080。
- inner：框住白膜骨骼所在区域，四周保留 viewport 外圈作为背景锚点。
- frames：100–300，闭区间，共 201 帧。

目标是只把这 201 帧、这一个视角交给 videoEdit 重绘，生成结果只替换 inner 区域，并在时间和位置上与抽取时记录的信息一致。

## 普通 videoEdit 的完整流程

1. 新建 patch case，源片是完整视频。case.toml 里记录源文件路径和 sha256。
2. 在 pick 页确定 viewport、inner、frames 三段草稿，点“保存范围”只写 case.toml；这时它们仍然可改。
3. 点“运行抽取”。`vrstudio extract name` 把草稿冻结成 `extracts/<版本>/clip.mp4`、`clip_mask.png`、`clip.json`，并把 `[extract] current` 指向这个版本。冻结之后，已生成版本的几何和时间不再随草稿变化。
4. videoEdit 提交。当前 clip 是整段 viewport 视频，模型看到的是这段 201 帧、带背景外圈的画面；mask 记录 inner，供 merge 融合使用。
5. 采用结果。返回件落到 `extracts/<当前版本>/result.mp4`，adopt 指针写入 case。
6. 运行 merge。merge 读源片、`clip.json` 和 `result.mp4`，重建 viewport 投影，把 AI 结果对齐到 clip 的帧数和 fps，只在 inner 区域融合，再把 viewport 反投影贴回 ERP 画布。
7. 当前代码输出 `out/<抽取版本>.mp4`；新命名方案是 `out/<抽取版本>_space.mp4`。它是 201 帧、完整 ERP 画布（8000×4000），第 i 帧对应源片第 `100 + i` 帧，不是整条 600 帧视频。

## 位置一致性如何保证

- `clip.json` 是冻结后的几何权威：viewport 的 yaw/pitch/fov/width/height，inner 的 x/y/w/h，都由 extract 写入，merge 只读它，不重新解释 case.toml 里的草稿。
- merge 用 `SegmentMaps` 一次性重建 ERP→viewport 和 viewport→ERP 的采样图；inner mask 使用同一份几何。投影规则仍然只在 `vrstudio/patch/projection` 里定义，merge 不复制一套新的几何算法。
- 融合时只替换 inner；viewport 的外圈保留源片原像素，AI 结果的外圈不参与贴回。白膜骨骼在 inner 内，外圈提供背景和光照锚点，所以背景不会因为模型重绘而漂移。
- viewport footprint 之外的画面在段内逐位不变；merge 只处理源片的 `[100, 300]` 段，段外的源片不进入当前输出。
- merge 前校验源片 sha256；源片被换成另一份文件时直接拒绝，避免“几何配错视频”。
- AI 返回分辨率与 viewport 不同时，同比例做等比缩放；比例不一致直接报错，首期不静默拉伸或裁切。

## 时间一致性如何保证

- `[frames] start/end` 是闭区间，`n_seg = end - start + 1`；例子里的 `n_seg` 是 201，不是 200。
- extract 从源片第 `frame_start` 帧开始顺序读取 `n_seg` 帧，写成 clip；clip 的第 0 帧对应源片第 `frame_start` 帧。
- merge 也从源片 `frame_start` 开始读，逐帧写 `n_seg` 帧；输出第 i 帧对应源片第 `frame_start + i` 帧。
- AI 返回件先经过 restore：帧数少了用 RIFE 拉伸或重复最后一帧，帧数多了选择或裁切，fps 标签不对就重新打时间戳；目标是正好 `n_seg` 帧、源片 fps。这个时间契约由 `clip.json` 的 segment 和源片 fps 决定，不由 AI 返回件的容器元数据决定。
- 如果 AI 改变了动作速度，restore 只修帧数和 fps，不修动作语义；动作节奏要靠提示词和模型本身保持。时间一致性保证的是“帧怎么映射回源片”，不是“AI 重绘的动作一定和原片同速”。

## 当前输出和整片的关系

空间合并的输出是“中间段成片”：

- 文件名：`out/<版本>_space.mp4`。
- 输出帧数：`n_seg`，例子是 201。
- 输出画布：完整 ERP 尺寸，例子是 8000×4000。
- 输出时间：从 0 开始，第 i 帧是源片第 `100 + i` 帧。
- 源片第 0–99 帧和第 301–599 帧不在这个文件里。
- 输出帧率就是抽取时记录的 fps，不是 AIGC 返回件的 24fps；AI 返回件在空间合并前已经由 restore 转成 `n_seg` 帧 @ 抽取 fps。

如果交付物是这段动作成片，`_space.mp4` 就是结果。如果交付物是“整条原片，中间替换成 AIGC 结果”，由独立入口 `vrstudio assemble` 把 `_space.mp4` 当作中间输入，再拼接源片前缀和后缀，输出 `out/<版本>_frame.mp4`。空间合并和时间合并是两个独立 CLI，前端在 merge 流程里串联。

如果 `frames` 本来就是整条源片，不调用 `assemble`，只有 `_space.mp4`；这时它本身就是整片长度。下游（对比页、输出选择）优先读 `_frame.mp4`，读不到再读 `_space.mp4`；非整片且只有 `_space.mp4` 时，页面要标注“仅中间段”，不能把它当成整片时间轴。具体见 `docs/patch-time-assembly-plan.md`。

## 时间范围：只重绘 `frames` 本身，不做前后余量

已定：`frames` 精确表示要交给 AIGC 重绘的内容，不做时间上的前后预留。切出 x 帧，就完整重绘 x 帧，再在时间和空间上恢复回去。

- `frames=100–300` 时，clip 是 201 帧，AI 只看到这 201 帧，merge 也只替换这 201 帧。
- 不增加“AI 上下文范围”和“只替换范围”两个参数；当前一个 `frames` 同时承担输入范围和替换范围。
- 动作前后的连续性由提示词、模型和 clip 内的实际画面负责，不靠额外抽取余量帧。
- 如果以后发现模型需要动作前后文才能稳定，再单独讨论是否扩展契约；首期不扩展。

时间余量和前后片段拼接是两件事：拼接解决输出时间轴上缺的前缀/后缀；`frames` 决定中间段本身有多长。首期把 `frames` 定为精确重绘范围，拼接只补 `frames` 之外的原片前后段。

## 复盘和教程要点

- 先区分草稿和契约：case.toml 的 viewport/inner/frames 可改；clip.json 一旦抽取就冻结。改草稿不会改已有版本。
- 先区分段成片和整片：空间合并输出 `_space.mp4`，整片由 `vrstudio assemble` 输出 `_frame.mp4`；整片抽取时只有 `_space.mp4`。
- 先区分来源和几何：源片提供像素，clip.json 提供投影和 inner；merge 不在代码里另写一套投影规则。
- 先区分帧映射和动作语义：restore 保证帧数和 fps，动作速度仍由模型和提示词决定。
- 先区分重绘范围和前后拼接：`frames` 是精确重绘范围，不做余量；前后拼接只补 `frames` 之外的原片段。
