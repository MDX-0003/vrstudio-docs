# patch 任意比例切分与合并实施与验收（WP1–WP7）

日期：2026-11-19。决策 104，方案见 `docs/plan/patch-arbitrary-ratio-plan.md`。

## 1. 实施范围

本轮只动视频 patch；patchimg 仍固定 16:9、只保留原来的两档视口尺寸，fullRedrawImg 与 gen 流不变。

- vrgen `params show` 的 `common` 新增 `limit`（`min_pixel` / `max_pixel` / `max_bytes`），取自当前模式的 `refVideoValidator`；不吃视频的模式三项为零。
- vrstudio 配置新增 `[patch]`：`viewport_max_pixels`、`viewport_min_pixels`、`viewport_align=8`、`aspect_ratio_diff_pct=1.0`。预算优先级是显式配置 → 平台 `limit` → 内置 2086876/409600。
- 新增 `vrstudio/patch/viewport.py`：`parse_ratio`、`ratio_label`、`aspect_ratio_diff`、`same_ratio`、`fit_viewport_size`、`box_to_viewport`、`PRESET_RATIOS`、`IMAGE_MODEL_RATIOS`。派生尺寸按 8 对齐，16:9 得 1920×1080、2.39:1 得 2216×928。
- web 新增 `POST /viewport-ratio`（预设比例）与 `POST /viewport-box`（自由框选，B 语义：框宽定 hfov、框高定 vfov、输出比例按 tan 投影算出）；`/viewport-size` 只留给 patchimg。
- 合并新增 `GET /merge-targets`：用 ffprobe 读合并输入的宽高，按“成片宽高比与记录宽高比的差距 ≤ `aspect_ratio_diff_pct`”筛出抽取记录；来源版本排第一并默认选中；无 exact 时给最近 3 条 near 与强制合并。
- `cli/merge.py` 抽出 `merge_normalize_plan`：差距 ≤ 0.1% 等比缩放、0.1%–1% 覆盖缩放加居中裁切、超过 1% 拒绝，显式 `--allow-crop` 时记 `cover_crop_forced`；报告新增 `ai_aspect`、`viewport_aspect`、`aspect_diff_pct`、`normalize_mode`。
- 首尾帧：`_keyframe_ratio` 改为从视口比例派生，并要求它属于图片模型比例表；`api_keyframe_run`、`api_keyframe_pick`、`cli/generate.py` 的 16:9 硬校验换成同一套比例校验。
- 前端：选区页增加“预设比例 / 自由框选”切换、预设下拉、全景图框选与只读预算读数；合并页改用 `merge-targets`，每条候选显示“成片宽高比 X 与这条记录 Y 的差距 Z%”，near 行标注大于上限，强制合并走 `allow_crop`。

## 2. 门禁结果

- vrstudio `uv run pytest -q` 全绿；新增 `tests/test_patch_viewport.py`，并更新 `test_web_console.py`（比例/框选/预算/merge-targets）、`test_merge_geometry.py`（三段规则）、`test_generate.py`（非 16:9 的首尾帧拒绝与 9:16 放行）。
- vrstudio `uv run ruff check .` 干净。
- vrgen `uv run pytest -q` 全绿；`test_cli.py` 的 `params show` 用例断言 `limit` 来自模型详情、firstLastFrame 三项为零。
- vrgen `uv run ruff check .` 干净。
- 前端 `npm run lint`、`npm run test`（33 个文件 252 条）、`npm run build` 通过；改动的文件已过 `prettier --write`。仓库里另有 12 个与本轮无关的文件仍未过 `format:check`（relight 与旧 keyframe 页面），本轮没有顺手改动它们。

## 3. 已验证的行为

- 派生尺寸：16:9 → 1920×1080、1:1 → 1440×1440、9:16 → 1080×1920、2.39:1 → 2216×928；面积不超过 2,086,876、宽高都是 8 的倍数。
- 自由框选：16:9 的框在 30° hfov 下输出 1.8064:1，在 75° hfov 下输出 1.9886:1，框住范围与预览覆盖一致。
- 宽高比差距：1920×800 对 2216×928 是 0.51%（cover crop），1920×780 是 3.08%（拒绝，`--allow-crop` 时 forced）。
- merge-targets：16:9 成片只筛出 16:9 记录；1.5:1 成片无 exact，near 按差距升序给 3 条；来源版本默认选中。
- 首尾帧：9:16 的 patch 视口可进入 firstLastFrame；1.825:1 被拒绝并说明不在图片模型比例表内。
- 真实浏览器（Chrome headless，case `1106-04`）：选区页渲染“预设比例 / 自由框选”切换、预设下拉 `16:9`、只读读数 `1.7778:1 · 3840×2160` 与“预算 8,295,044 像素（平台，只读）”；合并页在没有 `result.mp4` 时显示“抽取版本…没有生成结果”并禁用“开始合并”。这一轮只验证了渲染与错误态，没有做真实鼠标拖拽、预设切换与强制合并的点击。

## 4. 未做与待验收

- 真实 2.39:1 素材的端到端链路（extract → 外部生成 → merge → assemble）尚未跑，需要一段真实全景片与一次外部工具操作。
- 16:9 既有 case 的逐字节回归没有在真实素材上重跑；本轮单测覆盖了比例与合成规则，但没有用 8K 原片重出 `clip.mp4` 与 `_space.mp4` 对照 sha256。
- 浏览器端：选区页的预设下拉、自由框选拖拽、只读预算读数与合并页的候选/差距文案只过了类型检查与单测，未做真实浏览器点击验收。
- 平台 `maxPixel` 的真实读取已确认：case `1106-04` 的 `params show` 返回 8,295,044，页面据此把 16:9 派生到 3840×2160。方案里举例用的 2,086,876 与这个平台值不同；如果目标上限是 2,086,876，需要在 `vrstudio.toml` 写 `[patch] viewport_max_pixels = 2086876`，页面会显示“配置”来源。哪一种才是要交付的上限，需要你确认。
- 自由框选的输出比例可能不是标准值（16:9 框在 75° 下是 1.99:1），需要在实际外部工具里确认它能接受这个比例。
