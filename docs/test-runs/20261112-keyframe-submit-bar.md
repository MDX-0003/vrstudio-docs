# 首尾帧页复用生成页固定底栏（2026-11-12）验收

关联：`docs/key-issues/frontend-decisions.md` 条目 32、`docs/plan/keyframe-page-layout-plan.md` 的状态修正。

## 1. 本轮改了什么

- 删除首尾帧页「首帧候选 / 尾帧候选」标题栏里的图片模型、分辨率、候选张数与生成按钮，标题栏只留「刷新批次」。
- 新增图片生成专用固定底栏，复用视频生成页的底栏外壳与扣费额度行：
  - 第一行：图片模型、分辨率、候选张数、生成状态。
  - 第二行：项目、剧集、会话、刷新、生成首帧候选 / 生成尾帧候选。
  - 底部条件行：未满足生成条件时常显原因；未选项目会话时按钮禁用。
- 会话沿用 `POST /api/case/{name}/params` 写 `generation.toml`，首尾帧运行仍由服务端读该会话，CLI 契约不变。
- 抽出 `SubmitBar.vue`（固定外壳）与 `SessionQuotaRow.vue`（项目/剧集/会话行），视频页与首尾帧页共用。

## 2. 自动门禁

| 门禁 | 结果 |
|---|---|
| `npm run test`（`vrstudio/frontend`） | 31 个文件、225 条全绿 |
| `npm run build`（含 `vue-tsc -b`） | 通过 |
| `npm run lint` | 通过 |
| `prettier --check`（仅本轮改动文件） | 通过 |
| `uv run ruff check .`（`vrstudio`） | 通过 |
| `uv run pytest -q`（`vrstudio`） | 2 条失败，其余通过；失败与本轮无关，见 §4 |

新增/更新的前端用例：

- `keyframe-step.spec.ts`：候选标题栏不再有生成参数、参数只在固定底栏；未选项目会话时生成按钮禁用并显示原因；切换会话后先保存 `session_id/project_id/episode` 再以当前分辨率、张数与图片模型提交。
- 原有用例继续通过：图片模型切换保存、候选批次折叠、四格输入、交接禁用、候选图打开链接。

## 3. 浏览器验证（Chrome headless，1440 宽）

`walk_4k`，路由 `/next/case/walk_4k/keyframe`：

1. 候选标题栏只剩「首帧候选 / 尾帧候选」与「刷新批次」，没有图片模型、分辨率、候选张数或生成按钮。
2. 底部固定条第一行：图片模型（`模型 #44`，清单不可用时按已保存 id 回退）、分辨率 `2K`、候选张数 `4 张`、右侧绿点「就绪」。
3. 底部固定条第二行：项目「2026大秦寻仙VR」、剧集「第 1 集 · 秦宫夜宴」、会话「ai会话_测试」、刷新、已获取项目数/刷新时间、右侧「生成首帧候选」。
4. 页面底部留白随底栏出现，固定的导航与底栏不重叠。

同路由切到 `/next/case/walk_4k/generate`：

5. 视频页底栏仍在：视频模型、模式、比例、输出分辨率、输入分辨率、时长、声音、项目、剧集、会话、刷新、状态、预演检查、再抽一版、提交生成。抽出共用外壳与额度行没有改变它。

未做：真实提交候选（会扣额度）；1400 以下窄屏断点；会话下拉展开后的交互；浏览器里真的改一次会话再刷新回读（单测已覆盖保存 payload，页面回读依赖 `emit('updated')`）。

## 4. 与本轮无关的 pytest 失败

`uv run pytest -q` 在 `tests/test_web_console.py` 报两条：

- `test_step_file_entries_open_url_does_not_depend_on_repo_rel`
- `test_external_source_has_path_but_no_open_url`

两条都断言「cases 在仓库外时 `rel is None`」。本机 `pytest` 的 `tmp_path` 落在 `E:\VRAIGC\vrstudio\pytest-of-Administrator\...`，位于仓库内，`file_entry` 因此算出了相对路径而不是 `None`。本轮没有改后端文件，失败来自测试临时目录位置，与底栏改造无关。测试产生的 `pytest-of-*` 与 `vrgen-*.json` 已清理。

## 5. 回退

前端改动集中在 `frontend/src` 的六个文件与 `styles/base.css`；回退时把 `KeyframeStep.vue` 的底栏与候选标题栏恢复、删掉三个新组件即可。不涉及数据、`generation.toml` 格式或 CLI 契约。

## 6. 第二轮：模型名称与档位跟随模型能力（同日）

### 6.1 改动

- `vrgen` 的 `mglc model list --type image` 不再传 `--page-size`；当前 mglc 不接受该 flag，之前整条列表命令失败，页面只能显示「模型 #44」。
- `params show` 新增 `image`：从 `mglc model --type image --model-id <id>` 的 `componentSettings` 取 `name`、`ratios`、`resolutions`、`max_num`、`default_num`，按 job+model 24h 缓存；失败时用陈旧缓存，仍失败只回 `model_id`（有列表名时带 `name`）与 `error`。
- 首尾帧底栏增加「比例」；比例选项是模型支持且与 patch 视口一致的值（当前只有 16:9）。分辨率与候选数改为消费 `image`；模型名优先用详情 `name`，列表读不到也不退回 id。
- `keyframe/run` 接收 `ratio`，并在服务端校验 patch 视口比例与模型支持的档位。

### 6.2 自动门禁

- `vrgen`：`uv run pytest -q tests/test_cli.py` 全绿；新增列表无 `--page-size`、详情解析与缓存、缓存过期降级、无缓存降级四条断言。
- `vrstudio`：`uv run pytest -q tests/test_web_console.py -k keyframe_run` 4 条全绿；新增比例与分辨率校验一条。
- 前端：`vue-tsc -b` 通过；`keyframe-step.spec.ts` 17 条、`generate-step.spec.ts` 10 条全绿；`npm run build` 通过。

### 6.3 真实数据与浏览器

- `vrgen params show --job walk_4k` 返回 15 个图片模型；`image = {"model_id": 44, "name": "专业图片-2.5", "ratios": [8 个], "resolutions": ["1K","2K","4K"], "max_num": 4}`。
- `mglc model --type image --model-id 25` 返回 `Seedream 4.5`，`resolutions = ["2K","4K"]`，`generateCountOptions = [1,2,3,4]`；对应模型切换后的档位收窄由前端单测覆盖。
- Chrome headless（1600 宽，`walk_4k` 首尾帧页）确认底栏显示「专业图片-2.5 / 16:9 / 2K / 4 张」，模型名不再是「模型 #44」。
- 未做：真实切换模型后提交（会扣额度）；比例下拉展开后的视觉检查（当前单项 16:9）。

### 6.4 回退

回退时删掉 `params show` 的 `image` 字段与 `models_image_<id>.json` 缓存、恢复 `--page-size`（仅当 mglc 重新支持）、把首尾帧底栏的比例/模型档位恢复为写死值。比例校验与 `keyframe/run` 的 `ratio` 字段一并回退。
