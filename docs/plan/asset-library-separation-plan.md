# 素材库独立页面与步骤内引用清单方案

状态：已实施（2026-10-26）。自动化门禁与免额度浏览器验收完成；真实付费图片与视频提交未跑。实施记录与差异见 §12，验收细节见 `docs/test-runs/20261026-asset-library-refs.md`。2026-10-27 更新：旧版控制台退役（决策 42），本文标注的旧版兼容点（`sheet`/`sheet_candidates`、`/keyframe/sheet`、角色同步）已删除。

原型：会话可视化目录下的 `asset-library-prototype/index.html`（不随仓库提交，实施后作废）。原型覆盖现状与方案两套视图，方案视图包含素材库页、生成页、首尾帧页与选择器；数据来自 `walk_4k` 的 26 个真实素材、两张原始帧与两组候选，`i27`/`i28` 是从三视图裁切的细节图示例。

关联文档：`docs/keyframe-workbench-plan.md`（本文取代其 §2.3 的「图片步输入是固定契约」前提）、`docs/plan/keyframe-page-layout-plan.md`（四格布局保留）、`docs/unified-submit-plan.md`（提交集与流程产物的边界）、`docs/case-model.md`（`--image-note` 契约）、`docs/key-issues/frontend-decisions.md`（前端决策惯例）。

## 0. 已确认的决策

1. **素材库独立成 case 级页面。** 它不进入流程步骤条；case 顶栏用「流程 / 素材库」开关切换。页面复用现有 case 加载、账号锁与保存状态，不新增第二套 case 状态。
2. **生成页本轮一起改。** 生成页不再显示全库列表，只显示本次视频提交的引用条目；未选文件在素材库，添加通过步骤内的选择器完成。
3. **文件库共用，引用声明分开，角色跟着引用条目走。** `[[assets]]` 仍是一个 case 级文件集合，只存文件事实；`[submit]` 服务视频提交，`keyframe.toml` 的 `refs` 服务图片步。两份声明各自记录顺序与角色，互不覆盖。同一张图可以同时出现在两份声明里，在两处可以有不同的角色。
4. **首尾帧页保持引导式流程。** 「先首帧、后尾帧、挑候选、交接」不变；只把参考图从单张扩成有序清单，清单内联在步骤页里，不再用只列三视图的抽屉。
5. **素材库不存引用角色。** 素材库只保留文件类型、尺寸、大小这类文件事实，以及一个从两份引用声明派生的引用次数；角色在步骤页的引用清单里选。

### 0.5 五条默认项

以下五条按推荐值写进本稿，原型已按此做出；评审要改时先改本节，再动代码。

- **视频提交清单也按条目存角色。** `[submit]` 保留 `selected` 的顺序，新增 `roles` 映射；素材库不再编辑角色；旧 case 没有 `roles` 时回退到 `[[assets]] role`。代价是 `[submit]` 形状扩展；旧版控制台在役时需要同步兼容层，已随决策 42 退役删除。
- **生成页与首尾帧页共用引用行组件。** 两页都用「序号、缩略图、角色下拉、顺序、移除」这一套；角色选项、用途输入列与保存端点由步骤注入。生成页在窄栏里用紧凑布局，首尾帧页用带用途输入的宽布局。
- **参考图两批共用，尾帧自动追加首帧定稿。** 首帧与尾帧共用同一份 `refs`；尾帧批次在人物三视图之后插入首帧定稿。代价是某一帧需要专属细节图时没有位置。
- **每张细节图逐张写用途。** `refs` 的每一项带 `note`，渲染进【参考图分工】。代价是 `keyframe.toml` 多一个字段，并要扩展 vrgen 的 `--image-note` 契约。
- **首尾帧页仍是专用图片步，不是通用图片生成面板。** 模板选择、任意图片生成仍属于生成页；本页只做两帧定稿。

### 0.6 本轮角色范围（已确认）

- 视频引用清单只开放三个角色：`edit_master`（编辑母版）、`subject_ref`（主体参考）、`motion_ref`（动作参考）。`firstLastFrame` 模式另开 `first_frame` / `last_frame` 两个模式专用角色。
- `scene_ref`、`space_ref`、`mid_frame` 本轮不进入普通选项。旧 case 已经写了这些角色的素材仍然可读；在引用清单里以「旧角色」标记显示，用户可以把它改成三个开放角色之一。
- 图片步只开放 `subject_ref`（人物三视图）与 `detail_ref`（细节参考）。
- 角色下拉的每个选项在悬停时显示一句说明；说明取自后端的角色文案，不在前端另写一套长文本。

## 1. 问题

### 1.1 用户原话与判定

用户在 2026-10-26 的描述：

> 提交的图片可能不止一张三视图，为了画面的细节的保真度，有时可能需要提交更多的细节图片来要求模型记住这些细节。这对于我们的网页来说，意味着首尾帧页面可能会出现更多的图片素材，并且提示词模板也不再适用于更多图片的场景。考虑到图片素材增多以后，首尾帧页和生成页在素材步骤的相似度进一步提高，我们要怎么设计才能兼容这种复杂流程？

判定：当前流程被打破不是因为提交链路装不下更多图片，而是因为「图片步只有一张三视图」被写进了页面、指针、后端、模板与变量白名单五处。`vrgen image submit` 的 `--image` 与 `--image-role` 已经可以重复，轮次的 `params.images` 记录了全部图片路径，`prompt.txt` 记录了渲染后的分工说明；真正缺的是一个表达「有序参考图清单」的数据结构与模板写法。

### 1.2 固定输入写在哪五处

- 页面文案：`KeyframeStep.vue:351` 写「图1 / 图2 / 图3 与提示词里的参考图一一对应」，`:560` 写「图片步固定用 图1 原始帧 + 这张三视图」。
- 指针：`keyframe.toml` 只有 `sheet = "i1"` 一个字符串。
- 后端：`_keyframe_inputs()` 固定返回三对（原始帧、三视图、首帧定稿），见 `app.py:1862-1873`。
- 模板：`keyframe-first.md` 写「严格按图2」，`keyframe-last.md` 写「图3 是同一个人的首帧定稿」。
- 变量白名单：`app.py:2048` 只允许 `figure`、`pose_first`、`pose_last`、`preserve` 四个变量；`IMAGE_ROLE_TEXT` 只认识五种角色。

### 1.3 生成页的耦合与角色归属

生成页的素材区同时承担三件事：展示文件库、勾选本次视频提交、修改库角色与删除。`GenerateAssets.vue` 渲染全部 26 个素材，未选项只是淡化；用户要在一屏里完成「找文件、勾提交、改角色、排序」。

角色归属是第二个耦合点：角色现在挂在 `[[assets]]` 上，生成页只能通过改库角色来表达视频提交的类型。同一张图被图片步复用时，视频角色与图片角色只能各存一份，素材库因此看起来同时承担「文件事实」与「引用语义」。用户 2026-10-26 的反馈把这一点说清楚了：素材起什么作用，应当由流程页在引用时决定，素材库不该再有库角色列；一张素材可能被多处引用，一个「用途」列会把多处角色压成一个值。

## 2. 目标与非目标

### 2.1 目标

- 素材库成为唯一文件管理面：上传、删除、查看文件事实与引用情况都在这里；引用角色不在素材库编辑。
- 生成页只显示本次视频提交的引用条目（asset + role）；首尾帧页只显示 `keyframe.toml` 的 `refs`。两份声明独立，顺序与角色各自记录。
- 生成页与首尾帧页共用同一套引用行组件；角色选项、用途输入列与保存端点由步骤注入，页面不复制两套行逻辑。
- 图片步支持 N 张参考图：一张人物三视图、任意多张细节参考；每张有角色与用途；编号由清单生成。
- 提示词模板正文按角色引用图片，不再写死图2、图3；参考图分工由计算段 `image_roles` 生成。
- 删除、改角色、上传只产生一份状态，不出现「素材库改了、步骤里没变」或反过来的情况。

### 2.2 非目标

- 不做跨 case 的素材复用或全局素材库。
- 不做通用图片生成面板；模板选择与任意图片生成仍属于生成页。
- 不改视频生成通道；`firstLastFrame` 仍只收首帧与尾帧两张图，细节图不会进入视频模型。
- 不做素材去重、批量重命名、批量改角色。
- 不就同一份清单里重复放置同一素材做特殊支持：同一素材在每份清单里只出现一次，跨步骤可以重复引用。
- 不改 `clip.json`、`_pad.json`、`run.json` 的字段集。

## 3. 数据模型

### 3.1 三层结构

- **文件库**：`case.toml` 的 `[[assets]]`，只存文件事实（id、kind、path、sha256）。`role` 保留为旧 case 的兼容默认，新页面的素材库不展示、不编辑。
- **视频提交集**：`[submit]` 的 `selected` 有序 id 数组与 `roles` 映射。顺序就是提示词 `@VideoN` / `@ImageN` 与 argv 的顺序；角色按 id 取 `roles[id]`，缺省回退到 `[[assets]] role`。
- **图片步参考集**：`keyframe.toml` 的 `refs`，新增。它是一个有序数组，每项含 `asset`、`role`、`note`。

### 3.2 视频提交集的角色

```toml
[submit]
selected = ["i2", "i4"]

[submit.roles]
i2 = "first_frame"
i4 = "last_frame"
```

规则：

- `selected` 决定顺序；`roles` 按 id 记录本次视频提交的角色。新增条目写 `roles`；旧 case 没有 `roles` 时回退到 `[[assets]] role`。
- 生成页的角色下拉写 `[submit.roles]`，不写 `[[assets]] role`；素材库不再出现角色下拉。
- 同一素材在同一份清单里只出现一次；跨步骤可以重复引用，两份清单的角色各自记录。`roles` 用 id 做键，天然保证一份清单里一个素材只有一个角色。
- `firstLastFrame` 门控读 `[submit.roles]`：恰好一张 `first_frame` 与一张 `last_frame`，其余条目会让门控给出具体原因。
- `vrgen submit --refs` 已经按条目接收 role，vrgen 侧不需要改；vrstudio 装配 `--refs` 时用 `roles[id]` 覆盖素材的兼容角色。
- 旧版控制台的兼容（已随决策 42 删除）：旧版在役时 `set_asset_role` 与只传 id 的 `set_submit_selected` 同步写 `[submit.roles]`；退役时同步已移除。

### 3.3 `keyframe.toml` 的新格式

```toml
extract = "20261023-085718"

[[refs]]
asset = "i1"
role = "subject_ref"
note = ""

[[refs]]
asset = "i27"
role = "detail_ref"
note = "头冠纹样与金色饰物"

[first]
round = "img-3485b660"
index = 2
asset = "i19"

[last]
round = "img-9c499cd2"
index = 4
asset = "i26"
```

规则：

- `role` 只能是 `subject_ref` 或 `detail_ref`；`subject_ref` 恰好一项，`detail_ref` 可以零到多项。
- `refs` 的顺序是用户编辑的顺序；`subject_ref` 固定排在第一位，细节图按用户在清单里的顺序排列。
- `note` 只对 `detail_ref` 有意义，长度上限 80 字；`subject_ref` 的 `note` 恒为空。
- 不允许把 `first_frame`、`last_frame`、`edit_master`、视频写进 `refs`；首帧定稿由尾帧批次自动追加，不占 `refs` 的一项。
- 删除素材时同步从 `refs` 移除；如果删掉的是 `subject_ref`，清单进入「缺少人物三视图」状态，不自动把某张细节图提升为主图。
- 旧格式 `sheet = "i1"` 在读取时视为只有一项 `subject_ref` 的清单；第一次写入新格式时写成 `[[refs]]`，不再写 `sheet`。

### 3.4 图片步的最终输入顺序

首帧批次：

```text
图1 = first_frame_raw.png        role=first_frame_raw
图2 = subject_ref                role=subject_ref
图3..N+2 = detail_ref（按清单顺序） role=detail_ref
```

尾帧批次：

```text
图1 = last_frame_raw.png         role=last_frame_raw
图2 = subject_ref                role=subject_ref
图3 = first_frame（当前首帧定稿）  role=first_frame
图4..N+3 = detail_ref（按清单顺序） role=detail_ref
```

首帧定稿固定插在人物三视图之后、细节图之前，让身份锚点先于细节出现；这条顺序由后端唯一决定，页面只展示编号。编号不写进 `refs`，每次按当前清单与步骤计算，避免顺序变化后编号失效。

### 3.5 提示词渲染

- `image_roles` 仍由 vrgen 按最终输入顺序生成，格式为 `图N = 角色说明[：用途]。`。
- `IMAGE_ROLE_TEXT` 增加 `detail_ref`：`细节参考图（只继承所指细节的外观，不取构图、背景与姿态）`。
- `keyframe-first.md` 与 `keyframe-last.md` 的正文不再出现「图2」「图3」这类位置编号；人物外观改为「严格按参考图分工里标注为『人物三视图』的图」，尾帧一致性改为「标注为『人物三视图』与『首帧定稿』的图」。
- 四个可编辑变量 `figure`、`pose_first`、`pose_last`、`preserve` 不变；它们描述人物与姿态，不描述图片。只把「从三视图抄要点」改成「从参考图抄要点」。
- 提示词正文上限仍是 2000 字；细节图用途会增加长度，`note` 上限 80 字，模板测试要覆盖多图场景。

## 4. 页面

### 4.1 case 级导航

- 新增 `/case/:name/library`，复用现有 `/case/:name/:step?` 路由与 `WizardView`，把 `library` 当作 case 级视图而不是流程步骤。
- `WizardView` 在 case 标题下增加「流程 / 素材库」开关；素材库计数取 `info.assets.length`。
- 素材库视图隐藏步骤条，不显示底部提交条；case 账号锁与保存状态继续生效。
- 「流程」回到上次停留的步骤；上次步骤记在 `WizardView` 的内存里，刷新后回到流程第一步。
- 顶部标题与 `stepLabel` 增加「素材库」。

### 4.2 素材库页

```text
素材库                                          28 个文件 · 图片 28 · 视频 0 · 被引用 7   [上传素材]
case 级文件集合。这里只存文件；角色由各步骤的引用清单决定。
[搜索 id 或文件名] [全部类型] [全部引用状态] [按 id]
┌ 缩略图 │ 文件名与 id            │ 文件类型 │ 尺寸 / 大小 │ 引用   │ 操作 ┐
│ 缩略   │ i1_大臣_三视图.png     │ 图片     │ 3072×2688  │ 2 处   │ 打开 ×│
│ 缩略   │ i2_keyframe-walk_4k…   │ 图片     │ 3840×2160  │ 1 处   │ 打开 ×│
│ 缩略   │ i3_keyframe-walk_4k…   │ 图片     │ 3840×2160  │ 未引用 │ 打开 ×│
└──────────────────────────────────────────────────────────────────────────┘
```

- 表格列固定为：缩略图、文件名与 id、文件类型、尺寸与大小、引用、操作。
- 文件类型只表示图片或视频，是文件事实，用于筛选与展示；它不是引用角色，也不是下拉框。
- 引用列是从两份引用声明派生的次数：视频提交、图片参考、首尾帧定稿各算一处。同一素材被多处引用时显示「N 处」，点击打开明细，列出「步骤 + 角色」。明细只读，不能在这里改角色。
- 筛选：搜索、文件类型、引用状态、排序。引用状态只有「全部 / 被引用 / 未引用」，不再有库角色筛选。
- 上传按钮打开现有 `AssetUploadDialog`；上传只写文件库，不自动加入任何提交集或参考清单。
- 删除调用现有 `removeAsset`；确认框列出引用明细，确认后后端同步清理 `[submit]` 的 `selected` 与 `roles`、`keyframe.toml` 的 `refs` 与首尾帧指针。
- 素材库不做排序编辑。库的顺序只是展示顺序；视频提交顺序由提交清单维护，图片参考顺序由参考图清单维护。

### 4.3 生成页

- 用 `GenerateSubmitList` 替换 `GenerateAssets`：它渲染 `info.submit_entries`，每个条目是 `{asset, role}`，按 `selected` 顺序编号 1、2、3。
- 每行显示序号、缩略图、文件名、角色下拉、其他步骤的引用摘要、上移、下移、从本次提交移除。角色下拉是本次视频提交的类型，改动立即写回 `[submit.roles]`。
- 头部的「N 项已选」「添加素材」「去素材库管理」保持不变；空状态显示「还没有选择素材」与「从素材库添加」。
- 「添加素材」打开选择器的视频模式；选择器只返回 id，加入后按文件类型给一个初始角色（图片 `subject_ref`、视频 `motion_ref`），由用户在清单里改成实际角色。
- 上下移动直接调用 `saveSubmitSelection(ids, roles)` 写入新的 id 顺序；不再调用 `reorderAssets`。
- `firstLastFrame` 的门控读清单里的角色：恰好一张 `first_frame` 与一张 `last_frame` 才算通过；多出的条目或角色不对时，清单下方常显「当前首帧 N、尾帧 M，共 K 项」，不新增本地硬限制。
- 角色不在素材库编辑，也不在生成页只读；它是清单条目的属性。

### 4.4 首尾帧页

四格保持不变，语义如下：

- 图1：当前步骤的原始帧，来自 `extracts/<current>/first_frame_raw.png` 或 `last_frame_raw.png`。
- 图2：参考图组。显示主三视图缩略图与「共 N 张」角标；「编辑参考图」滚动到下方清单。
- 图3：首帧定稿。只在尾帧步骤显示实际图片与编号；首帧步骤显示「尾帧步骤插入」，不占编号。
- 目标：当前步骤的定稿图。

参考图清单内联在四格下方：

```text
参考图清单                                      3 张参考图  [＋ 添加参考图]
编号与提示词里的图N 一致；第一张人物三视图固定在图2，尾帧步骤的首帧定稿自动插在它后面。
┌ 图2 │ 缩略 │ 人物三视图 · i1        │ [人物三视图▾] │ 主三视图不需要用途说明     │ 固定在图2 ┐
│ 图3 │ 缩略 │ 首帧定稿 · i19（自动）  │ 首帧定稿      │ 尾帧批次自动追加，不可移除 │ 🔒 自动   │
│ 图4 │ 缩略 │ 细节参考 · i27         │ [细节参考▾]   │ 头冠纹样与金色饰物         │ ↑ ↓ ×     │
│ 图5 │ 缩略 │ 细节参考 · i28         │ [细节参考▾]   │ 袖口刺绣与腰带             │ ↑ ↓ ×     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

交互规则：

- 主三视图只能有一张。把某张细节图改成人物三视图时，旧主图自动降为细节参考，新主图移到清单第一位；把唯一的主图改成细节参考会被拒绝并提示「先指定另一张人物三视图」。
- 细节图可以上下移动；首帧定稿行不可移动、不可删除；主图固定第一位。
- 用途输入防抖保存（400ms），与提示词变量保存一致；角色与顺序改动立即保存。
- 「添加参考图」打开选择器的图片模式；没有主三视图时，第一张选中图成为主三视图，其余默认细节参考。
- 保存调用 `PUT /api/case/<name>/keyframe/refs`，返回完整 case info；页面用返回的 `info.keyframe.refs` 重画。
- 提示词面板增加可折叠的「完整提示词（含参考图分工）」，直接显示 `prompt.rendered`；四个变量卡不变。
- 候选面板、定稿挑选、交接按钮、任务折叠行都不变。
- 删除三视图抽屉、`changeSheet`、`sheetOpen` 与相关样式；三视图的查看与更换由参考图清单承担。

### 4.5 选择器

`AssetPickerDialog` 一个组件，两种模式：

- **视频模式**：从全部素材选择；勾选顺序就是加入顺序；已加入本次提交的行显示「已加入」并禁用。角色不在选择器里设置，加入后在提交清单里选。
- **图片模式**：只列图片；已加入 `refs` 的行禁用；第一张在缺少主三视图时成为主三视图，其余默认细节参考。

两种模式共用：

- 搜索、文件类型筛选、「只看未加入」。
- 缩略图、文件名与 id、文件类型、尺寸、引用次数。
- 底部「已选 N 项」、上传、取消、添加。
- 上传调用现有 `AssetUploadDialog`；上传完成后刷新列表并继续选择，不关闭选择器。
- 选择器不写角色，也不直接写业务数据；确认后由调用方写 `[submit]` 或 `keyframe.toml` 的 `refs`。

### 4.6 组件边界

- 新增 `CaseLibraryView.vue`：素材库页，文件表格、筛选、引用明细、删除与上传。
- 新增 `AssetPickerDialog.vue`：两种模式的选择器，只返回 asset id。
- 新增 `AssetReferenceList.vue`：生成页与首尾帧页共用的引用行组件。属性为 `entries`、`roleOptions`、`showNote`、`addLabel`、`emptyText`；事件为 `add`、`remove`、`move`、`role`、`note`。父组件负责保存：生成页写 `[submit]`，首尾帧页写 `keyframe.toml`。
- 新增 `AssetUsageCount.vue`：引用次数与明细弹层，素材库与选择器共用。
- 新增 `GenerateSubmitList.vue`：`AssetReferenceList` 的视频薄包装，传入视频角色词表与 `saveSubmitSelection`。
- `KeyframeStep.vue`：四格 + `AssetReferenceList` 的图片模式 + 提示词预览；删除三视图抽屉。
- `WizardView.vue`：case 级「流程 / 素材库」开关与 `library` 视图。
- 共用的是行渲染、角色词表、排序、移除、上传入口与筛选；不共用选择状态。`[submit]` 与 `keyframe.toml` 的 `refs` 各自是唯一真源，角色随各自的条目走。
- 角色词表按素材种类与步骤注入：视频普通选项只包含 `edit_master`、`subject_ref`、`motion_ref`；`firstLastFrame` 模式只包含 `first_frame`、`last_frame`；图片步包含 `subject_ref`、`detail_ref`。`scene_ref`、`space_ref`、`mid_frame` 不进入普通选项，旧值以「旧角色」标记保留，可改成开放角色。
- 每个角色选项在悬停时显示说明；实现上用 `el-option` 的 `title` 或包一层 `el-tooltip`，说明文本来自后端返回的角色文案，避免前端另写一份长文本。
- 当前 `frontend/src/constants/assetRoles.ts` 的 `ASSET_ROLE_OPTIONS` 包含 `scene_ref`、`space_ref`（原型有、真实 UI 无）、`mid_frame`；实施时按 §0.6 收敛，`space_ref` 与 `mid_frame` 同时从普通选项移除。

## 5. 后端与契约

### 5.1 `vrstudio/src/vrstudio/keyframe.py`

- 新增 `Ref(asset, role, note)`；`State` 的 `sheet: str | None` 改成 `refs: list[Ref]`。
- `load()`：优先读 `[[refs]]`；没有时把旧 `sheet` 读成一项 `subject_ref`；都没有时 `refs = []`。
- `save()`：写 `[[refs]]`，不再写 `sheet`；保留 `first` / `last`。
- 新增 `normalize_refs(refs, image_ids)`：校验恰好一张 `subject_ref`、角色合法、素材存在且是图片、无重复、`note` 长度；校验失败抛 `KeyframeError`，错误文案直接给用户看。
- 新增 `remove_asset(case_dir, asset_id)`：从 `refs` 移除该素材；如果它正好是 `first` / `last` 指针，清空对应指针；返回是否有变化。
- 保留 `Pick` 与 `first` / `last` 的读写。
- 旧格式迁移只在读取时发生，不批量改写磁盘；第一次通过新接口保存时写成新格式。

### 5.2 vrstudio 后端（`case.py` 与 `web/app.py`）

- `case.py`：
  - 保留 `submit_selected` 的 id 顺序；新增 `submit_roles`（id → role）与 `submit_entries`（有序 `(id, role)`，role 缺省回退到素材的兼容角色）。
  - `set_submit_selected(name, ids, roles=None)`：同时写 `selected` 与 `roles`；只传 ids 时保留已有 roles，新增 id 用素材的兼容角色。
  - `set_asset_role`：写素材的 `[[assets]] role`；旧版在役时还同步 `submit.roles[id]`，该同步已随决策 42 删除。
  - 装配 `--refs` 清单时用 `submit_roles[id]` 覆盖素材的兼容角色；`firstLastFrame` 的角色校验读清单角色。
- `web/app.py`：
  - `_case_info` 增加 `submit_entries` 与 `submit_roles`；`submit_selected` 保留给旧版与测试。
  - `PUT /api/case/{name}/submit` 的请求体扩展为 `{"selected": [...], "roles": {...}}`；只给 `selected` 时按旧行为处理。
  - `_keyframe_state()`：
  - 新增 `refs`，每项带 `asset`、`role`、`note`、`file`、`url`、`exists`。`url` 用现有 `/img/asset/<case>/<id>`。
  - ~~保留 `sheet` 与 `sheet_candidates` 作为旧版控制台的派生字段~~（已随决策 42 删除；新前端只读 `refs`）。
  - 没有 `refs` 且素材库恰好一张 `subject_ref` 时，返回一个虚拟 `refs` 项并标记 `default: true`；读取不写文件，第一次编辑时保存。
  - `complete` 仍由两张定稿与 `stale` 决定；`ready` 改为「至少一张 `subject_ref` 且所有引用文件存在」。
- `_keyframe_inputs(case, step)`：
  - 从 `keyframe_mod` 读 `refs`，校验后构造最终顺序：原始帧、主三视图、（尾帧）首帧定稿、细节图。
  - 返回 `(path, role, note)` 三元组；非细节图的 `note` 为空。
- `_keyframe_argv()`：为每张图传 `--image`、`--image-role`、`--image-note`；条数一一对应。其余参数不变。
- `_keyframe_prompt()` / `_keyframe_save_prompt()`：把同样的角色与用途传给 `prompt show/save`；四个变量白名单不变。
- 新增 `PUT /api/case/{name}/keyframe/refs`：请求体 `{"refs": [{"asset": "i1", "role": "subject_ref", "note": ""}]}`；调用 `normalize_refs` 与 `keyframe_mod.save`；返回完整 case info。校验失败返回 400，错误文案说明哪一项不合格。
- ~~保留 `PUT /api/case/{name}/keyframe/sheet` 作为旧版控制台的兼容入口~~（已随决策 42 删除；设置主三视图改走 `keyframe/refs`）。
- `api_assets()` 的 `remove` 分支：删除素材后调用 `keyframe_mod.remove_asset()`，清掉 `refs` 与指针；返回的 case info 会反映新的 `keyframe` 状态。
- `_gates` 的 `keyframe` 原因文案改成「素材库缺少人物三视图；在首尾帧页的参考图清单里加入一张」等。
- `_case_info` 不需要新增素材用途字段；素材库页用 `assets`、`submit_entries`、`keyframe.refs`、`keyframe.first/last` 自己计算引用次数与明细。

### 5.3 vrgen

- `src/vrgen/round/image.py`：
  - `IMAGE_ROLE_TEXT` 增加 `detail_ref`。
  - `image_roles_text(roles, notes=None)`：有用途时输出 `图N = 角色说明：用途。`；无用途时保持原文。
- `src/vrgen/cli.py`：
  - `image submit` 增加 `--image-note`（可重复）。给了就必须与 `--image` 条数相同；只允许与 `--template` 同用；空字符串表示这张图没有用途。
  - `prompt show` 与 `prompt save` 增加 `--image-note`，传入 `_prompt_preview`。
  - `image_roles_text` 的调用点同步传 notes。
- `docs/case-model.md` §4 先更新：`--image-note` 的语义、条数约束、与 `--image-role` 的对应关系、`run.json` 不新增字段。渲染后的正文照旧写进 `prompt.txt`，台账可审计。
- `run.json` 的 `params.images` 仍记录全部图片路径；角色与用途不写台账字段，靠 `prompt.txt` 追溯。

### 5.4 前端类型与 API

- `types/case-info.ts`：`CaseInfo` 增加 `submit_entries: { asset: string; role: string }[]` 与 `submit_roles: Record<string, string>`；`submit_selected` 保留为兼容字段。
- `types/case-info.ts`：`KeyframeState` 增加 `refs: KeyframeRef[]`；`KeyframeRef` 含 `asset`、`role`、`note`、`file`、`url`、`exists`、`default`。保留 `sheet` / `sheet_candidates` 作为可选兼容字段，新页面不读。
- `api/case.ts`：`saveSubmitSelection(name, selected, roles)` 同时提交 id 顺序与角色映射；`reorderAssets` 不再被生成页调用，素材库不排序。
- `api/keyframe.ts`：新增 `setKeyframeRefs(name, refs)`；`setKeyframeSheet` 已随决策 42 删除。
- `constants/steps.ts`：`stepLabel('library')` 返回「素材库」；`stepsForFlow` 不变。
- `AssetDetail.role` 保留为兼容默认；素材库页只读文件事实，不展示库角色。

## 6. 迁移与兼容

- **旧 `keyframe.toml`**：读取时 `sheet` 视为一项 `subject_ref`；首次保存写成 `[[refs]]`。旧的两帧指针不变。
- **旧 `[submit]`**：没有 `roles` 时按 `[[assets]] role` 回退，顺序原样保留；新页面第一次保存时写 `roles`。旧 case 不需要批量迁移。
- **旧版控制台（已随决策 42 退役）**：旧版在役期间使用 `sheet` / `sheet_candidates` 与 `/keyframe/sheet`，以及 `[[assets]] role`；`set_asset_role` 同步写 `submit.roles`，保证旧版改角色仍然生效。退役时这三个兼容点已同批删除。
- **旧素材**：不批量改动；素材库页按现有 `[[assets]]` 展示。重复内容（walk_4k 里多张候选哈希相同）不在本轮去重。
- **旧轮次**：`run.json` 与 `prompt.txt` 不动；历史轮次仍可查看。新轮次的 `prompt.txt` 会包含细节图分工。
- **旧测试**：依赖 `sheet` / `sheet_candidates` / `submit_selected` 的测试保留，作为兼容层测试；新增 `refs` 与 `submit_roles` 的测试覆盖主路径。

## 7. 测试

### 7.1 vrgen

- `test_image_roles_text_includes_notes`：角色、用途、顺序生成正确的「图N = …：…」。
- `test_image_submit_rejects_note_count_mismatch`：`--image-note` 条数与 `--image` 不同时参数错。
- `test_image_submit_rejects_note_without_template`：`--image-note` 只能与 `--template` 同用。
- `test_image_submit_renders_detail_refs`：三张图 + 两条用途，`prompt.txt` 含正确分工。
- `test_prompt_show_and_save_carry_notes`：`prompt show/save` 的 `rendered` 含用途，草稿不含 `image_roles`。
- 模板覆盖测试：两个 `keyframe-*` 模板不再出现写死的「图2」「图3」；`detail_ref` 的文案存在。

### 7.2 vrstudio 后端

- `test_keyframe_refs_round_trip`：`Ref` 列表保存与读取，顺序、角色、用途不变。
- `test_keyframe_legacy_sheet_becomes_ref`：旧 `sheet` 读取为一项 `subject_ref`；保存后文件里是 `[[refs]]`。
- `test_keyframe_refs_require_one_primary`：零张或两张 `subject_ref` 被拒绝，文案可读。
- `test_keyframe_refs_reject_video_and_anchor_roles`：视频、`first_frame`、`last_frame` 不能写进 `refs`。
- `test_keyframe_inputs_order_first_step`：原始帧、主图、细节图的路径与角色顺序正确。
- `test_keyframe_inputs_order_last_step`：首帧定稿插在主图与细节图之间。
- `test_keyframe_argv_carries_image_notes`：argv 的 `--image-role` 与 `--image-note` 条数相同且对应。
- `test_keyframe_prompt_uses_refs_and_notes`：`prompt show/save` 传对角色与用途。
- `test_keyframe_refs_endpoint`：PUT 保存、返回完整体、非法请求 400。
- `test_remove_asset_cleans_refs_and_picks`：删除主图、细节图、首尾定稿分别清掉对应状态。
- `test_keyframe_gate_requires_primary_ref`：没有主图时门控失败；有主图但缺定稿时 `complete=false`。
- `test_keyframe_sheet_alias_is_derived`：`sheet` 始终等于主三视图；旧版 `/keyframe/sheet` 提升主图后 `refs` 顺序正确。
- `test_submit_roles_round_trip`：`selected` 顺序与 `roles` 映射保存、读取一致。
- `test_submit_roles_fallback_to_asset_role`：旧 `[submit]` 没有 `roles` 时按 `[[assets]] role` 回退。
- `test_submit_endpoint_accepts_roles`：PUT 同时写 `selected` 与 `roles`；只给 `selected` 时保留已有 roles。
- `test_refs_assembly_uses_submit_roles`：装配 `--refs` 时用清单角色覆盖素材的兼容角色。
- `test_submit_roles_gate_first_last_frame`：清单角色决定 `firstLastFrame` 门控，不是素材的兼容角色。
- `test_set_asset_role_syncs_submit_roles`：旧版改库角色时同步写 `submit.roles[id]`。
- `test_remove_asset_cleans_submit_roles`：删除素材时同步清掉 `submit.roles` 的键。

### 7.3 前端

- `asset-reference-list.spec.ts`：共用组件的两种布局；角色下拉、顺序、移除、用途输入（仅图片模式）；事件只发信号，保存由父组件负责。
- `keyframe-step.spec.ts`：四格渲染；参考图清单主图固定第一位；细节图用途输入；首帧步骤编号 1/2/3；尾帧步骤编号 1/2/3/4；首帧定稿锁定行；改主图时旧主图降级；移除唯一主图被拒绝；选择器添加细节图；完整提示词预览含用途；三视图抽屉不再存在。
- `generate-step.spec.ts`：提交清单来自 `submit_entries`；角色下拉写回 `roles`；添加、移除、上移、下移写回正确顺序；`firstLastFrame` 门控按清单角色；空状态；素材库不再出现库角色。
- `asset-picker.spec.ts`：视频/图片两种模式；已加入禁用；选择顺序；上传入口；文件类型筛选；不显示库角色、不写角色。
- `case-library-view.spec.ts`：26 项渲染；搜索、文件类型、引用状态筛选；引用次数与明细弹层；没有库角色列；删除确认列出引用明细；删除后同步清理 `selected`、`roles` 与 `refs`。
- `steps-and-flow.spec.ts`：`library` 路由与标题；素材库隐藏步骤条与底部提交条；流程回到上次步骤。

### 7.4 门禁

- 前端：`npm run lint`、`npm run typecheck`、`npm run test`、`npm run build`。
- 后端：两仓库 `uv run pytest` 全绿、`uv run ruff check .` 干净。
- 像素基线不涉及生成步骤的编码与几何；不新增像素比对。

## 8. 验收

浏览器（`walk_4k`，真实抽取版本 `20261023-085718`）：

1. 打开 case，case 顶栏出现「流程 / 素材库 28」开关；素材库页隐藏步骤条与底部提交条。
2. 素材库页显示全部文件；文件类型只读，引用列显示次数。初始 i1 为 1 处（图片参考）、i2/i4 各 1 处（视频提交）、i19/i26 各 1 处（首尾帧定稿）、i27/i28 各 1 处（图片参考）；页面没有库角色列。
3. 搜索 `i19`、筛选「被引用」「未被引用」与文件类型都能得到正确结果。
4. 在生成页把 i1 加入提交清单，角色设为 `subject_ref`；回到素材库，i1 的引用变为 2 处，点开明细看到「视频提交 · 主体参考」与「图片参考 · 人物三视图」；素材库没有角色下拉，也没有因为两处引用而出现冲突值。
5. 删除一张被引用的细节图，确认框列出「步骤 + 角色」；确认后首尾帧清单少一项，视频提交清单不受影响。
6. 删除主三视图，首尾帧页提示「缺少人物三视图」并禁用生成按钮；添加另一张并设为主图后恢复。
7. 生成页只显示 i2 与 i4；点「添加素材」打开选择器，选择 i1 后清单多一项、门控提示 `firstLastFrame` 当前首帧 1、尾帧 1、共 3 项；把 i1 的角色改成 `first_frame` 后门控提示首帧 2；移除 i2 后门控通过。
8. 生成页改角色、上移、下移后刷新页面，顺序与角色保持；`[submit] selected` 与 `[submit.roles]` 与页面一致。
9. 首尾帧页首帧步骤：图1 原始首帧、图2 主三视图、图3 起细节图；参考图清单编号与完整提示词一致。
10. 切到尾帧步骤：首帧定稿自动插为图3，细节图顺延为图4/图5；首帧定稿行不可删除。
11. 添加两张细节图并写用途，完整提示词的【参考图分工】逐行出现「图N = 细节参考图：用途」。
12. 把一张细节图改为主三视图，旧主图变细节图，清单顺序与提示词编号同步。
13. 交接给视频步，模式为 `firstLastFrame`、只勾选两张定稿、时长填 10 秒；细节图不进入视频提交清单。
14. 生成页与首尾帧页的引用行在 1440 下都不截断文件名；1920 下保持同样结构。
15. 1440 与 1920 各截一张整页，检查无横向溢出；素材库表头在滚动时可见。

真实图片提交仍受平台额度限制；首次真实提交时记录平台返回的图片数量上限与细节图比例是否被接受，回填本文 §9。

## 9. 风险与回退

- **旧版控制台兼容（已于 2026-10-27 随决策 42 删除）。** 旧版在役期间保留 `sheet` 派生字段与 `/keyframe/sheet` 一个版本；`set_asset_role` 同步写 `submit.roles`，旧版改角色仍然生效。旧版退役时这三处已同批删除；历史设计保留在 §5.2 与本节，不再作为现行接口。
- **视频角色迁移。** 旧 case 的 `[submit]` 没有 `roles`，按 `[[assets]] role` 回退；新页面第一次保存时写 `roles`。回退窗口内两套路径都能读，但只有新映射会写角色，不要在实施期间让旧版与新页面同时改同一 case 的角色。
- **生成页不再显示全库。** 用户可能找不到未选文件；缓解是「添加素材」选择器、素材库入口计数与空状态文案。若实际使用中仍难找，再考虑在生成页加一个只读的「未选 N 项」链接，不恢复全库列表。
- **`firstLastFrame` 加错文件。** 选择器不按角色过滤；加入后角色默认是 `subject_ref`，由用户在清单里改。清单下方的门控常显「当前首帧 N、尾帧 M、共 K 项」，不新增本地硬限制。
- **删除主三视图。** 不自动提升细节图；门控失败并给出「在参考图清单里加入一张人物三视图」的文案，避免静默换人。
- **提示词长度。** 细节图用途增加正文长度；`note` 上限 80 字，模板测试覆盖 6 张图的场景。超过平台上限时按平台返回的具体项报错，不在本地截断。
- **平台图片数量与比例。** 细节图可能是非 16:9；图片模型是否接受任意比例、单次最多几张，需要真实提交验证。当前计划不在本地写死数量上限。
- **三套顺序。** 素材库不排序；视频提交顺序由 `[submit] selected` 维护，角色由 `[submit.roles]` 维护，图片参考顺序由 `refs` 维护。页面文案要明确，避免用户以为在素材库拖动会改提交顺序。
- **迁移只读。** 旧 `keyframe.toml` 不批量改写；只有第一次通过新接口保存才写新格式。回退时旧版仍能读 `sheet`，但新格式的 `refs` 旧版读不到主图；因此回退窗口只保留在实施期内。
- **`--image-note` 是契约扩展。** 必须先改 `docs/case-model.md` 再改两侧代码；vrgen 的 `--image-note` 与 `--image` 条数校验要有测试，避免角色与图片错位。

回退方式：

- 前端：素材库页与选择器是新增文件；生成页、首尾帧页、`WizardView` 的改动分三次提交，可分别 revert。
- 后端：`refs` 端点与 `keyframe.py` 的新格式可保留，旧 `sheet` 兼容层保证旧版可用；回退前端不需要回退数据。
- vrgen：`--image-note` 是可选参数；不带时行为与现在一致。

## 10. 实施顺序

1. **文档**：新增本文；更新 `docs/keyframe-workbench-plan.md` §2.3 的固定契约前提；更新 `docs/case-model.md` §2/§4 的 `[submit] roles` 与 `--image-note`；更新 `AGENTS.md` 文档索引。
2. **vrgen**：`IMAGE_ROLE_TEXT`、`image_roles_text`、`--image-note`、`prompt show/save`、模板正文、测试。
3. **vrstudio 后端**：`case.py` 的 `submit_roles` / `submit_entries` / 兼容同步；`keyframe.py` 的 `Ref` 与迁移；`_keyframe_state` / `_keyframe_inputs` / `_keyframe_argv` / `_keyframe_prompt` / `_keyframe_save_prompt`；`refs` 端点；门控；删除清理；测试。
4. **vrstudio 前端**：类型与 API、`AssetReferenceList` 共用组件、素材库页、选择器、引用次数、生成提交清单、首尾帧参考图清单、case 级开关、单测。
5. **验收**：真实浏览器走 §8；写 `docs/test-runs/20261026-asset-library-refs.md`，记录截图、接口证据与未验证项。

每一阶段结束都跑对应仓库的门禁；第 3 阶段结束时两仓库 pytest 全绿，第 4 阶段结束时前端四项门禁全绿。

## 11. 实施前的确认记录

- 素材库独立页、生成页只留引用条目、首尾帧参考图清单内联、两页共用引用行：已确认。
- 视频提交清单按条目存角色（`[submit] selected` + `[submit.roles]`）：按引用清单决定角色的方向实施；旧 case 缺 `roles` 时回退到 `[[assets]] role`。
- 本轮角色范围：视频普通选项只开 `edit_master`、`subject_ref`、`motion_ref`；`firstLastFrame` 另开 `first_frame` / `last_frame`；`scene_ref`、`space_ref`、`mid_frame` 从普通选项移除，旧值保留为「旧角色」。图片步只开 `subject_ref` / `detail_ref`。
- 角色下拉的每个选项在悬停时显示一句说明；说明文本与后端角色文案保持一致。
- 每份清单里一个素材只出现一次；跨步骤可以重复引用，角色各自独立。
- `--image-note` 按本稿实施；如果后续改为整组说明，再改模板变量方案。
- 旧版控制台已随决策 42（2026-10-27）退役；`sheet` 兼容字段、`/keyframe/sheet` 与 `submit.roles` 同步已同批删除。

## 12. 实施记录（2026-10-26）

已落地：

- **契约与文档。** 根仓库 `e72a3f0` 登记本文，扩展 `docs/case-model.md` 的 `[submit] roles` 与图片步 `--image-note`；`docs/keyframe-workbench-plan.md` 标注固定输入前提失效。
- **vrgen。** `59636e8` 增加 `detail_ref` 角色文案、`image_roles_text` 的逐图用途、`image submit` / `prompt show|save` 的 `--image-note`，并把两个首尾帧模板改为按角色引用图片。
- **vrstudio 后端。** `3475637` 增加 `[submit.roles]`、`submit_entries`、`submit_role`、旧调用方回退与角色同步；`keyframe.toml` 的 `refs`、`Ref`、`validate_refs`、删除清理、`PUT /keyframe/refs`、门控与兼容 `sheet` 字段。
- **vrstudio 前端。** `aa83fc2` 新增 `AssetReferenceList`、`AssetPickerDialog`、`CaseLibraryView`、`GenerateSubmitList`；生成页只显示提交条目，首尾帧页改为参考图清单，case 顶栏增加「流程 / 素材库」开关；角色选项收敛为三个普通角色加 `firstLastFrame` 的首尾帧，`space_ref` / `mid_frame` 不再出现在普通选项；角色说明以固定行与选项悬停文本呈现。
- **测试。** vrgen 155 条、vrstudio 400 条、前端 87 条全绿；两侧 `ruff` 干净，前端 typecheck / lint / build 通过。详细验收见 `docs/test-runs/20261026-asset-library-refs.md`。

与稿的差异：

- 生成页的「去素材库管理」文字链接没有保留；case 顶栏的「素材库」开关承担入口，避免重复放导航。
- 上传对话框不再让用户选库角色，按文件类型写默认角色；实际引用角色在清单里设置。
- 视频选择器保留 clip/pad 流程产物；素材库页只列 `[[assets]]` 文件，另在表格上方用只读「流程文件」组显示源视频与流程母版（见 `docs/key-issues/frontend-decisions.md` 条目 18，2026-10-27 补充）。
- 首尾帧的锁定主图与首帧定稿锚点都作为共享引用行里的锁定行显示：尾帧步骤主图固定图2、锚点固定图3、细节图从图4 起；首帧步骤没有锚点，细节图从图3 起。

未验证：

- 真实付费图片提交（含细节图）与真实 `firstLastFrame` 视频提交；平台返回的图片数量与比例限制尚未实测。
- ~~旧版控制台的浏览器回归；兼容字段与 `/keyframe/sheet` 保留，但未逐页点验。~~ 旧版已于 2026-10-27 退役，不再需要回归。
