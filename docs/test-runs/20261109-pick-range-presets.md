# 选区范围预设与合并选版验收（2026-11-09）

## 范围

验证决策 97 / `docs/plan/pick-range-presets-plan.md` 的落地：

- `case.toml` 的 `[[range_preset]]` + `[pick] active`，旧顶层三段加载为 `r1`。
- `derived/pick/draft.toml` 承接 pick 页高频编辑，不写 `case.toml`。
- pick 页“保存的范围”列表：保存、另存为、单击选中、双击载入、行尾删除、dirty。
- 抽取页复选 preset，只读版本列表，最新一版标“最新”。
- 合并页按几何分组抽取版本，局部选版只影响本次合并；patch 合并输入只留上传入口与条件式“改用采用结果”。

## 提交

- `vrstudio` `b54d6d6`：case 模型与 CLI 支持 preset / draft / patch 外部合并输入。
- `vrstudio` `5ce8953`：web 草稿、preset API、`merge_ranges` 与显式 merge/assemble 版本。
- `vrstudio` `efdf013`：pick 页保存范围列表与草稿交互。
- `vrstudio` `a82c2d9`：抽取页、合并页复用范围行与局部选版，合并输入控件简化。
- `vrstudio` `80dab55`：载入 preset 时同步 active，修正合并输入显示。
- `vrstudio` `3331521`：帧范围草稿写入后同步父级选区状态。
- 根仓库：本验收记录与 `AGENTS.md` 索引。

## 自动门禁

- `uv run pytest`：全绿。
- `uv run ruff check .`：通过。
- `frontend` `npm run lint`：通过。
- `frontend` `npm run test`：31 个测试文件、219 条测试通过。
- `frontend` `npm run build`：通过；Vite 提示单包大于 500 kB，为既有体积提示，未新增拆包。

## 迁移回归

用真实旧 case `1109-test-region` 的临时副本验证，不改原 case：

1. 旧 `case.toml` 顶层 `[viewport]` / `[inner]` / `[frames]` 加载为 `r1`。
2. `case_mod.save` 后重新加载：`active=r1`、`range_presets` 1 条、yaw `-49.4`、帧 `0–56` 全部不变。
3. 新文件含 `[[range_preset]]`，不再含顶层 `\n[viewport]`。
4. 首次写入生成 `case.toml.bak-20261109-184941-435377` 备份。

## 浏览器验收

环境：Chrome 156 headless，CDP 驱动；临时 cases root 为 `1109-test-region` 副本；源片仍指向原 `sources/1106无桌子.mp4`。真实抽取/合并任务未运行，避免长任务与额度消耗。

### pick 页

- 初始显示 1 条范围：`11-09 16:04`，标“当前”，几何 `yaw -49.4° · pitch -8.8° · fov 94.5° · inner 1295×658 · 帧 0–56`。
- 点“另存为”后出现第 2 条 `11-09 18:51`，新条成为 active。
- 通过 `pick-draft` 把 yaw 改为 `-30`，再新建第 3 条；列表 3 条，active 为新条；刷新后 dirty 为空。
- 点全景后 yaw 变为 `-79.70°`，出现“未保存改动”，`case.toml` mtime 不变。
- 双击第 1 条时弹出“当前草稿有未保存改动，载入这条范围会丢弃这些改动。”；点“载入”后 yaw 回到 `-49.40°`，active 标到第 1 条，dirty 清空。
- 刷新后 draft 与 active 保持：yaw `-49.40°`，active `11-09 16:04`。
- 截图确认左栏“保存的范围”位于全景面板下方，三行时间、几何、最近保存时间、当前标记与删除按钮均可见。

### 抽取页

- 顶部显示 3 条 preset；当前选择标“本次抽取”。
- 版本列表显示 `v1`、`v2`，`v2` 标“最新”，版本行只读；`info.extract_current=v2`。
- 运行抽取按钮可用。

### 合并页

- 出现 2 个几何组：
  - `yaw -30.0° … 帧 0–56`，组头标签“与 11-09 18:51 的范围相同”，版本 `v2`。
  - `yaw -49.4° … 帧 0–56`，组头标签“与 11-09 16:04、11-09 18:51 的范围相同”，版本 `v1`。
- 初始局部选中 `v2`；点击 `v1` 后选中行变为 `v1`，开始合并按钮保持可用。
- 点击版本行前后 `case.toml` mtime 不变，确认局部选版不写 case。
- 合并输入区只显示“上传并用作拼接输入”；没有“从素材库选择”，外部输入未设置时不显示“改用采用结果”。

## 未覆盖与边界

- 未在浏览器里执行真实抽取与合并任务，因此没有新的 `clip.json` 与成片字节对照；显式 `--extract` / `[merge] input` 的 CLI 行为由 `tests/test_range_presets.py` 覆盖。
- 外部视口视频上传后的“改用采用结果”链接与合并门控由 `frontend/tests/unit/merge-step.spec.ts` 的 stub 覆盖，未在浏览器里走真实上传。
- 浏览器验收使用临时 case 副本与手工构造的两份 `clip.json`/`result.mp4`，只用于验证几何分组、标签与局部选版；它们不是真实抽取产物。
