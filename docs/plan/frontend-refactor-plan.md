# 前端重构实施计划：Vue 3 + Element Plus

记录时间：2026-10-23。
状态：Phase 0–5 的代码与门禁已落地（2026-10-23）；真实 500 MB 上传、双人并发与带额度预演仍待验收，旧前端保留一个版本周期。本文件是 Phase 0 到 Phase 5 的实施依据。
上游文档：`docs/key-issues/20261023-frontend-stack-selection.md`（需求与论证）、`docs/decisions.md` 第 17 与第 38 条（决策）、`docs/key-issues/frontend-decisions.md`（页面级问题记录）。

## 1. 目标与边界

### 1.1 目标

前端界面层改用 Vue 3 + TypeScript + Vite + Element Plus 独立工程重建，旧前端保留在 `/`，新前端挂在 `/next`，按页面迁移，功能对齐后切换默认入口。迁移完成后，删除旧前端，只保留一套界面代码。

同时补齐局域网多人使用所必需的后端能力：浏览器上传、身份与 case 归属、任务归属与只读任务列表、并发写入的版本检查、扣费归属。账号与密码暂缓；任务先用单队列；身份、队列与 case 占用都通过接口隔离，后续换实现时页面与接口不变。

### 1.2 不做什么

- 不做服务端渲染。页面在局域网登录后使用，没有搜索引擎收录与公开首屏需求。
- 不做桌面客户端。浏览器已经满足访问方式，桌面壳只增加安装、更新与分发成本。
- 不做多人同时编辑同一个 case。当前场景是各做各的 case；case 锁只作为安全网，不做协同编辑。
- 不做账号与密码。当前按决策 17 的免登录自报昵称执行，账号体系通过 `IdentityProvider` 预留。
- 不做多 worker 队列。当前按决策 17 的单队列执行，多 worker 通过 `TaskQueue` 预留。
- 不改 `docs/case-model.md` 已冻结的 CLI 契约。新增的 Web 层元数据与上传接口先更新契约文档，再改两侧代码。

### 1.3 必须保留的能力

- `erp360.js` 的 WebGL 投影、双路同步、分割线与视角控制。新前端只包一层组件，不改着色器与时钟对齐逻辑。
- `pick.js` 的拖框坐标计算。新前端只包一层组合式函数，不改坐标换算。
- `app.py` 的现有业务、`tasks.py` 的队列执行、`vrgen` 的 CLI 子进程调用。新前端只调用接口，不 import 后端模块。
- 现有 4K 代理、逐帧预览、任务轮询、预演与提交门控。迁移时逐项对照，不允许功能缺失。

## 2. 总体架构

### 2.1 运行形态

开发模式、构建步骤与运行模式是三件事。开发时有两个常驻进程；构建是一次性命令；运行时只有一个常驻进程。

**开发模式（两个常驻进程，两个终端）。**

1. 终端 A 启动后端：`cd E:\VRAIGC\vrstudio`，然后 `uv run vrstudio serve --host 127.0.0.1 --port 8760`。
2. 终端 B 启动前端：`cd E:\VRAIGC\vrstudio\frontend`，然后 `npm run dev`。
3. 浏览器打开 `http://127.0.0.1:5173/next/`。

Vite 只负责前端页面与热更新，并把 `/api`、`/img`、`/video` 代理到 8760。后端没有启动时，列表会显示 502；这是开发模式下的预期错误，不是页面功能损坏。前端应把 502 与 504 显示成“后端服务没有启动，请先运行 `uv run vrstudio serve`”。

**运行模式（一个常驻进程）。**

运行模式只有一个常驻进程。下面的第 1 步是一次性构建，不常驻；第 2 步才是服务进程。

1. 一次性构建（只在改前端后或发布时执行）：`cd E:\VRAIGC\vrstudio\frontend`，然后 `npm run build`。
2. 启动唯一常驻进程：`cd E:\VRAIGC\vrstudio`，然后 `uv run vrstudio serve --host 0.0.0.0 --port 8760`。
3. 浏览器打开 `http://<服务器地址>:8760/next/`。

Starlette 在 `/next` 挂载静态文件，所有未匹配的 `/next/*` 路径回退到 `index.html`，由 Vue Router 接管。`npm run build` 不参与运行时，运行时不加载 Node。发布时可以把 `src/vrstudio/web/static/next/` 作为构建产物随包发布；源码仓库不提交它。Starlette 启动时不会自动构建前端；缺少构建产物时返回 503 与构建提示，避免服务器被迫安装 Node。运行时常驻的只有 Starlette 的 Web 服务进程；任务队列按需启动 CLI 子进程，任务结束就退出，不会常驻 Node 或 Vite。

这样选不是为了兼容旧的 `uv run vrstudio serve` 命令，而是让运行时保持一个 Python 进程：前端是静态文件，后端负责接口、媒体、任务与权限，Node 只出现在开发与构建阶段。生产环境常驻 Vite 会多一个进程、多一个端口、多一套依赖与安全面，而热更新只在开发时有用。

局域网同事只访问 8760，不在自己的电脑上运行前端工程。旧前端仍在 `/`，新前端在 `/next`。

旧前端与旧接口保持原路径不变。新前端只新增 `/next` 页面与 `/api` 下的新接口；旧接口在迁移期间继续服务旧前端。

### 2.2 目录结构

```
vrstudio/
  frontend/                         # 新前端工程
    package.json
    vite.config.ts
    tsconfig.json
    index.html
    src/
      main.ts
      App.vue
      router/index.ts
      stores/
        session.ts                  # 当前使用者与显示名
        case.ts                     # 当前 case 的 info、revision 与写操作
        task.ts                     # 任务列表、轮询与排队位置
        ui.ts                       # 侧栏、抽屉、提示、密度
      api/
        client.ts                   # fetch 封装、错误归一化、超时与取消
        cases.ts
        assets.ts
        prompt.ts
        params.ts
        keyframe.ts
        tasks.ts
        uploads.ts
        types.ts
      components/
        layout/AppShell.vue
        layout/SideNav.vue
        layout/TopBar.vue
        wizard/StepNav.vue
        case/CaseTable.vue
        case/CreateCaseDrawer.vue
        upload/UploadDropzone.vue
        asset/AssetList.vue
        prompt/PromptEditor.vue
        prompt/VariableCard.vue
        keyframe/CandidateGrid.vue
        compare/CompareViewer.vue
        task/TaskCenter.vue
        common/EmptyState.vue
        common/ErrorState.vue
        common/ConfirmDialog.vue
      views/
        CaseListView.vue
        WizardView.vue
        TaskCenterView.vue
        SettingsView.vue
      styles/
        tokens.css
        element-overrides.css
        base.css
      types/
        case.ts
        task.ts
        upload.ts
    tests/
      unit/
      e2e/
  src/vrstudio/web/
    app.py
    identity.py                     # 身份接口与免登录实现
    case_meta.py                    # case 归属、revision 与元数据
    locks.py                        # case 占用接口与文件锁实现
    tasks.py                        # 现有队列，包一层 TaskQueue
    static/next/                    # Vite 构建产物，不进 git
```

`frontend/node_modules/`、`frontend/dist/` 与 `src/vrstudio/web/static/next/` 写入 `.gitignore`。服务启动时如果找不到 `static/next/index.html`，返回一条明确提示，要求先执行构建。

### 2.3 路由

新前端使用四条路由。

- `/next/`：case 列表。
- `/next/case/:name/:step?`：向导页。`:step` 取 `pick`、`extract`、`keyframe`、`generate`、`merge`、`compare` 之一；缺省时取当前流程的第一步。
- `/next/tasks`：任务中心。
- `/next/settings`：设置与身份。

步骤进入 URL，刷新页面回到同一步。流程与步骤的合法组合由前端路由守卫检查；非法步骤重定向到该流程的第一步，并给出提示。

### 2.4 状态与数据流

服务端是唯一事实来源。前端只保存当前页面需要的状态，不复制服务端的业务判断。

- `sessionStore` 保存当前使用者的 `id`、`display_name` 与是否已认证；现在 `authenticated` 恒为 `false`。
- `caseStore` 保存当前 case 的 `info`、`meta.revision`、加载状态与错误。写操作成功后，只更新受影响的分片；接口返回整份 `info` 时，用返回内容替换 `info` 并刷新 `revision`。
- `taskStore` 保存任务列表、轮询状态与筛选条件。页面不再各自写 `setInterval`，所有轮询集中在 store 与组合式函数里。
- `uiStore` 保存侧栏折叠、抽屉开关、提示消息与密度偏好。

数据流遵守五条规则。

1. 写操作先调接口，成功后再改 store；不先改界面再等接口。
2. 只有本地控件状态允许乐观更新，例如勾选框、拖拽中的位置、折叠面板；失败时回滚并提示。
3. 写操作带上当前 `revision`；接口返回 409 时打开冲突对话框，默认重新加载，覆盖保存必须二次确认。
4. 页面步骤、选中的成片、对比页的左右文件进入 URL；折叠面板、抽屉开关可以不进 URL。
5. 高频几何交互继续走轻量接口，只合并几何字段，不重扫素材、不重画整页。

### 2.5 接口客户端与类型

`api/client.ts` 统一处理五件事：JSON 序列化、错误归一化、超时、取消、凭据。错误统一成 `{code, message, detail?, field?}`，页面只根据 `code` 做分支，不解析 `message` 文本。

`api/types.ts` 与 `types/` 下的接口声明描述后端返回的数据形状。Phase 1 用手写接口加契约测试；Phase 4 再评估是否从后端模型导出 JSON Schema 并生成 TypeScript 类型。契约测试的最低要求是：后端测试断言关键字段存在，前端类型检查保证页面读取的字段在类型里存在。

### 2.6 组件清单与职责

- `AppShell` 负责整体布局：左侧导航、顶部栏、主内容区、右侧抽屉。
- `StepNav` 负责步骤条、当前步骤、门控原因与点击跳转。
- `CaseTable` 负责列表、搜索、筛选与行操作。
- `CreateCaseDrawer` 负责新建 case 的表单、源视频或模式选择、上传与校验。
- `UploadDropzone` 负责拖拽、选择文件、分片上传、进度、重试与取消。
- `AssetList` 负责素材行、角色选择、排序、勾选、删除与添加入口。
- `PromptEditor` 负责模板正文、变量卡、自动保存、提交前 flush 与错误提示。
- `VariableCard` 是生成页与首尾帧页共用的唯一实现，不再出现第二份。
- `CandidateGrid` 负责候选批次、批次元信息、定稿标记与挑选动作。
- `CompareViewer` 负责包住 `erp360.js`，提供属性、事件与生命周期管理。
- `TaskCenter` 负责任务列表、筛选、排队位置、日志与失败原因。
- `SubmitBar` 负责生成参数、额度选择、预演、提交与提交状态。
- `EmptyState`、`ErrorState`、`ConfirmDialog` 负责统一空态、错误与确认交互。

### 2.7 WebGL 对比器的封装

`CompareViewer.vue` 在挂载时创建 `Erp360Compare` 实例，在卸载时销毁；用 `ResizeObserver` 处理画布尺寸变化；页面隐藏时暂停纹理上传；属性变化时只更新必要的 uniform 与视频源。

组件对外暴露四类能力：设置左右视频源、设置分割比例、设置与复位视角、全屏切换。内部不重写着色器、不重写双路时钟对齐、不改纹理脏标记规则。验收时与旧页面对照同一视角、同一时间点的画面，确认像素与同步行为一致。

### 2.8 选区拖框的复用

把 `pick.js` 的坐标换算抽成 `useInnerDrag` 组合式函数，输入是视口尺寸、当前 `inner` 与缩放比例，输出是拖拽中的矩形与松开后的归一化矩形。服务端仍然是 `inner` 的权威，前端只在拖拽过程中维护临时矩形。摇杆继续按 100 毫秒节流发请求，请求未完成时不叠加新的请求。

## 3. 设计系统

### 3.1 先写设计计划，再写页面

Phase 0 先产出一份简短设计计划，包含四到六组命名颜色、字体角色、间距台阶、圆角与布局概念，并用 ASCII 线框比较两个关键页面。设计计划对照需求复查之后，才开始写页面代码。这个流程借用 Anthropic `frontend-design` skill 的方法，但只取它的“先计划、后编码”“克制装饰”“文案主动语态”，不照搬它面向展示页的大胆审美。

### 3.2 设计令牌

`styles/tokens.css` 定义项目自己的令牌，页面只引用令牌，不写颜色、字号、圆角的字面量。

- 颜色：`--color-bg`、`--color-surface`、`--color-border`、`--color-text`、`--color-text-muted`、`--color-primary`、`--color-success`、`--color-warning`、`--color-danger`、`--color-info`。
- 字体：`--font-sans` 用系统中文字体栈，`--font-mono` 用于帧号、路径与日志；字号按 `--text-xs` 到 `--text-2xl` 六级。
- 间距：`--space-1` 到 `--space-8`，取值 4、8、12、16、24、32、48、64 像素。
- 圆角：`--radius-sm`、`--radius-md`、`--radius-lg`，统一 4、6、8 像素。
- 阴影：`--shadow-1` 与 `--shadow-2`，只用于抽屉、对话框、下拉与浮层。
- 动效：`--duration-fast` 150 毫秒，`--duration-base` 200 毫秒；尊重 `prefers-reduced-motion`。

### 3.3 Element Plus 主题覆盖

`styles/element-overrides.css` 把项目令牌映射到 Element Plus 的 CSS 变量，至少覆盖主色、成功色、警告色、危险色、信息色、基础字号、基础圆角、边框色与背景色。暗色模式在 Phase 0 只预留变量，不作为首期交付项。

### 3.4 密度、动效与可访问性

- 列表与表格用紧凑密度，表单用舒适密度；密度偏好存入 `uiStore`，首期只提供一套默认值，不暴露开关。
- 动效只用于状态变化，不做每张卡的淡入，不做滚动触发的动画。
- 正文对比度至少 4.5 比 1；焦点样式可见；所有控件可键盘到达；错误提示与输入框通过 `aria-describedby` 关联。
- 页面最小宽度按 1280 设计，1024 到 1280 之间允许侧栏折叠，低于 1024 显示“请在更宽的窗口使用”的提示，不做移动端适配。

### 3.5 视觉验收

- 用真实内容：两千字提示词、真实长路径、4K 缩略图、真实候选数量。
- 至少检查 1280、1440、1920 三个宽度，确认没有横向溢出、控件挤压与长文本截断。
- 每页检查六种状态：正常、加载、空、错误、禁用、长内容。
- 用浏览器实测点击到反馈的时间；超过 100 毫秒的交互必须有即时反馈。
- 长任务显示阶段与进度，不用一个转圈图标代替。

## 4. 页面与交互规格

### 4.1 全局壳

- 左侧导航宽 220 像素，可折叠为 64 像素；包含 case 列表、任务中心、设置三项。
- 顶部栏高 56 像素，显示当前 case 名、流程标签、步骤条、保存状态与使用者菜单。
- 主内容区占满剩余空间；右侧抽屉宽 360 像素，用于日志、素材详情或候选详情，可收起。
- 底部提交条只在生成步骤出现；其它步骤不显示，避免两种提交混在一个视口。

### 4.2 case 列表

- 顶部工具栏包含搜索框、流程筛选、负责人筛选与“新建 case”按钮。
- 表格列包含名称、流程、负责人、最近活动、最近任务状态、可用成片数量与操作。
- 行点击进入 case；操作列提供“打开”与“查看任务”。
- 新建 case 用抽屉完成，不跳整页；表单包含名称、流程、源视频或生成模式、可选上传。
- 列表每 10 秒刷新一次任务状态，页面隐藏时暂停；刷新只更新状态列，不重画整张表。
- 空态给出“新建 case”与“上传素材”两个入口。

### 4.3 向导壳

- 步骤条按流程显示：patch 为选区、抽取、首尾帧、生成、合并、对比；fullredraw 为扩充画面、生成、裁回原尺寸、对比；gen 为生成。
- 未满足条件的步骤不隐藏，点击后显示具体原因，例如“还没有抽取版本”“首帧与尾帧没有齐全”。
- 顶部保存状态显示“已保存”“保存中”“未保存”三态；离开有未保存内容的页面时弹出确认。
- 日志与详情放进右侧抽屉，不占用主内容区。

### 4.4 选区

- 左栏占约 60%，上方是全景视频与视口示意框，下方是视口预览与拖框区域。
- 右栏占约 40%，放视口尺寸、yaw 与 pitch、抽取范围、摇杆、重置选区与保存状态。
- 点击全景设置视口中心；示意框随点击移动；拖框松开后保存；摇杆按住持续微调。
- 逐帧浏览用时间轴加帧号输入；播放与逐帧步进分开。
- 快捷键：空格播放或暂停，左右箭头逐帧，Shift 加左右箭头微调。
- 验收：4K 素材上点击到预览更新不超过 0.5 秒；拖框后刷新页面仍保留；示意框在跨经线时拆成两块，不覆盖整幅全景。

### 4.5 抽取

- 顶部显示当前选区摘要：源视频、视口尺寸、帧范围、预计帧数。
- 主行动是“运行抽取”；门控未满足时按钮禁用并显示原因。
- 输出列表直接列出 `clip.mp4`、`clip_mask.png`、`clip.json`、`first_frame_raw.png`、`last_frame_raw.png`，显示文件大小与打开链接，不额外分组。
- 任务状态在页面内显示，包括排队位置、开始时间、耗时与失败原因。
- 验收：一次抽取后五个文件都出现在同一个列表；失败时能直接看到日志尾部。

### 4.6 首尾帧

- 上方两帧并排，标注“首帧原始图”与“尾帧原始图”，当前定稿加徽标。
- 中间显示链条“首帧 → 尾帧 → 视频”，让用户知道当前处在哪一段。
- 模型、分辨率与三视图选择放在两帧下方；四个变量卡复用 `VariableCard`。
- 候选按步骤分组，用网格展示；每张候选显示批次、生成时间、尺寸与定稿状态。
- 挑首帧后自动排队尾帧批次；尾帧批次失败时保留首帧定稿，并给“重新生成尾帧”按钮。
- 交接按钮“用这两帧生成视频”在首尾帧齐全时可用；点击后写模式与提交集，跳到生成步骤。
- 验收：首帧挑选后尾帧批次自动出现；换首帧时旧尾帧指针清空；交接后生成页的模式与提交集正确。

### 4.7 生成

- 页面分两栏：左栏是素材与提示词，右栏是最近成片与候选。
- 素材区每行显示缩略图、文件名、角色、时长或分辨率、勾选状态；角色选择、排序、删除与添加入口都在行内或行尾菜单。
- 提示词默认显示摘要，点击打开全屏编辑器或抽屉；编辑器左侧是模板正文，右侧是变量卡；变量卡只突出显示名、说明与输入框。
- 最近成片区显示最近一轮可用成片；有可用未采用轮次时给“选用成片”，已采用或只有预演轮次时不显示按钮，最近一次失败时显示失败原因。
- 底栏按两组排列：左侧是模式、比例、输出分辨率、输入缩放、时长；右侧是项目、剧集、会话、预演与提交。
- 提交状态显示“未预演”“预演通过”“预演已过期”“提交中”“排队中”“运行中”“失败”，并给出原因。
- 提示词改动后 400 毫秒防抖保存；提交与预演前先 flush 未保存的变量。
- 验收：真实 case 完成一次预演；500 MB 文件上传有进度；提示词保存后刷新仍在；提交前能看到本次扣哪个项目与会话的额度。

### 4.8 合并与重组

- patch 的合并显示两个连续任务：空间合并与时间合并；空间合并成功后自动提交时间合并，失败不进入下一步。
- fullredraw 的扩充画面与裁回原尺寸各自显示任务状态与输出文件。
- 输出列表按已有命名规则显示 `_space.mp4` 与 `_frame.mp4`，并标注“仅中间段”或“整片”。
- 验收：两步任务各自有日志与重试；对比页能按 `_frame` → `_space` 回退找到文件。

### 4.9 对比

- 画布占满主内容区；底部控制条固定，包含播放、进度、分割线、视角复位与全屏。
- 左上角选择左路文件，右上角选择右路文件；默认左路源片代理，右路最近成片代理。
- 分割线只改左右占比，不触发视角变化；键盘左右键可以微调分割线。
- 代理未就绪时显示进度与预计时间；失败时给原因与重试。
- 验收：同一时间点两路画面同步，偏差不超过 0.05 秒；拖动分割线到 25% 生效；转头与滚轮变焦不改变分割比例；全屏后控制条仍可用。

### 4.10 任务中心

- 任务中心是全局抽屉或独立页面。Phase 1 先显示全部任务与负责人列；Phase 4 增加“我的任务”与“全部任务”筛选。
- 每行显示状态、任务类型、case、负责人、提交时间、开始时间、耗时、排队位置与进度。
- 详情面板显示日志尾部、完整日志链接、错误原因与本次提交参数。
- 轮询每 2 秒一次，页面隐藏时暂停；同一任务只保留一个轮询。
- 验收（Phase 4）：两位同事同时使用时，各自默认只看到自己的任务；排队位置与实际队列一致；失败任务能看到具体原因。

### 4.11 上传

- 支持拖拽与选择文件，支持多选；每个文件显示名称、大小、类型、进度与剩余时间。
- 分片大小 8 MB，单文件串行上传，失败自动重试三次；刷新页面后可以从 `GET /api/uploads/{id}` 继续。
- 上传完成后计算 SHA-256，按 case 内现有素材去重；重复文件给出提示，不静默覆盖。
- 上传期间用户可以继续填提示词；上传不阻塞页面。
- 验收：500 MB 文件在局域网完成一次上传；中断后能续传；上传完成后素材出现在素材库。

### 4.12 身份与设置

- 首次进入新前端时弹出昵称对话框，写入 `vrstudio_user` cookie；昵称只用于显示任务归属与 case 占用者。
- 顶部使用者菜单显示昵称与“修改昵称”；不显示账号、密码、退出登录等尚不存在的功能。
- 设置页首期只有昵称、界面密度与“旧版入口”链接；暗色模式与账号入口留空位，不实现。（旧版入口已于 2026-10-27 随决策 42 删除，设置页当前只剩显示名。）

## 5. 后端配套改动

### 5.1 契约更新顺序

按照工作区硬规则，先改 `docs/case-model.md`，再改两侧代码与测试。本计划涉及四类契约变化。

1. `GET /api/case/{name}` 增加 `meta` 字段：`owner_id`、`owner_name`、`revision`、`updated_at`。
2. 新增上传接口与上传状态字段。
3. `GET /api/tasks` 的任务视图增加 `owner_id`、`owner_name`、`queue_position`、`created_at`、`started_at`、`finished_at`、`progress`、`error`。
4. 写接口增加可选的 `revision` 参数与 409 错误码。

旧接口继续返回原有字段，新增字段只追加不删除。旧前端在迁移期间继续可用。

### 5.2 身份与归属

新增 `src/vrstudio/web/identity.py`，定义三个对象。

```python
@dataclass(frozen=True)
class User:
    id: str
    display_name: str
    authenticated: bool = False

class IdentityProvider(Protocol):
    def current_user(self, request) -> User: ...
    def set_display_name(self, request, name: str) -> User: ...

class NicknameProvider:
    # 首次访问生成随机 user_id 写入 cookie；
    # display_name 由 POST /api/me 写入，只用于显示。
    ...
```

- `GET /api/me` 返回当前使用者；首次访问生成随机 `user_id` 并写入 `HttpOnly` cookie；`display_name` 为空时页面弹出昵称对话框。
- `POST /api/me` 写入显示名；`user_id` 不变，避免改昵称后丢失任务归属。
- 所有 case 与任务写入从 `request.state.user` 取使用者，不允许页面直接传 `owner_id`。
- 将来接账号体系时新增 `AccountProvider`，实现同一接口；页面只读 `/api/me`，不改代码。

`src/vrstudio/web/case_meta.py` 负责 case 归属与版本。

```python
class CaseMetaStore(Protocol):
    def read(self, case: str) -> CaseMeta: ...
    def touch(self, case: str, user: User, expected_revision: int | None) -> CaseMeta: ...
```

- 当前实现 `FileCaseMetaStore` 把 `owner_id`、`owner_name`、`created_at`、`updated_at`、`revision` 写入 `cases/<name>/case-meta.json`。
- 旧 case 首次被新前端打开时，如果没有 `case-meta.json`，Web 层补写当前使用者为负责人，并记一条迁移日志；补写失败不阻止打开，只标记为“未归属”。
- `case-meta.json` 是 Web 层元数据，不写进 `case.toml`，不改变 CLI 读取的静态事实。
- 以后换数据库时替换 `CaseMetaStore` 实现，接口字段不变。

### 5.3 任务队列

`tasks.py` 保留现有单 worker 执行逻辑，在外面包一层 `TaskQueue` 接口。

```python
class TaskQueue(Protocol):
    def submit(self, spec: TaskSpec, user: User) -> TaskId: ...
    def list(self, user: User, scope: str = "mine") -> list[TaskView]: ...
    def cancel(self, task_id: str, user: User) -> bool: ...

class SingleChannelQueue:
    # 现有单通道队列的实现；一次只跑一个任务。
    ...
```

- `TaskView` 至少包含：`id`、`kind`、`case`、`owner_id`、`owner_name`、`status`、`queue_position`、`created_at`、`started_at`、`finished_at`、`progress`、`log_path`、`error`。
- `GET /api/tasks?scope=mine|all` 返回任务视图；`GET /api/task` 保留给旧前端。
- 排队位置在读取时按队列顺序计算：正在运行的是 1，第一个排队的是 2，依此类推。
- 将来换多 worker 或按人公平调度时新增 `WorkerPoolQueue`，实现同一个接口；前端读取的字段不变。
- 单队列阶段不假装并行：界面如实显示“排队中”和预计位置，不显示虚假的并行进度。

### 5.4 上传

新增四类接口，全部走流式写入磁盘，不把文件读进内存。

- `POST /api/uploads`：创建上传会话，返回 `upload_id`、`chunk_size`、`max_size`。
- `PUT /api/uploads/{upload_id}`：按 `offset` 追加分片；服务端校验偏移，拒绝越界与重复写入。
- `GET /api/uploads/{upload_id}`：返回已接收字节数、总大小与状态，用于续传。
- `POST /api/uploads/{upload_id}/complete`：合并分片、计算 SHA-256、移动到临时完成区，返回 `file_id`、`name`、`size`、`sha256`。
- `DELETE /api/uploads/{upload_id}`：取消并清理临时文件。

存储与校验规则：

- 临时目录为 `cases/.uploads/<upload_id>/`；完成后移动到 `cases/.uploads/complete/<file_id>/`。
- 文件加入 case 时，由 `POST /api/case/{name}/assets` 接受 `upload_ids`，复制到 `cases/<name>/assets/`，并写入现有素材记录。
- 默认单文件上限 10 GB，按配置可调；允许的扩展名与现有素材类型一致；磁盘空间不足时明确拒绝。
- 文件名只用于显示，存储名使用 `file_id`，避免路径穿越与重名覆盖。
- 超过 24 小时未完成的上传在服务启动时清理。

### 5.5 版本检查

- 所有写接口接受可选 `revision`；`case-meta.json` 的 `revision` 在每次成功写入后加一。
- `revision` 不匹配时返回 409，响应包含 `code: "revision_conflict"`、`current_revision`、`updated_by`、`updated_at`。
- 迁移期间旧前端不传 `revision`，后端允许写入并递增版本；新前端成为默认入口后，再把 `revision` 改为必填。
- 页面收到 409 时打开冲突对话框：默认“重新加载”，覆盖保存需要二次确认；提示词这类长文本将来可以做字段级合并，首期不做。
- CLI 直接改 case 时，Web 层用关键文件的修改时间兜底检测变化，无法精确到字段，但能避免静默覆盖。

### 5.6 扣费归属

- 提交任务时记录 `owner_id`、`owner_name`、`project_id`、`episode_id`、`session_id`。
- 任务中心显示本次提交扣哪个项目与会话的额度。
- 如果 mglc 能查余额，任务中心显示剩余额度；查不到就显示“以平台为准”，不猜数字。
- 额度归属不改变现有 `vrgen submit` 的参数面；Web 层只把使用者信息写进任务记录。

### 5.7 新增接口清单

- `GET /api/me`
- `POST /api/me`
- `POST /api/uploads`
- `PUT /api/uploads/{upload_id}`
- `GET /api/uploads/{upload_id}`
- `POST /api/uploads/{upload_id}/complete`
- `DELETE /api/uploads/{upload_id}`
- `GET /api/tasks?scope=mine|all`

现有 `/api/cases`、`/api/case/{name}`、`/api/case/{name}/assets`、`/api/case/{name}/run`、`/api/task` 等接口保留，新增字段做追加，不删除旧字段。

## 6. 新旧并行与切换

### 6.1 托管方式

- 旧前端继续占 `/` 与 `/case/{name}`（2026-10-27 已由决策 42 退役：`/` 与 `/case/{name}` 只做 307 跳转到新前端）。
- 新前端占 `/next` 与 `/next/case/{name}/{step}`。
- Vite 的 `base` 设为 `/next/`，构建输出目录设为 `../src/vrstudio/web/static/next`。
- Starlette 在 `/next` 挂载静态文件，并为 `/next/*` 的未匹配路径返回 `index.html`。
- 开发时用 Vite 开发服务器，`/api`、`/img`、`/video` 代理到本机 Starlette。

### 6.2 迁移顺序

1. case 列表先切到新前端；它只读，风险最低。
2. 生成页迁移完成后，新前端承担主要生产工作；旧前端仍可作为回退。
3. 选区、抽取、首尾帧、合并与对比迁移完成后，整条 patch 流程在新前端可用。
4. 任务中心与身份、归属、版本检查完成后，切换默认入口。
5. 旧前端保留一个版本周期，确认没有回归后删除。

### 6.3 回退

- 新前端通过配置项或环境变量开关控制；默认入口在 Phase 4 才切到 `/next`。
- 旧前端代码、旧接口与旧静态资源在切换前保持不动。
- 任何阶段出问题，把默认入口切回 `/`，不影响正在使用旧前端的人。

### 6.4 下线

- 旧前端下线前，按页面列出功能对照表，逐项确认新前端已覆盖。
- 下线时删除旧模板与静态脚本，保留 `erp360.js` 与 `pick.js` 中被新组件复用的部分，或把复用的数学与着色器代码迁到新目录。
- 下线后更新 `AGENTS.md`、`docs/architecture.md`、`docs/key-issues/frontend-decisions.md` 与 README。

## 7. 开发阶段与验收

### Phase 0：需求与原型（1–2 周）

产出：

- 需求卡：角色、任务、失败路径、约束、验收标准，以本文与选型记录为基础整理成可勾选清单。
- 信息架构：四条路由、页面层级、每页主行动。
- 设计计划：四到六组颜色、字体角色、间距台阶、圆角、两个关键页面的 ASCII 线框。
- 两个可点击原型：case 列表与生成页，用真实内容，不接后端或只接只读数据。
- 三项技术验证：Vite 产物由 Starlette 在 `/next` 托管；`erp360.js` 包成 Vue 组件后能播放与同步；500 MB 文件完成一次分片上传。

验收：用户在浏览器里走完“建 case → 上传 → 填提示词 → 预演”的原型流程，并确认视觉方向。原型不碰现有代码。

### Phase 1：新壳与只读页（2 周）

任务：

- 建立 `frontend/` 工程、路由、Pinia store、接口客户端与类型。
- 完成 `AppShell`、`SideNav`、`TopBar`、`StepNav`。
- 完成 case 列表与新建 case 抽屉（2026-10-23 已接真实 `/api/cases`）、向导壳、任务中心只读；任务记录带负责人字段。
- 接入昵称身份与 `GET /api/me`。
- 处理代理失败与运行模式说明：前端把 502 与 504 显示成“后端服务没有启动”，README 写清开发模式两个进程、运行模式一个进程。
- 把构建产物挂到 `/next`，旧前端保持默认。

验收：新旧前端同时可用；新前端能创建与打开 case；刷新回到同一步；任务中心能看到任务列表、负责人列与排队位置；旧前端功能不受影响。

### Phase 2：生成页迁移（3 周）

任务：

- 上传组件与上传接口。
- 素材库、角色、排序、勾选、删除、添加。
- 提示词编辑器、变量卡、自动保存、提交前 flush。
- 生成参数、额度选择、预演、提交、最近成片、选用成片。
- 任务状态与失败原因。

验收：在真实 case 上完成一次预演；500 MB 上传有进度与续传；提示词保存后刷新仍在；提交前校验与旧前端一致；生成页的禁用原因清楚可读。

Phase 2 结束是可用的最小版本，约 6 到 7 周。

### Phase 3：选区、首尾帧、对比迁移（3 周）

任务：

- 选区页、全景点击、视口示意框、拖框、摇杆、逐帧浏览。
- 抽取页、输出列表、提取任务状态。
- 首尾帧页、两帧展示、变量卡复用、候选网格、自动接尾帧、交接。
- 合并与重组页、两步任务与输出列表。
- `CompareViewer` 包住 `erp360.js`，统一控制条与全屏。

验收：与旧前端逐项对照功能不缺失；4K 素材上点击到预览不超过 0.5 秒；对比页两路同步偏差不超过 0.05 秒；首尾帧交接后生成页状态正确。

### Phase 4：多人能力与切换（2–3 周）

任务：

- 身份与归属：`IdentityProvider`、`NicknameProvider`、`/api/me`、case 与任务归属。
- 任务视图：`GET /api/tasks` 的“我的/全部”筛选、排队位置校准、任务详情。
- 版本检查：`revision`、409 冲突对话框、`case-meta.json`。
- case 占用：`CaseLock` 与文件锁实现，作为安全网。
- 扣费归属：任务记录与任务中心显示项目、剧集、会话。
- 切换默认入口到 `/next`，旧前端保留一个版本周期。

验收：两位同事同时使用，各自任务不串、case 不互相覆盖；任务中心能看出谁在跑、排第几；默认入口切换后旧前端仍可回退；pytest、ruff 与前端门禁全绿。

### Phase 5：日志分层与索引（2–3 周）

这一阶段把日志从“每个操作一个文件、分布在两棵树里”收敛成“事件日志 + 任务原始输出 + 轮次审计日志”。当前规则与目标规则见第 10 节。

任务：

- 后端任务记录增加 `task_id`、`owner_id`、`request_id`、`created_at`、`started_at`、`finished_at`；Web 任务的原始输出改到 `logs/tasks/YYYYMMDD/<task_id>_<kind>_<case>.log`。
- 后端事件日志补齐 `request_id`、`task_id`、`round_id`、`user_id`、`case`、`op`、`status`、`duration_ms`、`error`、`log_ref` 字段；客户端错误带同一套关联字段。
- 后端新增 `GET /api/tasks`、`GET /api/tasks/{id}`、`GET /api/tasks/{id}/log?tail=N`；旧 `log_path` 保留为只读兼容。
- 后端停止写 `logs/web_*`、`logs/proxy_*`、`logs/extract_*` 等新文件；旧文件不迁移，Phase 5 上线时先输出清理清单，确认后删除。
- 后端让 pytest 与本地实验使用临时日志目录，不再写生产 `logs/`。
- 前端任务中心按 case、状态与时间筛选；任务详情抽屉显示结构化摘要与原始输出尾部，提供完整日志下载；主界面不展示原始路径。
- 文档更新 `docs/decisions.md` 第 39 条与 `docs/architecture.md` 的日志说明。

验收：

- 一次任务只产生一个原始日志文件，路径在 `logs/tasks/`；同一次操作的请求、任务与轮次能用 `request_id`、`task_id`、`round_id` 串起来。
- `cases/` 与 `logs/` 根目录不再出现新的日志文件；旧前缀文件不再被写入。
- 旧日志清理先输出清单与总大小，确认后执行；执行结果写一条事件。
- 任务中心能看到任务摘要、失败原因、日志尾部与完整日志。
- pytest 运行后生产 `logs/` 不新增文件。

### 时间估算与里程碑

- Phase 0：1–2 周。
- Phase 1：2 周。
- Phase 2：3 周。
- Phase 3：3 周。
- Phase 4：2–3 周。
- Phase 5：2–3 周。
- 合计：13–16 周。按一个人加 AI 协作估算；Phase 2 与 Phase 3 可以部分重叠，但不要跳过 Phase 0 的原型验收。
- 最小可用版本：Phase 0 到 Phase 2，约 6–7 周。

## 8. 测试与门禁

### 8.1 前端

- `vue-tsc --noEmit` 做严格类型检查。
- ESLint 加 Prettier 做代码检查与格式化；Vue 单文件组件使用官方 ESLint 插件。
- Vitest 覆盖 store 的写操作、冲突处理、上传状态机、任务轮询与排队位置。
- Playwright 覆盖四条关键路径：新建 case、上传素材、提示词保存、预演与提交；再覆盖两条协作路径：两个使用者各自任务、409 冲突提示。
- 浏览器手工验收每页六种状态，保留截图。

### 8.2 后端

- pytest 覆盖 `IdentityProvider`、`TaskQueue`、`CaseMetaStore`、`CaseLock` 的接口与默认实现。
- pytest 覆盖上传的创建、分片、续传、完成、取消、越界与类型拒绝。
- pytest 覆盖 `revision` 冲突返回 409，以及旧前端不传 `revision` 时的兼容路径。
- 契约测试断言 `/api/case/{name}`、`/api/tasks`、`/api/uploads` 的关键字段，防止前后端字段漂移。

### 8.3 CI

- Python 任务保持现有 `uv run pytest` 与 `uv run ruff check .`。
- 新增 Node 任务：`npm ci`、`npm run typecheck`、`npm run lint`、`npm run test`、`npm run build`。
- 固定 Node 版本，使用 `package-lock.json` 与依赖缓存。
- 前端构建失败时 CI 失败；构建产物不作为提交内容。
- 前端门禁先在 CI 跑通，再写进 `AGENTS.md` 的提交门禁。

### 8.4 浏览器验收

- 使用真实 case 与真实素材，不用占位文本。
- 记录点击到反馈的时间、任务排队位置、上传进度与冲突提示。
- 视觉验收按 3.5 节的三个宽度与六种状态执行。
- 对比页验收同一时间点、同一视角的画面；选区页验收示意框与拖框坐标。

## 9. 风险与应对

- **Element Plus 默认观感偏保守**：Phase 0 先定令牌与主题，不直接使用默认皮肤；每个页面按设计计划验收，避免“装了组件库但仍然不好看”。
- **单队列在多人下成为瓶颈**：界面如实显示排队位置与预计等待；Phase 4 测量 CPU、磁盘与 ffmpeg 负载，再决定是否实现 `WorkerPoolQueue`。
- **前端类型与后端 JSON 漂移**：Phase 1 起加契约测试；Phase 4 评估从后端模型导出 JSON Schema 并生成 TypeScript 类型。
- **WebGL 对比器重写引入像素与同步问题**：只包组件，不改着色器、时钟对齐与纹理脏标记；验收时与旧页面对照。
- **新旧并行期间双倍维护**：设定 Phase 4 结束为切换期限，旧前端只保留一个版本周期。
- **Node 工具链增加本地与 CI 成本**：固定 Node 版本，使用 lockfile 与缓存；README 写清安装与构建命令。
- **上传中断与磁盘压力**：分片、续传、SHA-256、临时目录清理、磁盘空间预检；单文件上限可配置。
- **身份可伪造**：局域网内自报昵称本身不防伪造，这是当前接受的风险；账号体系通过 `IdentityProvider` 替换，不在首期解决。
- **冻结契约被顺手改动**：所有新增字段先写进 `docs/case-model.md`，再改代码；`case.toml` 不放 Web 层元数据，使用 `case-meta.json`。
- **旧前端下线过早**：切换默认入口后保留一个版本周期，按页面功能对照表确认后再删除。

## 10. 日志机制

本节先写当前规则，再写 Phase 5 的目标规则。当前规则是实施前的现状，不是要保留的最终形态。

### 10.1 当前规则（实施前）

当前有四类日志，分布在两棵树里。

1. **Web 结构化事件**：`logs/serve/service-YYYYMMDD.jsonl` 记录启动、HTTP 请求、预览耗时、几何变更与任务生命周期；`logs/serve/client-YYYYMMDD.jsonl` 记录浏览器上报的错误。按本地日期切换，默认保留 14 天；`/api/task`、`/api/client-log`、`/static/` 与 favicon 跳过访问日志；视频 Range 请求只在 DEBUG 记录。来源是 `web/logging.py` 与决策 28。
2. **任务与命令原始输出**：每个 Web 任务写 `logs/web_<kind>_<case>_<timestamp>.log`（`web/tasks.py:47-48`）；每次代理构建写 `logs/proxy_<case>_<stem>_<timestamp>.log`（`web/proxy.py:306-307`）；每个 CLI 运行写 `logs/<stem>_<timestamp>.log`（`progress.py:110-123`）。
3. **vrgen 轮次日志**：每个轮次目录写 `mglc.log` 与 `progress.log`（`vrgen/round/ledger.py:36-37`），Web 的 workdir 下对应 `vrgen_runs/<job>/<round>/`。
4. **测试日志**：pytest 调用同一套 CLI 与日志函数，把 `extract_e2e_*`、`restore_good_*` 等文件写进生产 `logs/` 根目录。

当前目录的证据：

- `cases/` 下 `.log` 与 `.jsonl` 文件数量为 0；当前代码不把日志写进 case。
- `vrgen_runs/` 下有 88 个 `.log` 文件，主要是每个轮次的 `mglc.log` 与 `progress.log`。
- `logs/` 根目录有大量按操作与时间戳命名的文件，例如 `extract_e2e_...`、`merge_..._space_...`、`assemble_...`、`restore_...`、`web_...`、`proxy_...`。

现状有六个问题：

- 每个操作一个文件，短时间内产生大量文件，难以找到与某次提交对应的那一份。
- 日志分布在 `logs/` 与 `vrgen_runs/` 两棵树，命名规则不一致。
- 请求、任务、轮次与用户之间没有统一的关联 ID，无法从一条失败记录串到完整链路。
- 任务原始输出与 CLI 日志没有保留期与清理，磁盘会持续增长。
- 前端拿到的是原始 `log_path`，用户要自己判断文件在哪、该看哪一份。
- 测试日志写进生产目录，审阅时混入大量 `extract_e2e`、`restore_good` 等噪声。

### 10.2 目标规则（Phase 5）

目标规则保留两层日志与一类审计产物，不再为短操作单独建文件。

1. **事件层**：继续使用 `logs/serve/service-YYYYMMDD.jsonl` 与 `logs/serve/client-YYYYMMDD.jsonl`，保留决策 28 的按天轮转与 14 天保留。新增统一字段：`request_id`、`task_id`、`round_id`、`user_id`、`case`、`op`、`status`、`duration_ms`、`error`、`log_ref`。短操作只写事件层，例如改素材角色、保存提示词、点选视口、查询参数。
2. **任务原始层**：每个长任务写一个文件 `logs/tasks/YYYYMMDD/<task_id>_<kind>_<case>.log`，只放子进程 stdout 与 stderr。文件头写入 `task_id`、`request_id`、`user_id`、`case`、`kind` 与完整 argv。默认保留 30 天，可配置。
3. **轮次审计层**：`vrgen_runs/<job>/<round>/mglc.log` 与 `progress.log` 保留原位，因为它们与轮次台账、断点续跑和审计绑定。事件日志记录 `round_id` 与 `log_ref`，页面通过 API 读取，不要求用户浏览 `vrgen_runs/`。

约束：

- `cases/` 与新 `logs/` 根目录不再写日志；新原始日志只出现在 `logs/tasks/`，事件只出现在 `logs/serve/`。
- 除任务原始输出外，不再为单次操作建立文件。
- 所有事件带已知关联 ID；任务提交时把 `request_id`、`owner_id` 与 `case` 写入任务记录。
- 旧前缀文件不迁移。Phase 5 上线时先输出清理清单（路径、大小、总数），确认后删除；删除动作写一条事件。
- pytest 与本地实验使用临时目录，生产 `logs/` 不新增文件。
- 前端只调用任务与日志 API，不直接读取文件路径。

接口：

- `GET /api/tasks?scope=mine|all&case=&status=&since=`
- `GET /api/tasks/{id}`
- `GET /api/tasks/{id}/log?tail=N`
- `GET /api/events?case=&task_id=&level=&since=`（Phase 5 后半段）

前端：

- 任务中心按 case、状态与时间筛选。
- 任务详情抽屉分两栏：结构化摘要与原始输出尾部；完整日志提供下载。
- 失败任务直接显示错误行，不只显示“失败”。
- 原始路径放在详情里，不作为主界面的导航入口。

验收：

- 一次任务只产生一个原始日志文件；事件日志能用 `task_id` 与 `request_id` 找到它。
- 一次提交能用 `request_id` 串起请求、任务、轮次与原始输出。
- `cases/` 与 `logs/` 根目录不再出现新日志。
- 旧日志清理有清单、有确认、有结果记录。
- pytest 后生产 `logs/` 不新增文件。

## 11. 待决与后续

- 账号与密码的启动时间：等局域网多人使用稳定后再评估，届时只替换 `IdentityProvider`。
- 多 worker 队列的启动时间：等单队列出现可观察的排队瓶颈后再评估，届时只替换 `TaskQueue`。
- case 占用锁的强制范围：Phase 4 先做文件锁与提示，是否在所有写接口强制检查，等实际并发情况再定。
- `case-meta.json` 的最终命名与字段：Phase 1 前写进 `docs/case-model.md`，与现有契约测试一起落地。
- 是否引入 Pydantic 与 JSON Schema 生成 TypeScript 类型：Phase 4 评估，首期用手写类型加契约测试。
- 暗色模式、移动端适配、快捷键全集、操作记录查询：不进入首期，按使用反馈排期。

## 12. 参考

- 需求与论证：`docs/key-issues/20261023-frontend-stack-selection.md`
- 开发流程与 skill 留档：`docs/plan/frontend-workflow-and-skills.md`
- 决策：`docs/decisions.md` 第 17 条（多用户分层）、第 28 条（Web 事件日志）与第 39 条（日志分层）
- 日志机制：本文件第 10 节
- 页面级问题记录：`docs/key-issues/frontend-decisions.md`
- 现状画像：`docs/20261023-vrstudio-Web-前端现状画像.md`
- 早期技术栈对比：`docs/web-stack.md`
- 契约权威：`docs/case-model.md`
- [Anthropic frontend-design skill](https://github.com/anthropics/skills/tree/main/skills/frontend-design)
- [Element Plus 主题定制](https://element-plus.org/en-US/guide/theming.html)
- [Element Plus 更新日志](https://element-plus.org/en-US/guide/changelog)
- [Vue 官方文档](https://vuejs.org/)
- [Vite 官方文档](https://vite.dev/)
- [Playwright 官方文档](https://playwright.dev/)
