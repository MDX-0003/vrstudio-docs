# 前端关键问题与决策记录

本文记录 E:\VRAIGC 前端（web 模板、静态脚本、页面交互与客户端状态）的关键问题、已拍板决策、被排除的方案和最终解决办法。后端契约与算法决策仍在 `docs/case-model.md`、`docs/decisions.md` 与各自的计划文档里，本文只在它们影响前端交互时引用。

最后更新：2026-10-26。

前端技术栈选型的需求与论证见 `20261023-frontend-stack-selection.md`，实施计划见 `../plan/frontend-refactor-plan.md`；本文只记录页面级与交互级问题，不重复选型论证。

## 使用方式

- 每条记录至少包含六段：问题、决策、排除的方案、验证、涉及文件、后续入口；需要单独拆开根因时在问题与决策之间加「原因」段。
- 新问题按日期追加到文末，条号递增；不覆盖旧条目。旧条目的结论被推翻时，在原条目末尾追加“修正”段，并指向新条目。
- 用户的原话与判定并记：先引用用户描述或提问的原文，再写判定与理由。用户框选或点名的段落原样保留。
- 前端问题的证据优先用浏览器实测（点击到画面更新的毫秒数、页面状态、截图）与服务端日志；单测只作为回归防线，不替代页面验证。
- 没有解决的条目放进文末「待决与未做」，写明当前立场与触发条件，不写成“以后再说”。

## 1. 2026-10-22 · 生成页从长列表改为折叠分区与固定底栏

**问题**

生成步骤原来是一条从上到下的长列：素材、关键帧、Seedance 入口、生成参数、扣费额度、提示词、生成记录平铺。提交按钮在最上方，依赖的素材、参数与提示词都在下方，用户点击前无法核对本次提交。两个概念都叫 Session：扣费用的「生成会话」与底部的「Session 列表」（实际是生成轮次）。提示词预览固定高度，两千多字的提示词只能看到约十行；变量显示英文键名，非技术用户无法对应到内容。

**决策**

- 生成设置（模式、比例、输出分辨率、输入分辨率、时长）与扣费额度（项目、剧集、会话）的控件整体迁入固定底栏，页面主体不再出现这两个区域。
- 页面主体按主题折叠：最近成片、素材与提交集、首尾帧、提示词、外部成片。素材默认展开，其余收起。
- 删除「生成记录与选用」区域，收敛为「最近成片」一行上的「选用成片」按钮。
- 提示词占位符支持 `{键|显示名|填写说明}`；页面只消费 vrgen 下发的 `labels` 与 `help`，不维护第二份键名映射。
- 预演状态用页面输入快照判断是否过期，状态文字只说「当前选择未改动」，不声称与服务器身份完全相等。

**排除的方案**

- 保留长列表、只调整顺序：提交所需控件仍然分散，用户还是要上下滚动核对。
- 把生成参数单独做成一个步骤：软向导的步骤是流程阶段，参数不是阶段；拆出去会让「生成」步骤失去可提交的完整上下文。
- 保留「生成记录与选用」并只做折叠：预演轮次、失败轮次与可用成片混在一起，信息污染源没有消失。
- 前端维护一份显示名映射：模板正文与页面映射会漂移，新增变量时必然漏改。

**验证**

方案见 `docs/generate-page-plan.md`，决策编号 37。浏览器手测覆盖三条流程；预演后不做修改直接提交会复用轮次；模板渲染前后逐字节一致；两侧 pytest 与 ruff 全绿。

**涉及文件**

`vrstudio/src/vrstudio/web/templates/partials/submitbar.html`、`generate.html`、`prompt.html`、`static/params.js`、`static/prompt.js`、`static/wizard.js`、`vrgen/templates/*.md`、`vrgen/src/vrgen/prep/prompt.py`。

**后续入口**

新增生成设置或额度控件时，先判断是否真的需要新控件；底栏已经承载八个控件，继续增加会挤压窄屏空间。新增提示词变量时，必须在模板里写显示名与填写说明，模板覆盖测试会拦住漏写。

## 2. 2026-10-22 · 首尾帧工作台提升为独立步骤

**问题**

关键帧工作台原来放在生成页的折叠区里。生成页的底栏「提交生成」始终可见，用户在挑图片候选的同时也能看到视频提交按钮，两种额度混在一个视口里。工作台展开后包含两张底图、四个输入卡与两组候选网格，和素材库、提示词、最近成片叠在一页会很长。用户提出：

> 我在考虑要不要把关键帧工作台做成和”生成“一个级别的步骤更好？先做设计，你已经了解了流程，我需要你从使用的简易程度和维护成本出发考虑方案

**决策**

把首尾帧重绘做成 patch 的独立步骤，插在「抽取」与「生成」之间，步骤条变成「选区 / 抽取 / 首尾帧 / 生成 / 合并 / 对比」。标签写「首尾帧」，面板首行说明「用首尾帧生成视频时才需要，其它模式可以跳过」。

- 首尾帧步骤不显示底栏，只有本步骤的「生成候选」按钮；扣费入口按步骤分开。
- 交接动作「用这两帧生成视频」写模式与提交集，然后 `showStep("generate")`；真正的视频提交仍由底栏完成。
- 服务端 `_gates` 增加 `keyframe` 一项，四种状态分别给原因：无原始帧、无三视图、只定首帧、两帧齐全；门控只决定步骤条的对勾，不阻止用户进入生成步骤。

**排除的方案**

- 保持生成页折叠区：改动最小，但底栏在图片步同样可见，两种提交仍混在一个视口里，素材库与提交集的语义只能靠文案解释。
- 在生成页里再套一层子向导：一页两套向导，步骤状态、门控与返回路径都要各维护一份，维护成本最高，收益与独立步骤相同。
- 做成 case 级独立页面：脱离线性流程，用户要自己记住「先做帧再回来生成」，多一次导航。

**验证**

浏览器在 walk_02 上确认步骤条、两帧大图、四个变量卡、自动接尾帧与交接；`_gates.keyframe` 的四种状态由 `test_keyframe_gate_states` 覆盖；两侧测试全绿。

**涉及文件**

`vrstudio/src/vrstudio/web/static/wizard.js` 的 `FLOW_STEPS.patch` 与 `showStep`、`templates/wizard.html` 的 `pnl-keyframe`、`templates/partials/keyframe.html`、`static/keyframe.js`、`web/app.py` 的 `_gates` 与 keyframe 端点。

**后续入口**

gen 的首尾帧入口尚未接。gen 没有 extract，需要「上传两张原始帧」的入口与存放位置；`keyframe.toml` 与状态结构已按两流程通用预留，接 gen 时不要另造一套状态。

## 3. 2026-10-22 · 素材库、图片步输入与视频提交集拆开

**问题**

生成页把 `[[assets]]` 与 `[submit] selected` 当成同一件事展示。用户提出：

> 我觉得有一个容易发生冲突的地方：”本次提交集“是服务于视频生成模型的asset的，但是看起来你准备复用这个区域，同时让一个三视图服务于视频和图片生成模型的提交请求，虽然事实上确实如此，但是我认为有必要拆分开来

**决策**

拆成三层，每层只承担一件事：

- **素材库**是 case 级的文件集合：三视图、首尾定稿、用户上传的参考图。角色是库属性；增删改排发生在素材库；库里有什么不代表本次要提交什么。
- **图片步的输入**是固定契约：图1 原始帧、图2 人物三视图、图3 首帧定稿（只在尾帧批次出现）。三张图谁是谁由步骤决定，用户不勾选。
- **视频提交集**只服务视频模型：勾选哪些候选（clip/pad/文件素材）就提交哪些，存在 `[submit] selected`。

规则三条：

1. 图片步不读 `[submit] selected`，也不读素材卡片上的勾选框。
2. 视频步不自动带入图片步用过的参考图；首尾定稿进视频提交集，是因为交接动作显式勾选了它们。
3. 同一个文件可以被两步同时使用，但两步各自声明输入。三视图留在素材库，图片步通过 `keyframe.toml` 的 `sheet` 指针绑定它；视频步是否使用三视图，仍由视频提交集的勾选决定。

**排除的方案**

- 复用同一块勾选区域，让图片步与视频步共享选择状态：一份状态被两个模型读取，用户在任一处的操作会改变另一处，冲突无法解释。
- 图片步也允许任意勾选素材：参考图顺序与角色会变成用户每次都要维护的事实，非技术用户容易漏掉图3或把顺序弄反。
- 把三视图做成图片步私有副本：同一张图会出现两份真源，更新外观时要改两处。

**验证**

`test_keyframe_inputs_ignore_submit_selection` 覆盖「提交集为空或勾了别的素材时，图片步参考图仍由原始帧、`sheet`、首帧指针解析」；`test_keyframe_sheet_switch_does_not_touch_submit` 覆盖换绑三视图不改视频提交集；浏览器确认取消视频提交集里的三视图后图片步仍保留绑定。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py` 的 `_keyframe_state`、`_keyframe_inputs`、`_keyframe_sheet`；`vrstudio/src/vrstudio/keyframe.py`；`templates/partials/assets.html` 的标题与说明。

**后续入口**

新增图片步参考图类型时，先问它是不是固定槽位。固定槽位放进 `_keyframe_inputs` 与模板的 `image_roles`；可选参考图才考虑扩展工作台输入区，不要退回共享勾选。

## 4. 2026-10-22 · 点选首帧后自动接尾帧

**问题**

旧的图片步需要用户切步骤下拉、重新勾参考图；尾帧的默认参考图还用了字面量 `first_frame`，素材 id 是 `i1`/`i2`，永远不匹配，选中的首帧不会进入图3。非技术用户容易漏掉图3，或者连续挑两张首帧后在素材列表里留下两条同角色素材。

**决策**

- 用户点选一张首帧候选后，服务端把这张图落成素材、写入 `keyframe.toml` 的 `first`，并立即用「尾帧原始图、三视图、刚选的首帧」排入尾帧批次。
- 尾帧候选按步骤分组；首帧与尾帧各只有一个「设为…定稿」按钮，避免误点。
- 换首帧时清空旧尾帧指针并从视频提交集取消勾选；旧素材保留，不删除。尾帧批次失败时首帧定稿保留，页面给「重新生成尾帧」按钮。
- 首帧批次与尾帧批次用 `run.json` 的 `params.step` 区分，页面只展示当前步骤的候选。

**排除的方案**

- 首帧自动取第一张：首帧挑错时尾帧整批作废，损失的额度比省下的点击大；只保留为可选开关，不作为默认路径。
- 完全手动：用户要切步骤、重新勾图，最容易漏图3。
- 用「最新修改时间的同角色素材」推断当前一对：素材被复制、检出或重新添加都会改修改时间，顺序不可复现。

**验证**

`test_keyframe_pick_first_queues_last` 断言排入的尾帧 argv 第三张 `--image` 是刚选的首帧、`--step last`；walk_02 的真实运行产生 `img-8c3ed455` 尾帧批次并返回四张候选；浏览器确认挑选后候选区标出当前定稿。

**涉及文件**

`web/app.py` 的 `_keyframe_accept`、`_keyframe_argv`、`api_keyframe_pick`；`static/keyframe.js` 的 `pickKeyframe`、`renderKfStep`；`case.py` 的素材增删。

**后续入口**

新增中间帧时，把它挂在同一条链上：首帧 → 尾帧 → 中间帧。不要为中间帧另开一套批次状态。

## 5. 2026-10-22 · 图片步提示词用两个模板与四个共用字段

**问题**

图片步提示词原来写死在 `keyframe.js`，内容是 dacne 大臣剧情（矮案、红毯、黑袍人物）。换一个 case 后这段文字仍然出现，既不能复用也会误导用户；图片轮次只接收整段文本，没有模板机制。

**决策**

- vrgen 新增 `keyframe-first.md` 与 `keyframe-last.md` 两个模板，共用 `figure`（人物外观）、`pose_first`（首帧姿态）、`pose_last`（尾帧姿态）、`preserve`（必须保持）四个变量。
- 「局部编辑」「界面清理」「画质」「禁止项」写成模板固定段落，不占输入框。
- 尾帧模板额外固定三处：图3 的身份锚点、「必须与图2、图3是同一个人」、「与图3同一光照与色调」。
- `image submit` 支持 `--template`、`--vars-file`、`--step`、`--image-role`；渲染后的正文写入轮次 `prompt.txt`，台账可审计。
- 提示词卡片沿用显示名与填写说明机制，页面不写键名映射。

**排除的方案**

- 一个模板加「当前步骤」变量：模板里会出现条件段落，阅读与测试都更绕。
- 只保存自由文本草稿：实现最省，但没有框架复用，换 case 还要从头写。
- 在前端拼骨架、只把字段发给 vrgen：提示词渲染会出现两份实现，违反唯一权威点。

**验证**

`test_image_submit_renders_template` 断言正文含人物外观与图1/图2 分工、`params.step` 正确；`test_keyframe_templates_share_aliases` 断言两个模板的共用字段显示名一致；`test_prompt_show_renders_image_roles` 覆盖页面预览的 `image_roles`。

**涉及文件**

`vrgen/templates/keyframe-first.md`、`keyframe-last.md`；`vrgen/src/vrgen/jobs.py`、`round/image.py`、`cli.py`；`vrstudio/src/vrstudio/web/app.py` 的 keyframe prompt 端点；`static/keyframe.js`。

**后续入口**

新增图片步变量时，先在两个模板里决定它属于共用字段还是单步字段；两个模板的共用字段显示名必须一致，模板覆盖测试会拦住漏写说明。

## 6. 2026-10-22 · 一批四张候选对应四个并列任务

**问题**

首帧批次请求了 `--num 4`，页面只显示一张。最初的判断是平台只返回一张；查任务记录后确认平台生成了四张，代码只取了第一个任务 ID。

**决策**

- 新增 `extract_task_ids()`：从提交应答里收齐所有 `taskId`，兼容 `taskIds` 数组；`task_id` 保留第一个以兼容旧读取方。
- `Run` 增加可选字段 `task_ids`；`run.json` 记录整批任务。
- `execute_image_round` 逐个等待所有任务完成；`_fetch_all` 逐个取 `imageUrl`，按 URL 去重后下载成 `result_1.png … result_N.png`。
- 断点续跑时，已有结果数量少于任务数会重新取齐，不会停在半批。
- 页面在每批候选上显示「请求 N 张 / 返回 M 张」。

**排除的方案**

- 继续只取第一个任务：其余已付费的结果会被丢弃，页面显示的候选数量永远不对。
- 在页面层循环提交四次：一次提交已经产生四个任务，再循环会重复扣费。
- 依赖 `mglc image result 图片ID…`：当前 CLI 版本没有这个子命令（`mglc image --help` 只有 `generate` 与 `upscale`），逐任务 `task status` 取 URL 是等价且可用的路径。

**验证**

平台任务 `2063687411157760 / 762 / 764 / 766` 各一张图；用只读的 `mglc task status` 把后三张补回同一轮次，`results` 变为四张 3840×2160 候选；`test_image_batch_polls_and_downloads_every_task` 用两个并列任务的伪 payload 覆盖下载与 `task_ids`。

**涉及文件**

`vrgen/src/vrgen/round/task.py` 的 `extract_task_ids`、`round/ledger.py` 的 `Run.task_ids`、`round/image.py` 的 `execute_image_round` 与 `_fetch_all`；`vrstudio/src/vrstudio/web/app.py` 的 `_keyframe_rounds`；`static/keyframe.js` 的轮次标题。

**后续入口**

视频轮次如果将来也出现并列任务，沿用同一套 `task_ids`，不要为视频另造字段名。

## 7. 2026-10-23 · firstLastFrame 的输出分辨率下拉被误禁用

**问题**

用户反馈：

> 准确地说，我在前端无法为这个case选择其他分辨率

`params.js` 原来用一个 `noAssets` 同时判断输出与输入：

```js
const noAssets = !(gp.output || []).length || !(gp.input || []).length;
if (noAssets) {
  resSel.disabled = true;
  scaleSel.disabled = true;
}
```

firstLastFrame 没有输入视频，`input` 数组必然为空，于是输出分辨率下拉也被一起禁用。下拉里其实有 480p、720p、1080p 三项，但被禁用后只能停在第一项 480p；页面又把 480p 写进了 `generation.toml`，看起来像「这个 case 只能输出 480p」。

**决策**

- 输出与输入分开判断：`output` 为空才禁用输出下拉，`input` 为空只禁用输入缩放下拉。
- `current.resolution` 正常回显；walk_02 被写坏的 480p 改回 1080p。
- `params.js` 版本号升到 v5，刷新页面拿到新脚本。

**排除的方案**

- 保留联动禁用：firstLastFrame 永远只有 480p 可选，属于功能性错误。
- 隐藏输入分辨率下拉：`input` 为空时下拉值对提交无影响；隐藏不是必需的，但禁用逻辑仍要修正，否则其他纯图片模式会复现。
- 用 CSS 覆盖禁用状态：下拉的 `disabled` 属性仍在，用户仍然不能选。

**验证**

浏览器在 8760 的 walk_4k/walk_02 页面确认三项都可选、当前选中 1080p；输入缩放下拉仍禁用（符合 firstLastFrame 没有输入视频的事实）。

**涉及文件**

`vrstudio/src/vrstudio/web/static/params.js` 的 `renderGenParams`；`templates/wizard.html` 的脚本版本号。

**后续入口**

新增任何按模式变化的控件时，先分开判断「这个模式的输入是什么」与「这个控件的选项是否为空」，不要用一个布尔值同时控制两个控件。

## 8. 2026-10-23 · 时长“自动”从 clip 帧范围与帧率推导

**问题**

walk_4k 的 clip 是 294 帧、约 9.8 秒，但 firstLastFrame 的“自动”仍然取纯图片默认 4 秒。用户连续两次用 4 秒提交，模型把起身加长距离行走压进 4 秒，出现瞬移与冻结。用户问：

> 时长的”自动“有没有办法从已有参数（如patch时选择的帧范围 + 原始视频的帧率 推断） 推导得到？

**决策**

- 在 vrstudio 的 `clip_duration_s()` 里读当前 `extract/clip.json` 的 `frame_end - frame_start + 1` 与 `fps`，四舍五入到整秒，最低 4 秒。
- walk_4k 是 294 帧、30fps，推导为 9.8 秒，取整后是 10 秒。
- `vrstudio generate submit` 在没有显式 `--duration` 且模式是 firstLastFrame 时，把推导值作为 `--duration` 传给 vrgen；CLI 与网页走同一条规则。
- gen 没有 clip，仍回退到纯图片默认 4 秒。
- 页面拿到 `auto_duration_s`，时长下拉的“自动”显示成“自动（约 10 秒）”，生成设置的提示同步显示推导值。
- 时长仍然不写进 `generation.toml`；实际采用值只记在轮次台账的 `params.duration_s`。

**排除的方案**

- 继续用纯图片默认 4 秒：clip 是 9.8 秒时必然压缩动作，调提示词只能改变跳变的样子。
- 在 vrgen 里推导：vrgen 只看到首尾两张图，看不到 clip 的帧范围与帧率；硬塞进去会让 vrgen 认识 case 结构。
- 把时长写进 `generation.toml` 作为下次偏好：违背「时长是本次提交参数，不是持久偏好」的已有决策。
- 只在前端推导并直接发 10 秒：CLI 用户仍得到 4 秒，两套规则会漂移。

**验证**

`test_clip_duration_uses_frozen_frame_range` 断言 240 帧 @30fps 得 8 秒；`test_submit_firstlast_defaults_to_clip_duration` 断言 argv 含 `--duration 8`；`test_submit_firstlast_explicit_duration_wins` 断言显式 10 秒优先；`test_generation_params_exposes_clip_auto_duration` 覆盖页面字段。浏览器确认 walk_4k 的“自动”显示“自动（约 10 秒）”。

**涉及文件**

`vrstudio/src/vrstudio/cli/generate.py` 的 `clip_duration_s` 与 `submit`；`web/app.py` 的 `_generation_params`；`static/params.js` 的 `_fillDuration` 与固定提示；`docs/case-model.md` §4、`docs/firstlast-dev-plan.md` WP0-2。

**后续入口**

如果平台以后给 firstLastFrame 返回非整秒时长，先确认模型的 `--duration` 是否接受小数；当前 CLI 与模型都按整数秒处理，取整规则不要在下游偷偷改。

## 9. 2026-10-23 · 预演后手动时长被刷回“自动”

**问题**

用户反馈：

> 我手动修改为10s，然后点击预演时，会导致前端的时长参数被刷新回”自动“，预演提示”参数有改动“

**决策**

`params.js` 的 `_fillDuration()` 每次重画都执行 `sel.value = "auto"`。预演返回后 `renderAll()` 重画下拉，手动选的 10 秒被刷回自动，预演签名比对就报“参数有改动”。修复：

- 重画下拉前先记下当前值；选项里仍然有它，就保留；只有新模式的选项里没有这个值时才退回“自动”。
- `genDuration` 的 onchange 同时刷新生成设置的提示文字，不再只更新按钮状态。
- 预演签名仍包含时长；因为下拉值被保留，预演完成后签名不再漂移。

**排除的方案**

- 把时长写进 `generation.toml` 记住上次选择：与决策 8 的口径冲突；时长是本次提交参数。
- 预演返回后不重画页面：素材、门控与状态文字都需要刷新，跳过重画会留下过期状态。
- 只对 dry_run 做特殊处理：问题会在任何触发 `renderAll()` 的动作上复现，补丁式特判会留下同类 bug。

**验证**

浏览器在 walk_4k 上选 10 秒 → 点“预演检查（不扣费）” → 任务完成后下拉仍为 10 秒，状态显示“✓ 预演通过 · 当前选择未改动”。

**涉及文件**

`vrstudio/src/vrstudio/web/static/params.js` 的 `_fillDuration`；`templates/partials/submitbar.html` 的 `genDuration` onchange。

**后续入口**

任何“每次重画都重建选项”的下拉框，都要在重建前保留旧值；不要假设重画发生在用户操作之前。

## 10. 2026-10-23 · pick 点击后下方预览像没更新

**问题**

用户反馈：

> patch页的点击 上图全景视频，决定下图的1920x1080区间，该功能里我点击某个位置以后，下方画面没有更新

服务日志显示 viewport 已经变化，但 `POST /api/case/walk_4k/viewport` 单次耗时 2–7.7 秒；前端 `post()` 要等完整响应回来才更新下方 `vpImg.src`，连续点击会排队，画面看起来像完全没反应。

**原因**

`api_viewport`、`api_nudge`、`api_inner` 每次点击都返回完整的 `_case_info`。这份信息会重新扫描 4K 素材、两张 4K 原始帧、轮次与门控；walk_4k 上单次 4–7 秒。几何交互本身只改 `viewport` / `inner`，不需要重扫素材。

**决策**

- 新增 `_geometry_payload()`，三个几何端点只返回 `viewport`、`inner`、`previews.vp`；`nudge` 额外带 `nudged`；`reset-draft` 同样走轻量应答。
- 前端新增 `fetchGeometry()` 与 `applyGeometry()`：取回轻量结果后合并到 `info`，只重画选区，不重扫素材，也不重画整个页面。
- 点全景、摇杆微调、拖框、重置选区四条路径统一走这套合并逻辑。

**排除的方案**

- 优化 `_case_info` 本身：即使去掉一部分探测，完整信息仍然包含轮次、素材、门控与原始帧，几何点击不需要这些，优化方向不对。
- 每次点击给预览 URL 加 `Date.now()`：能强制刷新，但每次重画都会触发一次无意义的 4K 重投影，且掩盖真正的慢响应。
- 禁用预览或加长防抖：只是把延迟藏起来，用户仍然看不到即时反馈。
- 只在点击后手动刷新图片：摇杆与拖框仍然慢，且会出现三套更新路径。

**验证**

浏览器在 walk_4k 上点击顶部全景：约 185 ms 预览 URL 更新，新图加载约 206 ms，点击到画面更新约 0.4 秒；截图确认画面切到点击对应的视角。`test_viewport_click_sets_yaw_pitch`、`test_inner_drag_submits_fractions`、`test_nudge_wraps_yaw_and_clamps_pitch`、`test_reset_draft_restores_from_version` 增加了轻量 payload 断言。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py` 的 `_geometry_payload`、`api_viewport`、`api_nudge`、`api_inner`、`api_reset_draft`；`static/wizard.js` 的 `fetchGeometry`、`applyGeometry`、`erpClick`、摇杆、拖框与 `resetDraft`。

**后续入口**

新增任何只改几何或页面局部状态的端点时，先问它是否需要完整 case 信息。不需要就返回最小字段，并让前端合并；不要复用 `post()` 的全量 `info` 替换。

## 11. 2026-10-23 · walk_4k 的视频提示词精简与“中央位置”冲突

**问题**

用户换成 4K 视频后，最近几次提交的结果不符合物理原理。日志显示两次真实提交都是 `--duration 4`，而 clip 是 294 帧、约 9.8 秒；4 秒运动抽帧里，高官在 t=1.5 秒还在右侧矮案后，t=2.0 秒已经出现在画面最左侧，0.5 秒跨了大半幅画面，是跳变而不是行走。

提示词本身还有两个问题：

- “走到尾帧的中央位置站定”与尾帧图 `i4` 不一致：`i4` 里人物实际站在画面左侧偏中，不是正中。
- 动作段写了大量微观细节：抬脚离地、脚掌落地、膝盖微屈、肩胯反向转动、双臂摆动、宽袖与玉佩流苏滞后、不能整体平移。4 秒里无法同时满足，反而稀释了“起身、走过去、站定”这个主动作。

**决策**

- 时长改用自动推导的约 10 秒（见条目 8），不再用 4 秒。
- 视频提示词精简为三拍：起身、沿红毯走到尾帧位置、停下并保持与尾帧一致的朝向。
- 去掉“中央位置”，改为“尾帧的位置”；去掉微观关节与衣料细节，只保留“脚步交替落地，不要滑行或跳跃”这一条与观察到的失败直接相关的约束。
- 旧稿备份为 `vrgen_runs/walk_4k/prompt-vars-long.toml`，当前稿在 `prompt-vars.toml`；旧稿全文也保存在对应轮次的 `prompt.txt` 里。
- 首尾帧端点匹配本身没有问题：新视频首帧与 `i2` 的平均绝对误差约 2.02，尾帧与 `i4` 约 2.03；问题在中段，不在关键帧。

**排除的方案**

- 只改时长、保留长提示词：“中央位置”仍与尾帧图冲突，微观细节仍在争夺模型注意力。
- 继续在 4 秒里调提示词：模型只能把跳变换个样子，不能让 4 秒装下 10 秒的动作。
- 立刻加中间帧：当前还没有验证 10 秒加精简稿是否足够；先验证，再决定是否拆段。
- 为 firstLastFrame 单独新建视频模板：固定段落里确实有与当前模式无关的“参考视频/空间参考”描述，但这是模板层的改动，等精简稿验证后再决定是否值得。

**验证**

4 秒运动抽帧与首尾帧对照图在 `vrgen_runs/walk_4k/out/review/`；精简稿用 `vrgen prompt show` 渲染通过；自动时长在页面上显示“自动（约 10 秒）”。10 秒新稿的真实提交尚未进行。

**涉及文件**

`vrgen_runs/walk_4k/prompt-vars.toml`、`prompt-vars-long.toml`；`vrgen/templates/gen-multi.md`；`docs/keyframe-workbench-plan.md` 的 2026-10-23 补充。

**后续入口**

若 10 秒加精简稿仍出现跳变，先缩短首尾帧之间的行走距离或增加中间帧；不要回到叠约束的老路。

## 12. 2026-10-23 · 首尾原始帧在 extract 产出，但抽取页没有列出

**问题**

用户问：

> 目前抽取首尾帧是在哪一步发生的？extract吗？extra页面里目前看到的输入输出文件列表里，好像没有两张图片，我无法定位两张图片是在何时得到的

两张图确实是 `vrstudio extract` 写的：写完 `clip.mp4` 后调用 `_write_raw_frames()`，从 clip 的首帧与末帧导出 `first_frame_raw.png` 与 `last_frame_raw.png`，不缩放，与 clip 同目录。但抽取页的文件列表只列了 `clip.mp4`、`clip_mask.png`、`clip.json`，没有列这两张图，用户无法从页面确认它们是什么时候、由哪一步产出的。

用户随后修正了展示方式：

> 既然是一次输出的，我觉得你只需要把两张图片的真实路径解析出来，放到已有的”输出“列表里就好了，不要额外写新列表

判定：成立。两张图和 clip、mask、clip.json 是同一次抽取的产物，额外分组只是给同一件事加了一层结构，用户还要多读一个标题。展示方式收敛为直接追加。

**决策**

- 产出位置不变：仍在 `extract` 里完成，不新增「抽帧」步骤。
- 把 `first_frame_raw.png` 与 `last_frame_raw.png` 的真实路径直接追加到抽取步骤已有的「输出」列表，顺序在 `clip.mp4`、`clip_mask.png`、`clip.json` 之后；不新增分组，也不新增第二个列表。
- 它们仍是工作台输入，不是提交候选；不进入 `[[assets]]`，也不进入 `[submit] selected`。

**排除的方案**

- 新增一组「首尾帧工作台输入」：用户明确否定了这个写法；一次抽取的产物放在同一个输出列表里就够了，分组只会增加阅读层级。
- 新增一个「抽帧」步骤：抽取已经写了这两张图，再加一步会让同一次操作分成两处，且用户仍要理解两步的先后。
- 把两张图放进 `[[assets]]`：它们是工作台输入底图，不是视频或图片模型的提交素材；放进去会污染提交集与候选编号。
- 只在首尾帧步骤里展示、不在抽取页列出：用户无法回答「什么时候得到」，正是这次问题的来源。

**验证**

`test_patch_extract_files_list_raw_frames` 断言抽取步骤的 `outputs` 依次是 `clip.mp4`、`clip_mask.png`、`clip.json`、`first_frame_raw.png`、`last_frame_raw.png`，且响应里没有 `groups`；浏览器在 walk_4k 的抽取页确认五个文件都在同一个「输出」列表里（两张图各约 1.6 MB / 1.7 MB）。

**涉及文件**

`vrstudio/src/vrstudio/cli/extract.py` 的 `_write_raw_frames`；`vrstudio/src/vrstudio/web/app.py` 的 `_patch_step_files`；`vrstudio/tests/test_web_console.py`。

**后续入口**

gen 没有 extract，首尾原始帧需要「上传两张原始帧」的入口；接 gen 时沿用同一条边界：它们是工作台输入，不是提交候选。不要因为「页面上要有文件列表」就把它们塞进素材库。

## 13. 2026-10-23 · 选区页增加视口示意框，并留出多分辨率扩展点

**问题**

用户提出两件事：

> 我还希望给patch界面的”上方全景预览图“加一个示意框，让用户能理解”下图1920x1080 = 上图的哪个区域“，随着鼠标点击上图的位置变化而更新。 另外为了以后可以拓展patch阶段的多种分辨率选项，需要你在这方面留出接口，方便拓展

原来的顶部 ERP 只有点击选中心，没有告诉用户下方视口占 ERP 的多大范围；视口尺寸也写死在 1920×1080，没有任何可选档位的入口。

**决策**

- 示意框的几何由 `patch/projection.py` 的 `viewport_erp_rects()` 计算，输入是视口宽高、yaw、pitch、水平 FOV 与 ERP 宽高，输出 1–2 个 ERP 像素矩形；跨 0/360 经线时拆成左右两块，不再退化成整幅宽度的框。
- 服务端把矩形换算成 0..1 分数，放在 `info.viewport_footprint` 与几何交互的轻量 payload 里；页面在 `#erpWrap` 内用 `.vpFoot` 绘制边框与半透明填充，位置按视频当前的显示尺寸换算，点击、摇杆、切换尺寸后都重画。
- 多分辨率扩展点是一张表：`PATCH_VIEWPORT_OPTIONS` 列出可用档位（当前只有 `1920×1080`）。`_viewport_options()` 会把当前尺寸补进列表；页面用 `#vpSize` 下拉渲染这张表，只有一档时禁用，新增一档后自动可选。
- `POST /api/case/<name>/viewport-size` 只接受列表里的尺寸；`PreviewStore.set_viewport_size()` 保持 yaw/pitch/fov 不变，按新旧宽高比例缩放 `inner`，并更新预览 key，让下方预览按新尺寸重画。
- 新增档位不改前端逻辑：在 `PATCH_VIEWPORT_OPTIONS` 里加一行即可；如果新档位的宽高比不是 16:9，firstLastFrame 的 16:9 提交校验仍会拦住，这一点由生成步骤负责，不在选区页偷偷裁切。

**排除的方案**

- 前端用 `fov/360` 与 `fov/180` 直接算矩形：投影数学会出现第二份实现，跨经线、俯仰和宽高比变化时必然与 `patch/projection` 漂移。
- 跨经线时画整幅宽度的框：框会覆盖整个 ERP，用户无法判断视口实际在哪；拆成两块才是可读的示意。
- 新增一个「分辨率」步骤：视口尺寸是选区步骤的属性，单独成步只会多一次导航，且尺寸变化必须立刻反映到预览与示意框。
- 改尺寸时保持 `inner` 的绝对像素不变：同一取景区域会随分辨率改变而漂移；按宽高比例缩放才能保持用户选的区域。
- 把档位写死在前端下拉：后端校验、预览尺寸与 future 档位会分成两份事实。

**验证**

- `test_viewport_footprint_centered` 与 `test_viewport_footprint_splits_at_seam` 覆盖居中框与跨经线拆块。
- `test_viewport_size_scales_inner_and_switches_preview` 断言 320×180 → 1920×1080 时 `inner` 按 6 倍缩放、预览 key 改变；`test_viewport_size_rejects_unknown_option` 断言列表外的尺寸被拒；`test_case_info_exposes_viewport_options` 与 `test_footprint_payload_normalizes_to_fractions` 覆盖页面数据。
- 浏览器在 walk_4k 上确认绿色示意框随点击从 ERP 左侧移动到另一处；`#vpSize` 显示 1920×1080（单档禁用），接口已就绪。

**涉及文件**

`vrstudio/src/vrstudio/patch/projection.py` 的 `viewport_erp_rects`；`web/app.py` 的 `PATCH_VIEWPORT_OPTIONS`、`_viewport_options`、`_footprint_payload`、`api_viewport_size`；`web/render.py` 的 `PreviewStore.set_viewport_size`；`templates/wizard.html` 的 `#vpFoots`/`#vpSize`；`static/wizard.js` 的 `drawFootprint`、`renderViewportSize`、`changeViewportSize`。

**后续入口**

新增档位时只改 `PATCH_VIEWPORT_OPTIONS`。如果要加非 16:9 档位，先在生成步骤明确它只对哪些模式开放；选区页不负责把非 16:9 裁成 16:9，merge 也不会静默拉伸。

## 14. 2026-10-23 · 新前端从原型补到可执行链路

**问题**

审查 Phase 2 进展时发现：生成页的预演与提交只改本地状态，参数不落盘，采用按钮禁用，上传、素材排序/删除、任务状态回显与前端门禁都还没有；选区、抽取、首尾帧、合并、对比仍是占位页。

**决策**

- 预演与提交改为 `POST /api/case/{name}/run`，提交前先 flush 提示词并保存参数；任务状态按 case 过滤并每 2 秒轮询。
- 采用成片走 `adopt`，只对最新可用轮次开放；采用成功后刷新 case。
- 参数修改 300 毫秒防抖写 `generation.toml`；提示词顶部显示“已保存/保存中/未保存”三态。
- 上传使用 `cases/.uploads` 的 8 MB 分片、offset 校验、SHA-256 去重与断点续传；素材加入仍走 case 的素材函数。
- 选区拖框的坐标换算抽成 `useInnerDrag`，只提交 0..1 分数；对比页把 `erp360.js` 迁成 `Erp360Compare`，保留原着色器与时钟对齐。
- 并发写用 `X-Case-Revision` + `case-meta.json`，409 默认重新加载；占用锁只提示不阻断；任务记录扣费归属；默认入口切到 `/next/`，旧前端保留在 `/case/{name}`。
- 日志按任务收敛到 `logs/tasks/`，CLI 通过 `VRSTUDIO_CLI_LOG_PATH` 复用同一文件；pytest 用临时日志目录。

**排除的方案**

- 冲突时允许直接覆盖：需要字段级合并与二次确认，首期只提供重新加载。
- 用占用锁阻断写入：锁是安全网，真正的写冲突由 revision 检查负责；阻断会让浏览器崩溃后留下死锁。
- 让旧前端同时支持 revision：旧页面只保留回退能力，不再加新功能。

**验证**

`npm run lint`、`format:check`、`test`、`build` 全绿；`uv run pytest` 全绿、`ruff` 干净。浏览器在 walk_4k 上打开选区、抽取、首尾帧、合并与对比页，确认视口示意框、候选定稿、输出文件与对比页播放时间同步；500 MB 上传与双人并发仍待真实环境验收。

**涉及文件**

`vrstudio/frontend/src/views/wizard/`、`frontend/src/api/`、`frontend/src/composables/`、`frontend/src/legacy/Erp360Compare.ts`；`vrstudio/src/vrstudio/web/app.py`、`case_meta.py`、`locks.py`、`tasks.py`、`logging.py`、`proxy.py`；`docs/plan/frontend-workflow-and-skills.md`。

## 15. 2026-10-26 · 抽取页的完成刷新不再依赖“本页点过按钮”

**问题**

用户在 dacne 上跑完抽取（任务日志显示成功），抽取页仍把 `first_frame_raw.png` 与 `last_frame_raw.png` 标成“文件缺失”：

> E:\VRAIGC\vrstudio\logs\tasks\20261026\18da9d76b3de_extract_dacne.log 执行完毕以后，抽取界面还是显示 first_frame_raw.png 和 last_frame_raw.png ”文件缺失"。

**原因**

文件与指针都正确（API 复查五个文件 `exists=true`）。抽取 CLI 在最后一步才写 `extract.current` 指针（`cli/extract.py:190`），抽取运行的近三分钟里 API 一直指着旧版本目录，而旧目录没有首尾帧文件——期间加载的页面显示“缺失”是当时的事实。但完成后页面不自动刷新有两层原因：完成回调有 `if (!running.value) return` 守卫，`running` 只在本页点击“运行抽取”时置位，中途刷新或从别处发起的任务永远不触发刷新；且任务轮询 `start()` 只在点击运行/刷新时才启动，页面干等着根本没有数据源。

**决策**

- `running` 改为从任务列表推导（最近一条 extract 任务 queued/running 即进行中），另加提交瞬间的本地 `submitting` 防双击。
- 完成回调去掉 `running` 守卫：本页挂载之后创建的 extract 任务变 done 就 `fetchCase` 刷新；挂载之前完成的旧任务不触发（挂载时的 info 已是最新）。
- 挂载即 `start()` 轮询，卸载停止由 `useCaseTasks` 自理。

**排除的方案**

- 保留点击标志、只补轮询：任务从别的页面发起时刷新逻辑仍会被守卫挡掉。
- 轮询到 done 无条件刷新：挂载时旧任务会立刻触发一次多余请求，且和挂载时的 info 竞争。

**验证**

组件测试三例（外部任务完成触发刷新、挂载前旧任务不触发、running 随任务状态变化）；真浏览器在 `qa_patch_fix_1026` 上复现用户场景——页面开着不动、任务从 curl 发起，完成后页面自动换到新版本号且无“文件缺失”。门禁 56 用例全绿。

**涉及文件**

`vrstudio/frontend/src/views/wizard/ExtractStep.vue`、`frontend/tests/unit/extract-step.spec.ts`。

**后续入口**

KeyframeStep / MergeStep 的任务驱动刷新是同一模式（点击标志 + 手动 start），排查记录见 `../test-runs/20261026-user-feedback-fixes.md`；出现同类陈旧显示时按本条方式改。

## 16. 2026-10-26 · 选区页：删掉全景中心圆环，微调加速度滑块

**问题**

用户报告两处：

> 选区窗口-全景界面中央有一个圆形图案，不确定是不是bug。
> 选区页面的“按住持续微调（0.1°/0.1 秒）”我希望速度可以在页面上有个滑块实时修改。

**原因/决策**

- 圆环是 Vue 迁移时新加的 `.erp-cross`（14px 白色半透明圆环固定在 50%,50%），旧前端没有对应物，场景内容里也没有圆形物体（从代理视频抽帧核实过）。它不承载信息（选区位置由示意框表达），却被用户当成可疑图形——删除。
- 摇杆原来写死 0.1°/100ms（即 1°/秒）。改为摇杆只传方向（-1/0/1），步长 = 速度(°/秒) × 0.1s；页面滑块范围 0.2–5.0、步进 0.1、默认 1.0（与旧行为一致），实时生效并写入 `localStorage('vr.pickNudgeDegPerSec')`。

**排除的方案**

- 圆环改成悬停显示的十字准星：点击定位已有示意框与提示文案，再加准星是重复表达。
- 速度档位用下拉：实时调速要连续拖动，滑块才是对的控件。

**验证**

组件测试（滑块范围/默认值、2.5°/秒时每 tick 0.25°、localStorage 持久化、圆环不存在）；真浏览器键盘把滑块调到 3.0°/秒后按住 ↑ 半秒 pitch 0→1.8°（约 6 tick × 0.3°），localStorage 记住 3。

**涉及文件**

`vrstudio/frontend/src/views/wizard/PickStep.vue`、`frontend/tests/unit/pick-step.spec.ts`。

**后续入口**

若以后觉得 0.2°/秒仍太快（远焦视口），把下限降到 0.05 再说；不要为此加档位预设。

## 待决与未做

### 选区与对比页的播放卡顿（2026-10-26，等讨论）

用户报告选区和对比窗口播放都非常卡顿。排查事实：两页播放的都是代理视频，代理上限 `PROXY_MAX_W=4096`、帧率与源一致（dacne 为 4096×2048@60fps），对比页同时播两路；本机经远程桌面使用，若 Chrome 走软解（`chrome://gpu` 的 Video Decode 为 Software）则 4K60 必卡。候选方案：把代理宽度上限做成配置（`web.proxy_max_w`，默认不变，本机设 2048/2560 后按新尺寸重建代理）；或选区页与对比页用不同清晰度的两套代理（编码与存储翻倍，倾向不做）。fps 不能降——帧同步要求与源一致。等用户选定上限值与方案后实施。

### gen 的首尾帧入口

gen 没有 extract，需要「上传两张原始帧」的入口与存放位置。`keyframe.toml` 与状态结构已按两流程通用预留；接 gen 时只补上传与 `_keyframe_inputs` 的来源，不另造工作台。

### gen 的自动时长

gen 没有 clip，firstLastFrame 的“自动”仍回退到纯图片默认 4 秒。若 gen 将来也有可推导的参考时长（例如首尾帧来自一段有明确时长的视频），再按条目 8 的方式扩展；不要在没有依据时猜一个值。

### 图片与首尾帧的真实提交验收

图片多任务下载已经修好，真实四张候选也已补回；首尾帧视频的真实提交与合并仍受额度限制。首次真实提交后需要回填图片 URL 形状（R2）与 firstLastFrame 成片宽高（R7），这两个事实会影响后续页面的候选数量与尺寸提示。

### merge 日志的帧数警告

合并日志会打印「AI clip is N frames short」并按原始帧数比较 24fps 素材与 30fps 片段；实际重采样是时间感知的，成片末尾没有冻结，但日志会误导。下一步应改为按时间比较，或在重采样后重新计算缺口；目前只记录，不改逻辑。

### firstLastFrame 专用视频模板

`gen-multi.md` 的「素材与分工」段落提到参考视频与空间参考，firstLastFrame 只有两张图，这段对当前模式是噪声。是否单独做一个更短的视频模板，等精简稿在 10 秒下验证后再定；如果做，模板选择仍按 `(flow, mode)` 落在 `template_for`，不在前端分叉。
