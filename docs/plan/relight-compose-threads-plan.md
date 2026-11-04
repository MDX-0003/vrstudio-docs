# 8K 重打光合成多线程与读帧传输计划

状态：2026-11-04 用户认可「先传输、再线程化」的顺序，并要求把内存实例的生命周期管理作为验收项。
关联：决策 82、决策 80（上一轮去复制优化）、`docs/plan/relight-8k-compose-perf-plan.md`、
`docs/plan/relight-decode-cache-plan.md`。

## 1. 现状

`cases/RL_video_02` 的整段报告（`out/20261104-154033_relit.json`）是 378 帧、
1409.50 秒（23.5 分钟），折合 3.73 秒/帧。决策 80 的四项去复制改动把单帧压到
2.22 秒（`--sample 10` 实测），按同样的争用比例外推约 14–17 分钟。

在真 8K 帧（8192×4096，单帧 uint8 BGR 约 100.7 MB）上逐项重测，单帧预算如下：

- `LightCompose.apply`：1106 ms；`soft_clip`：356 ms。
- `estimate_fields`：335 ms，其中 6 次引导滤波串行 247 ms。
- `light_compose`：364 ms，其中两次 `np.power` 各 192 ms，`cv2.resize` 各 17 ms。
- 读帧：GT 298 ms、氛围 225 ms（`FrameReader` 的 `BufferedReader.read(整帧)`）。
- x264 veryfast 编码：真实内容 76 ms/帧，不是瓶颈。

这说明 11 分钟量级的瓶颈已经不在算术本身，而在三处可以分别处理的地方：整帧读管道的
系统调用粒度、逐像素运算的单线程执行、以及每帧新申请大数组的缺页。

## 2. 改动

### 2.1 读帧传输改为分块 `os.read`

`FrameReader` 现在对每个 100 MB 帧调用一次 `BufferedReader.read(整帧)`。Windows 下实测
298 ms/帧；改成 64 KB 的 `os.read` 循环后是 62 ms/帧，字节内容与像素路径完全不变。
更大块反而更慢（4 MB 读实测 1719 ms/帧），所以块大小固定在 64 KB，不暴露成配置。

每帧分配一个独立的 `np.empty` 缓冲，**不复用**。现有调用方会保留帧（参考帧扫描、小样、
`list(reader)` 的测试），复用缓冲会让上一帧被下一帧覆盖；生命周期交给 Python 的引用计数，
生成器本身不持有上一帧。

`FrameWriter.write` 用 `memoryview` 直接写管道，不再 `.tobytes()` 复制一份 100 MB。

### 2.2 逐像素计算按行带分线程

新增 `vrstudio/relight/bands.py`：

- `workers_for()`：`min(16, cpu_count - 4)`，下限 1；留 4 个逻辑核给 ffmpeg 解码、
  x264 编码与系统。只有一个用法的参数不新增 CLI 项。
- `run_bands(height, fn, pool, workers)`：把行区间切给线程池，按行顺序返回结果；
  `pool` 为 `None` 时串行执行，供测试与单核机器使用。

四个调用点：

- `LightCompose.apply`：每个行带自己做 LUT、`einsum`、两次就地乘法和 8-bit 量化，
  结果写入预分配的输出数组。
- `soft_clip`：每个行带只对本带做过曝判定与浮点计算。
- `estimate_fields`：6 次 `guided`（3 个 GT 通道 + 3 个氛围通道）并行，结果按原顺序
  `np.stack`。每次调用仍然完整算自己的引导统计量，不共享中间量（共享统计量是下一轮
  的独立改动）。
- `light_compose`：`gain` 与 `visibility` 的两次 `np.power` 分带就地覆写。

线程池由渲染函数创建一次，`with ThreadPoolExecutor(...)` 包住整段渲染，退出时 join；
不在模块级保存线程池、不保存行带缓冲。线程数小于 2 时直接用串行路径，不创建线程池。

不采用多进程：8K 帧经过进程间通信要么复制 100 MB、要么上共享内存，复杂度与收益不匹配；
numpy/cv2 在这些运算里会释放 GIL，线程已经能并行。

### 2.3 内存生命周期规则

这次改动引入并发和更大的瞬时缓冲，内存管理按下面七条执行：

1. **帧缓冲一帧一个，谁产出谁负责**。`FrameReader` 每帧新建数组并 yield，不维护缓冲池；
   调用方丢掉引用即释放。测试保证两帧不是同一块内存。
2. **线程池一次渲染一个**。只在渲染函数内创建，`with` 退出时关闭并 join；异常路径同样。
   不建立模块级线程池，避免进程生命周期内挂着线程并间接持有帧。
3. **行带任务只持有自己的切片**。任务函数内申请浮点临时数组，返回后由引用计数释放；
   输出数组在任务外预分配，按行区间写入，不用 `np.concatenate` 再复制一整帧。
4. **单帧峰值有明确预算**：输入 100 MB + 输出 100 MB + 浮点行带合计 402 MB +
   8K `gain`/`visibility` 268 MB + 余量，约 1 GB。16 个行带的临时数组总量与单线程
   整帧相同，不随线程数线性增长。
5. **参考帧样本不再跨整段持有**。原实现把小样帧留到整段结束才算过曝比例；改为在
   参考帧那一刻算完，只留一个浮点数。
6. **解码进程在退出路径上收干净**。读帧提前停止时关闭 stdout/stderr 并 terminate，
   再 wait；正常读完时读空 stderr 并检查退出码。异常路径不能留下 ffmpeg 进程。
7. **本轮不加队列预取**。读者与计算仍在一帧粒度上交替；将来如果加，队列上限固定为
   1–2 帧，并在文档里单独记预算。

### 2.4 像素等价性

所有并行点都是逐像素独立、按行切开，运算顺序不变；`np.einsum` 在 float32 上实测等价于
「逐项乘再按 k 顺序加」，不使用 FMA，所以分带与整帧结果逐位相同。`np.power`、LUT 查表、
就地乘法、`clip` 与 `uint16` 截断都是逐元素运算，同样不受切带影响。

验收以 `maxdiff == 0` 为准：分带结果与整帧结果比较，覆盖多个线程数和过曝图。

## 3. 预期

按原型实测（60 帧真素材，含逐帧估光场、光场放大、合成与编码）：

- 32 线程：668 ms/帧，约 4.2 分钟/378 帧。
- 16 线程：703 ms/帧；8 线程：770 ms/帧。

原型与新实现同为逐位一致。整段实际耗时还要叠加机器负载与磁盘速度，
预期落在 4–6 分钟，相对当前 23.5 分钟约 4–5 倍。

## 4. 评估后不做

- **GPU**：本轮不做。RTX 5080 能跑，`np.einsum` 的累加顺序也可以在 CUDA 上用
  `__fmul_rn`/`__fadd_rn` 逐位复现；但 8K H.264 的 NVENC 实测打不开（消费级上限
  4096×4096），编码仍留在 CPU，而且要为 `apply` 维护第二套 kernel 与无 GPU 回退。
  等本轮实测数字出来再决定是否立项。
- **多进程**：理由见 2.2。
- **4 MB 大块读**：实测比整帧读还慢。
- **线程数配置项**：线程数由 `workers_for()` 按机器推导，不新增 CLI 参数；需要串行时
  测试直接传 `pool=None`。

## 5. 验收

1. 新增单元测试：`apply`、`soft_clip`、`light_compose`、`estimate_fields` 的分带结果
   与串行结果逐位相同，覆盖 1/2/3/7 个行带与存在过曝像素的图。
2. 新增生命周期测试：渲染结束后没有新增存活线程；`FrameReader` 相邻两帧不是同一块内存，
   且读完关闭后仍可访问已取出的帧。
3. 既有 `tests/test_relight.py`、`tests/test_relight_video.py`、
   `tests/test_relight_atmo_video.py`、`tests/test_videoio_smoke.py` 全部通过。
4. 真实 8K 素材：`relight --sample 10` 记录 `sample_compose`；整段跑一次记录
   `timing` 各项，与 3.73 秒/帧的台账对照。
5. `uv run pytest` 全绿、`uv run ruff check .` 干净。

## 6. 改动清单

- `vrstudio/src/vrstudio/media/videoio.py`：读帧改 64 KB `os.read`，每帧独立缓冲；
  `FrameWriter.write` 用 `memoryview`。
- `vrstudio/src/vrstudio/relight/bands.py`（新增）：线程数推导与行带调度。
- `vrstudio/src/vrstudio/relight/compose.py`：`apply` 与 `soft_clip` 接受
  `pool`/`workers`，分带执行并写入预分配输出。
- `vrstudio/src/vrstudio/relight/fields.py`：`estimate_fields` 并行 6 次引导滤波。
- `vrstudio/src/vrstudio/cli/relight.py`：三条渲染路径创建并关闭线程池；参考帧的
  过曝统计改为即时计算，不再持有 100 MB 样本。
- `vrstudio/tests/test_relight.py`、`tests/test_relight_video.py`、
  `tests/test_videoio_smoke.py`：分带等价、生命周期与读帧缓冲独立性。
- `docs/decisions.md`：决策 82。

## 7. 风险与回退

- 线程数过多会让 x264 与解码抢内存带宽；上限 16 且留 4 核，实测 8/16/32 线程的差异在
  10% 以内。若真实整段出现反向收益，回退到串行只需不传 `pool`，像素路径不变。
- `os.read` 的分块行为在 Windows 上验证过，POSIX 上语义相同但未实测；CI 不跑 ffmpeg
  相关用例，本地门禁覆盖。
- 逐帧光场仍然是 335 ms 的大头，本轮只并行、不改变算法；如果整段仍不够快，
  下一轮再做共享引导统计量与 GPU 评估。

## 8. 实施结果（2026-11-04）

真实素材 `cases/RL_video_02`（8192×4096、378 帧，强度 0.8 / 局部明暗 0.4 / 高光软裁切）。

- 小样 `--sample 10`：`sample_compose=6.87s`，0.69 秒/帧；改动前同一路径 3.18 秒/帧。
  10 张小样与改动前的 PNG 逐像素对照，**全部 `maxdiff == 0`**。
- 整段：`render_compose=219.92s`（0.58 秒/帧）、`render_decode=20.01s`、
  `render_decode_atmo=16.21s`、`render_write=18.13s`、`render_total=275.77s`、
  `total=276.40s`，即 **4.6 分钟**。台账基线是 1409.50 秒（23.5 分钟），快 5.1 倍。
- 整段成片与改动前的成片 **SHA256 完全相同**（`976F0666…8DBD`，54,111,217 字节），
  说明像素与编码都没有变化。
- 进程峰值工作集 1.71 GB（含 16 个行带、8K 光场与输入/输出帧），与 2.3 节的预算一致。
- 单元测试新增 5 条（分带 `apply`/`soft_clip`/`light_compose`/`estimate_fields` 的逐位
  等价、线程数推导）、2 条线程不残留、1 条读帧缓冲独立；`uv run pytest` 全绿，
  `uv run ruff check .` 干净。
