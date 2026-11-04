# 视频 recompose 性能计划

状态：2026-11-04 用户认可三项改动（A、B、C），C 指定按 48 帧抽样；本文记录实测、设计与验收口径。
关联：决策 77、`docs/decisions.md`、`docs/architecture.md`、`vrstudio/src/vrstudio/redraw/recompose_core.py`、`vrstudio/src/vrstudio/cli/recompose.py`。

## 1. 实测口径与数据

测试素材用仓库里现成的真实链路：输入 `vrstudio/cases/ship_01/result.mp4`（2208×944、HEVC、185 帧），清单 `vrstudio/cases/ship_01/seedance_input_pad.json`（画布 4668×2000、输出 4000×2000、P=668）。机器为 32 逻辑核，计时脚本不进入仓库。

4K 档按阶段串行计时，单帧成本如下：

- 解码：6 ms，独立进程，与主循环重叠。
- `restore_canvas`（lanczos4 2208×944 → 4668×2000）：11–15 ms。
- `recompose`：132–136 ms，其中 `R.astype(float64)` 单独占 32 ms。
- `finalize`（整帧 `rint+clip+astype`）：60–178 ms。
- `SeamAccumulator.add`：20–55 ms。
- 写管道 `tobytes()`：5 ms。
- 编码 libx264 crf18 veryfast 4000×2000：13 ms，独立进程，与主循环重叠。

合计实测 245 ms/帧，即 4.1 fps。仓库日志 `vrstudio/logs/web_recompose_ship_01_20261022-162433.log` 记录闸门段 7 fps、渲染段 2.8 fps，量级一致。闸门段每帧约 124 ms，其中 `circular_translate` 占 80–178 ms。

8K 档用 7000×3000 合成帧放大到 8960×3840 画布、输出 7680×3840：

- 当前计算链路 753 ms/帧（1.33 fps），优化原型 190 ms/帧（5.25 fps）。
- `circular_translate` 610 ms/帧，其中 MAE 曲线 471 ms（搜索半径 ±320，共 641 次移位）。
- 真实 8K 解码：8192×4096 H.264 为 311 ms/帧，7000×3000 为 127 ms/帧。
- 8K 编码 crf18 veryfast 为 242 ms/帧，ultrafast 为 74 ms/帧。

## 2. 瓶颈根因

1. R 区全程参与 float64 运算，但结果就是原字节。R 占输出宽度的 3332/4000，`recompose` 把它转成 float64 拼进输出，`finalize` 再对整帧做 `rint/clip/astype`；按现有数学，这段是恒等变换，不改变任何一个字节。
2. 每帧新申请大数组，开销主要来自缺页而不是算术。8K 上同样一次 `rint+clip+cast`，新申请缓冲 160 ms，复用预分配缓冲 28 ms；`np.empty` 本身耗时 0，说明成本发生在首次写入的缺页与分配器切换。4K 上对应 59.5 ms 与 4.6 ms。
3. 闸门段对每一帧都做配准。`d_star_mode` 默认 `clip_median`，最终只取一个段级 d*，却为每一帧跑完整搜索；8K 上 610 ms/帧，570 帧的片子光闸门段就要约 6 分钟。
4. 8K 上编码与解码成为剩余天花板。解码 311 ms/帧与 Python 主循环通过管道部分重叠，编码 242 ms/帧同样重叠，单帧下限约由 `max(解码, 计算)` 决定。

## 3. 改动设计

**A. R 区直通，只对混合带量化**

混合带继续在 float64 里按原公式计算，结果第一次也是唯一一次舍入成 uint8；R 区直接从画布切片拷贝。新增视频入口 `recompose_u8(canvas, spec, buffers)`，`recompose` 与 `finalize` 保持原样，静图与现有测试不受影响。`repair == "feather"` 时仍走原来的 float 装配路径，保证罕见配置的结果不变。

字节等价性已在 21 帧真实素材与一帧 `d*=7` 的用例上验证：新旧输出 `max abs diff = 0`。

**B. 渲染循环复用缓冲**

`ComposeBuffers` 在每次运行开始时创建，持有混合累加、临时乘积、带区 uint8、移位带区与整帧 uint8；所有运算带 `out=` 参数，换帧时只覆写不复用。缓冲是局部对象，不作为模块级缓存。混合公式与加法顺序保持不变，因此结果与 A 之前的路径逐字节相同。

**C. 闸门段按帧分析**

新增配置键 `[recompose] gate_max_frames = 48`，0 表示分析全部帧。总帧数不超过该值时行为不变；超过时按 `np.linspace(0, total-1, count)` 取整去重，得到均匀分布的索引，只对这些帧做 `circular_translate` 与基线统计。解码仍是顺序读完，抽样只跳过分析与统计，避免逐帧 seek 在长 GOP 上的前向解码代价。

报告里的 `frames_used` 因此等于实际分析的帧数（最多 48），`d_star_mode` 的中位数与闸门结论都基于这批均匀样本。

## 4. 预期收益

- 4K（ship_01 这类）：渲染段 4.1→12.1 fps；闸门段从每帧 124 ms 的分析降到约 48/185 的比例；整条 recompose 从日志里的约 92 秒降到约 20 秒量级。
- 8K：计算段 1.33→5.25 fps，端到端受解码 311 ms 与编码 242 ms 限制，约 2 倍提升；闸门段的分析成本降到可忽略，剩余主要是顺序解码。
- 编码档位与解码路径本轮不动；8K 上若要继续提速，需要另立决策讨论编码 preset 或硬件编码。

## 5. 验收与门禁

1. 字节一致性：同一帧在相同 `d_star`、`endpoint_lock_px` 与 `repair=off` 下，`recompose_u8` 与 `finalize(recompose(...))` 的 `max abs diff` 必须为 0；测试覆盖 `d_star` 为 0 与非 0、端点锁为 0 与非 0、缓冲跨帧复用、以及 `repair="feather"` 的回退路径。
2. 抽样正确性：`_sample_indices(total, count)` 在 `total > count` 时返回 count 个递增且不重复的索引，在 `total <= count` 时返回全部索引。
3. 门禁：vrstudio `uv run pytest` 全绿、`uv run ruff check .` 干净。
4. 实测：在 ship_01 上重跑 `vrstudio recompose`，记录闸门段与渲染段的 fps，与本文第 1 节的基线对照。

## 6. 改动清单

- `vrstudio/src/vrstudio/redraw/blend.py`：新增带输出缓冲的 `blend_into`，`blend_block` 改为调用它。
- `vrstudio/src/vrstudio/redraw/recompose_core.py`：新增 `ComposeBuffers` 与 `recompose_u8`。
- `vrstudio/src/vrstudio/cli/recompose.py`：渲染循环改用 `recompose_u8`；闸门段按 `gate_max_frames` 抽样。
- `vrstudio/config/default.toml` 与 `vrstudio/src/vrstudio/config.py`：新增 `recompose.gate_max_frames`，两处保持一致。
- `vrstudio/tests/`：新增字节一致性与抽样函数测试。
