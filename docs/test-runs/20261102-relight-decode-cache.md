# 视频重打光：去重、缓存与运行计时验收

记录时间：2026-11-02。背景：决策 64（删除同位检查、缓存参考帧与相似变换）、决策 65（运行时间与分段计时）；方案见 `docs/plan/relight-decode-cache-plan.md`。结论：378 帧 8K 小样冷跑 66.6 秒、热跑 30.3 秒（改动前同一组输入为 128.1 秒）；20 帧整段冷/热输出逐帧 maxdiff 0；换氛围图会命中不到缓存并重新选帧。

## 1. 落点

- vrstudio `f7eb0e6`：删除同位检查、单遍取参考帧、`relight/cache.py`、小样透传 `--ref-frame`。
- vrstudio `def40ce`：报告增加 `kind`/`started_at`/`finished_at`/`cache`/`timing`；`/api/case` 新增 `sample_report`；前端显示运行时间与分段耗时。
- 根仓库 `69ab7a8`、`1fd2ea1`：决策 64/65、方案与索引。

## 2. 缓存契约

- 落点：`cases/<case>/derived/relight/fixed.json`；只存参考帧号、未对齐重合度与全精度 `AlignResult`。
- 键：GT 身份（素材 sha256，缺失时 `size + mtime_ns`）、氛围图身份（同上）、请求的 `ref_frame`（`"auto"` 或整数）、`CACHE_VERSION`。
- 命中：跳过 91 帧扫描与 SIFT，按参考帧号 seek 一帧，重算光照场。
- 未命中：扫描 + SIFT + 光照场，然后原子写缓存。
- 失效：换视频、换氛围图、换参考帧、升级缓存版本都自动 miss；损坏或写入失败静默重算。
- 只保留最近一组输入；换回之前的氛围图会重新扫描。

## 3. 8K 小样（378 帧，i5）

报告：`cases/relight_web_01/out/samples/20261102-112703.json`（冷）与 `20261102-112813.json`（热）。命令参数：`--sample 10 --scene day --strength 0.3 --local-shading 0.2`。

- 冷跑：`cache.hit=false`，`ref_frame=80`，`seconds=66.6`。分段：`scan=29.842`，`read=0`，`align=0.284`，`fields=0.353`，`sample_decode=8.182`，`sample_compose=14.669`，`sample_write=12.240`。
- 热跑：`cache.hit=true`，`ref_frame=80`，`seconds=30.3`。分段：`scan=0`，`read=0.809`，`align=0`，`fields=0.367`，`sample_decode=8.276`，`sample_compose=14.632`，`sample_write=5.197`。
- 固定光照准备从约 30.5 秒降到约 1.2 秒；10 张 PNG 冷/热 SHA256 全部相同。
- 改动前同一视频、同一氛围图的小样报告是 128.1 秒（`strength 0.55`；本次为 0.3，扫描与光照场耗时不受影响）。冷跑省掉的是“扫描后再顺序解到第 80 帧”的第二遍解码；小样本来就跳过同位检查，所以这一项不影响小样。
- `sample_write` 冷 12.24 秒、热 5.20 秒，是磁盘/系统缓存的波动；输出像素未变。

## 4. 氛围图变化

- 把氛围图从 `i5` 换成 `i2` 后冷跑 5 帧：`cache.hit=false`，`ref_frame` 从 80 变为 47，`seconds=45.3`。分段：`scan=29.800`，`align=0.230`，`fields=0.400`，`sample_decode=4.010`，`sample_compose=7.300`，`sample_write=2.590`。
- 说明缓存键里的氛围图身份生效：换图后重新从视频里选参考帧，不复用旧变换。
- 验收后把槽位恢复为 `i5`，并用一次 1 帧小样重建 i5 的缓存（`scan=29.660`，`align=0.310`，`fields=0.360`，`total=34.1`）；重建产物已删除，case 的最新小样仍是 i5 的 10 帧热跑。

## 5. 20 帧整段（v1_gt20 + i2）

临时 case `cases_qa/relight_timing_qa`，参数 `--crf 0 --scene day --strength 0.3 --local-shading 0.2`；验收后删除临时 case。

- 冷跑：`cache.hit=false`，`ref_frame=0`，`seconds=46.0`。分段：`scan=6.845`，`read=0`，`align=0.267`，`fields=0.358`，`render_decode=6.119`，`render_compose=29.341`，`render_write=0.969`，`render_flush=1.007`，`render_total=37.490`。
- 热跑：`cache.hit=true`，`ref_frame=0`，`seconds=52.9`。分段：`scan=0`，`read=0.751`，`align=0`，`fields=0.357`，`render_decode=8.348`，`render_compose=40.097`，`render_write=1.320`，`render_flush=0.933`，`render_total=50.749`。
- 固定光照准备从约 7.5 秒降到约 1.1 秒。热跑总时间反而更高，是 `render_compose` 从 29.3 秒涨到 40.1 秒（机器负载/热状态波动），不是缓存失效。
- 冷/热输出解码帧 20/20 逐帧 maxdiff 0。
- 整段的主体仍是逐帧合成：20 帧的 `render_compose` 占 29–40 秒；缓存只能省掉扫描与匹配。

## 6. 门禁

- `uv run pytest -m "not slow"`：605 passed，1 deselected（8K slow），只有一条既有的 Starlette 弃用警告。
- `uv run ruff check .`：干净。
- `npm run typecheck`（`vue-tsc -b`）：干净。
- 未做浏览器视觉复核：本轮没有重启 web 服务。`/api/case` 的 `sample_report` 有单测覆盖，前端类型检查通过；服务重启后页面即可看到“上次运行”与小样标题上的时间戳。

## 7. 已知限制与未做

- 缓存只存变换，不存光照场；热跑仍要解码一帧参考帧并估光照场（8K 约 1.1 秒）。
- 缓存只保留最近一组输入；换氛围图会重新扫描，换回旧图也不会命中上一次的缓存。
- `render_write` 是写 ffmpeg 管道的耗时，编码在 ffmpeg 进程里并行进行，收尾等待记在 `render_flush`。
- 未跑 378 帧整段：20 帧整段已经覆盖缓存命中与像素一致，378 帧小样覆盖扫描/缓存计时；整段渲染按帧数线性增长，378 帧预计十几分钟。
- 机位移动仍不在支持范围；同位检查已删除，只有固定机位素材适用。

## 8. 额度

0。
