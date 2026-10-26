# 首尾帧页与抽取页排布重做：浏览器验收记录

记录时间：2026-10-26。
背景：`docs/plan/keyframe-page-layout-plan.md` 的首尾帧页（A2 通栏）与抽取页产物条实施完成后，按该文档 §6 做真浏览器验收。
结论：§2 的六个测试点全部通过；页面无 JavaScript 报错；两页在 1440 与 1920 下无横向溢出。

## 1. 环境

- 仓库：vrstudio `main`；首尾帧页提交 `a0f51e7`，抽取页提交 `8695fd2`。
- 前端：Vite 开发服务器 `http://localhost:5173/next/`（`/api`、`/file`、`/img` 代理到 8760），因此验收的是改动后的源码，不是 `static/next` 里的旧构建。
- 后端：`vrstudio serve` 已在 8760 运行（非本轮启动），默认 `cases/`。
- 用例：`walk_4k`（patch，抽取版本 `20261023-085718`，首帧定稿 i2、尾帧定稿 i5、三视图 i1）。
- 只读边界：该 case 已被另一会话锁定，本轮只做读取与视图切换，没有点候选定稿、没有绑定三视图、没有上传，避免写 `keyframe.toml` 与素材目录。
- 浏览器：Playwright MCP，视口 1440×1000 与 1920×1080。

## 2. 测试点与证据

### T1 首帧步骤的四格输入

- 图1 `first_frame_raw.png`、图2 `i1_大臣_三视图.png`、图3 显示「生成并定稿首帧后填入」、目标格显示已定稿的 `i2_keyframe-walk_4k-aez87fha.png`。
- 四格图片地址分别为 `/img/asset/walk_4k/first_raw`、`/img/asset/walk_4k/i1`、`/img/asset/walk_4k/i2`。
- 图2 的文件名来自候选路径的 basename；后端 `sheet_candidates[].label` 是 `@Image1` 这类别名，直接显示不可辨认。
- 尺寸：1440 下每格 269px；1920 下 383px；四格等宽。

### T2 切到尾帧

- 图1 变 `last_frame_raw.png`（`/img/asset/walk_4k/last_raw`）；图2 不变；图3 填入 i2 并标注「来自首帧定稿」；目标格变 `i5_keyframe-walk_4k-3v5ssd_4.png`。
- 候选标题变「尾帧候选」，批次头变 `img-d759363b`，第四张带「已定稿」徽标。
- 交接按钮可用（首尾都已定稿），禁用原因为空。

### T3 三视图抽屉

- 点图2 的「查看 / 更换」打开右侧抽屉，宽 382px；列出 1 张候选，缩略图 `/img/asset/walk_4k/i1`，带「已绑定」标签与完整文件名；底部有「上传三视图」。
- 抽屉脚注左对齐，不再被 Element Plus 的 footer 右对齐带歪。

### T4 候选与任务

- 首帧 4 张、尾帧 4 张，各占一行；1440 下每张 272px，1920 下 386px。
- 批次头显示 `img-…` 与阶段标签；面板头部不再重复批次编号。
- 当前会话没有抽取/生成任务，底部显示「还没有生成任务。」；失败展开与「技术详情」未触发（无任务可造，未覆盖）。

### T5 抽取页

- 控制行：当前版本 `20261023-085718`、两个绿色门槛、「重新抽取」为主按钮。
- 本次产物四格：`clip.mp4`（首帧海报 + 播放）、`clip_mask.png`（`/file` 直出 1920×1080）、`clip.json`、首尾原始帧（两张并排）。
- mask 的 `<img src>` 就是 `open_url`，`/file` 返回 `inline` 与正确 media type，naturalWidth 为 1920。
- 版本与任务并排；页面右侧不再出现 2×2 配对留下的竖向空洞。

### T6 1920 与横向溢出

- 1920×1080 下 `documentElement.scrollWidth - clientWidth = 0`；四格 383px、候选 386px，均在首屏一条线上。

## 3. 控制台与网络

- 控制台只有两条 `409 Conflict`，来自 `/api/case/walk_4k/lock`（case 被另一会话占用），不是本轮改动引入。
- 没有 Vue 运行时错误、没有组件解析失败。

## 4. 门禁

- 前端：`npm run lint` 干净；`npm run typecheck` 通过；`npm run test` 77 条通过；`npm run build` 成功（产物在 gitignore 内）。
- 后端：`uv run ruff check .` 干净；`uv run pytest` 在临时移开本机 `vrstudio.toml` 后 386 条通过（不移开时 `test_web_proxy` 9 例按 `proxy_max_w=2048` 失败，见 `docs/lessons-learned.md` §4）。

## 5. 未覆盖与限制

- **未点候选定稿、未换三视图、未上传**：三条都会写 case 数据或产生服务端文件；该 case 处于锁定状态，留到可写的下一次验收。
- **任务折叠行**：当前 case 没有进行中的生成任务，失败自动展开与「技术详情」只做了单测层面的结构断言，没有真实任务触发。
- **320px 缩略的清晰度**：四格沿用 `/img/asset` 的 320px 缩略，2x 屏会略软；这是既有伺服面的边界，本轮不改。
