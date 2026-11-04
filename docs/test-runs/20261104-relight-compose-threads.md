# 8K 重打光合成多线程与读帧传输验收（2026-11-04）

关联：决策 82，方案见 `docs/plan/relight-compose-threads-plan.md`。

## 1. 结论

`cases/RL_video_02`（8192×4096、378 帧）的整段重打光从 **1409.50 秒（23.5 分钟）降到
276.40 秒（4.6 分钟）**，快 5.1 倍；成片与原实现 **SHA256 完全相同**。改动只有两处：
读帧管道改 64 KB 分块、逐像素计算按行带分线程。

## 2. 环境

- CPU：i9-14900KF（24 核 32 线程），内存 64 GB。
- 显卡：RTX 5080 16 GB（本轮未参与计算）。
- 素材：`cases/RL_video_02/assets/v1_20261030-182248_space.mp4`（GT，8K 30fps 378 帧）、
  `v5_360-closure-e5257812.mp4`（氛围视频，8K 24fps 297 帧）。
- 参数：strength 0.8、local-shading 0.4、`--highlight-clip`；编码默认
  libx264 veryfast crf 18 yuv420p。

## 3. 改动落点

- `media/videoio.py`：`FrameReader` 用 64 KB `os.read` 循环读帧，每帧独立 `np.empty` 缓冲；
  `FrameWriter.write` 用 `memoryview` 直接写管道。
- `relight/bands.py`（新增）：`workers_for()`、行带切分、`run_bands` / `run_tasks`、
  `executor()`。
- `relight/compose.py`：`apply`、`soft_clip` 支持 `pool`/`workers`，输出预分配。
- `relight/fields.py`：6 次引导滤波并行。
- `cli/relight.py`：三条渲染路径创建并关闭线程池；参考帧过曝统计即时算完。

## 4. 实测

### 4.1 单帧分项（真 8K 帧，改动前 → 改动后）

- `apply`：1106 → 125 ms（32 线程，`maxdiff == 0`）。
- `soft_clip`：356 → 156 ms。
- 6 次引导滤波：247 → 72 ms（16 线程，结果逐位相同）。
- `light_compose` 两次求幂：384 → 64 ms。
- 读帧：GT 298 → 62 ms/帧，氛围 225 → 43 ms/帧。
- x264 veryfast 真实内容编码：76 ms/帧，未成为瓶颈。

### 4.2 小样

`--sample 10`：`sample_compose=6.87s`（0.69 秒/帧），改动前同一路径 3.18 秒/帧。
10 张小样与改动前的 PNG 逐像素对照，**全部 `maxdiff == 0`**。

### 4.3 整段

报告 `total=276.40s`：

- `render_compose=219.92s`（0.58 秒/帧，原 1196.53 秒）。
- `render_decode=20.01s`（原 105.49 秒）。
- `render_decode_atmo=16.21s`（原 84.21 秒）。
- `render_write=18.13s`、`render_flush=1.39s`、`render_total=275.77s`。
- 对齐与光场准备命中缓存，均为 0。

### 4.4 逐位对照

整段成片 `20261104-171834_relit.mp4` 与改动前的 `20261104-154033_relit.mp4`：

- SHA256 相同：`976F06669B437405C2F6597B2B031EE5D43D66F14A1D96213082B169997C8DBD`。
- 字节数相同：54,111,217。

### 4.5 内存

渲染进程峰值工作集 **1.71 GB**（稳定态约 0.6–0.9 GB）。构成与方案预算一致：
输入帧 100 MB + 输出帧 100 MB + 16 个行带的 float32 临时数组合计 402 MB +
8K `gain`/`visibility` 268 MB + 2K 光场与 6 路引导滤波临时量。

## 5. 内存生命周期逐条对账

1. 帧缓冲一帧一个：`FrameReader` 每帧 `np.empty`，测试断言相邻两帧地址不同、改第二帧
   不影响第一帧。
2. 线程池一次渲染一个：`_relight_video`、`_render_pair`、`_write_samples*` 各自创建，
   `finally` 里 `shutdown(wait=True)`；两条 CLI 测试断言渲染后没有存活的
   `ThreadPoolExecutor` 线程。
3. 行带任务只持有自己的切片：任务内临时数组随返回释放；输出数组预分配、按行写入，
   没有整帧 `concatenate`。
4. 单帧峰值：实测 1.71 GB，与预算相符。
5. 参考帧样本：过曝比例在参考帧那一刻算完，只保留浮点数，不再跨整段持有 8K 帧。
6. 解码进程：`FrameReader.__exit__` 关闭 stdout/stderr，未读完则 terminate 再 wait。
7. 队列预取：本轮未加；读者与计算仍按一帧交替。

## 6. 门禁与未做

- `uv run pytest`：全绿（新增 8 条用例）。
- `uv run ruff check .`：干净。
- 本轮未做 GPU。8K H.264 的 NVENC 实测报 “No capable devices found”（消费级上限
  4096×4096），1080p 正常、8K HEVC 正常；GPU 只对 `apply`/`soft_clip` 有收益，
  需要新增 CuPy 与第二套 kernel，留待后续单独评估。
- 剩余大头是逐帧估光场（约 180 ms/帧）与 8K 光场放大求幂；下一轮若继续优化，
  先做共享引导滤波统计量，再评估 GPU。
