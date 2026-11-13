# 视频链路 16-bit 帧与 10-bit 交付档计划

日期：2026-11-11
状态：待批（本文是 WP0 的输入，代码未动）
关联：决策 19（被本文取代）、决策 98 之后的 99 号（新增）、`docs/case-model.md`、`AGENTS.md` 硬规则 4。

## 1. 换标准的依据

现行标准是「全流程只产出一个视频编码档：H.264 8-bit yuv420p，crf 18，preset veryfast」（[config.py](../../vrstudio/src/vrstudio/config.py#L72-L79)）。2026-11-11 在 case `1110-0101` 上做的实测表明，这个档位的瓶颈不在码率，而在位深。

- 取 1892×946 成片同一帧的天空平坦窗口（400×200），母版（平台返回的 HEVC 10-bit）有 236 个亮度级、平坦段中位数 14 px、台阶 0.58。
- 现行 crf 18 veryfast 只有 59 级、平坦段 25 px、台阶 1.17；crf 14 slow 是 64 级、21 px、1.17；crf 10 slow 是 64 级、21 px、2.34，体积从 2.50 MB 涨到 11.13 MB。
- x265 10-bit crf 20 是 230 级、14 px、0.29，体积 1.60 MB；x265 10-bit crf 18 是 243 级、12 px、1.46，体积 2.09 MB。

结论有三条。第一，8-bit 下无论 crf 怎么降，天空都只有 60 级左右的量化层次，色带是位深造成的结构性问题，不是码率问题。第二，真正的 10-bit 编码能把这些层次拿回来，而且体积比现状更小。第三，只把输出容器换成 10-bit、内部仍然按 8-bit 处理没有用：实测那种组合的 221 级是编码噪声，平坦率只有 25%，画面会变脏。

因此这次改的是两件事：帧泵从 8-bit 升到 16-bit，交付档从 H.264 8-bit 换成 HEVC Main10 10-bit。只改后者不会有效果。

## 2. 新标准

### 2.1 帧泵

- 解码与编码的中间格式统一为 `bgr48le`：每通道 uint16，值域 0..65535。
- 内部计算沿用现有的 float64 路径，量化上限从 255 改为 65535。
- 读取端不再有 10→8 bit 的截断，写入端由 ffmpeg 把 16-bit 转成 10-bit YUV。

### 2.2 交付与中间件

- 编码器 `libx265`，像素格式 `yuv420p10le`，profile Main10。
- 质量默认 `crf 14`、`preset slow`；需要更高时改配置一行即可到 `crf 10`。
- 色彩标签沿用决策 86：`colorspace`、`color_primaries`、`color_trc` 全写 BT.709，`color_range` 写 tv；x265 通过 `-x265-params` 补 `colorprim/transfer/colormatrix`。
- 关键帧间隔沿用 `KEYFRAME_INTERVAL_S = 0.5`，保证 8K 成片 seek 可用。
- 音频仍走第二遍 `-c copy` 复用源片音轨。

### 2.3 唯一例外：浏览器预览代理

预览代理保持 H.264 8-bit yuv420p。它的用途是「让浏览器播得动」，不是交付件；把它换成 10-bit 会让代理失去存在意义。这一条例外在契约里写清楚，不靠分支判断。

### 2.4 不在范围内

图片流程（`patchimg`、`fullRedrawImg`、relight 的静图输出）继续用 8-bit PNG，本次不动。它们走 `media/imageio.py`，与视频帧泵是两条路径。

## 3. 影响面清单

### 3.1 契约与文档

- `docs/decisions.md`：改写决策 19 的编码档定义；新增 99 号决策记录本次标准、依据与例外。
- `docs/case-model.md`：补上 `_pad.json` 的 `video` 表取值（字段集不变，`encoder`/`pix_fmt` 的合法值改变）；确认 `clip.json` 不承载编码参数，无需改字段。
- `AGENTS.md` 硬规则 4 与 `vrstudio/AGENTS.md` 的编码语义段落，把「H.264 8-bit yuv420p delivery 一档」替换成新标准。
- `docs/architecture.md` 第 46、126、179 行；`vrstudio/README.md` 第 97 行。`vrstudio/config/default.toml` 的 `[video]` 注释与取值一起放到 WP1，避免出现「注释写 10-bit、值还是 8-bit」的中间态。

### 3.2 配置与校验

- `config/default.toml` 的 `[video]` 表是权威取值，当前写的是 `libx264 / 18 / veryfast / yuv420p`；`config.py` 的 `_FALLBACK` 里还有一份同内容副本，只在仓库里的 `default.toml` 缺失时生效。两处都要改。
- 覆盖顺序在 `config.py` 的 `load()` 里固定：`--set` > `--config FILE` > 本机 `vrstudio.toml` > `~/.config/vrstudio/default.toml` > 仓库 `default.toml`。仓库里的本机覆盖文件 `vrstudio/vrstudio.toml` 目前没有 `[video]` 段，本次也不写进去，标准只落在 `default.toml`。
- `pix_fmt` 不是自由配置项：`config.py` 第 328–334 行把非 `yuv420p` 直接判为配置错误，帧泵的输入格式来自 `videoio.py` 的常量 `FRAME_PIX_FMT`。这两处是 WP1 的拆锁点，改配置本身不会生效。
- 配置改动对 `serve` 不即时生效：`activate()` 只在进程启动时读一次，改完要重启服务。
- `redraw/manifest.py` 的 `VideoSettings` 字段集不变，只改写入值。
- **crf 目前是半集中的**：`recompose`、`pad`、`seam_center` 整表取 `conf.video`，`relight` 在它之上叠 `--crf`；而 `FfmpegSink` 的默认 `crf=18`、patch 输入件 `crf=14`、patch 还原 `crf=14`、`merge` 与 `assemble` 的 `--crf` 默认 `18` 都是各写各的，预览代理另有 `PROXY_CRF = 22` 常量。改完 `default.toml` 不会自动改到中间件。本次要在 WP1 把前六处收拢到一处取值（`FfmpegSink` 缺省从 `[video]` 取，`merge`/`assemble` 的 `--crf` 缺省同源），代理常量保留并写明理由。

### 3.3 media 层

- `media/videoio.py`：`FRAME_PIX_FMT` 改为 `bgr48le`；`FrameReader` 分配 uint16 缓冲；`FrameWriter` 接收 uint16、输出 10-bit、按编码器补 x265 参数；偶数尺寸校验保留。
- `media/ffmpeg.py`：`FfmpegSink` 同样改为 uint16 输入与 10-bit 输出，并把写死的 `crf=18` 缺省改成从 `[video]` 取。
- `media/frames.py`、`media/binres.py`：核对是否假设 8-bit，按需同步。
- `media/imageio.py`：不改（图片流程 8-bit）。

### 3.4 redraw 域（fullredraw / img2video 共用）

- `redraw/recompose_core.py`：`finalize` 的量化上限改 65535；`recompose_u8` 改为按 uint16 输出（区域直通与混合带量化同步）；`ComposeBuffers` 的键名与 dtype。
- `redraw/registration.py`：`to_gray` 接受 uint16 并归一化到 float32；相位相关与 SIFT 的输入口径。
- `redraw/blend.py`、`redraw/restore.py`、`redraw/pipeline.py`：核对 dtype 与裁剪上限。
- `cli/pad.py`、`cli/recompose.py`：写 10-bit；`recompose` 的 `FrameWriter` 配置。
- `redraw/image.py`：不改（静图）。

### 3.5 patch 域

- `patch/extract.py`：`read_clip` 目前用 `cv2.VideoCapture`（只能 8-bit），改为 ffmpeg 16-bit 读取；`open_writer` 与 `_FfmpegWriter` 同步；写死的 `crf=14` 改为取 `[video]`。
- `patch/restore.py`：两处 `FfmpegSink` 的 crf 与位深；默认 14 改为取 `[video]`。
- `patch/composite.py`：`np.clip(sub, 0, 255)` 改为 65535。
- `patch/blend.py`、`patch/projection.py`、`patch/scalefit.py`、`patch/framealign.py`：核对 dtype 假设。
- `cli/extract.py`、`cli/restore.py`、`cli/merge.py`、`cli/assemble.py`：crf 默认值与 `FfmpegSink` 调用。

### 3.6 relight 域

- `relight/fields.py`：`srgb_to_linear` 的 256 项 LUT 改为 65536 项或浮点换算；`SHADOW_PIVOT`、`0.01` 这类以 255 为尺度的常量改成归一化。
- `relight/compose.py`：`LightCompose.apply` 与 `soft_clip` 的量化与裁剪。
- `relight/align.py`：SIFT 与相位相关要求 8U 或浮点，uint16 灰度要先降到 8-bit 或转 float。
- `relight/atmo.py`、`relight/regions.py`：核对掩与权重。
- `cli/relight.py`：`--crf` 的默认与取值范围；8K 整段的内存与耗时。

### 3.7 web 与前端

- `web/proxy.py`：`_browser_safe` 现在按 `codec == h264 and pix_fmt == yuv420p` 判定（第 163 行），新交付件永远不满足，代理会一直生成；这是预期行为，写进注释与测试。
- `web/app.py`：从帧生成缩略图/预览图的地方统一按 16-bit 输入转 8-bit PNG（第 1189 行一带）。
- `frontend/src/views/wizard/CompareStep.vue`：播放质量默认值从 `original` 改为 `proxy`，因为交付件不再是浏览器可播的 8-bit H.264；「原始分辨率」选项保留给已装 HEVC 解码器的环境。
- `frontend/src/views/wizard/PickStep.vue` 与其他播放器：代理就绪判定不变。

### 3.8 测试与像素基线

- `tests/test_videoio_smoke.py`、`tests/test_infra.py`、`tests/test_e2e_fullredraw.py`、`tests/test_generate.py`、`tests/test_web_console.py`、`tests/test_web_proxy.py`：所有写死 `yuv420p` 的断言与 `VideoSettings` 构造。
- 像素基线：crf 0 的往返必须仍然逐位一致（`maxdiff == 0`）；x265 的无损模式要实测确认。
- 新增一条色带回归测试：合成一张带平滑渐变的图，编码后检查平坦窗口的级数不低于阈值。
- `tests/test_relight.py` 的 sRGB 往返恒等式：8-bit 下成立的前提在 16-bit 下要重新推导。

## 4. 工作包与顺序

### WP0 契约先行（只改文档，不动代码）

改动：3.1 列出的四份文档与两处注释。
验收：`docs/decisions.md` 的 19 与 99 写定；`AGENTS.md` 与 `case-model.md` 的措辞与新标准一致；没有代码改动。

### WP1 帧泵与配置（media 层）

改动：3.2 与 3.3。
验收：用一段 3 秒样片走「读 16-bit → 写 10-bit → 读回」，crf 0 时解码后 `maxdiff == 0`；`ffprobe` 显示 `hevc / yuv420p10le`；8K 单帧的内存占用记录在案；改一次 `default.toml` 的 `crf` 后，`pad`、`recompose`、`seam_center`、`relight`、`merge`、`assemble` 与 patch 中间件全部跟着变（用日志里的编码参数核对），没有残留的写死值。

### WP1a 平台输入件接受度核查（与 WP1 并行，不阻塞）

用现成的 `seedance_input.mp4` 转一版 10-bit HEVC，走一次真实的 `vrgen` 提交或 `prep` 校验，确认平台接受这个输入件。结论只有三种：接受、接受但转码、拒绝。第三种要回到 WP2 之前重新决定 pad 的输出档，其他两种继续。

### WP2 redraw 域（pad 与 recompose）

改动：3.4。
验收：`cases/1110-0101` 重跑，成片是 1892×946 的 HEVC 10-bit；同一平坦窗口的级数、平坦段、台阶对齐母版（236 / 14 / 0.58 一档）；成片相对母版的 PSNR 不低于 50 dB；记录体积与耗时。

### WP3 patch 域

改动：3.5。
验收：既有 patch 像素基线在 crf 0 下 `maxdiff == 0`；`clip.json` 的帧范围、fps、sha256 校验不变；三段拼接的帧数与 fps 不变。

### WP4 relight 域

改动：3.6。
验收：8K 整段 378 帧跑通，抽帧 PSNR 与改动前同量级；进程峰值内存与单帧耗时记录；`--sample` 小样路径不变。

### WP5 web 与前端

改动：3.7。
验收：浏览器打开 case，对比页默认走代理并能播放；下载到的原件是 HEVC 10-bit；代理侧仍是 H.264 8-bit。

### WP6 回归与验收

改动：3.8 与 `docs/test-runs/` 的验收记录。
验收：`uv run pytest` 全绿、`uv run ruff check .` 干净、前端单测通过；真实 case 的指标表与改动前逐项对照。

## 4.1 提交切分

硬规则 6 要求的是「提交前 pytest 全绿」，不是任何时刻全绿。所以红的状态只留在未提交的工作区里，能绿的提交只能发生在契约翻面的那一刻。两种切法：

- **一次翻面**：media、redraw、patch、relight、web 与所有断言同一次提交。最终形态最干净，代价是三十多个文件的单次 diff，出问题时定位范围大；靠改动前的对照产物（旧成片 SHA256、PSNR 与色带指标表）保证每个 WP 有独立验收点。
- **三步走**：第一步给 `FrameReader`/`FrameWriter` 加显式 depth 参数、默认仍 8-bit，配一条直接测 16-bit 往返的新测试，这一步是绿的且是真实新增能力；第二步翻默认（`FRAME_PIX_FMT` 改 `bgr48le`、拆掉 `config.py` 的 `pix_fmt` 锁、同步改全部消费方与断言），这是那个大提交；第三步把第一步留下的 8-bit 分支删干净，回到单一 16-bit 路径。代价是 media 层改两遍，中间态存在一条两种帧格式都能进的分支。

### 测试纪律

- 迁移期间不新增任何 `skip` / `xfail`。仓库里本来就有一层静默跳过：`test_videoio_smoke`、`test_e2e_fullredraw`、`test_assemble`、`test_patch_flow`、`test_relight_video`、`test_relight_regions` 在 `bin/ffmpeg.exe` 不存在时整文件 skip，而 CI 的 runner 上没有 `bin/`，所以 CI 今天就已经把全部真实编码测试跳过了。把 `bin/` 挪走能让本地「全绿」，绿掉的恰好是唯一能证明 16-bit 帧泵成立的几条。
- 像素基线不能关。crf 0 的 `maxdiff == 0`（`test_videoio_smoke` 与 `test_roundtrip`）是「16-bit 改造没有动画面」的唯一证据。
- 新增的色带回归测试与 16-bit 往返测试在本地写、本地跑红、改代码到绿，红的时候不提交。
- WP6 验收加一条：`pytest -q -rs` 的跳过清单与改动前逐条一致，且 CI 上新增的跳过数为 0。

## 5. 风险与验证点

- **平台输入件**：Seedance 的输入件能不能吃 10-bit HEVC 目前没有验证。WP1a 用一次真实提交换结论，这是唯一需要提前花的额度。
- **浏览器播放**：Chrome 对 HEVC 10-bit 的依赖平台解码器，对比页必须默认代理；「原始分辨率」只作为已装解码器环境的选项。
- **8K 内存**：一帧 bgr24 是 88 MB，bgr48le 是 177 MB；relight 同时持有 GT、氛围图与输出，1.71 GB 的峰值预计翻倍。WP4 必须实测，必要时重新评估逐帧缓冲的复用。
- **编码耗时**：本机 193 帧 1080p，x264 veryfast 1.1 秒、x265 10-bit medium 3.1 秒；8K 的像素量是 18.6 倍，`preset slow` 的代价要实测后决定是否降到 medium。
- **像素基线的语义**：现有基线在 8-bit 下成立，换成 16-bit 后要重新推导并逐条复核，不能只改断言。
- **cv2 的 16-bit 支持面**：`resize`、`warpAffine`、`GaussianBlur` 支持 16U，但个别插值与色彩转换不支持，WP2 与 WP3 要逐函数确认。

## 6. 明确不做的事

- 不改 `clip.json`、`_pad.json`、`run.json` 的字段集，只改 `video` 表的取值。
- 不给 recompose 单独开 10-bit 分支，也不保留「8-bit 交付 + 10-bit 母版」的双产物。
- 不改图片流程的 PNG 位深。
- 不为某一条 case 做兼容开关；旧 case 重跑即可，不回填历史成片。

## 7. 验收清单

1. `docs/decisions.md` 的 19 与 99、`AGENTS.md`、`case-model.md`、`architecture.md`、`README.md` 全部改到位，措辞一致。
2. `ffprobe` 检查所有新产物：`hevc / yuv420p10le / bt709`。
3. crf 0 往返 `maxdiff == 0`。
4. 110101 的色带指标对齐母版，PSNR 不低于 50 dB。
5. 对比页默认代理可播，下载原件是 10-bit。
6. pytest、ruff、前端测试全绿。
7. 8K 内存与耗时数据记录在 `docs/test-runs/`。

## 8. 实施状态（2026-11-13 更新）

已落地：

- 帧泵 `bgr48le`/uint16，交付与中间件 `libx265 + yuv420p10le`，`crf 0` 自动切 x265 无损（vrstudio `563e02f`）。
- `recompose` 量化到 0..65535，`to_gray` 统一回到 0..255 口径，注册与接缝指标含义不变（`563e02f`）。
- `pad`、`recompose`、`seam_center` 全 16-bit（`563e02f`）；浏览器对比页默认走代理，代理仍是 H.264 8-bit（`563e02f`）。
- WP3 patch 域全 16-bit（`f448036`，2026-11-13）：extract/restore/merge/assemble 的读写全部走 16-bit 帧泵，`to_u16` 是 8-bit 边界的唯一显式升位点；`FfmpegSink` 缺省改从 `[video]` 取（`--set` 对 patch 全链生效），libx264 过时注释与报告字段修掉。
- WP4 relight 域全 16-bit（`97491b3`，2026-11-13）：删 `_u8_reader`，sRGB LUT 改 65536 项（反向表网格 2^20），compose 全部换 65535 满量程；8K 整段 378 帧实测与等价论证见 `docs/test-runs/20261113-video-10bit-wp3-wp4.md`。

未做（按计划顺序）：

- WP3 遗留：`cli/extract.py` 的 ERP 源解码（clip 中间件输入侧）仍走 cv2 8-bit，影响交给平台的输入件精度上限，不影响交付成片。
- WP4 遗留观察：`GUIDED_EPS = 300` 疑似历史遗留（引导项实测不生效），改它会改画面，建议单独立项；拿到真实 10-bit 素材后应重跑 8K 对照。
- WP1a 平台输入件接受度：尚未做真实提交。
- WP2 验收：尚未用 `cases/1110-0101` 重跑对比色带与 PSNR。
