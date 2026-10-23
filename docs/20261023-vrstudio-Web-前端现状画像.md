# vrstudio Web 前端现状画像

以下所有路径均以 `E:\VRAIGC\vrstudio\src\vrstudio\web` 为根，行号为当前工作区实际行号。

------

## 一、总体结论

- 后端是 Starlette + uvicorn + Jinja2，不是标准库 `http.server`，也不是 Flask/FastAPI。`E:\VRAIGC\vrstudio\src\vrstudio\web\app.py:27-30` 引入 `Starlette`/`Route`/`StaticFiles`；`pyproject.toml:22-26` 把 `starlette>=0.37`、`uvicorn>=0.30`、`jinja2>=3.1` 放在 `web` 可选依赖；启动入口在 `E:\VRAIGC\vrstudio\src\vrstudio\cli\serve.py:27-45`（`uvicorn.run(build_app(cases_dir), ...)`）。
- 前端是"两层壳 + 单页应用式面板"：`cases.html` 是 case 列表/新建页，`wizard.html` 用一页承载三条流程的全部步骤面板；数据全部通过 `fetch` + JSON 获取，Jinja 只渲染 `name`/`flow` 两个变量。
- 无任何前端框架、无 npm、无打包器、无 CSS 文件。原生 DOM + 手写 WebGL；CSS 全写在两个 HTML 的 `<style>` 块和零散 `style=""` 属性里。
- 状态管理的核心是一个 36KB 的全局对象 `info`：每个会改动状态的请求都把整份 `info` 换掉，然后无条件重跑 12 个渲染函数。这是理解现有实现的关键，也是最大的耦合点。
- 代码组织的主要问题集中在三处：`app.py` 2216 行单文件、`wizard.js` 980 行单文件、两处 `renderAll` 式全量重渲染；另有大量字符串拼 HTML、重复渲染逻辑和硬编码绝对路径。

------

## 二、后端框架与路由清单

框架与装配：

- 路由表是显式的 `routes = [...]` 列表，位于 `app.py:2144-2185`；`build_app` 在 `app.py:2209-2216` 组装 Starlette、挂 `NoStoreMiddleware`（禁用缓存）与 `RequestLogMiddleware`，并把 `/static` 挂到 `StaticFiles`。
- Jinja 环境启用 `autoescape=True`（`app.py:64-65`），但实际只渲染页面壳：`app.py:179-190`。
- 全局上下文只有一个 `_ctx = {"cases_root": None}`（`app.py:68`），属于单人本地工具的写法（`__init__.py:1-4` 也写明"单人本地优先"）。

页面与媒体路由（默认 GET）：

- `GET /`：渲染 `cases.html`，即 case 列表 + 新建 case（`app.py:179-180`）。
- `GET /case/{name}`：渲染 `wizard.html`，只注入 `name` 与 `flow`（`app.py:183-190`）。
- `GET /img/{name}/{file}`：pick 步骤下方视口预览 PNG，`?frame=N` 指定帧（`app.py:249-268`）。
- `GET /img/asset/{name}/{file}`：素材/候选缩略图，按需现算 JPEG（`app.py:1194-1229`）。
- `GET /img/keyframe/{name}/{round}/{index}`：首尾帧候选图（`app.py:1704-1723`）。
- `GET /video/source/{name}`：源视频（`app.py:196-204`）。
- `GET /video/proxy/{name}`：源片的浏览器可播代理；未就绪返回 404（`app.py:218-227`）。
- `GET /video/out/{name}/{file}`：成片（`app.py:207-215`）。
- `GET /video/outproxy/{name}/{file}`：成片的 4K 预览代理（`app.py:230-246`）。

API 路由（共 28 条，`app.py:2154-2184`）：

- `GET|POST /api/cases`：列表返回 name/flow/gates 摘要；POST 新建 case（`app.py:1012-1075`、`1078-1085`）。
- `GET /api/case/{name}`：向导页唯一主数据源，返回完整 `info`（含 assets/extracts/outputs/step_files/gates/previews/rounds 等），并现场附加 `generation_params` 与 `prompt`（`app.py:1137-1153`；字段清单在 `app.py:966-1002`）。
- `POST /api/case/{name}/draft`：写 pick 草稿的 viewport/inner/frames（`app.py:1802-1819`）。
- `POST /api/case/{name}/prompt`：提示词变量 set/unset（`app.py:1726-1757`）。
- `POST /api/case/{name}/params`：生成参数、分辨率、项目会话等（`app.py:1760-1796`）。
- `POST /api/case/{name}/assets`：素材 add/remove/role/reorder（`app.py:1232-1272`）。
- `GET /api/case/{name}/derived`：流程产物列表（`app.py:1286-1292`）。
- `GET|PUT /api/case/{name}/submit`：提交集 `[submit] selected` 的读写（`app.py:1295-1317`）。
- `POST /api/case/{name}/extract-frames`：已退役，固定返回 410（`app.py:1320-1323`），前端无调用方。
- `POST /api/case/{name}/keyframe/run`：排队首/尾帧图片生成（`app.py:1481-1489`）。
- `GET /api/case/{name}/keyframe/rounds`：候选批次（`app.py:1492-1496`）。
- `POST /api/case/{name}/keyframe/pick`：选定首/尾帧定稿（`app.py:1600` 起）。
- `GET|PUT /api/case/{name}/keyframe/sheet`：绑定人物三视图（`app.py:1517-1543`）。
- `GET|PUT /api/case/{name}/keyframe/prompt`：图片步变量读写（`app.py:1546-1569`）。
- `POST /api/case/{name}/keyframe/handoff`：切到 firstLastFrame 并勾选两帧（`app.py:1572-1597`）。
- `GET /api/sessions`：项目/剧集/会话树，每次现查 vrgen（`app.py:1156-1160`、`389-394`）。
- `GET /api/modes`：新建 gen case 的模式列表（`app.py:1163-1169`）。
- `POST /api/case/{name}/viewport`：点全景定位视口（`app.py:1822-1833`）。
- `POST /api/case/{name}/viewport-size`：切换视口分辨率（`app.py:1836-1861`）。
- `POST /api/case/{name}/inner`：拖框保存选区（`app.py:1864-1881`）。
- `POST /api/case/{name}/nudge`：摇杆微调 yaw/pitch（`app.py:1884-1896`）。
- `POST /api/case/{name}/reset-draft`：回退到当前 extract 的 viewport/inner（`app.py:1899-1919`）。
- `POST /api/case/{name}/run`：统一任务入口，`op` 决定 CLI argv（`app.py:2000-2013`，op 注册表 `app.py:1925-1982`）。
- `GET|POST /api/case/{name}/proxy`：查询或触发源片/成片代理构建（`app.py:2073-2111`）。
- `GET /api/task`：任务队列状态与日志尾部（`app.py:2016-2017`）。
- `POST /api/client-log`：浏览器错误上报（`app.py:2028-2070`）。
- `GET /api/browse`：本地目录浏览，支持 `kinds=assets` 过滤视频/图片（`app.py:2120-2141`）。
- `GET /api/sources`：`sources/` 下的视频清单（`app.py:2114-2117`）。

路由之外的执行模型：所有长任务进单通道队列 `QUEUE.submit`，跑 `python -m vrstudio ...` 子进程（`app.py:2008-2012`、`tasks.py:105-133`），前端只轮询 `/api/task`。

------

## 三、页面清单与跳转

真正的 HTML 页面只有 2 个，另有 6 个 partial：

- `templates/cases.html`（150 行）：case 列表 + 新建 case 表单。列表项点击即 `location.href = "/case/<name>"`（`cases.html:78`）；创建成功后同样跳转（`cases.html:145`）。

- ```
  templates/wizard.html
  ```

  （335 行）：向导页壳。所有步骤面板一次性输出到同一 DOM：

  - `#pnl-pick` 选区（`wizard.html:200-239`）
  - `#pnl-extract` 抽取（`242-248`）
  - `#pnl-keyframe` 首尾帧，仅 patch 流程渲染（`250-256`，`{% if flow == "patch" %}`）
  - `#pnl-generate` 生成（`259-261`，内含 assets/prompt/外部成片/提交条）
  - `#pnl-merge` 合并（`264-269`）
  - `#pnl-pad`、`#pnl-recompose` 全流程重绘两步（`272-289`）
  - `#pnl-compare` 对比（`292-314`）
  - 任务记录区（`316`，来自 `partials/tasks.html`）、文件浏览器弹层（`318-322`）

- partials：`assets.html`（素材侧栏 + 多选浏览器）、`prompt.html`（提示词）、`keyframe.html`（首尾帧工作台）、`generate.html`（组合生成面板）、`submitbar.html`（底部固定提交条）、`tasks.html`（任务日志）。

页面间跳转只有两处，全部是整页导航：

- case 列表 → 向导：`cases.html:78`、`cases.html:145`。
- 向导 → 列表：`wizard.html:195` 的"← case 列表"链接；另外 `/api/case` 404 时前端也跳回 `/`（`wizard.js:54`、`common.js:51`）。

步骤切换不产生页面跳转，也不写 URL：`curStep` 只是 JS 内存变量（`common.js:12`），`showStep()` 通过给面板加 `.cur` 类切换显示（`wizard.js:34-48`）。刷新页面会回到第一步（`wizard.js:978`）。

三条流程的步骤定义：

- `patch`：选区 → 抽取 → 首尾帧 → 生成 → 合并 → 对比（`wizard.js:10-11`）
- `fullredraw`：扩充画面 → 生成 → 裁回原尺寸 → 对比（`wizard.js:12-13`）
- `gen`：生成（`wizard.js:14`）

------

## 四、前端技术栈与 CSS

技术栈：

- 原生 DOM API，无 React/Vue/jQuery，无模板运行时。DOM 构造混用两种方式：约 50 处 `document.createElement`，40 余处 `innerHTML` 赋值。
- 10 个独立 JS 文件，总计约 2845 行：`wizard.js` 980、`keyframe.js` 488、`assets.js` 359、`params.js` 298、`prompt.js` 225、`erp360.js` 181、`pick.js` 134、`common.js` 77、`clientlog.js` 67、`tasks.js` 36。
- 手写 WebGL 全景对比器：`erp360.js:14-41` 内嵌 GLSL 顶点/片元着色器，`Erp360Compare` 类在 `erp360.js:47-181`，用 scissor 在一个 canvas 上并排画两路 ERP 视频。
- 无任何第三方 CDN 资源；脚本以 `<script src="/static/...">` 顺序加载（`wizard.html:324-333`、`cases.html:61`）。

CSS 承载位置：

- `wizard.html` 内联 `<style>` 块：第 6 行到第 191 行，约 186 行 CSS，约 5.6KB。
- `cases.html` 内联 `<style>` 块：第 6 行到第 33 行，约 28 行 CSS。
- 模板内联 `style=""` 属性：共 28 处（`wizard.html:195-321` 14 处，`assets.html` 5 处，`prompt.html` 3 处，`cases.html` 3 处，`keyframe.html` 2 处，`generate.html` 1 处）。
- 没有任何 `.css` 文件；`static/` 下只有 JS（目录清单已在上面）。

设计 token 与变量：

- 只用了 1 个 CSS 自定义属性 `--submit-bar-h`（`wizard.html:130` 的 `.gen-step`，由 `wizard.js:633-637` 的 `syncSubmitBarHeight` 写入），用途是给固定底栏留出 padding，不是设计 token。
- 颜色全是重复字面量：`wizard.html:8-9` 与 `cases.html:8-9` 各自重复定义 `#faf6ef`/`#3d362c`/`#5a4a30`；`#fffdf8` 在 `wizard.html` 出现 7 行、`cases.html` 出现 1 行；两页的 badge/button/select 样式几乎是复制粘贴（`wizard.html:10-13,47-53` 对 `cases.html:16-27`）。
- 布局是固定像素：`#scrub` 宽 512px（`wizard.html:45`）、对比区 800×450（`wizard.html:62-63`）、`#cmpCtl` 800px（`wizard.html:69`）；全文件没有一条 `@media`（grep 无命中）。

------

## 五、状态管理与数据流

状态分布：

- 服务端是唯一权威：case 配置、草稿、提交集、提示词都写磁盘经由 `vrstudio.case` / vrgen（`app.py:1-10` 的文件头明确写了"web 层只是编排层"）。
- 前端主状态是 `common.js` 里的 6 个全局变量：`CASE`、`FLOW`、`info`、`curStep`、`wasRunning`、`vpFrame`，另有 `sessionTree`（`common.js:8-15`）。各模块还有自己的模块级全局：`assetPick`（`assets.js:23`）、`kfPrompts/kfRounds/kfPending`（`keyframe.js:12-17`）、`preview`（`wizard.js:544`）、`promptView/pendingPromptSaves`（`prompt.js:9-11`）。
- 没有 localStorage、sessionStorage、URLSearchParams、location.hash、history API 的用法（对 `static/` 与 `templates/` 做过全量 grep，无命中）。
- URL 只承载"当前是哪个 case"（`/case/{name}` 路径参数，`app.py:2146`）和页面种类；步骤、选中素材、面板展开状态都不进 URL。

数据从后端到前端的方式：

- 100% `fetch` + JSON，没有任何 `<form>` 提交。通用封装是 `post()`（`common.js:46-64`）与 `run()`（`common.js:66-76`）；页面脚本里还有 23 处直接 `fetch` 调用（wizard 5、keyframe 7、cases 4、assets 2、common 2、params 1、prompt 1、tasks 1）。
- Jinja 只做页面骨架：只有 `name`、`flow` 两个变量（`app.py:189-190`），落到 `body data-name/data-flow`（`wizard.html:193`），前端在 `common.js:8-9` 读取。其余内容都由 JS 渲染。
- 大部分写接口的响应就是"整份新 `info`"，前端直接替换全局对象后重绘：`app.py:1272`（assets）、`1317`（submit）、`1543`（sheet）、`1597`（handoff）、`1796`（params）、`1755-1757`（prompt）。`prompt` 接口还会把保存回显直接塞进 `info["prompt"]`。
- 几何类高频接口是例外，只回精简 payload（`app.py:151-164`），所以 `post()` 里专门补丁式保留 `generation_params` 与 `prompt`（`common.js:58-61`）——两种响应契约并存，是隐式约定。
- 轮询：任务状态 2 秒一次（`wizard.js:979-980`）；源片代理与成片代理各自 2 秒轮询（`wizard.js:276`、`846`）。

------

## 六、主要交互模式与操作流

1. 选 case / 建 case（`cases.html:63-146`）
   - 进入页面并发拉取 `/api/cases`、`/api/sources`、`/api/modes`（`cases.html:147`）。
   - 选流程（`flowSel`，`cases.html:46-50`）；gen 必须选模式，patch/fullredraw 必须选源视频（`cases.html:110-135`）。
   - 点"创建"发 POST `/api/cases`，成功即整页跳到 `/case/<name>`（`cases.html:136-145`）。
2. 选区（pick，仅 patch）（`wizard.js:60-455`）
   - 顶部 ERP 视频 + 帧滑块/上一帧/下一帧/播放（`wizard.html:203-214`，事件在 `wizard.js:397-405`）。
   - 点全景任意位置 → POST `/viewport`（`wizard.js:336-340`）。
   - 在下方视口图上拖框 → 松手 POST `/inner`（`pick.js:92-131` 提供拖拽器，提交在 `wizard.js:406-436`）；拖拽期间只动本地虚线框，不等服务端（`wizard.js:281-294`、`406-436`）。
   - 摇杆按住持续 POST `/nudge`，100ms 一次（`wizard.js:437-446`）。
   - 视口尺寸下拉 → POST `/viewport-size`（`wizard.js:185-192`）；下拉选项由服务端 `viewport_options` 下发（`app.py:121-130`）。
   - 抽取帧范围 → POST `/draft`（`wizard.js:449-451`）；"重置选区"→ POST `/reset-draft`（`wizard.js:453-455`）。
   - 逐帧预览图 URL 带 `&frame=N`，150ms 防抖（`wizard.js:70-73`、`107-110`）。
3. 抽取出片（`wizard.js:457-471`）
   - 读 `info.gates.pick.ok` 决定按钮禁用（`wizard.js:461-462`）。
   - 点"运行抽取"→ POST `/run {op:"extract"}`（`wizard.html:245` → `wizard.js:680` → `app.py:1931-1932`），随后只靠任务轮询与收尾 `loadInfo()` 刷新（`tasks.js:30-33`）。
4. 首尾帧工作台（patch 专用）（`keyframe.js:41-488`、`partials/keyframe.html`）
   - 展示两张原始帧（`keyframe.js:79-108`）。
   - 选图片模型/分辨率/三视图（`keyframe.html:13-29`）；三视图选择 PUT `/keyframe/sheet`（`keyframe.js:175-186`）。
   - 四个变量（figure/pose_first/pose_last/preserve）在卡片里编辑，400ms 防抖 PUT `/keyframe/prompt`（`keyframe.js:243-274`）。
   - "生成候选"→ POST `/keyframe/run`（`keyframe.js:421-444`），候选按批次渲染（`keyframe.js:324-363`）。
   - 点某张候选"设为首帧/尾帧定稿"→ POST `/keyframe/pick`（`keyframe.js:446-458`），服务端可能自动排队尾帧批次。
   - "用这两帧生成视频"→ POST `/keyframe/handoff`，然后自动 `showStep("generate")` 并把时长调到最接近 clip 的整秒（`keyframe.js:460-488`）。
5. 生成（三条流程共用）（`wizard.js:473-685`、`partials/generate.html`、`submitbar.html`）
   - 素材：勾选参与本次提交 → PUT `/submit`（`assets.js:46-57`）；全选/全不选/反选（`assets.html:9-11`）；改角色/上移下移/拖拽排序/删除 → POST `/assets`（`assets.js:79-182`）；"添加视频或图片"打开本地目录多选 → GET `/api/browse?kinds=assets` → POST `/assets op=add`（`assets.js:264-359`）。
   - 提示词：完整预览/模板骨架切换、变量卡片编辑（400ms 防抖 POST `/prompt`）、添加/删除变量（`prompt.js:22-225`）。
   - 生成设置：模式/比例/输出分辨率/输入缩放/时长 → POST `/params`（`params.js:68-155`）；项目/剧集/会话 → POST `/params`（`params.js:268-298`）。
   - 底栏状态：服务端 gates 的 `ready/reason` + 本地"预演签名"比对（素材/参数/提示词/额度四类），任一项变化即标"预演已过期"（`wizard.js:544-631`）。
   - "预演检查（不扣费）"→ POST `/run {op:"dry_run"}`；"提交生成"→ POST `/run {op:"submit"}`（`wizard.js:664-685`），参数直接取自底栏下拉（`wizard.js:669-676`）。
   - 成片生成后"选用成片"→ POST `/run {op:"adopt"}`（`wizard.js:504-539`）。
6. 合并 / 裁回 / 对比（`wizard.js:689-937`、`wizard.html:264-314`）
   - 合并、扩充画面、裁回原尺寸都是 `/run {op:...}`（`wizard.html:267,277,287`）。
   - 对比：下拉选成片 → 两路隐藏 video 同步播放 → `Erp360Compare` 画到 canvas；拖动中间竖线改分割比例（`wizard.js:921-936`、`erp360.js:102`），画布拖动转头、滚轮变焦、`回正视角`复位（`erp360.js:120-141`、`wizard.js:919`）。
   - 源片/成片任一缺 4K 代理都会后台触发构建并轮询（`wizard.js:248-278`、`812-848`）。
7. 外部成片登记：`openBrowse()` → GET `/api/browse` → 点文件 → POST `/run {op:"register"}`（`wizard.js:941-971`）。

------

## 七、代码组织上的明显问题（带证据）

1. 单文件过大，职责混杂
   - `app.py` 2216 行 / 99KB：路由表、页面渲染、缓存代理、OpenCV 缩略图、几何计算、任务 argv 组装、日志全部混在一个模块（`app.py:2144-2185` 是路由，`1925-1982` 是 op 注册表，`1172-1191` 是缩略图，`133-173` 是几何 payload）。同类逻辑本可拆成 `routes_media.py`、`routes_keyframe.py`、`thumbs.py` 等。
   - `wizard.js` 980 行 / 36.5KB：步骤条、pick 全部交互、提交条、文件列表、对比器接线、目录浏览器、启动逻辑都在一个文件（`wizard.js:18-48`, `60-455`, `541-685`, `745-774`, `776-937`, `939-971`）。
2. 大量字符串拼 HTML，且与 createElement 混用
   - `wizard.js:467-469` 在循环里 `el.innerHTML += ...` 拼接版本列表，每次迭代都触发整段 HTML 重新解析。
   - `wizard.js:856-858` 用模板字符串拼 `<option>`；`params.js:101-105` 同样拼 option；`assets.js:122-123` 拼素材卡片元信息。
   - `cases.html:75-77` 把 `c.flow`、`c.name` 直接塞进 `innerHTML`，`cases.html:87-88`、`99-101` 拼 `<option>` 与文件名，没有转义。服务端 Jinja 开了 `autoescape`（`app.py:64-65`），但客户端的这些拼接绕过了它。
   - 同一份 UI 里既有 `document.createElement`（如 `keyframe.js:285-363` 整段），又有 `innerHTML`，维护时要在两套写法之间切换。
3. 同构渲染逻辑重复
   - 变量卡片：`keyframe.js:188-241`（`renderKfVars`）与 `prompt.js:78-167`（`_varCard`/`renderPrompt`）几乎逐行对应（都是 details + summary + vname/vkey/vhelp + textarea + autoGrow）；防抖保存也是两份（`keyframe.js:243-274` 对 `prompt.js:170-201`）。
   - 视频源切换：`wizard.js:200-211`（`setVideoUrl`）与 `wizard.js:781-792`（`_cmpSetSrc`）逻辑一致，只差 `src` 与 `dataset.want` 的比较方式。
   - 代理轮询：`wizard.js:248-278`（`ensureProxy`）与 `wizard.js:812-848`（`ensureOutProxy`）是同一套 setInterval + 状态文案分支，状态文案又在 `wizard.js:231-245` 与 `794-809` 各写一遍。
   - 格式化函数三份近似实现：`_fmtRoundTime`（`wizard.js:479-486`）、`_fmtMtime`（`711-717`）、`_fmtTime`（`882-884`）。
4. 全量重渲染 + 手动维护的渲染函数注册表
   - `common.js:37-44` 用字符串数组列出 12 个渲染函数，靠 `typeof window[name] === "function"` 跳过未加载者。新增模块必须同时改这里和 `wizard.html` 的 script 顺序。
   - `post()` 每次成功都把 `info = d` 后调用 `renderAll()`（`common.js:56-63`），意味着改一个素材角色会重跑 steps、assets、pick、extract、result、params、submitbar、finish、files、prompt、compare、keyframe 全部渲染。`loadInfo()` 同理（`wizard.js:52-58`）。
   - 后端对大多数写操作回整份 info（`app.py:1272`、`1317`、`1543`、`1597`、`1796`），与几何端点回精简 payload（`app.py:151-164`）形成两套契约，前端用补丁式合并来兼容（`common.js:58-61`）。
5. 全局命名空间与加载顺序耦合
   - 所有脚本都没有模块化（无 `type="module"`、无 IIFE 包裹公共代码）；`CASE`、`FLOW`、`info`、`$` 是全局的（`common.js:8-25`），`renderAll` 依赖函数名全局可见（`common.js:38-42`）。
   - 脚本顺序被硬编码在 `wizard.html:324-333`，`clientlog.js` 必须最先、`wizard.js` 最后。`keyframe.js:45-46`、`loadSessions` 里 `params.js:261` 都用 `typeof ... === "function"` 做防御式调用，说明模块间存在隐式可选依赖。
   - 全局可变状态分散：`info` 在 `common.js:11`，但 `assets.js:55`、`keyframe.js:183/453/467`、`prompt.js:196/207/219` 都直接赋值 `info = d`，绕过统一的 `post()`。
6. 事件绑定方式混杂
   - HTML 内联处理器约 32 处：`submitbar.html` 11 处（`:5,8,11,14,17,21,23,30,33,36,38`）、`assets.html` 6 处（`:9-11,17,28,33`）、`wizard.html` 9 处（`:218,235,237,245,267,277,287,298,319`）、`keyframe.html` 3 处、`prompt.html` 2 处、`generate.html:10`。
   - JS 侧又用 `onclick = ...` 直接赋值（`wizard.js:29,400-405,911,919`）和 `addEventListener`（wizard.js 26 行、erp360.js 5 行、pick.js 3 行、keyframe.js 1 行）。三种风格并存，销毁/重建 DOM 时容易出现监听重复绑定；`wizard.js:930-936` 用临时 add/remove 的写法尤其不易读。
7. CSS 散落与主题重复
   - 两页各写一套色板与控件样式（`wizard.html:8-53`、`cases.html:8-27`），`#fffdf8` 等字面量重复十几次；没有变量、没有共享文件。
   - 28 处 `style=""` 承担布局（`wizard.html:195-321`），其中 `width:512px`、`max-height:300px`、`float:right` 这类都应在样式表里。
   - 固定像素尺寸与零 `@media`（`wizard.html:45,62-63,69`）意味着窄屏下对比器会横向溢出。
8. 硬编码路径与已退役接口残留
   - `wizard.js:943` 和 `assets.js:270` 把初始浏览目录写死为 `E:\VRAIGC`；后端 `/api/browse` 默认用 `config_mod.REPO_ROOT`（`app.py:2122`）。换机器或换仓库位置就要改前端源码。
   - `/api/extract-frames` 仍挂在路由表（`app.py:2162`），实现固定 410（`app.py:1320-1323`），前端无任何调用。
   - `_canEditAssets()` 恒为 `true`（`assets.js:34-36`），调用处的条件判断是死代码（`assets.js:241`）。
   - `GET /api/case/{name}/submit` 分支（`app.py:1302-1303`）与 `GET /keyframe/sheet` 分支（`app.py:1523-1526`）前端都未使用，前端只发 PUT（`assets.js:49-51`、`keyframe.js:177-180`）。
9. 状态不进 URL、刷新即丢失
   - 当前步骤只是内存变量（`common.js:12`、`wizard.js:34-48`），启动时固定回到第一步（`wizard.js:978`）。用户在第 5 步刷新或从任务通知里回到页面，会回到选区步骤，需要重新点。
   - 对比页选中的成片、展开的折叠面板、面板切换状态同样不持久化。
10. 手工缓存版本号
    - 每个脚本的 `?v=N` 是人工维护的（`wizard.html:324-333` 中 v=1/4/5/3/6/3/3/2/12；`cases.html:61` v=1），靠开发者记得改；`NoStoreMiddleware` 只保证 HTML 与 API 不缓存（`app.py:2188-2206`），静态文件本身由 `StaticFiles` 正常返回。

------

## 八、构建工具现状

- 没有 `package.json`、没有 `node_modules`、没有 `vite.config.*` / `webpack.config.*`、没有 `.bundle.js` / `.min.css`（在 `E:\VRAIGC` 下做过全量查找，均无结果）。
- 前端资源就是 `static/` 下的 10 个原始 `.js`，由 Starlette 的 `StaticFiles` 直接挂在 `/static`（`app.py:2214-2215`），不做转译、不做压缩、不做模块解析。
- 浏览器端能跑的语法是 ES2020 级别（可选链 `??`、模板字符串、class、`Object.fromEntries`），依赖现代浏览器；`erp360.js` 要求 WebGL，不支持时降级为一段提示文字（`erp360.js:57-64`）。
- 唯一的"工具链"证据是 Python 侧依赖声明：`pyproject.toml:22-26`。前端没有任何构建步骤，也没有 lint/format 配置。

------

## 九、后续讨论前端方案时值得先定的几件事

- 是否保留"一页装下所有步骤"的形态，还是拆成真正的多路由页面。当前所有面板同处一页（`wizard.html:200-314`），而每条流程只用其中一部分；`renderPick/renderExtract/renderCompare` 里到处用 `if (FLOW !== "patch") return` 兜底（`wizard.js:303,460,851,889`）。
- 是否引入组件/状态库。当前 `info` 全量替换 + `renderAll` 的模式在功能上够用，但每次改动都重绘全部区域，且渲染函数注册表靠字符串数组维护（`common.js:38-42`）。
- 是否把这些交互原样搬走：WebGL 双路 ERP 对比（`erp360.js`）、视口拖框坐标体系（`pick.js`）、逐帧预览（`/img/{name}/vp.png?frame=N`）。这三块是最有技术含量也最不该重写的部分。
- 是否需要把 CSS 抽公共文件并建立 token；目前两页色板重复且无 `@media`。
- 是否顺便修掉硬编码 `E:\VRAIGC`（`wizard.js:943`、`assets.js:270`）与已退役的 `/api/extract-frames`。