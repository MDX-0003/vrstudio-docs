# 统一文件视图：浏览器验收记录

记录时间：2026-10-26。
背景：`docs/plan/unified-file-view-plan.md` 的 WP0–WP5 实施完成后，按 WP5 要求做逐页真浏览器验收。方案与决策见该文档。
结论：全部测试点通过；浏览器控制台 0 错误。

## 1. 环境

- 仓库：vrstudio `main`，WP1–WP5 的提交依次为 `8ae9117`（/file）、`4732c8d`（file_entry）、`40c561f`（FileRow）、`0600950`（图片卡）、`0dafadf`（选区/生成记录/删 /video/out）；WP0 为 `7dfdb60`、`19d21fd`、`0a5e931`。
- 前端：`npm run build` 产物写入 `src/vrstudio/web/static/next/`（gitignore）。
- 服务：`vrstudio serve --port 8773`，默认 `cases/`；用例为 `walk_02`（patch，含抽取、首尾帧定稿与候选、采用轮次、成片）。
- 浏览器：Playwright MCP；开始时发现 profile 被当天 10:55 启动的旧 MCP 实例占用，按 `docs/lessons-learned.md` §1 只清理带 `ms-playwright-mcp` 的进程树后恢复。
- 截图目录：`E:\VRAIGC\vrstudio\logs\gui-test-20261026\`（logs/ 不进 git）。

## 2. 测试点与证据

### T1 抽取页：输出文件行与 /file 原片

- 观察：五个输出（clip.mp4、clip_mask.png、clip.json、first_frame_raw.png、last_frame_raw.png）均显示文件名、仓库相对路径、大小；视频行文案“播放”，其余“打开”；链接均为 `/file?root=cases&p=…`。
- 点击 clip.mp4 的“播放”后新标签页加载 `/file?root=cases&p=walk_02%2Fextracts%2F20261022-164714%2Fclip.mp4`，浏览器原生播放器显示画面。
- 截图：`t1-extract-files.png`、`t1b-clip-open.png`。

### T2 选区页：源片文件行

- 观察：播放器工具条下新增一行，名字 `单小白人.mp4`、路径 `sources\单小白人.mp4`、18.0 MB、“播放”链接 `/file?root=sources&p=%E5%8D%95…`。内嵌播放仍走 `source_url`/代理，互不影响。
- 截图：`t2-pick-source-row.png`。

### T3 首尾帧页：底图、定稿图、候选图

- 观察：两张原始帧与两张定稿图的右上角都有打开图标，分别指向 cases 下的原始帧与素材原图；候选网格四张图各有一个打开图标，链接为 `/file?root=workdir&p=walk_02%2Fimg-1ce2b5e4%2Fresult_N.png`。
- 结构：打开链接是候选按钮的兄弟节点，不在按钮内部；点击候选 1 的打开链接后，已定稿仍停在第 2 张（`picked` 索引仍为 `[1]`，徽标数 1），说明没有误触发定稿。
- 原图页：新标签页标题为 `file (3840×2160)`，即 4K 候选原图。
- 截图：`t3-keyframe-open-links.png`、`t3b-keyframe-candidates.png`、`t3c-candidate-original.png`。

### T4 生成页：素材卡与逐轮生成记录

- 观察：四张素材卡（clip.mp4、三视图、首帧定稿、尾帧定稿）的操作用前列均有“打开素材原文件”图标，链接指向 cases 内原文件。
- 生成记录 3 条，每条都带 result.mp4（“播放”）与 run.json（“打开”），路径形如 `vrgen_runs\walk_02\gen-multi-730e1703\result.mp4`，链接为 `/file?root=workdir&p=…`；未采用的轮次同样有文件行。
- 截图：`t4-generate-assets-and-rounds.png`、`t4b-generate-round-files.png`。

### T5 合并页：输入、输出与成片

- 观察：合并输入四行（源片、轮次 result.mp4、clip.json、clip.mp4）与合并输出一行都带路径、大小与打开/播放链接；“成片”面板的播放链接已从 `/video/out` 改为 `/file`。
- 截图：`t5-merge-files.png`。

### T6 对比页：不加文件行（既定边界）

- 观察：页面上只有两路播放器与控制，没有文件行；`/video/out` 删除后右路回退走 `open_url`，代理就绪时仍走 outproxy。
- 截图：`t6-compare-no-file-rows.png`。

### T7 台账 run.json 的原生打开

- 观察：`/file?root=workdir&p=walk_02%2Fgen-multi-730e1703%2Frun.json` 以 `application/json` 内联展示，`document.contentType` 为 `application/json`，内容为正文本。
- 按方案 §3.1 记录的安全边界，该文件含带 `q-ak`/`q-signature` 的签名下载 URL；本次仅本机验证，未对局域网开放。
- 截图：`t7-run-json-inline.png`。

## 3. 门禁结果

- 后端：`uv run ruff check .` 通过；`uv run pytest tests/test_web_console.py` 111 passed（全量 pytest 在提交前另行执行）。
- 前端：lint、format:check、typecheck 通过；vitest 21 个文件 71 用例通过（含 FileRow 4、FileOpenLink 3、GenerateAssets 2、KeyframeStep 2、GenerateResults 2、PickStep 4、ExtractStep 5）。
- 浏览器控制台：0 错误、0 警告。

## 4. 未覆盖

- 未测试 `--host 0.0.0.0` 下的 /file 访问控制（方案已记录需另做鉴权或收窄）。
- 8K 原片在软解环境的卡顿未复测（用户已知并接受）。
