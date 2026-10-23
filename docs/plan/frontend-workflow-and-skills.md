# 前端开发流程与 skill 留档

记录时间：2026-10-23。
状态：持续更新。每完成一个阶段、引入新的 skill 或改变验收方式时追加，不覆盖旧记录。
用途：让接手者从这份文档就能知道我们怎样对齐需求、怎样选型、怎样做原型、每一步怎样验收，以及用过哪些 skill 与工具。代码与提交历史负责回答“改了什么”，本文负责回答“为什么这样做、下次怎样重复”。

关联文档：

- 需求与选型论证：`docs/key-issues/20261023-frontend-stack-selection.md`
- 实施计划：`docs/plan/frontend-refactor-plan.md`
- 设计计划：`vrstudio/frontend/DESIGN.md`
- 页面级问题记录：`docs/key-issues/frontend-decisions.md`
- 决策记录：`docs/decisions.md` 第 17、28、38、39 条

## 1. 当前进度快照

### 1.1 已完成

- **Phase 0 的原型与骨架**：Vue 3 + TypeScript + Vite + Element Plus 工程、设计令牌、应用壳、case 列表原型、生成页原型、`/next` 托管。浏览器在 1440 与 1280 两个宽度验收。
- **Phase 1 的只读数据接入**：case 列表读取真实 `/api/cases`；新建 case 使用真实 `/api/sources` 与 `/api/modes`；昵称身份走 `/api/me`；任务中心读取真实 `/api/tasks`；项目、剧集、会话读取真实 `/api/sessions`。
- **Phase 2 的生成页真实数据**：素材、勾选、角色、提示词、提示词保存、生成参数、最近成片与生成轮次都已接真实 `/api/case/{name}`。
- **后端配套**：新增 `identity.py`、`/api/me`、`/api/tasks`、任务负责人与时间字段、`/next` 静态托管与单页回退。
- **日志计划**：当前日志规则与目标规则已写入实施计划第 10 节；旧日志按淘汰处理，清理放在 Phase 5。

### 1.2 未完成

- **Phase 0 的两项技术验证**：`erp360.js` 包成 Vue 组件、500 MB 文件分片上传，尚未执行。
- **Phase 1 的收尾**：502 与 504 的专门提示尚未实现。
- **Phase 2 的执行链路**：预演、提交、采用成片、上传、任务状态回显仍是原型或未接。
- **Phase 3**：选区、抽取、首尾帧、合并、对比页面尚未迁移。
- **Phase 4**：case 归属、版本检查、case 占用、扣费归属与默认入口切换尚未实施。
- **Phase 5**：日志分层、任务原始日志目录、旧日志清理尚未实施。

### 1.3 主要提交索引

根仓库 `E:\VRAIGC`：

- `50739f9` `docs: 登记前端技术栈选型与重构计划（决策 38）`
- `a91787e` `docs: 补日志分层 Phase 5 与开发运行模式`
- `80d7076` `docs: 澄清开发与运行的常驻进程`
- `a05680c` `docs: 记录生成页真实数据接入进展`

vrstudio 仓库：

- `5f22c6a` `frontend: 搭 Phase 0 原型与设计令牌`
- `f23ae4a` `web: 在 /next 托管新前端并回退到 index.html`
- `7f3122c` `frontend: 固定生成页提交条并补会话刷新`
- `ff3abda` `web: case 列表补充更新时间与成片数`
- `a967eca` `frontend: case 列表接真实接口`
- `61cbfb7` `web: 增加免登录昵称身份`
- `843d919` `frontend: 接入昵称身份`
- `765472f` `web: 增加任务视图与归属字段`
- `3ec2c1f` `frontend: 任务中心接真实任务视图`
- `ed35703` `frontend: 接入真实会话选择器`
- `0139f51` `frontend: 生成页素材接真实接口`
- `24a7c46` `frontend: 生成页接真实提示词、参数与轮次`

## 2. 规划流程

这套流程按顺序执行。每一步都留下文档或提交，避免“做完才想起来为什么”。

### 2.1 需求对齐

- 先分轮提问，不先讲方案。提问覆盖使用范围、主要痛点、技术代价、视觉方向、数据入口、文件体积、协作边界、重构节奏。
- 每轮只问能改变方案的问题。例如“半年内局域网多人”直接推翻“单人本地工具”的旧假设；“先解决改不动”直接决定组件化路线。
- 用户的选择与补充逐条写入 `docs/key-issues/`，包括被推翻的旧假设与用户的复述。
- 需求收敛成“使用者、协作方式、数据入口、痛点、视觉方向、重构节奏、硬约束、身份与并发”八到九条，不写成功能清单。

### 2.2 技术选型

- 先判断“页面由谁渲染、状态住在哪、后端出什么”，再看用什么库。
- 列出候选路线的做法、优点、代价与适用场景，不用表格承载长对照。
- 版本证据必须写到具体日期：Element Plus 2.14.7（2026-09-30）、Ant Design 6.6.5（2026-09-20）、Ant Design Vue 4.2.6（2024-11-11）。
- 结论与排除理由写入 `docs/key-issues/`，用户确认后写入 `docs/decisions.md`。
- 选型结论不覆盖旧决策原文；旧决策前提变化时新增决策并指向前提变化。

### 2.3 设计与原型

- 先写设计计划，再写页面代码。设计计划包含四到六组命名颜色、字体角色、间距台阶、圆角与 ASCII 线框。
- 本项目选择中性冷灰表面加蓝色主色，避开“暖奶油底加衬线标题加陶土色”这类模板化默认。
- 设计令牌写入 `vrstudio/frontend/src/styles/tokens.css`，Element Plus 变量覆盖写入 `element-overrides.css`。
- Phase 0 先做 case 列表与生成页两个原型，使用真实长度的中文内容与真实路径，不用占位文本。
- 原型验收看 1280、1440、1920 三个宽度，检查横向溢出、长文件名换行、控件挤压与固定底栏。
- 原型不碰后端执行链路，只验证信息架构、视觉方向与关键交互。

### 2.4 实施顺序

实施按“先骨架、再只读、再写操作、最后多人能力”的顺序推进。

1. 新前端工程、路由、状态、设计令牌、应用壳。
2. case 列表、向导壳、任务中心只读。
3. 生成页真实数据：素材、提示词、参数、成片、轮次。
4. 生成页写操作：预演、提交、采用、上传。
5. 选区、抽取、首尾帧、合并、对比页面。
6. 身份归属、版本检查、case 占用、扣费归属、默认入口切换。
7. 日志分层与旧日志清理。

每一步只改一个可独立验收的面。数据接入与执行链路分开提交，避免一次提交同时改页面、接口与任务队列。

### 2.5 每步验收与提交

每个小步按同一套门禁执行。

1. 前端通过 `npm run typecheck` 与 `npm run build`。
2. 后端通过 `uv run pytest` 与 `uv run ruff check .`。
3. 用真实服务与真实 case 在浏览器走一遍；必要时用临时 cases 目录避免污染现有数据。
4. 修改真实 case 的勾选、提示词或角色时，记录原值并在测试后恢复。
5. 验收通过后单独提交；文档改动与代码改动分开提交。
6. 提交信息用中文动词开头，例如 `frontend: 生成页素材接真实接口`。

### 2.6 文档落点

- 选型论证与用户确认：`docs/key-issues/20261023-frontend-stack-selection.md`。
- 实施计划与阶段验收：`docs/plan/frontend-refactor-plan.md`。
- 页面级问题与排除方案：`docs/key-issues/frontend-decisions.md`。
- 已拍板决策：`docs/decisions.md`。
- 里程碑进度：`docs/roadmap.md`。
- 开发流程与 skill：本文。

## 3. 开发 skill 与工具

### 3.1 本次实际使用的本地 skill

- **表达与记录规范**：`C:\Users\Administrator\.agents\skills\expression-and-record\SKILL.md`。
  - 用于对话、计划、决策与本文的写作形态。
  - 关键约束：句子主谓宾齐全；精简靠合并而不是省略；长段拆成分层列表；并列内容用列表不用表格；标题说清主语；示意图零重叠并过视觉验收。
- **浏览器验收**：本次使用 ZCode 环境里的 Playwright MCP 工具，包括 `browser_navigate`、`browser_take_screenshot`、`browser_evaluate`、`browser_run_code_unsafe`。
  - 截图保存在 `E:\VRAIGC\.playwright-mcp\phase0`、`phase1`、`phase2`，这些目录不进 git。phase2 只保留了部分截图，后续验收可以重新生成。
  - 同环境还有 `browser-use` skill，路径是 `C:\Users\Administrator\.zcode\cli\plugins\cache\zcode-plugins-official\browser-use\0.5.1\skills\control-browser\SKILL.md`；本次没有直接调用它，记录在这里供接手者选择。

### 3.2 网络上的前端 skill 与参考

- **Anthropic 官方 frontend-design skill**：`https://github.com/anthropics/skills/tree/main/skills/frontend-design`。
  - 直接读取的 skill 正文：`https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md`。
  - 本次没有把它安装成本地 skill，而是读取 `SKILL.md` 后按它的流程执行。
  - 它的核心要求是先以设计负责人身份写设计计划，再写代码；设计计划包含四到六组命名颜色、字体角色、布局概念与 ASCII 线框；它明确列出要避开的模板化默认，例如暖奶油底加衬线标题加陶土色、近黑底加单一荧光色、所有内容切成同样圆角卡片。
  - 它面向有独特视觉识别的展示页，不完全适合高密度内部工具；本项目借用的是“先计划、后编码”“克制装饰”“文案主动语态”“空态与错误要给方向”，没有照搬它的大胆审美要求。
- **社区前端 skill 集合**：`https://github.com/JaimeJunr/claude-code-frontend-skills`。
  - 这个仓库把 Anthropic frontend-design、`uiux-storybook-architect`、`impeccable`、`ui-ux-pro-max`、`taste`、`emil-design-eng` 等 skill 放在同一个市场里，并用一个路由 skill 解决多套规则冲突。
  - 本次只做了调研，没有安装。原因是同时装多套设计规则会互相冲突，而且当前项目已经有明确的 Element Plus 设计系统与 `DESIGN.md`。
  - 仓库里列出的 `uiux-storybook-architect`、`gral-frontend-skill`、Addy Osmani 的 Web Quality Skills 等，本次没有逐个核实独立仓库地址，也没有安装；需要时从上面这个集合或各自官方仓库再确认。
- **Element Plus**：
  - 主题定制：`https://element-plus.org/en-US/guide/theming.html`
  - 更新日志：`https://element-plus.org/en-US/guide/changelog`
- **Vue**：`https://vuejs.org/`
- **Vite**：`https://vite.dev/`
- **Playwright**：`https://playwright.dev/`

### 3.3 skill 选择的判断标准

- 先看项目是展示页还是高密度工具。展示页可以用大胆审美；内部工具优先信息层级、密度与状态可见性。
- 一次只选一套主设计 skill，再配一套可访问性审查。多套装在一起会让规则互相抵消。
- skill 的流程比它的审美偏好更可复用。本次真正沿用的是“先写设计计划、再写代码”和“克制装饰”，不是某个具体配色。
- 任何 skill 生成的设计都要用真实内容过浏览器验收，不能只看文字描述。

## 4. 运行与验证命令

### 4.1 开发模式

```powershell
# 终端 A
cd E:\VRAIGC\vrstudio
uv run vrstudio serve --host 127.0.0.1 --port 8760

# 终端 B
cd E:\VRAIGC\vrstudio\frontend
npm install
npm run dev
```

浏览器打开 `http://localhost:5173/next/`。后端没有启动时 Vite 代理返回 502，这是预期错误。

### 4.2 运行模式

```powershell
cd E:\VRAIGC\vrstudio\frontend
npm run typecheck
npm run build

cd E:\VRAIGC\vrstudio
uv run vrstudio serve --host 0.0.0.0 --port 8760
```

浏览器打开 `http://<服务器地址>:8760/next/`。运行模式只有一个常驻 Web 服务进程，不需要 Node 与 npm；任务队列按需启动 CLI 子进程。

### 4.3 门禁与浏览器验收

```powershell
cd E:\VRAIGC\vrstudio\frontend
npm run typecheck
npm run build

cd E:\VRAIGC\vrstudio
uv run pytest
uv run ruff check .
```

浏览器验收至少覆盖：

- 1280 与 1440 两个宽度。
- 正常、加载、空、错误、禁用、长内容六种状态。
- 真实 case、真实长提示词、真实文件名。
- 点击到画面反馈的时间；长任务显示排队位置与阶段。

## 5. 设计约定

- 页面底色 `#f4f6f9`，卡片 `#ffffff`，主色 `#2563eb`，正文 `#1f2937`，次要文字 `#64748b`。
- 正文 14 像素、行高 1.6；标题 20、24、32 像素三级。
- 间距取 4 与 8 的倍数；圆角统一 4、6、8 像素；阴影只用于抽屉、对话框与下拉。
- 最小设计宽度 1280 像素；1024 到 1280 之间折叠侧栏；低于 1024 提示使用更宽窗口。
- 生成页提交条固定在视口底部，左侧偏移跟随侧栏宽度；页面内容底部留出 160 像素。
- 长内容默认折叠：提示词、日志、文件列表先给摘要，展开后再看全文。
- 详细设计计划见 `vrstudio/frontend/DESIGN.md`。

## 6. 后端配套与日志

- 身份：`IdentityProvider` 的当前实现是 `NicknameProvider`；`vrstudio_uid` 是稳定 id，`vrstudio_name` 是显示名；未来换账号体系只替换实现，页面不改。
- 任务：`GET /api/tasks` 返回任务 id、负责人、状态、排队位置、提交/开始/结束时间、日志尾部与错误；旧 `/api/task` 保留给旧前端。
- case 数据：`GET /api/case/{name}` 返回素材、提交集、提示词、生成参数、成片、轮次与门控；生成页只读这个端点。
- 会话：`GET /api/sessions` 返回项目、剧集、会话三层树；生成页刷新按钮每次重新请求。
- 日志：当前规则与目标规则见 `docs/plan/frontend-refactor-plan.md` 第 10 节。目标是事件层、任务原始层、轮次审计层三层；旧日志不迁移，Phase 5 清理时先列清单再删除。

## 7. 后续工作

1. 生成页接预演、提交、采用成片与任务状态回显。
2. 接上传与素材库。
3. 迁移选区、抽取、首尾帧、合并、对比页面。
4. 补 case 归属、版本检查、case 占用与扣费归属。
5. 实施日志分层与旧日志清理。
6. 每完成一步，在本文第 1 节更新进度，在第 1.3 节追加提交号。
