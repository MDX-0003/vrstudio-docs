# 8K 重打光合成性能计划

状态：2026-11-04 用户认可四项优化方向，要求先落地文档以便追溯优化前后的方案对比。
关联：决策 80，`docs/plan/relight-video-plan.md`、`docs/plan/relight-decode-cache-plan.md`。

## 1. 现状与瓶颈

`cases/RL_video_02` 的一次整段重打光（GT 8192×4096、378 帧；氛围视频 297 帧）报告：

- `render_compose` 1196.53 秒，占总额 1409.50 秒的 85%，平均 3.17 秒/帧。
- `render_decode` 105.49 秒，`render_decode_atmo` 84.21 秒，合计约 13.5%。
- `render_write` 20.95 秒，`render_flush` 1.16 秒。
- 对齐与光照场都是 0 秒，固定缓存命中。

瓶颈在逐帧合成，不在解码、对齐或编码。

## 2. 逐项实测

用该 case 的真实 8K GT 帧（8192×4096，单帧 uint8 BGR 约 100.7 MB）单独计时。

一帧视频氛围的完整 `_compose_pair`（视频氛围逐帧估光场，不只是 `apply`）：

- `work_frame`（GT 与氛围各缩到 2K）：6 ms。
- `warp_with_matrix`（2K）：1 ms。
- `structure_correlation`：17 ms。
- `estimate_fields`（2K 上 6 次引导滤波）：344 ms。
- `light_compose`（2K 光场放大到 8K 并求幂）：415 ms。
- `LightCompose.apply`：约 1234 ms/帧。
- `soft_clip`：约 901 ms/帧。

合计约 2.9 秒/帧；日志里的 3.17 秒包含与解码、编码进程的带宽争用。

`LightCompose.apply` 的内部：`srgb_to_linear` 66 ms，`np.einsum` 342 ms，乘 `gain` 约 300 ms，乘 `visibility` 62 ms，`clip` 59 ms，`linear_to_srgb8` 405 ms。

`soft_clip` 的内部：转 float32 并除以 255 197 ms，算亮度 160 ms，乘回比例并乘 255 299 ms，`clip` 后转 uint8 473 ms。

一张 float32 BGR 帧是 402 MB。`apply` 与 `soft_clip` 每帧要做十几次全帧读写，单帧内存流量约数 GB。算术本身不复杂，成本在内存带宽与每帧新申请大数组的缺页。

## 3. 改动（像素等价）

四项都只替换实现，不改变公式与运算顺序，目标是逐帧 `maxdiff == 0`。

1. **去掉 `apply` 里多余的类型转换与全帧临时数组**：`srgb_to_linear` 对 uint8 输入跳过 `clip`/`astype` 的两次复制；LUT 结果本来就是 float32，不再 `.astype(np.float32)`；`linear_to_srgb8` 改为就地乘 65535、clip、转 uint16、查 LUT，并去掉多余的一次 `clip(…, 0, 1)`（65535 的 clip 已覆盖两端）。
2. **`gain` 与 `visibility` 两次乘法就地执行**：`einsum` 的结果直接 `*=` `gain`、`*=` `visibility`，不创建两张 402 MB 临时数组；与原来的 `einsum * gain * visibility` 保持同一运算顺序。
3. **`light_compose` 的求幂就地覆写**：`np.power(..., out=...)` 直接改写已放大的光场，不再生成两份新数组。415 → 360 ms。
4. **`soft_clip` 只对过曝像素做浮点运算**：先按通道算亮度，只对 `y > knee` 的像素走原来的浮点公式；其余像素直接 `copy` 返回。`uint8 → float32 → uint8` 的往返对 0–255 全部精确，已逐值验证。

同一进程内交替测量的 A/B（机器当时处于高负载，绝对时间比早期微测高）：

- `apply`：1892 → 1830 ms（1.03x）。
- `soft_clip`：1403 → 454 ms（3.09x）。
- `light_compose`：418 → 360 ms（1.16x）。

合计单帧约省 1.1 秒。最终代码在真实 8K 素材上跑 `--sample 10`，`sample_compose=22.22s`，即 **2.22 秒/帧**；日志基线是 3.17 秒/帧。按同样的争用比例估算，整段 378 帧从约 23.5 分钟降到约 17 分钟。收益主要来自 `soft_clip`；`apply` 里 `einsum` 与 8-bit 量化仍是主体。

## 4. 评估后不采用的方案

- **`np.einsum` 换成 `cv2.transform`**：单独测 342 → 60 ms，但两者在 float32 上有 5.96e-8 的末位差异，乘上 `gain`/`visibility` 放大后真实帧出现 `maxdiff = 1`（约 771 万个像素的矩阵结果不同）。为了守住 `maxdiff == 0`，不采用。
- **把 `gain × visibility` 预先合成一个场**：单帧乘法从两次降到一次，快约 250 ms，但 `(a×g)×v` 与 `a×(g×v)` 的浮点结合顺序不同；在真实帧上 `maxdiff = 1`。不采用。
- **预分配缓冲复用**：`apply` 从 861 ms 变成 665 ms（仅融合版本）但需要额外的 `copyto` / `take(out=)` 遍；与保持精确的两次乘法组合后不再有优势，且在 8K 上预分配数组长期驻留反而增加内存压力。
- **按行分块**：512 行 943 ms、256 行 1063 ms，比整帧慢。
- **用最大通道预筛 `soft_clip` 候选**：474 ms，比按通道算亮度的 444 ms 慢。
- **共享 `estimate_fields` 的引导滤波统计量**（guide 的均值与方差只算一次，6 个通道复用）：预计省约 100 ms，是精确改动，但本轮不做，留作下一步。
- **按行多线程**：理论上有 2–4 倍空间，但会和 8K 解码、x264 的线程争 CPU，复杂度高；先做上面四项，再评估。

## 5. 验收

1. `tests/test_relight.py` 的既有断言全部通过，包括 `strength=0` 输出与 GT 逐位一致、`light_compose` 与 `relight` 一致、`soft_clip` 单调有界与中间调不变。
2. 新增单元测试：在随机小图上，把 `LightCompose.apply` 与「旧公式的参考实现」比较，`maxdiff == 0`；把 `soft_clip` 与旧实现比较，`maxdiff == 0`，覆盖存在过曝像素的图。
3. vrstudio `uv run pytest` 全绿、`uv run ruff check .` 干净。
4. 真实 8K 素材：用 `relight --sample 10` 记录优化后的 `sample_compose` 与分项计时，与日志的 3.17 秒/帧对照。像素等价性由第 2 条的参考实现对照保证；若要做整段成片对照，两次都用 `--crf 0`，不拿 crf18 成片与未编码像素比较。
5. 提交后把优化后的 `--sample` 计时写进本文的「实施结果」一节，保持前后可追溯。

## 6. 改动清单

- `vrstudio/src/vrstudio/relight/fields.py`：新增就地版线性光到 8-bit 转换；`srgb_to_linear` 对 uint8 输入跳过复制。
- `vrstudio/src/vrstudio/relight/compose.py`：`LightCompose.apply` 去掉多余复制与类型转换、两次乘法就地执行；`light_compose` 就地求幂；`soft_clip` 改为过曝像素路径。
- `vrstudio/tests/test_relight.py`：补 `apply` 与 `soft_clip` 的旧公式参考实现对照测试。

## 7. 实施结果（2026-11-04）

- 单元测试：`tests/test_relight.py` 的旧公式对照在随机图与真实尺寸上 `maxdiff == 0`；`strength=0`、`light_compose` 与 `relight` 一致、`soft_clip` 中间调不变等既有断言全部通过。
- 真实 8K 素材：`--sample 10` 的 `sample_compose=22.22s`（2.22 秒/帧），同次 `sample_decode=8.34s`、`sample_decode_atmo=12.59s`、`sample_write=5.25s`、总计 51.20s。
- 与日志基线的对照：`render_compose` 3.17 秒/帧 → 约 2.2 秒/帧；整段预计约 23.5 分钟 → 约 17 分钟。
- 说明：`np.einsum → cv2.transform` 在单独微测里快 282 ms，但真实 8K 帧经 `gain`/`visibility` 放大后出现 `maxdiff = 1`，已回退，不进入交付路径。
