# 视频重打光（relight-video）实施与验收

记录时间：2026-10-30。背景：决策 56，方案见 `docs/plan/relight-video-plan.md`。
结论：`vrstudio relight-video` 已实施并通过门禁（`uv run pytest` 全量、`uv run ruff check .` 干净）；8K 真实素材 20 帧小样跑通，单帧约 4 秒，输出没有引入帧间闪烁。

## 1. 落点

- `src/vrstudio/relight/align.py`：参考帧选帧的 2K 缩略（`reference_small`）、结构打分（`structure_score`）、同位判据（`frame_hold`）。相似变换的估计与 warp 未改动，`estimate_similarity` 的签名保持接受数组。
- `src/vrstudio/relight/compose.py`：`LightCompose` + `light_compose`，把 2K 光场一次放大到原尺寸、把强度与局部明暗折进指数与矩阵；`relight()` 改为它的薄包装，输出逐位不变。
- `src/vrstudio/cli/relight.py`：新增 `relight_video` 命令，与图像版共用 `resolve_params`、`_check_video`（2:1 且偶数宽高）、报告构造与写盘。
- `src/vrstudio/cli/__init__.py`：注册 `relight-video`。

## 2. CLI 契约

```text
vrstudio relight-video --gt GT.mp4 --atmo ATMO.png --out OUT.mp4
  [--ref-frame N] [--scene night|day] [--strength 0..1] [--local-shading 0..1]
  [--highlight-clip] [--clip-knee 0.72] [--clip-max 0.98] [--crf 0..51]
  [--report report.json] [--config TOML] [--set key=value]... [--quiet]
```

- `--ref-frame` 缺省时在整段前 90 帧里自动选与氛围图结构最相关的一帧；显式给出时超出帧数或为负是退出码 2。
- `--crf` 只覆盖 `video.crf`，其余编码参数仍读 `config.video`。它的存在是因为像素基线测试需要钉 0，生产默认值仍是 18。
- 退出码：0 成功；2 视频不是 2:1、宽高不是偶数、氛围图与视频尺寸不一致、参数越界、`--ref-frame` 越界、配置错误、找不到 ffmpeg/ffprobe；1 探测失败、参考帧不可用（黑场）、对齐不可信、读图失败、编解码失败、写报告失败。失败路径都不留下输出视频。

## 3. 与方案的两处差异

方案 §2 写的「跟踪其余帧的纯平移」在实施中换成了「按同一坐标直接比较其余帧与参考帧」：

- 相位相关在这类 2K 带通图像上不可靠。合成素材实测单帧平移 4 像素只测出 0.5–0.7 像素，原因是带通后能量集中在低频，纯平移接近半个通带周期时峰值塌成噪声；多帧复合后累计漂移更大。
- 判据本身不需要位移量。「固定变换是否适用」等价于「其余帧是否仍与参考帧同位」，直接在像素上比较结构重合度即可，也不会把跟踪误差引进判据。

判据：两帧灰度各做 2 像素与 6 像素高斯模糊相减（带通），再算归一化相关；全段最低值低于 `MIN_FRAME_HOLD = 0.94` 时命令给出警告（不中断，输出仍然产出，因为错误已经发生）。合成素材实测的对应关系：同坐标 1.0、平移 4 像素 0.99、16 像素 0.887、40 像素 0.798。真实 8K 素材（`sources/dance_move.mp4` 前 20 帧，固定机位）19 帧最低 0.976。

报告字段：`{gt, atmo, size, frames, fps, ref_frame, ref_matched, frames_checked, min_hold, params, align, clip, light, seconds}`，其中 `params`/`align`/`clip`/`light` 与图像版同构。

## 4. 实施中修掉的缺陷

- `reference_small` 原先直接用 `cv2.resize` 的返回值。尺寸不变时 OpenCV 直接返回传入的数组，而 `FrameReader` 会复用同一个缓冲区，于是「参考帧」在下一帧被覆盖，同位检查永远得到 1.0。改为显式 `.copy()`。
- 自动选参考帧时只扫了第一帧：扫描循环的 `break` 条件写成 `index + 1 >= MAX_REFERENCE_SCAN` 之外的判断位置不对（离开循环的判断不成立时仍会退出），且 `open_frames()` 返回的生成器被完整消费一遍后再次迭代什么也不产出。现在选帧、同位检查、取原分辨率参考帧各打开一次视频，共三遍。

## 5. 门禁

- `uv run ruff check .` → All checks passed。
- `uv run pytest` 全量通过：`tests/test_relight.py` 30 条（图像版 24 条 + 视频版 6 条），`tests/test_relight_video.py` 13 条错误路径。
- 图像版基线未受影响：`--strength 0` 全链路逐位一致、8K 真实素材 maxdiff 0 的两条原有断言照旧通过。

新增的视频测试：

- `test_light_compose_matches_relight`：复用光场与图像版 `relight` 在任何强度下逐位一致。
- `test_video_strength_zero_keeps_gt_pixels`：输出解码帧与 GT 解码帧的差不超过编码器自身的往返噪声。测试先量这个噪声（同一组解码帧再编码一次的最大偏差，实测 4 级），因为 YUV 转换与 4:2:0 子采样在第二次编码时会重新量化，crf 0 也消不掉。
- `test_video_reference_frame_and_lighting`、`test_video_ref_frame_explicit`：自动选帧与显式选帧、输出确实被压暗。
- `test_video_audio_is_copied`：GT 带音轨时，输出的音轨被 `-c copy` 带过来，帧数与尺寸不变。
- `test_frame_hold_follows_the_threshold`：同坐标 1.0，平移 16 像素跌到 0.94 以下。

## 6. 真实素材小样（8K）

素材：GT 取 `sources/dance_move.mp4` 前 20 帧（8192×4096，30fps），氛围图取 `cases/dance_move/out/20261030-120614_frame.mp4` 的第一帧（同尺寸 AI 重绘）。

- 对齐：内点 1313、缩放 0.99997、旋转 0.0000°、重合度 0.9684 → 0.9686，可信。
- 打光强度取默认 night（1.0/0.35）：增益均值 0.711（p05 0.521 / p95 0.949），可见度均值 0.858，白点矩阵偏离单位阵不到 3%。
- 速度：20 帧共 81.7 秒（含选帧与同位检查两次解码），渲染约 3 秒/帧，1 分钟成片约 30 分钟。
- 稳定性：输出逐帧均值的帧间最大跳变 0.022，GT 自身是 0.035，没有引入闪烁。
- 观感：成片保留 GT 的梁柱、柱子花纹与地面细节，木梁被调得更暖更亮，与 AI 重绘的低频走向一致。

产物在 `vrstudio/.tmp_frames/real/`（gitignore 外的临时目录）：`relit20.mp4`、`relit20.json`、`compare.png`。

## 7. 已知限制与未做

- 判据只判断「画面整体是否在动」，运动物体（`sources/walk_4k.mp4` 里的发光人物来回走）不影响判定，但其阴影与高光仍按参考帧的位置落在 GT 上。这一条与方案 §3 登记的限制一致。
- 机位移动时只警告、不实现逐帧重估加时间平滑。
- 氛围图只有一张；多张氛围图随时间切换未做。
- case 与 web 接入未做，等这一步的小样结论。
