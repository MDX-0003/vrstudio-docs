# Web 控制台技术栈对比（决策 11 的论证文档）

本文比较三条路线，服务于 M4 已拍板的交互目标（决策 12–16）：**软向导**页面流、
pick 原样交互（全景点击定视口/拖框定 inner/nudge 微调/逐帧浏览）、generate 页
**轮询任务状态 + mglc.log tail + 断点续跑提示**、末尾**同步播放 + 滑动对比**。

结论先行：**推荐路线 A（沿用 Starlette + jinja2 + 原生 JS），按需局部引入无构建
依赖的小工具库**。理由与让步见 §4。

## 0. 现状盘点（旧 vrpatch web 骨架）

| 部分 | 规模 | 内容 |
|---|---|---|
| `app.py` | 495 行 | Starlette 路由 13 条（页面 1 + 图片 1 + API 11）、asyncio 任务队列 |
| `dashboard.html` | jinja2 单页 | 单 dashboard，pick/extract/merge 全在一页 |
| `dashboard.js` | 411 行 | 任务轮询、状态渲染、对比图 |
| `pick.js` | 134 行 | 全景点击定视口、inner 拖框、nudge、逐帧浏览 |

依赖：`starlette + uvicorn + jinja2`（numpy/opencv 是库本身的依赖，与 web 层无关）。
没有 Node、没有构建步骤、没有 npm 锁文件——`uv run` 起服务即用。

M4 要在它之上加的**新前端能力**只有三块，都不重：
1. case 列表 + 向导框架（步骤条 + 置灰门控）——纯 DOM，比旧单页简单；
2. generate 页轮询 + 日志 tail——旧 dashboard.js 已有轮询骨架，tail 是增量；
3. 同步播放 + 滑动对比——两个 `<video>` 共享 currentTime + 一条拖动分割线，
   100 行以内的原生 JS；真要省事可用 CDN 引入一个无构建的对比组件。

## 1. 路线 A：原样沿用（Starlette + jinja2 + 原生 JS）

**做法**：app.py/tasks.py/render.py 骨架照迁；页面从单 dashboard 拆成向导流；
旧 pick.js/dashboard.js 改造复用；后端 API 从"读 vrpatch 私有 case"改为调
`vrstudio case.py` + subprocess CLI（决策 1/4 的既有架构）。

- ✅ 零新依赖、零构建链；CI 不需要 Node；`uv run vrstudio serve` 即用。
- ✅ 符合 AGENTS.md"原样迁入"精神与 M2/M3 的搬迁节奏；495+545 行旧代码里
  pick 交互与任务队列是验证过的资产，直接继承。
- ✅ 服务端渲染 + 少量 API，向导的"下一步置灰门控"用服务端判（draft_ready /
  extract_current / adopt_round 现成的守卫函数），逻辑不复制到前端。
- ⚠️ 交互多了之后手写 DOM 状态会变琐碎（向导步骤切换 × 轮询刷新叠加）；
  无组件化，两条流程页面会有一定 HTML 重复（jinja2 宏可缓解大半）。
- ⚠️ 前端没有类型检查，JS 改错只能在浏览器里发现。

## 2. 路线 B：Starlette + HTMX（+ Alpine.js）

**做法**：后端不动；HTML 片段端点代替手写 `fetch + innerHTML`；
Alpine 处理滑动对比、pick 画布这类纯客户端状态。

- ✅ 仍是零构建（两个 CDN/ vendored js 文件），但把"轮询刷新/日志 tail/步骤
  置灰"从手写 JS 变成 `hx-get + hx-trigger="every 2s"` 声明式一行——这恰好
  命中 M4 交互的主体（轮询 + tail + 门控），代码量预计比 A 少三成。
- ✅ 状态留在服务端，与"唯一权威点在 Python 侧守卫函数"的架构气质一致。
- ⚠️ 引入两个新前端依赖（可 vendor 进 static/，避免运行时 CDN 依赖）；
  pick 的 canvas 交互（拖框/nudge/逐帧）HTMX 管不了，仍是原生 JS——
  即 pick.js 那 134 行照旧要迁，只是换触发方式。
- ⚠️ 团队（含 AI 协作者）需要学 HTMX 属性集；调试多一层"片段端点"。
- ⚠️ 偏离"原样迁入"：dashboard.js/pick.js 的改造成本与 A 相当，收益集中在
  generate/向导页。

## 3. 路线 C：前后端分离（Vue/React + Starlette 纯 API）

**做法**：vrstudio 只出 JSON API；前端独立工程（Vite + Vue3/React），构建产物
进 static/。

- ✅ 交互天花板最高：组件化的向导、帧级 scrub 时间线、多 case 管理仪表盘
  都顺手；前端有类型（TS）与单测。
- ⚠️ 引入整条 Node 工具链：package-lock、构建步骤、CI 要加 Node job——
  违反本仓库"门禁 = uv run pytest + ruff"的简单性；AGENTS.md 未给前端立项。
- ⚠️ 服务端渲染资产（jinja2 模板）全部废弃，旧 web 代码只剩 API 形状可参考；
  相当于 web 层重写，M4 工作量估算是 A 的 2–3 倍。
- ⚠️ 本工具是**单用户本地工具**（一台 Windows 工作站、一个浏览器），
  分离架构解决的多端/多人/部署问题在这里不存在。

## 4. 对比与推荐

| 维度 | A 原生 | B HTMX | C 分离 |
|---|---|---|---|
| 新增依赖 | 0 | 2 个 vendored js | Node 全家桶 |
| 构建步骤 | 无 | 无 | Vite 构建 + CI 加 Node |
| M4 工作量 | 基准 | ≈A（generate 页省，pick 页照旧） | 2–3×A |
| 旧代码复用 | 直接 | 大半 | 仅 API 形状 |
| 交互上限 | 够用（本轮需求全够） | 够用 | 最高 |
| 契约/测试影响 | 无 | 无 | API 面扩大，需立前端契约 |

**推荐 A**，附两条让步：
- 向导/轮询页面若手写 DOM 出现明显疼痛，**允许升级到 B**——A 与 B 的后端
  完全同构（HTML 片段端点是超集），届时只是前端逐步换写法，不是重构；
- 滑动对比若手写超预期（视频同步受编解码器时钟漂移影响），允许 vendor 单个
  无构建对比组件，不引构建链。

不推荐 C：它支付的是"多人多端产品"的成本，买不到本地单用户工具用得上的东西。

## 5. 若采纳 A，M4 web 段的落点（预览，动工前再细化）

```
vrstudio/src/vrstudio/web/
  app.py        # Starlette 路由：页面（case 列表 + 向导）+ API
  tasks.py      # 队列：subprocess 跑 vrstudio/vrgen CLI（决策 1/4）
  render.py     # PreviewStore（pick 帧浏览的帧图缓存）
  templates/    # cases.html + wizard_patch.html + wizard_fullredraw.html
  static/       # pick.js（迁）+ wizard.js + compare.js（新）
```

向导门控的服务端判据（现成函数，web 只是调用方）：
`draft_ready` / `check_source` / `extract_current` / `adopt_round` /
vrgen 台账（经 CLI 查 status，不越契约读内部文件……台账文件本身是契约接口，读无妨）。
