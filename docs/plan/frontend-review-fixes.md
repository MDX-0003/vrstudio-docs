# 前端审查修复计划（2026-10-24）

状态：进行中。本文只处理 `vrstudio/frontend` 新前端（`/next`）的已审查问题；
不新增折叠、不改关键帧工作台内容、不改后端契约。

## 1. 范围与原则

- 目标页面：Vue 新前端 `/next`。旧版 `/case/<name>` 只保留回退，不再加功能。
- 本轮不做：生成页的折叠式信息架构、首尾帧工作台内容、视觉改版、移动端重排。
- 优先修“会写坏数据”和“流程判断错误”的问题，再做显示可读性与代码结构。
- 每个修复必须有对应测试；测试要能复现审查时确认的问题，而不是只测实现细节。
- 门禁：`npm run lint`、`npm run typecheck`、`npm run test`；后端 `uv run pytest`、
  `uv run ruff check .`（若本轮未改后端，仍记录现状）。

### 0. 实施状态（2026-10-24）

已完成并有测试：

- [x] FR-01 保存队列按 case 捕获；切 case 不再串写。
- [x] FR-02 `useCaseTasks` 接受响应式 case 名；步骤组件按 case 重挂载。
- [x] FR-03 `useCaseLoader` 用请求序号 + case 名丢弃旧响应。
- [x] FR-04 `applyCaseInfo` 在提示词/参数有未保存改动时不覆盖编辑区。
- [x] FR-05 `gateBlocked` 统一门控；`MergeStep` 扩充/裁回按钮修正。
- [x] FR-06 提示词变量按 `placeholders` 排序，不再按下标取。
- [x] FR-07 变量卡以别名为主标题，key 只放悬停提示；输入框自适应高度。
- [x] FR-08 无改动保存不再让预演失效。
- [x] FR-09 `nextStepForFlow` 用 `ready` 判断可操作性；打开 case 进入下一步。
- [x] FR-10 步骤定义收敛到 `constants/steps.ts`；顶栏补 `pad/recompose`。
- [x] FR-11 页头保存状态聚合提示词、参数、素材。
- [x] FR-12 生成记录隐藏预演轮次与 `stage/gate`；任务日志收进“技术详情”。
- [x] FR-13 上传对话框卸载时取消上传循环。
- [x] FR-14 设置页显示名接真实保存；移除假密度输入。
- [x] FR-21 前端单测从 5 个增加到 38 个，覆盖保存队列、加载竞态、任务轮询、
  步骤流转、提示词排序、门控、轮次、状态映射、格式化、请求超时与 `MergeStep`
  按钮禁用条件。

说明：FR-12 的轮次文案与过滤有纯函数测试；FR-13 的上传取消、FR-14 的设置保存
目前由 `typecheck`/`build` 与代码审查覆盖，尚未补组件测试。

部分完成：

- [ ] FR-07 抽屉宽度仍是 760px；变量输入框已自适应，但专注编辑体验留到下一轮。
- [ ] FR-16 任务轮询已响应 case 变化，但 `WizardView` 与 `useCaseTasks` 两套轮询
  仍在，后端按 case 过滤未做。
- [ ] FR-17 `formatSize`、任务状态、步骤定义、门控已收敛；首尾帧的 `allowed`
  变量集合与 1K/2K/4K 档位仍是硬编码。
- [ ] FR-18 API client 已合并为一个 `request()` 并加超时；视图层尚未统一消费
  `ApiRequestError`，revision Map 清理未做。
- [ ] FR-15 `WizardView` 仍未拆分；本轮只抽出了保存队列、加载器和共享定义。

未开始：

- [ ] FR-19 类型去重与死代码清理。
- [ ] FR-20 样式去重、颜色与 inline width 令牌化。
- [ ] 组件级浏览器回归测试（当前只有纯函数/composable 测试）。

本轮门禁结果：

- `npm run typecheck` 通过。
- `npm run lint` 通过。
- `npm run test`：11 个测试文件、38 个用例全绿。
- `npm run build` 通过（Vite 提示主 chunk 超过 500 kB，未处理）。
- `uv run pytest`：360 passed。
- `uv run ruff check .`：通过。

## 2. 问题清单

### P0：会写坏数据或直接阻碍流程

- **FR-01 切换 case 时保存会写错对象。**
  `WizardView.vue:98`、`:107` 的 `promptTimer` / `paramsTimer` 在卸载和切 case 时
  未清理；`flushPromptSaves` 在 `:397`、`persistParams` 在 `:456` 使用当前
  `caseName.value`。用户在 A 编辑后立刻打开 B，旧值会写进 B。
- **FR-02 切 case 时子步骤拿到“新 caseName + 旧 info”。**
  `ExtractStep.vue:12`、`KeyframeStep.vue:46`、`MergeStep.vue:12` 把
  `props.caseName` 的字符串快照交给 `useCaseTasks`；Vue Router 复用组件实例后，
  轮询仍盯旧 case。父组件 `loadCase` 是异步的，`caseInfo` 在新数据回来前仍是旧 case。
- **FR-03 `loadCase` 没有请求序号或取消。**
  `WizardView.vue:251-269` 每个响应都直接 `applyCaseInfo`；快速切 A → B 时旧响应
  可能覆盖新 case。
- **FR-04 任务完成时的刷新会覆盖本地编辑。**
  `syncRunStatus` 在 `:644`、`:656` 调 `loadCase`，`applyCaseInfo` 在 `:210-215`
  整体替换 `promptVars`。用户正在编辑提示词时，任务完成会把未保存内容冲掉。
- **FR-05 `MergeStep` 的“扩充画面”按钮禁用条件反了。**
  `MergeStep.vue:145` 只在 `!ok && reason === ''` 时禁用；真正有原因时按钮反而可点。

### P1：流程判断与显示逻辑

- **FR-06 生成页提示词摘要按下标取变量。**
  `WizardView.vue:1112-1117` 使用 `promptVars[0]`、`promptVars[2]`；变量顺序变化
  就显示错字段。应按模板 `placeholders` 顺序生成变量列表。
- **FR-07 提示词仍显示内部 key，编辑区过窄且高度固定。**
  `WizardView.vue:1426-1430` 同时显示别名和 key；`:1435` 的
  `maxRows: 8` 固定八行；抽屉 760px 过窄。
- **FR-08 “保存并关闭”会无条件让预演失效。**
  `WizardView.vue:535-541` 即使没有任何改动也把“预演通过”改成“预演已过期”，
  提示文案还写着“回到未预演”。
- **FR-09 Case 列表的“下一步”和“打开”不一致。**
  `CaseListView.vue:35-51` 用 `gates.generate.ok` 判断可操作性；后端 `ok` 表示
  已有结果，`ready` 才表示可以生成。`:100-102` 又永远跳到 `generate`，
  与“等待选区/等待抽取”的标签冲突。
- **FR-10 顶栏步骤名缺 `pad` / `recompose`。**
  `TopBar.vue:18-25` 只映射六个步骤；全流程重绘页面会显示英文 key。步骤定义在
  `WizardView.vue:62-80`、`CaseListView.vue:35-51`、`TopBar.vue:18-25` 各一份。
- **FR-11 保存状态只代表提示词。**
  页头 `saveState` 只由提示词驱动；参数和素材保存另有状态，但页头仍显示“已保存”。
- **FR-12 轮次与任务日志直接暴露开发信息。**
  `WizardView.vue:1190-1204` 显示 `stage` / `gate` / 轮次 ID；`:1243` 常显日志
  tail；预演轮次也混在生成记录里。
- **FR-13 上传对话框卸载后不会取消上传。**
  `AssetUploadDialog.vue:85-143` 的上传循环只检查 `row.status`；父组件直接关闭
  或路由切换时没有 `onUnmounted` 取消。
- **FR-14 设置页是假页面。**
  `SettingsView.vue:5-6` 的昵称与密度只存在本地 ref，刷新即丢。

### P2：维护成本与重复

- **FR-15 `WizardView.vue` 巨型组件。**
  约 1995 行，script 约 922 行、template 约 525 行、style 约 545 行，9 个 watch、
  4 个定时器；生成步骤内联，其他步骤是组件。
- **FR-16 任务轮询两套。**
  `WizardView.vue:683-689` 常驻轮询，`useCaseTasks.ts:44` 每个步骤再起一份；
  两套都在前端按 `task.case` 过滤。
- **FR-17 业务规则与格式化重复。**
  `firstLastFrame` 校验、门控原因、任务状态映射（至少五份）、`formatSize`（三份）、
  步骤定义（至少三份）、首尾帧 `allowed` 变量集合与 1K/2K/4K 档位。
- **FR-18 API 层重复且缺少超时。**
  `api/client.ts:80-144` 五个近重复请求函数；`ApiRequestError` 的 `status/payload`
  未被视图消费；revision Map 只增不减；`casePath` 在四个模块各写一份。
- **FR-19 类型与死代码。**
  `Gate` 两处定义、`RoundSummary` 全字符串、页面本地 body 类型与 API 类型重复；
  `addAssetsByPaths`、`fetchLock`、`CandidateRound` 等无消费方。
- **FR-20 样式重复和硬编码。**
  `.task-tail`、`.task-summary`、`.gate-alert`、`.load-error`、`.ctl`、`.empty`
  多份；颜色、px、inline width 分散。
- **FR-21 测试覆盖薄。**
  只有 `tests/unit/api-client.spec.ts` 5 个用例；没有组件、composable、竞态测试。

## 3. 工作包

### WP1 case 作用域保存与加载（FR-01 ~ FR-04）

- 新增 `useCaseSaveQueue`：每个待保存条目捕获自己的 case 名；`flush(caseName?)`
  只处理指定 case；`cancel()` 清空；卸载时取消。
- 提示词保存改为队列；保存响应仅在 case 名仍匹配时写回页面。
- 参数保存改为队列；提交前 flush 当前 case，参数快照在调度时捕获。
- 新增 `useCaseLoader`：请求序号 + case 名双重校验，旧响应不得覆盖新 case；
  切 case 时先清空旧 `caseInfo` 或让模板只渲染与当前 case 名一致的数据。
- `applyCaseInfo` 增加脏状态保护：本地有未保存提示词/参数时，不用轮询结果
  直接覆盖编辑区；至少保证任务完成刷新不会冲掉正在输入的值。

验收测试：

- `useCaseSaveQueue`：A、B 两个 case 的待保存条目分别写到各自 case；切 case 后
  flush 不串写；取消后不再保存。
- `useCaseLoader`：先发 A、再发 B，B 先返回、A 后返回，最终只应用 B。
- 组件级或 composable 级测试：正在编辑时收到同一 case 的新数据，不清空未保存值。

### WP2 步骤组件切 case（FR-02、FR-16）

- `useCaseTasks` 接收 `MaybeRef<string>`，内部用 `toValue`；case 变化时清空
  `tasks/latest` 并重新拉取。
- 三个步骤组件传入 `computed(() => props.caseName)`。
- 生成步骤给所有步骤组件加 `:key="caseName"`，隔离局部状态。
- 后续把后端任务接口改为按 case 查询，前端不再拉全量再过滤。

验收测试：

- `useCaseTasks`：case ref 从 A 改到 B，任务列表只保留 B；旧请求返回不覆盖。
- 组件 key 切换时，PickStep 的本地 viewport/inner 不会被旧 case 数据污染。

### WP3 门控与流程判断（FR-05、FR-09、FR-10）

- 新增 `gateBlocked(gate)`：有 `ready` 时以 `ready` 为准，否则以 `ok` 为准；
  `MergeStep` 的扩充/裁回按钮统一使用它。
- 新增唯一的步骤定义 `constants/steps.ts`：每个 flow 的步骤 key、中文名、顺序。
- 新增 `nextStepForFlow(flow, gates)`：返回 `{ key, label, actionable }`；
  生成步用 `ready` 判断“可以生成”，用 `ok` 判断“已有结果”。
- `CaseListView` 的“下一步”使用它；`openCase` 跳到该步骤。
- `TopBar` 使用统一步骤名，补 `pad` / `recompose`。

验收测试：

- `gateBlocked`：`{ok:false, reason:'x'}` 为 blocked；`{ok:false, ready:true}` 不 blocked。
- `nextStepForFlow`：patch 抽完 → 生成 ready 时返回 `generate/可以生成`；
  生成有结果但未采用 → `generate/等待选用成片`；全流程重绘补 `pad/recompose`。
- `stepLabel('pad')`、`stepLabel('recompose')` 返回中文。

### WP4 提示词显示与保存语义（FR-06 ~ FR-08）

- 新增 `buildPromptVariables(prompt)`：按 `prompt.placeholders` 排序，只保留
  `prompt.vars` 中可编辑的键；`label = labels[key] || key`；`help` 透传。
- 生成页提示词摘要改为遍历变量列表，不按下标取值。
- 变量卡片以别名为主标题，key 移入悬停提示或技术信息；输入框改为
  `minRows: 3` 且不设固定 `maxRows`，用 CSS `max-height: 40vh` 封顶。
- 完整提示词预览 `max-height: 65vh`；标题改为“完整提示词”。
- `savePrompt` 只有存在待保存改动时才让预演失效；文案与状态一致。
- 更新过时的素材区说明。

验收测试：

- `buildPromptVariables`：模板顺序与 `vars` 顺序不一致时，输出按模板顺序；
  别名、说明、只保留可编辑键都正确。
- 保存语义：无待保存改动时不改变预演状态；有待保存改动时才改。
- 浏览器验收：长 `plot` 输入框随内容增高，40vh 后内部滚动；卡片不显示 key 正文。

### WP5 共享工具与 API（FR-17、FR-18、FR-20）

- `utils/format.ts` 的 `formatSize` 替换三份实现。
- `constants/taskStatus.ts` 的任务状态文案/颜色替换五份三元表达式。
- `api/path.ts` 的 `casePath` 替换四个模块。
- `api/client.ts` 合并为一个 `request()`，增加超时、AbortError 归一化；
  `putBlob` 使用更长超时。视图逐步消费 `ApiRequestError`。
- 样式重复项收敛到 `base.css` 或共享 class；inline width 改为 token/class。

验收测试：

- `formatSize` 边界：B/KB/MB/GB、null。
- `taskStatusMeta`：四种状态与未知状态。
- `request`：404/502 文案、超时、JSON body、revision header 保持现有测试全绿。

### WP6 显示降噪与后续（FR-11 ~ FR-14）

- 页头保存状态聚合提示词、参数、素材、额度；任一保存中显示“保存中”，
  全部成功才显示“已保存”。
- 生成记录隐藏 `stage` / `gate` / 轮次 ID，预演轮次默认不当作成片；
  失败原因优先展示，完整 tail 放“技术详情”。
- 上传对话框增加 `onUnmounted` 取消；父组件关闭时也走取消。
- 设置页接真实昵称保存，或明确标成只读原型；不保留假输入框。

验收测试：

- 保存状态聚合：提示词保存中、参数已保存时页头仍显示“保存中”。
- 轮次渲染：`stage=prepared` 不显示为可用成片；失败轮次显示原因。
- 上传取消：卸载后不再发起后续分片请求。
- 设置页：昵称保存后刷新仍存在（若接后端）。

## 4. 实施顺序

1. WP3 的纯函数与测试（小、低风险，先建立共享定义）。
2. WP1 的保存队列/加载器与测试，再接入 WizardView。
3. WP2 的轮询与组件 key。
4. WP4 的提示词函数、模板与保存语义。
5. WP5 的共享工具按“先新增、再替换”推进。
6. WP6 的显示降噪与设置页。

每个工作包单独跑前端门禁；涉及后端字段时再跑后端门禁。

## 5. 不在本轮

- 生成页折叠式信息架构。
- 关键帧工作台内容与交互（只修它切 case 的轮询/局部状态，不改界面）。
- 旧版 `/case/<name>` 页面。
- 新增后端端点或改 `case-model.md` 契约；任务按 case 过滤若需要后端支持，
  单独立项。
- 视觉重设计、移动端适配、暗色模式。
