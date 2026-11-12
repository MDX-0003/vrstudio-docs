# 首尾帧图片输入重排与 10 张上限方案

状态：已实施（2026-11-12）。验收见 `docs/test-runs/20261112-keyframe-input-cap.md`。原型在 `.tmp_prototype/keyframe-refs/index.html`（不随仓库提交），截图为该目录 `shots/`。

关联文档：`docs/keyframe-workbench-plan.md`（图片步工作台的历史设计）、`docs/plan/asset-library-separation-plan.md`（有序参考图清单的来源）、`docs/case-model.md`（`keyframe.toml` 与 `--image-role` 契约）、`docs/spec/asset-roles.md`（角色词表边界）、`docs/key-issues/frontend-decisions.md`（前端决策记录）。

## 1. 问题

首尾帧页的「图片步输入」现在有四格，第二格写「图2 参考图组」，下方另有一份「参考图清单」，清单编号从图2、图3 起。用户提出四个问题：

1. 清单编号不从1 开始，不知道为什么，也不知道怎么解决。
2. 「图2 参考图」这个格子过时了：除默认的原始首尾帧、重绘首帧外，要提交的图片数量不固定，可以是0 张（只用提示词），也可以是多张（三视图加氛围、细节参考）。
3. 首帧选到10 张（含原始首帧）正好到上限；尾帧因为多一张重绘后的首帧，会变成图11，超限。尾帧的用户可添加参考图必须是8 张。
4. 真机上只给三张图、删掉图3 后，完整提示词预览里仍然显示「图3」；需要分析原因、记录并避免。

## 2. 已确认的决策

1. **一条动态卡片带。** 输入区只保留一条带：图1 底图（锁定）→ 图2..N 参考图（可改角色、顺序、用途）→ ＋添加参考图 → 图N+1 首帧定稿（仅尾帧，自动追加）。目标另起一行「输出」，不占图号。
2. **编号从图1 开始。** 图1 是当前步骤的原始帧；参考图按用户顺序占图2..N+1；首帧定稿固定在所有参考图之后，只在尾帧出现。同一张参考图在首帧、尾帧两步编号不变。
3. **允许0 张参考图。** 没有三视图也可以生成；黄色提示说明人物外观只能靠提示词，或在尾帧时以首帧定稿为锚点。尾帧仍然要求首帧定稿，这是另一条前置。
4. **三类参考图角色。** `subject_ref`（人物三视图，最多一张，可不在第一位）、`detail_ref`（细节参考）、新增 `lighting_ref`（氛围与光影参考，只读光线）。新增参考图默认 `detail_ref`，由用户改成三视图或氛围图。
5. **单次最多10 张输入图。** 首帧：底图 + 参考图 ≤ 10，参考图最多9 张。尾帧：底图 + 参考图 + 首帧定稿 ≤ 10，参考图最多8 张。超限不自动删图，显示红色提示、把超限的卡标出来，禁用添加、生成与交接；移除到上限后恢复。
6. **提示词按结构条件渲染。** 0 张时整段【参考图分工】不出现；没有细节或氛围图时【细节保持】【光线保持】不出现。实现用计算键配合现有的「裸标题行删除」规则，不新增模板条件语法。
7. **提示词预览必须随参考图刷新。** 参考图变化后重新请求当前步骤的提示词，并用请求序号防止旧响应覆盖新响应。
8. **三视图自由排序。** 原型允许三视图在图2、图3、图4；角色改变时保持原位置，不自动移到第一位。
9. **本轮固定10 张。** 模型44 的详情写13 张、模型25 写6 张，`params show` 还没下发参考图上限；先按10 张做页面与提交前校验，后续再按模型收窄。

## 3. 为什么用计算键，而不是在模板正文里写 if

这是本轮最重要的一处实现取舍，按「整洁和便于阅读」优先，结论是**计算键 + 现有空行删除**。

- **模板正文保持纯文本。** 模板现在是一行一句的说明文，`{键}` 只表示这里填一段内容。如果引入 `{{#if}}` 或「有参考图才渲染下一行」这类分支，模板就混进了控制流：分支要配对、要处理嵌套与转义，每加一个条件都要改模板解析器，还要给所有模板补测试。
- **现有渲染器已经能表达「有内容就保留、空就整行删」。** `prompt.render()` 的规则是：本行引用的占位符全为空，且渲染后只剩 `【标题】` 或空白时，整行删掉。把整段分工做成一个计算键 `image_roles_section`，空时返回空字符串，模板行就自然消失；不需要第二套语法，也不会误删没有占位符的独立标题行。
- **条件有名字，能单测。** `image_roles_section`、`detail_rule`、`lighting_rule` 三个键名直接说明它们管什么。测试可以逐个断言「只有底图时为空」「有细节图时只出现细节句」「有氛围图时只出现光线句」；如果写成模板 if，测试只能在整篇渲染结果里找字符串，失败时定位更差。
- **版本差异只落在数据层。** 后续再加角色或规则，只需要改计算键的返回值，模板不用动；反过来，模板文案改动不会碰分支逻辑。两条变化轴分开，review 更容易。
- **不改变现有模板的语义。** `image_roles` 仍服务其他图片模板；首尾帧模板改用 `image_roles_section`，其他模板不受影响。`COMPUTED_KEYS` 增加三个键后，`prompt save --set` 会自动拒绝它们，页面也不会把它们当可编辑变量。

代价是 `detail_rule` 与 `lighting_rule` 的句子落在 vrgen 代码里，而不是模板正文。这是有意的：它们是「有没有这个角色」的条件结果，和 `image_roles` 的图N 分工一样属于计算段；模板只负责决定句子出现在哪一行。

## 4. 为什么用显式空 `refs = []`，而不是再加一个字段或靠 if 猜

0 张参考图要能刷新后仍然是0 张。现在的 `keyframe.toml` 没有 `[[refs]]` 时，`_keyframe_refs` 与 `_keyframe_state` 会把素材库里唯一一张 `subject_ref` 自动绑回来；用户清空清单再刷新，三视图又会出现。所以「空清单」必须和「从未配置」区分开。

- **不新增布尔字段。** 加 `refs_set = true` 会造出第二个事实：`refs` 是清单，`refs_set` 说清单算不算数，两者可以互相矛盾。读的时候还要判断「有 refs 但 refs_set=false」这种不可能状态。
- **不用 if 猜。** 「refs 为空就自动绑定」正是现在的 if，它无法表达「用户明确要0 张」；「refs 为空且素材库没有三视图才允许0 张」也只是把问题挪到素材库状态上，换个 case 又会错。
- **用同一个键的空数组表达。** 清空时写 `refs = []`；读取时把「`refs` 键存在且为空」视为显式0 张，把「没有 `refs` 键」视为未配置，继续走旧 `sheet` 与唯一三视图的兼容路径。字段集没有增加，语义只有一条：键在就代表用户编辑过清单。TOML 允许空数组，`tomllib` 读出来就是空列表，不需要新解析。

这与「新建字段」的区别是：新字段要维护两份状态；空数组是一个值，状态只有一份。

## 5. 数据与契约

### 5.1 `keyframe.toml`

```toml
extract = "20261023-085718"

[[refs]]
asset = "i1"
role = "subject_ref"

[[refs]]
asset = "i25"
role = "detail_ref"
note = "头冠纹样与金色饰物"

[[refs]]
asset = "i4"
role = "lighting_ref"
note = "暖色侧光，光源在画面左上方"

[first]
round = "img-3485b660"
index = 3
asset = "i27"

[last]
round = "img-9c499cd2"
index = 3
asset = "i28"
```

规则：

- `role` 只能是 `subject_ref`、`detail_ref`、`lighting_ref`。
- `subject_ref` 最多一张，可以不在第一位；`detail_ref` 与 `lighting_ref` 任意多张。
- `refs` 的顺序就是图片步的上传顺序，也是提示词里的图2..N+1。
- `note` 对 `detail_ref` 与 `lighting_ref` 有意义，上限80 字；`subject_ref` 的 `note` 恒为空。
- 空清单写成 `refs = []`；没有 `refs` 键时继续按旧 `sheet` 与唯一三视图兼容。
- 删除素材时同步从 `refs` 移除；删掉 `subject_ref` 不自动把细节图提升为主图。

### 5.2 图片步最终输入顺序

首帧批次：

```text
图1 = first_frame_raw.png        role=first_frame_raw
图2..N+1 = refs 按用户顺序         role=subject_ref | detail_ref | lighting_ref
```

尾帧批次：

```text
图1 = last_frame_raw.png         role=last_frame_raw
图2..N+1 = refs 按用户顺序         role=subject_ref | detail_ref | lighting_ref
图N+2 = first_frame（当前首帧定稿） role=first_frame
```

首帧定稿固定追加在最后，参考图的编号因此跨两步稳定。总数不得超过10 张。

### 5.3 vrgen 计算键

新增三个计算键，写进 `jobs.COMPUTED_KEYS`：

- `image_roles_section`：本次只有底图（`first_frame_raw` 或 `last_frame_raw`）时返回空；否则返回完整的 `image_roles_text`，包括图1。
- `detail_rule`：角色里有 `detail_ref` 时返回「参考图分工里标注为『细节参考图』的图只贡献所指细节；不取它们的构图、背景与姿态。」，否则返回空。
- `lighting_rule`：角色里有 `lighting_ref` 时返回「参考图分工里标注为『氛围与光影参考图』的图只贡献光线、色温与明暗对比；不取它的构图、背景、人物与画面内容。」，否则返回空。

实现位置：`vrgen/src/vrgen/round/image.py` 增加 `image_role_variables(roles, notes)`，三个键与 `image_roles` 一起返回；`vrgen/src/vrgen/cli.py` 的 `image_submit` 与 `_prompt_preview` 都改用它。`image_roles` 保持原值，其他模板不受影响。

### 5.4 模板

`vrgen/templates/keyframe-first.md` 与 `keyframe-last.md`：

- `【参考图分工】{image_roles}` 改成 `【参考图分工】{image_roles_section}`。
- 固定句 `【细节保持】…` 改成 `【细节保持】{detail_rule}`；新增 `【光线保持】{lighting_rule}`。
- `figure` 的填写说明改成「有三视图时从它抄脸、发型、服装、配色与标志性饰物；没有就按这段文字描述。」。
- `subject_last` 的填写说明同样写成「有三视图或首帧定稿时……；没有就按这段文字描述。」。

渲染后空键只剩标题的那些行会被现有规则删掉，效果就是结构条件。

## 6. 页面

### 6.1 输入区

- 一条卡片带：图1 底图、图2..N 参考图、添加卡、首帧定稿锚点（仅尾帧）；目标单独一行「输出」。
- 每张参考图卡上有图号、缩略图、文件名与尺寸、角色下拉、用途输入、上移/下移/移除、打开原图。
- 卡头显示本步上限：首帧「本步参考图 N / 9」，尾帧「N / 8」；总数显示在「本次提交 N / 10 张」。
- 达到上限时添加卡禁用并写「已达上限 8 张」；超限卡红框、标「超出上限」；生成与交接禁用。
- 0 张时添加卡保留，提示「本步最多9 张」。
- 新增参考图默认 `detail_ref`；没有三视图时黄色提示，不拦生成。

### 6.2 提示词

- 完整提示词与分工随参考图刷新；`saveRefs` 成功后调用 `loadPrompt`。
- 请求带自增序号，只接受最新一次响应；刷新期间显示「参考图已改，提示词刷新中」。
- 提示词变量保存与参考图保存共用现有队列，避免后发先至。

## 7. 实施工作包

### WP0 文档

- 本文与 `AGENTS.md` 索引。
- `docs/case-model.md` §2 的 `keyframe.toml` 规则、§4 的计算键说明。
- `docs/spec/asset-roles.md` 的图片步小词表加 `lighting_ref`。
- `docs/keyframe-workbench-plan.md` 与 `docs/plan/asset-library-separation-plan.md` 顶部加修订指针。

### WP1 vrgen

- `round/image.py`：`image_role_variables`；`image_roles_section`、`detail_rule`、`lighting_rule`。
- `jobs.py`：`COMPUTED_KEYS` 增加三个键。
- `cli.py`：`image_submit` 与 `_prompt_preview` 改用 `image_role_variables`。
- 两个首尾帧模板。
- 测试：只有底图时分工段消失；有细节图时只出现细节句；有氛围图时只出现光线句；两种角色并存；`prompt save --set image_roles_section` 被拒；其他模板的 `image_roles` 不变。

### WP2 vrstudio 后端

- `keyframe.py`：`ROLES` 加 `lighting_ref`；`State` 增加 `refs_explicit`；`load/save` 支持显式空 `refs = []`；`validate_refs` 接受 `lighting_ref`，保留最多一张 `subject_ref`。
- `web/app.py` 的 `_keyframe_refs` 与 `_keyframe_state`：只有 `not refs and not refs_explicit` 才自动绑定唯一三视图。
- `_keyframe_inputs`：按 `refs` 顺序生成 pairs，允许0 张 `subject_ref`，锚点追加在最后，`lighting_ref` 带 note。
- `_keyframe_argv`：提交前检查 `len(pairs) > KEYFRAME_MAX_IMAGES`（10），错误文案写清当前张数与上限。
- `_gates`：去掉「必须有一张三视图」；保留 stale、缺文件、两帧定稿检查。
- `role_help`：加 `lighting_ref`。

### WP3 前端

- 新增 `components/keyframe/KeyframeInputCards.vue`（或等价拆分），承载卡片带与角色/用途/顺序交互；`KeyframeStep.vue` 只负责数据与保存。
- `KeyframeStep.vue`：上限计算、超限提示、默认 `detail_ref`、`saveRefs` 后刷新提示词、移除「必须有 primary」的校验。
- `constants/assetRoles.ts`：`KEYFRAME_ROLE_OPTIONS` 加 `lighting_ref`。
- `api/keyframe.ts`：`KeyframeRefInput.role` 加 `lighting_ref`。
- 测试：`keyframe-step.spec.ts` 重写；新增 `keyframe-input-cards.spec.ts`；覆盖 0/2/4/8/9/10、超限、锚点编号、角色切换、提示词刷新。

### WP4 门禁与验收

- `cd vrgen && uv run pytest -q && uv run ruff check .`
- `cd vrstudio && uv run pytest -q && uv run ruff check .`
- `cd vrstudio/frontend && npm run lint && npm run typecheck && npm run test && npm run build`
- 8761 临时 `vrstudio serve` + Vite dev（代理指向8761），Chrome CDP 验收；8760 不重启、不重建。
- 验收状态：首帧0/9、尾帧0/8/9 超限、删参考图后提示词刷新、0 张三视图可生成、10 张首帧超限、1440/1920 无横向溢出。

## 8. 风险与回退

- **显式空 refs 与旧文件兼容。** 旧 `keyframe.toml` 没有 `refs` 键，继续按 `sheet`/唯一三视图自动绑定；第一次保存清单后写 `[[refs]]` 或 `refs = []`。回退只需恢复 `keyframe.py` 的读取分支。
- **模板计算键影响其他图片模板。** 只改首尾帧模板使用新键；`image_roles` 与 `image_role_variables` 的其他返回值保持原样，其他模板测试必须全绿。
- **上限写死10 与模型上限不一致。** 这是本轮的已知取舍；页面与提交前校验都按10，后续 `params show` 下发模型上限后再收窄。
- **提示词刷新竞态。** 用请求序号只接受最新响应；如果仍出现旧文本，先查 `saveRefs` 是否在 pending 队列的最后一跳才调用 `loadPrompt`。
- **回退。** 前端改动集中在 `KeyframeStep.vue` 与新组件；后端集中在 `keyframe.py` 与 `app.py` 的 keyframe 段；docs 与代码分开提交，可独立 revert。
