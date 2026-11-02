# 视频重打光：消除重复解码与固定光照缓存

状态：代码已实施，单测与 ruff 已通过；8K 冷/热验收待补（线上重打光进程结束后执行）。
验收见 `docs/test-runs/20261102-relight-decode-cache.md`（待补）。

## 1. 问题

视频重打光一次执行要读多遍视频，而且每遍都是 8K 原始帧：

- 选参考帧扫描：前 91 帧（`MAX_REFERENCE_SCAN=90`，循环实际处理 0..90）。
- 同位检查：整片，逐帧与参考帧比结构重合度。
- 取参考帧原图：从片头顺序解码到参考帧，只为拿这一帧的原分辨率图。
- 正式渲染：整片再读一遍。

378 帧 8K、10 帧小样的报告 `seconds` 是 128.1 秒，其中约 100 秒花在“扫描 91 帧 + 顺序解到第 80 帧”这 172 次解码；SIFT+RANSAC 与引导滤波只有几秒。`docs/test-runs/20261030-relight-space-e2e.md` §8 记录了整段多遍读片约 87 GB，扫描加同位检查约 30 分钟。

用户拍定的边界：

- 重打光素材都是固定机位，删除同位检查，不再为它读一遍全片。
- 视频与氛围图都没换时，复用参考帧与相似变换；氛围图一换，重新从视频里选参考帧。
- 只缓存变换，不缓存 2K 光照场。

## 2. 方案

### 2.1 删除同位检查

- 删除 `relight/align.py` 的 `MIN_FRAME_HOLD` 与 `frame_hold()`。
- `resolve_reference` 不再读全片比较其余帧，`FixedLight` 去掉 `frames_checked`/`min_hold`/`static`。
- 视频报告去掉 `frames_checked`/`min_hold`；前端“上次运行”面板去掉“同位检查”一行。
- 只适用于固定机位；机位移动仍在本期范围外。

### 2.2 单遍取参考帧

- 自动选帧在更新最佳帧时同时保留该帧的原分辨率图，光照场直接用它，删掉 `_reference_fields` 的第二次读片。
- 显式 `--ref-frame` 改为按帧号 seek（`open_frames(index=N)`），不再从片头顺序解码；索引越界仍按参数错退出 2。
- `fps` 未知时回退顺序解码，保证仍能取到目标帧。

### 2.3 固定光照缓存

- 落点：`cases/<case>/derived/relight/fixed.json`。`derived/` 是文档化的可删缓存，不进文件视图，也不会命中 `out/*.mp4`、`out/*.png` 或 `*_pad.json`。
- 内容：解析后的参考帧号、未对齐重合度、`AlignResult` 的全部字段与全精度矩阵（含 dtype）。
- 键：GT 身份（`[[assets]].sha256`，缺失时 `size + mtime_ns`）、氛围图身份（同上）、请求的 `ref_frame`（`"auto"` 或整数）、`CACHE_VERSION`。
- 命中：跳过 91 帧扫描与 SIFT，按缓存的参考帧号 seek 一帧，重算光照场。
- 未命中：扫描 + SIFT + 光照场，然后原子写缓存（`.tmp` + `os.replace`）。
- 失效：换 GT、换氛围图、换 `ref_frame`、升级 `CACHE_VERSION` 都自动 miss；缓存损坏或写入失败静默重算，不影响出片。
- 只在 `--case` 模式启用；显式 `--gt/--atmo` 不缓存，不新增全局缓存目录。

### 2.4 小样接受显式参考帧

- `web/app.py::_op_argv` 在 `--sample` 时也传 `--ref-frame`；`--crf` 仍只给整段。
- 缓存键仍包含参考帧；自动与显式是两个不同的键。

### 2.5 运行时间与分段计时

- 视频报告新增 `kind`（sample/full）、`started_at`/`finished_at`（本地时区 ISO 8601）、`cache`（enabled/hit/load）与 `timing`。`started_at` 与产物文件名的时间戳同源，`finished_at = started_at + seconds`。
- 准备阶段：`cache_load`、`scan`、`read`、`align`、`fields`；小样：`sample_decode`/`sample_compose`/`sample_write`；整段：`render_decode`/`render_compose`/`render_write`/`render_flush`/`render_total`。
- `render_write` 是写 ffmpeg 管道的耗时，编码在 ffmpeg 进程里并行进行，收尾等待记在 `render_flush`；所以整段渲染总时间要加 `render_flush` 才完整。
- `/api/case` 的 relight 负载新增 `sample_report`，前端在“上次运行”标题与小样标题上直接显示运行时间；分段耗时作为次要信息。老报告没有时间戳时回退到产物文件 mtime。
- 计时只进报告，不进缓存文件；缓存键与失效规则不变。

## 3. 代码落点

- `vrstudio/src/vrstudio/relight/cache.py`：新增 `CACHE_VERSION`、`CacheKey`、`CachedFixed`、`cache_path`、`load`、`save`。
- `vrstudio/src/vrstudio/relight/align.py`：删除同位检查；相似变换的唯一权威点不变。
- `vrstudio/src/vrstudio/cli/relight.py`：`resolve_reference` 单遍取帧与缓存命中路径；`RelightInputs` 承载缓存身份；`_relight_video` 读写缓存；报告去掉同位检查两项，并加入 `kind`/`started_at`/`finished_at`/`cache`/`timing`。
- `vrstudio/src/vrstudio/web/app.py`：小样透传 `--ref-frame`；`/api/case` 的 relight 负载新增 `sample_report`。
- `vrstudio/frontend/src/views/wizard/RelightStep.vue`：报告类型与面板去掉同位检查；标题显示运行时间，分段耗时作为次要信息。

## 4. 验收

- `uv run pytest -m "not slow"` 全绿；`uv run ruff check .` 干净。
- 单测：
  - 缓存 `save`/`load` 往返，矩阵 `np.array_equal`，键/版本/损坏文件返回 `None`。
  - 自动选帧只开一次视频；显式参考帧只取目标帧；缓存命中时 `estimate_similarity` 不被调用。
  - 冷跑与热跑的 `LightFields` 逐位相等；小样 PNG 与整段输出帧逐位相等。
  - 报告含 `kind`/`started_at`/`finished_at`/`cache`/`timing`；`timing.total == seconds`；缓存命中时 `scan == align == 0`；`/api/case` 暴露 `sample_report`。
- 8K 真实素材（本次最后一次验收）：
  - 378 帧、`i5` 氛围图：冷跑 `--sample 10` 与热跑各一次，记录墙钟、报告 `seconds` 与各阶段耗时。
  - 换氛围图 `i2` 冷跑一次，确认 cache miss 并重新选帧。
  - 20 帧整段冷/热各一次（`--crf 0`），比较解码帧 maxdiff 为 0，记录 `render_*` 分段。
- 浏览器：连续点两次“先看 5 帧小样”，第二次日志显示 cache hit；两个面板都显示运行时间；整段与报告正常；小样显式参考帧生效。

## 5. 不做

- 不缓存 2K 光照场（用户选择只缓存变换；热跑仍 seek 一帧并重算光照场）。
- 不在氛围图变化时复用旧参考帧（按用户要求重新选帧）。
- 不把扫描改成 2K 解码（会改变重采样与阈值依据，另立项）。
- 不新增 CLI 开关；报告字段的计时与时间戳见决策 65。缓存自动生效，损坏或失败静默重算。

## 6. 风险与回退

- 如果实测 seek 取到的不是扫描时的同一帧，冷/热光照场会差一点。回退方案是把扫描得到的 2K 参考帧一起缓存（约 2–4MB），热跑直接用它做 `estimate_fields` 的 GT 输入，仍不缓存光照场。
- 缓存键里的 `sha256` 取自 case.toml，文件被原地替换但 sha 未更新时，靠 `size + mtime_ns` 失效；两者都没变时可能命中旧缓存，属于可接受的低概率事件。
