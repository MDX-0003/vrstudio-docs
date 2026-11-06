# 前端关键问题与决策记录

本文记录 E:\VRAIGC 前端（web 模板、静态脚本、页面交互与客户端状态）的关键问题、已拍板决策、被排除的方案和最终解决办法。后端契约与算法决策仍在 `docs/case-model.md`、`docs/decisions.md` 与各自的计划文档里，本文只在它们影响前端交互时引用。

最后更新：2026-11-05。

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
- 2026-10-30 起改为槽位架构（决策 50）：四个变量扩展为 `target`、`source_first` / `source_last`、`figure`、`subject_last`、`pose_first` / `pose_last`、`preserve`、`cleanup`；「界面清理」改为可空的 `cleanup` 槽位，页面按模板占位符自动出六张卡。
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

## 17. 2026-10-26 · 预览代理宽度配置化（web.proxy_max_w）

**问题**

选区页与对比页播放卡顿（远端桌面软解环境），而抽取页 clip.mp4 的独立播放流畅——差异在解码量：clip 是 1080p 选区片段，两页播的是 4096×2048 的全景代理（对比页两路、且过 WebGL 画布）。用户认可该判断并要求：

> 我希望这个代理视频的播放比例是针对所有4k甚至更高分辨率的VR视频的，我们应该有办法解耦地调节这个参数。

**决策**

- 新增配置键 `web.proxy_max_w`（默认 4096，int，范围 [256, 8192]，校验进 `_validate`）：选区页的全景代理、对比页左右两路、`_browser_safe` 直连判定共用这一个值——解码能力是机器级属性，所有 4K+ 源统一缩放。
- `proxy.py` 每次调用现读配置（`proxy_max_w()`）：改 `vrstudio.toml` 即时生效，无需重启 serve。

  > **2026-10-28 修正**：这条已被决策 43 取消。上面「每次调用现读配置、改 `vrstudio.toml` 即时生效、无需重启 serve」不再成立；现在 `proxy_max_w()` 读进程启动时定格的 `config.active()`，改这个值要重启 serve 才生效。修正原因是配置数据热读、Python 代码不热更新，两者能错开：2026-10-27 18:14 旧进程用旧 `_validate` 读删掉 `web.default_frontend` 的新 `default.toml`，每个请求 500。侧车 `max_w` 的判定没有变，重启后旧代理仍按新宽度自动重建，所以「改完重启、代理自动重建」的结果与原来一致，只多一步重启。详见 `../test-runs/20261028-config-snapshot-and-log-dedup.md`。
- 侧车记录构建时的 `max_w`；ready/disabled 判定要求侧车 `max_w` 与当前配置一致，配置变更后旧代理自动失效、按需按新宽度重建（比 bump `PROXY_VERSION` 精确：只重建真正受影响的）。旧版侧车没有该字段，升级后首次访问会重建一次。
- 帧率不配置：代理与源帧数/帧率必须一致（选区页按帧号同步），`_encode_proxy` 有校验。
- 代理宽度暴露给页面：`/api/case` 的 `proxy.width`、outputs 的 `proxy_width`、`/api/case/<>/proxy` 响应的 `width`；对比页"4K 代理"硬编码文案改为跟随实际宽度（"2048 代理"）。

**排除的方案**

- bump `PROXY_VERSION` 强制全部重建：配置没变的机器也被迫重转一遍，浪费且慢。
- 选区页与对比页用两套不同清晰度的代理：编码与存储翻倍，且对比页两路才是大头。
- 降低帧率：帧同步要求帧数/帧率与源一致，动了滑块对不上帧号。
- 前端按设备自适应：解码能力无法可靠探测，且 serve 是单机单用户场景，配置项就是正确的解耦点。

**验证**

pytest 新增 5 用例（目标宽度跟随配置、侧车 max_w、配置变更失效、`_browser_safe` 跟随、成片代理同样判定、配置校验），全量 370 passed；真机验证：8763 运行中把 `vrstudio.toml` 的 `proxy_max_w` 从 4096 改 2048，旧代理 state 即时变 missing，POST 重建出 2048×1024 的新代理（见 `../test-runs/20261026-user-feedback-fixes.md`）。

**涉及文件**

`vrstudio/src/vrstudio/web/proxy.py`、`web/app.py`、`src/vrstudio/config.py`、`config/default.toml`；`frontend/src/views/wizard/CompareStep.vue`、`api/workflow.ts`、`types/case-info.ts`；`tests/test_web_proxy.py`。

**后续入口**

本机 `vrstudio.toml`（gitignore）已设 `proxy_max_w = 2048`；换本地有硬解的机器就删掉恢复 4096。若 2048 下对比页判断接缝仍不够细，先试 2560 再考虑对比页单独提清晰度。

## 18. 2026-10-27 · 素材库显示源视频，但仍不作为素材

**问题**

用户在 `case/CYQF_01`（fullredraw）新建时选了一份源视频，进入 case 的素材库页后看不到它：

> case/CYQF_01 里我选择了一份视频作为source，但是进去case页面后素材库里没有这个视频，这是符合设计预期的吗？

排查结论：符合当时的实现，但文档没有把 fullredraw 的理由写下来。`docs/case-model.md` 只写了「与 `[source]` 的哈希契约形成双重真源」，而这条只对 patch 成立（`[source] sha256` 在 merge 前校验；fullredraw 的 sha256 是可选的，pad 之后源不再被读）。`docs/multi-asset-plan.md` 的原话是「patch 与 fullredraw 保持现状」，属于当年的范围划分。源视频在 fullredraw 下只剩对比页 A 路可见，扩充画面步骤上完全看不到。

**决策**

- 数据模型不动：源视频仍只放 `[source]`，不写进 `[[assets]]`。素材库只列 `[[assets]]` 的规则也不动。
- 素材库在表格上方增加只读「流程文件」组：源视频来自 `info.source_file`，流程母版来自 `asset.source === 'flow'`（fullredraw 的 pad、patch 的 clip），可查名、查路径、打开原片；母版标出「已加入本次提交 / 未加入本次提交」。
- 前端不按 flow 名字分支：pad 与 clip 走同一条派生规则，pad 产物存在就显示，所以点完 pad 任务、页面拿到新 case info 后它自动出现，不需要在按钮回调里做特殊处理。
- 素材库为空时区分两种空态：没有任何素材文件（说明上方的流程文件不是素材、需要参考文件就上传）与筛选后为空。
- 「被引用」计数覆盖素材与流程文件，避免出现「母版已加入本次提交、被引用 0」这种自相矛盾的头部。
- `docs/case-model.md` 补一条设计说明，写清 patch 与 fullredraw 各自不进 `[[assets]]` 的理由。

**排除的方案**

- 把源视频写成一条 `[[assets]]`（`role = "edit_master"`），与 gen 完全统一：fullredraw 的生成母版是 `pad` 产物（候选 id `pad`、`role_fixed` 的 `edit_master`），并进素材库会出现两个 `edit_master` 视频，而提交几何由 manifest 决定，选中原件就是静默错片；`[[assets]]` 的语义是复制进 `cases/<name>/assets/`，把 2.4 GB 的 6K 原片按 case 复制一份没有收益；patch 还会与 `[source] sha256` 形成双重真源。
- 只在对比页或扩充画面页显示源视频：用户要在「素材库」这个统一文件入口找文件，分散到步骤页仍然要猜。
- 把 `pad`/`clip` 当普通素材列进表格（可删除、可改角色、可加进任何清单）：它们是流程产物，删除会破坏 manifest 与 mask 的配对，角色也是固定的；所以只放在只读的「流程文件」组里，主表格仍只列 `[[assets]]`。
- 在 pad 按钮的完成回调里写「如果是 fullredraw 就把 pad 加进素材库」：显示不需要事件，pad 产物存在就是事实，按 `source === 'flow'` 派生即可；把显示做成按钮副作用会让刷新、直接打开链接、CLI 跑过 pad 这些路径都不一致。

**验证**

单测四条（`case-library-view.spec.ts`）：源视频渲染为只读流程文件且不占素材表格；流程母版显示「已加入本次提交」并计入被引用；未选中的母版显示「未加入本次提交」；空素材库给出带流程文件说明的空态。前端 95 条全绿，`typecheck` 与 `lint` 干净。浏览器实测两处：`CYQF_01`（只有源视频，头部「流程文件 1 · 被引用 0」）与 `walk_01`（源视频 + `seedance_input.mp4` 母版 + 「已加入本次提交」，头部「流程文件 2 · 被引用 1」），截图 `../test-runs/20261027-library-source-video/cyqf01-library-source-only.png` 与 `walk01-library-source-and-pad.png`。

**涉及文件**

`vrstudio/frontend/src/views/case/CaseLibraryView.vue`、`frontend/tests/unit/case-library-view.spec.ts`；`docs/case-model.md`。

**后续入口**

若以后真要让源视频参与生成（例如直接把原片作为可选参考），必须先解决两个 `edit_master` 与 manifest 几何的冲突，再谈并进 `[[assets]]`；不要只改展示。gen 没有流程段也没有母版，源视频就是第一条素材，这条差异不要为了「看起来统一」抹平。

## 19. 2026-10-27 · 旧版控制台整体退役

**问题**

设置页仍有「旧版入口 / 打开旧版控制台」；用户确认今后只维护 Vue 这一版前端，询问旧版后端是否还有真实接口。核对结果：入口指向 `/`，默认配置下 `index()` 直接 307 到 `/next/`，点开只是第二个新前端；但旧版后端仍完整存在——`templates/` 8 个模板、`static/` 10 个旧脚本、`GET /case/{name}` 渲染 `wizard.html`，还有三个为旧版保留的 API 兼容点。

**决策**

整体退役（决策 42）：删除设置页入口、模板与旧静态、`wizard` 路由与 `web.default_frontend` 配置；`/` 固定 307 到 `/next/`，`/case/{name}` 改为 307 到 `/next/case/{name}`，旧书签不 404。同批删除 `keyframe.sheet`/`sheet_candidates` 派生字段、`GET/PUT /api/case/{name}/keyframe/sheet`、`set_asset_role` 对 `[submit.roles]` 的同步。`/api/*`、`/img/{name}/vp.png`（新前端 `PickStep` 在用）、`/file`、`/video/*` 保留。

**排除方案**

只删设置页那两行、保留旧版后端：旧版入口消失后仍可通过 `/case/{name}` 进入旧页面，兼容层还得继续维护，与“只维护一版”矛盾。保留 `/static` 挂载与 Jinja2 依赖：删除旧脚本后没有任何调用方，属于死装配。

**验证**

pytest 332 条全绿（需在无本地 `vrstudio.toml` 的目录跑，见下）；ruff 干净；前端 build、typecheck 与 vitest 95 条全绿。新增 `test_legacy_case_url_redirects_to_next`；旧版页面渲染测试与 `test_set_asset_role_syncs_selected_role` 删除，`sheet` 相关断言改读 `refs`。详细记录见 `docs/test-runs/20261027-legacy-console-retirement.md`。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py`、`case.py`、`config.py`、`config/default.toml`、`pyproject.toml`；`frontend/src/views/SettingsView.vue`、`frontend/src/api/keyframe.ts`、`frontend/src/types/case-info.ts`、`frontend/src/views/wizard/KeyframeStep.vue`；`tests/test_web_console.py`、`tests/test_casemodel.py`、`tests/test_web_media_cache.py`。

**环境注意**

本机 `vrstudio.toml` 设了 `web.proxy_max_w = 2048`，在仓库根跑 pytest 会让 9 条代理测试按 4096 默认值失败；在无本地配置的目录执行 `pytest E:\VRAIGC\vrstudio\tests` 可复现基线全绿。这与本次改动无关。

## 20. 2026-10-30 · 选用成片改为按轮次逐行选用

**问题**

生成页只有一个「选用成片」按钮，固定采用最新一个可用轮次（`latestUsableRound`），按钮不带轮次参数；一旦最新可用轮次就是已采用轮次，按钮禁用并提示「当前成片已是采用结果」，想换回旧一轮在页面上没有任何入口。dance_move 上用户连生两轮后，把成片文件名里的抽段时间戳（`20261030-120614`）误读成「第一次生成」，又因为合并产物早于第二次采用、面板仍播旧画面，得出「选用只对第一次生效」的结论——实际上第二次采用已成功（`extracts/<抽段>/result.mp4` 与第二轮结果哈希一致），只是没重新合并。后端契约本就支持按轮采用：op=adopt 透传 `body.round`（`app.py` 的 `_op_argv`），CLI `generate adopt --round`；缺的只是前端入口。

**决策**

选用动作下沉到「生成记录」每一行：可用轮次（`result=yes`）行内放「选用」按钮，点击以 `round_dir` 调 adopt；当前采用轮次显示「已采用」标签、不显示按钮；任一采用进行中时所有选用按钮禁用。「最近成片」面板变纯展示，只显示当前采用轮次名（无则「尚未采用任何轮次」），不放按钮、不做「成片落后于采用」之类的判断——采用的不是最新轮次不是需要修复的问题，只说清必要信息。轮次行同时展示轮次目录名（如 `gen-multi-c205667f`），让面板里的「当前采用轮次：…」能对到具体行，抽段时间戳与轮次名两套标识不再混用。顺带删除 `recentOutput` 里 `version === adopted` 的死匹配：version 是抽段时间戳（非 patch 流为 undefined），adopt_round 是轮次名，永远不匹配，实际一直走「取最后一个成片」的兜底。

**排除方案**

保留单按钮改成「采用最新并合并」：点击少，但选不了旧轮，不满足逐轮独立选用。按钮原地弹轮次选择器：多一跳弹窗，轮次列表就在同页，不划算。

**验证**

vitest 107 条全绿（generate-results 新增：逐行选用携带轮次载荷、已采用轮次显示标签不出按钮、无可用结果的轮次不出按钮、采用进行中互斥禁用、未采用提示；generate-step 新增：点击行内选用以 `round_dir` 调 `runOperation`、已采用轮次标记）。typecheck、eslint、pytest、ruff 全绿。真实数据核对：dance_move 第二次采用（14:38）后指针与 `extracts/20261030-120614/result.mp4` 哈希均指向第二轮。

**涉及文件**

`vrstudio/frontend/src/components/generate/GenerateResults.vue`、`frontend/src/views/wizard/GenerateStep.vue`、`frontend/tests/unit/generate-results.spec.ts`、`frontend/tests/unit/generate-step.spec.ts`。

## 21. 2026-10-30 · typecheck 脚本空转：vue-tsc --noEmit 在 solution 式 tsconfig 下不检查任何文件

**问题**

条目 20 提交后用户跑 `npm run build`（`vue-tsc -b && vite build`）报出 TS2322：`adoptedRoundName` 的 `split().pop()` 返回 `string | undefined`，与 `GenerateResults` prop 声明的 `string` 不符——这是条目 20 引入的类型错误，提交门禁却没拦住。原因：`frontend/package.json` 的 `typecheck` 脚本是 `vue-tsc --noEmit`，而 `tsconfig.json` 是 solution 式配置（`files: []`，只挂 `tsconfig.app.json` 与 `tsconfig.node.json` 两个 references）；不带 `-b` 时 vue-tsc 没有任何输入文件，静默退出 0。核对 git 历史：这个写法从 Phase 0 前端脚手架（`5f22c6a`）起就是这样，此前所有报告「typecheck 全绿」的提交，实际只被 vitest 与 eslint 检查过。

**决策**

`typecheck` 脚本改为 `vue-tsc -b`：跟随 references 真检查，与 build 的第一步完全一致；被引用的 tsconfig 均为 `noEmit`，不落盘产物。同时给 `adoptedRoundName` 补 `?? ''` 兜底，修掉 TS2322 本身。

**教训（门禁层）**

「某条命令退出 0」不等于「它检查了东西」：solution 式 tsconfig 加无 `-b` 是静默空转的典型形态，门禁里的每个检查命令要么能证明它真的在查，要么删掉。本次暴露的另一个缺口是门禁顺序：提交前跑了 vitest、eslint 与（假绿的）typecheck，唯独没跑 build，而 `vue-tsc -b` 只有 build 才执行；typecheck 修复后两者等价，缺口随之补上。

**验证**

`npm run typecheck`（修复后）、`npm run build`、vitest 107 条、eslint 全绿；build 产物目录 `src/vrstudio/web/static/next/` 不受 git 跟踪，工作区干净。

**涉及文件**

`vrstudio/frontend/package.json`（typecheck 脚本）、`frontend/src/views/wizard/GenerateStep.vue`（类型兜底）；对应提交 `b833954` 与 `bb50380`。

## 22. 2026-10-30 · 生成页换模型后输出档位不刷新（Seedance 2.0 看不到 4K）

**问题**

在生成页把视频模型切到 Seedance 2.0 后，输出分辨率下拉仍然只有 480p/720p/1080p，选不到 4K；刷新页面后 4K 出现。服务端是实时的：`params show` 读 `generation.toml` 里保存的模型，再按该模型当前模式的 `resolutions` 过滤档位（`vrgen/src/vrgen/cli.py:844-845`、`vrgen/src/vrgen/prep/params.py:68-81`）。实测 `GET /api/case/dance_walk_01` 返回 `video_model_id=22` 且 `output` 含 4K，新标签页打开同一 URL 下拉也有 4K，说明模型切换本身已写入、服务端已按新模型重算。

根因在前端保存时序：保存回调只把返回的 `generation_params` 写进 `generationParams`，没有更新 `resolutionOptions` 等清单，然后 `emit('updated')`；父组件回传后 `applyInfo` 先算 `paramsDirty = paramsSaveQueue.has(caseName)`，而保存队列是先 `await save(entry)`、后 `pending.delete(id)`（`frontend/src/composables/useCaseSaveQueue.ts:57-61`），`emit` 发生在保存返回之前，条目仍在队列里，`has()` 为真，整个参数块被跳过，之后没有第二次应用。结果是模型 id 与 `generation.toml` 都更新了，下拉却停在上一个模型的档位列表。同类后果：从支持 1080p 的模型切到只支持 480p/720p 的模型时，`resolution` 会保留无效值，提交时才被平台退回。

**决策**

把档位与模型清单的整组赋值抽成 `applyParamsLists(params)`，整页刷新（`applyInfo`）与两条保存路径（防抖队列回调、提交前 `persistParams`）都调用它：保存返回的就是新模型的结果，直接生效，不等下一次刷新。另加 `watch(resolutionOptions)`：当前 `resolution` 不在新清单里就回落到第一档，避免把该模型不支持的档位留在下拉里再发出去。`paramsDirty` 守卫保留，它防的是「未保存的本地选择被服务端旧值覆盖」，不适用于一次已经完成的保存。

**排除方案**

把队列改成先删条目再回调：能绕过本次现象，但 `applyInfo` 仍只在非脏状态下更新清单，其他路径（并发刷新、提示词保存回传）还会再踩；改队列表义也会影响提示词保存。只在前端给 4K 加一条补丁：等于把档位规则复制到前端，违反「档位以模型清单为准」的唯一权威点。要求用户切模型后手动刷新：把机制问题留给使用者。

**验证**

`npm run typecheck`（`vue-tsc -b`）、`npm run lint`、vitest 117 条全绿；`generate-step.spec.ts` 新增两条：保存返回后 `resolutionOptions` 立即变成 480p/720p/1080p/4K；新模型只支持 480p/720p 时 `resolution` 回落到 480p。pytest 全绿。ruff 对仓库根目录 3 个未跟踪的 `.tmp_*.py` 诊断脚本报错，与本次改动无关。线上证据：`GET /api/case/dance_walk_01` 的 `generation_params.output` 含 4K；新标签页打开生成页下拉含 4K，页内切换后才缺失。

**涉及文件**

`vrstudio/frontend/src/views/wizard/GenerateStep.vue`（`applyParamsLists`、两条保存路径、`watch(resolutionOptions)`）、`frontend/tests/unit/generate-step.spec.ts`。

## 23. 2026-11-02 · case 列表筛不到新流程；case 增加删除入口

**问题**

Case 列表的流程筛选是 5 条手写 `<el-option>`（`CaseListView.vue:215-222`），不含 `relight`；而 `flowMeta` 与 `Flow` 联合类型早已有该流程，表格 tag 显示正常。结果是 relight 的 case 只能看不能筛。同期 case 级没有任何删除能力：`/api/case/{name}` 只支持 GET，CLI 的 `case` 子命令也只有新建与查看。

**决策**

筛选选项改为遍历 `flowMeta` 生成的 `flowOptions`，与 tag 共用同一份词表；今后加流程只改 `constants/flow.ts`，漏改 `Flow` 会由 typecheck 拦下。删除新增 `DELETE /api/case/{name}`，清 `cases/<name>/` 与 `vrgen_runs/<name>/` 两棵目录，`sources/` 与 `logs/` 不动；前端在行尾「打开」旁放「删除」，`ElMessageBox.confirm` 普通确认，任务运行中/排队时按钮置灰。后端两道闸门：case 被他人持锁（心跳有效）或该 case 有运行中/排队任务时返回 409。`case_mod.delete` 先直接删除，Windows 句柄占用时改名进 `cases/.trash/` 再删，仍删不动则报残留路径。

**排除方案**

筛选只补一条 relight：下一次新增流程还会漏，且选项与 tag 继续两处维护。删除只清 `cases/<name>/`：`vrgen_runs/<name>/` 残留会让同名重建读到旧轮次，也继续占盘。输入 case 名二次确认：用户当次选择普通确认弹窗即可，不额外加交互。只允许负责人删除：当前没有管理员角色，负责人为 demo 的历史 case 其他人会删不掉。

**验证**

`tests/test_web_case_delete.py` 5 条（两棵目录清空、缺 case 404、他人持锁 409、任务在跑 409、rmtree 失败后改名重试仍删净）；`case-list-view.spec.ts` 2 条（选项覆盖 `flowMeta`、删除走确认并刷新列表）。typecheck、vitest、pytest、ruff 全绿。

**涉及文件**

`vrstudio/src/vrstudio/case.py`、`vrstudio/src/vrstudio/web/app.py`、`vrstudio/src/vrstudio/web/tasks.py`、`vrstudio/frontend/src/constants/flow.ts`、`vrstudio/frontend/src/views/CaseListView.vue`、`vrstudio/frontend/src/api/cases.ts`、`vrstudio/tests/test_web_case_delete.py`、`vrstudio/frontend/tests/unit/case-list-view.spec.ts`。

## 24. 2026-11-02 · 图片流程生成页缺任务日志与状态回显，候选只认 mtime 最新一轮

**问题**

relight_01 提交成功后，生成页只看到候选缩略图与「已采用」标签，没有进程日志，也没有「已生成」的状态。

- 图片流程不渲染 `GenerateResults`（`GenerateStep.vue` 的 `v-else` 只给视频流程），它里面的「最近任务」与「技术详情」不会出现在图片面板；`ImageGeneratePanel` 只有一行 `status/statusDetail`，日志文件写了也没入口看。
- 页面加载后状态固定回「未预演」：`status` 是组件内 `ref`，只在本次页面点过预演/提交才更新，刷新页面或重启 serve 后不从轮次台账反推，已经出了成片仍显示未预演。
- 候选按目录 mtime 取 `rounds[0]`（后端 `app.py` 的 `_image_rounds` 按 `st_mtime` 倒序，前端 `latestImageRound` 直接取第一条）。本次先建的空 prepared 轮次 `img-59e3901c` 只因 mtime 更旧才没遮住 `img-556ed938`；一旦空轮次更新，候选区就是「还没有候选图」。
- 已采用轮次只剩「已采用」标签，没有查看大图、去拼接、去对比的入口，采用后用户不知道下一步在哪。
- 任务历史全在内存（`web/tasks.py` 的 `current/pending/history`），serve 一重启任务中心与生成页都拿不到日志。

**决策**

1. 把 `GenerateResults` 的任务块抽成共用组件 `components/common/TaskPanel.vue`：props 为 `task`、可选 `title`、`emptyText`，行为保持原样（kind+状态 tag、摘要、失败 alert、技术详情折叠、tail pre）。`GenerateResults` 与 `ImageGeneratePanel` 都用它，图片流程在候选面板之后渲染。
2. 状态以台账为准：图片流程有本地运行态时用本地状态，否则按 `image_rounds` 里最新有结果的轮次反推（有结果 = 已完成，`stage=failed` = 失败，只有 prepared = 仅预演）；「未预演」只在没有任何轮次时出现。视频流程的状态回显不动，避免把视频预演语义混进来。
3. 候选改用「最新有结果的轮次」而不是纯 mtime 最新（`utils/rounds.ts` 新增 `latestResultRound`）；已采用轮次在候选面板底部常驻一行「当前采用 + 查看大图 + 去拼接 + 去对比」，查看走 `/img/round/<case>/<round>/<index>`，去拼接/去对比走步骤路由。
4. 任务历史落盘：任务结束时向 `logs/tasks/<day>/tasks.jsonl` 追加 `view()` 记录，`TaskQueue` 启动时回填最近 50 条；只回填有日志文件的 finished 任务，running/queued 不复活。

**排除方案**

- 只给图片面板复制一份任务块：tail 渲染与失败行处理会有两份，下一次改文案或加字段要改两处，违背共用优先。
- 把状态写进 `generation.toml`：状态是轮次台账的推导值，落盘会多出第二个真源，轮次被删或覆盖后对不上。
- 候选继续按 mtime：空 prepared 轮次会遮住真实结果，且 mtime 依赖结果写盘时序，不稳定。
- 已采用轮次只在缩略图上保留链接：拼接与对比是流程的下一步，行内不给入口用户还得自己找步骤。

**验证**

vitest：`rounds.spec.ts` 补 `latestResultRound`、`adoptedImageRound`、`imageRoundStatus`；`image-generate.spec.ts` 补状态反推（显示已完成、不出现未预演）、空 prepared 轮次不遮住结果、已采用行的查看大图/去拼接/去对比、最近任务与日志尾巴；`generate-step.spec.ts` 原有用例保持。前端 127 条 vitest、typecheck、lint、build 全绿；`tests/test_web_console.py` 新增 `test_task_history_survives_restart`（落盘后重建队列仍能列出 done 任务与 tail，日志被删后不再回填），pytest 与 ruff 全绿。浏览器实测 `/next/case/relight_01/generate`：状态显示「已完成」、候选为 `img-556ed938 · gate=ok`、已采用行有「查看大图 / 去拼接 / 去对比」，点两个按钮分别跳到 `/merge` 与 `/compare`；「最近任务」面板已在图片页出现（该 case 的历史早于本功能，显示空提示）。

**涉及文件**

`vrstudio/frontend/src/components/common/TaskPanel.vue`、`frontend/src/components/generate/GenerateResults.vue`、`frontend/src/components/generate/ImageGeneratePanel.vue`、`frontend/src/views/wizard/GenerateStep.vue`、`frontend/src/utils/rounds.ts`、`vrstudio/src/vrstudio/web/tasks.py`、`frontend/tests/unit/*.spec.ts`。

## 25. 2026-11-02 · 图片对比页与视频不同构，成片不能打开或下载

**问题**

patchimg / fullRedrawImg 的对比页是两套实现里唯一没和视频对齐的一处，浏览器实测（relight_01 的 `/compare`）：

- 页面只有两个 `<img>`（左 `light_source.png` 8192×4096、右 `out/<版本>_image.png` 8192×4096），全页没有指向 `/file` 的链接，也没有「打开」「下载」按钮。
- 图片分支是两个可滚动面板、图片按 `width: zoom%` 缩放、同步方式是抄 `scrollLeft/scrollTop`（`CompareStep.vue` 的 `.image-pane` 与 `syncPaneScroll`）。没有缩放滑杆以外的视角控制，没有分割线，也没有 ERP→透视投影，所以既不是「两侧共用一个窗口」，也不是 360 环绕。
- 后端 `/file` 固定 `content_disposition_type="inline"`（`app.py` 的 `file_open`），前端全仓没有任何 download 元素；视频能下载靠的是浏览器原生 video 控件，不是流程能力。
- 图片成片按 `sorted(odir.glob("*.png"))` 升序下发（`_outputs`），对比页又取 `outputs[0]`，显示的是最旧一份；图片分支没有成片下拉。

原因：`CompareStep` 的图片分支是 WP6 为「先能看」单独写的静态并排，而 `Erp360Compare` 从构造到纹理上传都写死视频元素（`[HTMLVideoElement, HTMLVideoElement]`、`videoWidth/readyState/currentTime`），当时没有抽象纹理来源，图片这条线就没有接进查看器。

**决策**

1. `Erp360Compare` 的纹理来源抽象为 `ErpSource = HTMLVideoElement | HTMLImageElement`：视频仍按 `currentSrc:currentTime` 去重；图片按 `complete/naturalWidth` 判断，`src` 不变就只上传一次。投影、分割线、拖拽与滚轮逻辑一行不改。
2. 纹理尺寸兜底：上传前比对 `MAX_TEXTURE_SIZE`，超限的源（9558 宽的 padded 画布在 8192 上限的 GPU 上必然超限）按比例降采样到离屏 canvas 再上传，避免整块黑屏。
3. 图片对比页与视频共用同一个 stage：一块 canvas、分割线拖动、拖动转头、滚轮变焦、视角复位、全屏；删除 2D 并排滚动、缩放滑杆与差异高亮（用户决定不做）。
4. 成片选择与视频一致：右路默认最新一份，下拉可切换；图片底版的 relight 仍用 `relight.current`。
5. 打开与下载：右路放「打开原图」（新标签）与「下载」；后端 `/file` 增加 `download=1` → `Content-Disposition: attachment`，前端下载链接带该参数并加 `download` 属性（同源）。

**排除方案**

- 保留 2D 并排只补按钮：两套对比逻辑永久并存，正是本次要消除的不一致。
- 只加一个 360 预览抽屉：看得到但对比仍不在同一视角，问题没解。
- 前端各写一份下载逻辑：没有服务端 attachment 兜底，且大图在各浏览器的行为不一致。
- 直接把原始 8K 图当纹理上传：超过 `MAX_TEXTURE_SIZE` 时纹理创建失败，画面整块黑。

**验证**

vitest 新增 `compare-step.spec.ts` 4 条：只渲染一块 canvas 与分割线（`.image-pane` 为 0）、右路默认最新成片并把两张图交给查看器、切换下拉后重建查看器、打开/下载链接（下载带 `download=1` 与 `download` 属性）；前端 131 条全绿，typecheck、lint、build 全绿。pytest 在 `test_file_route_serves_each_whitelist_root` 补 `download=1` → `attachment; filename="clip_mask.png"`，不带参数仍是 inline；vrstudio 全量 pytest 与 ruff 全绿。浏览器实测 relight_01 对比页：`.compare-canvas` 1600×720、WebGL 可用，拖拽后视角转动、滚轮后视场收窄，左右两半同属一个 camera；`curl` 复核两种 Content-Disposition 与预期一致。

**涉及文件**

`vrstudio/frontend/src/legacy/Erp360Compare.ts`、`frontend/src/views/wizard/CompareStep.vue`、`frontend/tests/unit/compare-step.spec.ts`、`vrstudio/src/vrstudio/web/app.py`、`vrstudio/tests/test_web_console.py`。

## 26. 2026-11-03 · relight 对比页右路被 out/ 散件带偏，新成片不实时

**问题**

用户报（原话）：

> http://127.0.0.1:8760/next/case/relight_web_01/relight 审查一下为什么最新生成的打光结果在对比页里没有实时展示？

浏览器实测 relight_web_01 的 `/compare`：右路 videoB 实际播放 `out/relight-tset-结果视频.mp4`——10 月底手工拷进 out/ 的测试视频（文件名还带着 tset 拼写错误），而不是当天 11:00 刚出的 `20261103-103409_relit.mp4`；两路都是 8192×4096、readyState 4，页面不报任何错，安静地放旧片。根因四环叠加：

1. out/ 混入两个非产物文件（`relight-test-原始视频.mp4`、`relight-tset-结果视频.mp4`）；
2. 后端 `_outputs` 对 relight 收 out/ 下全部 `.mp4/.png` 按文件名排序：数字开头的时间戳产物排前，`relight-*` 排最后；
3. 对比页默认选中 `rows[rows.length - 1]`，正中散件；relight 视频底版没有「右路成片」下拉（下拉只给 `isStill && !isRelight` 渲染），想手动切都没有入口；`[relight] current` 钉针只有图片底版路径（`imageOutput`）消费，视频路径不读；
4. 停在对比页没有任何刷新机制：`WizardView` 只在挂载与切 case 时拉数据，切步骤不重拉；打光页「任务完成 → 刷新」的 watcher 依赖组件内 `running` 状态，切到对比页组件已卸载、切回时状态重置直接 return。刷新浏览器也无效——选中仍被散件带偏。

**决策**

1. 右路默认选中收敛为 `defaultSelection(rows)`：relight 跟随 `[relight] current`（后端 `_relight_current` 已兜底——钉针优先，否则 out/ 按 mtime 取最新，mtime 不受文件名排序影响）；其余流程仍取列表最后一项。
2. current 指针变化即切右路（新 watch）；手动选中的旧版本在下一次成片落盘前保持。
3. 「右路成片」下拉放开给 relight（条件 `isStill || isRelight`）；图片底版与视频共用同一 `selected` 机制，删除 `imageOutput` 特例。
4. 对比页接入 `useCaseTasks(['relight'])`（复用打光页同一条轮询机制）：任务完成且「挂载后新建、或挂载期间见过它运行」时向父级发一次 `updated`，`WizardView` 重新拉 case；挂载前就完成的存量任务不触发；按任务 id 去重，拉取失败下轮重试。
5. 数据卫生：两个散件移到 `cases/relight_web_01/manual/`，out/ 只放流程产物；`relight-test.zip` 不在成片过滤器（`.mp4/.png`）内，留原处。

**排除的方案**

- 只删散件不改代码：机制坑还在，任何不带时间戳前缀的文件落进 out/ 都会再次带偏默认值；机制问题用机制修。
- 前端按 `_relit` 后缀过滤 outputs：把产物命名规则抄进第二处，违背唯一权威点；后端列表语义不动。
- 对比页自己写一套任务轮询：与 FR-16「全站只留 useCaseTasks 一套轮询」的方向相反。
- 让后端在任务完成时写回 `[relight] current`：`_relight_current` 的注释已说明产物名自带时间戳、按 mtime 兜底即可，为它加任务完成回调是长期成本换短期便利。

**验证**

- vitest `compare-step.spec.ts` 从 4 条加到 9 条：relight 默认右路 = current（不是字母序靠后的散件）、relight 出现下拉且切换会换右路、case 刷新后跟随新 current、任务 running → done 触发一次 `updated`（`fetchCase` 以 case 名调用、载荷透传）、挂载前已完成的任务不触发。全仓 26 个测试文件 146 条用例全绿。
- `npm run typecheck`、`lint`、`build` 通过；`format:check` 全仓 34 个文件存量漂移（HEAD 未改动文件同样不过，`endOfLine: auto` 与仓库既有混合换行符冲突），本轮新代码与相邻文件同风格，存量不处理。`uv run pytest` 全绿、`uv run ruff check .` 通过。
- 浏览器实测 relight_web_01 对比页：刷新后右路 = `20261103-103409_relit.mp4`、下拉三项全是真产物；手动切 `20261102-105534_relit.mp4` 右路换旧片、再切回 `20261103` 生效。任务完成刷新由单测覆盖（真实触发需一次 8K 整段重打光渲染，未消耗额度）。

**涉及文件**

`vrstudio/frontend/src/views/wizard/CompareStep.vue`、`vrstudio/frontend/src/views/WizardView.vue`、`vrstudio/frontend/tests/unit/compare-step.spec.ts`、`vrstudio/cases/relight_web_01/out/` 与 `manual/`（数据移动，不进 git）。

**后续入口**

- out/ 只放流程产物目前靠约定维持；若散件再次混入，考虑后端 `_outputs` 对 relight 收紧命名（如必须 `*_relit.*`），动命名规则先立项。
- patch / fullredraw 的视频对比页没有下拉是历史行为，本次只放开 relight；其余流程要切换入口时复用同一 `selected` 机制即可。

## 27. 2026-11-04 · case 列表卡顿与多种排序

**问题**

> 每次我打开case列表都会经历较长时间的卡顿，我想知道是什么原因导致的？有什么解决方法？另外case列表我也需要支持多种排序方式，目前是什么排序方式？

**原因**

`/api/cases` 对每个 case 调 `_brief`，而 `_brief` 直接复用了向导的完整门控 `_gates`。patch 流程为了算 `generate` 门会调 `_keyframe_state` → `_asset_details`，这条链对每个素材做两件列表页不需要的事：`candidates()` 里的 `check_assets()` 逐个算 SHA-256，`_media_meta()` 逐个把整张图解码取宽高。`walk_4k` 有 28 张 5–6 MB 的 4K 候选图，单张解码约 85 ms，一次请求约 2.4 秒；`dance_move` 10 张图约 0.84 秒。另外 `_outputs(case)` 在一次 `_brief` 里被算了两遍（`_gates` 内一次、返回 `outputs` 计数一次），patch 的 `_space` 成片还要打开 8K 源片读帧数（约 0.16 秒/次，无缓存）。所有 case 串行处理，每次进入列表页都从头重算。

实测本机 26 个 case：冷进程合计约 4.0 秒，热进程仍有 1.3–2.0 秒。

**决策**

- 列表页走轻量路径：`_gates(..., list_only=True)` 不算首尾帧工作台状态（`nextStepForFlow` 的 patch 分支也不读 `keyframe` 门），`_brief` 不调 `_asset_details`，因此不解码图片、不哈希素材。
- 成片只算一次：新增 `_output_files` 统一选择规则并返回 `(路径, patch 版本, 是否 space-only)`；列表只取文件名与数量，详情页 `_outputs` 再补文件信息、代理状态与 `partial`。
- 「最近活动」改为真实活动：取 `case.toml`、`keyframe.toml`、`extracts/`、`out/` 直接子文件、`vrgen_runs/<case>/*/run.json` 的最大 mtime，接口新增 `updated_ts`（epoch 秒）供排序；显示格式仍是 `YYYY-MM-DD HH:MM`。
- 默认排序改为「最近活动」倒序，后端先排好序再返回；前端支持按最近活动 / 名称 / 负责人 / 流程 / 成片数排序，并可选升序或降序，全部在前端本地完成，不改后端分支。主键同值时固定按名称升序，升降序只作用于主键，避免倒序时 tie-break 也跟着反向。

**排除的方案**

- 给 `_media_meta` 与 sha256 加缓存：能缓解冷启动后的重复开销，但列表根本不需要这些值，先把调用去掉比加缓存更彻底；详情页要用时再用现有 `_media_meta` 的 lru。
- 列表分页：26 个 case 轻量化后一次请求 35–46 ms，分页只会增加接口与前端状态，收益为零。
- 「最近活动」只取 `case.toml` mtime：跑抽取、定稿首尾帧、合并出片都不一定写 case.toml，排序会明显偏旧，不满足用户按活动找 case 的用法。
- 后端按每种排序各出一个分支：排序是展示层偏好，数据量小，前端一次拿到全部行本地排序最简单。

**验证**

- 同一份 26 个 case 的实测：`_brief` 冷进程合计从约 4.0 秒降到 31.5 ms 以内（单 case 最慢 2.6 ms）；`/api/cases` 端到端 35–46 ms、24 KB 响应。
- 新增 `test_cases_list_does_not_decode_or_hash_assets`：把 `_media_meta` 与 `check_assets` 钉成一旦调用就失败，`GET /api/cases` 仍返回 200，锁住轻量路径。
- 新增 `test_cases_list_sorts_by_last_activity_desc`：两轮 case 的 case.toml 都改旧、其中一轮的成片改新，断言列表按成片时间排序且 `updated_ts` 更大。
- `uv run pytest` 全绿（含新增两条）、`uv run ruff check .` 通过；前端 `npm run typecheck`、`lint`、`build` 通过，vitest 26 个文件 146 条用例全绿。
- 未做真实浏览器点击计时：排序控件在列表页 toolbar，交互与筛选下拉同构，由类型检查与现有挂载测试覆盖。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py` 的 `_output_files` / `_outputs` / `_gates` / `_brief` / `_last_activity` / `api_cases`、`vrstudio/tests/test_web_console.py`、`vrstudio/frontend/src/views/CaseListView.vue`、`vrstudio/frontend/src/types/case.ts`。

**后续入口**

- 列表页再要新字段时先问「是不是详情页的东西」：`_asset_details`、`_media_meta`、哈希校验都属于详情页，不要加回 `_brief`。
- 「最近活动」的口径集中在 `_last_activity` 一处；新增会改变 case 状态的文件类型时在那里补路径，不要在别处再算一遍。
- 排序键集中在 `CaseListView.vue` 的 `primaryCompare` 与 `SORT_OPTIONS`；新增键只改这两处，主键同值按名称升序兜底。

## 28. 2026-11-04 · 视频对比页补右路成片下拉，成片列表按产物来源与时间收敛

**问题**

> 视频的 video fullredraw 流程里，即使生成了多份视频，最终对比页里也只能选一份结果视频放在右边。哪些流程实现了可以选「多份结果视频」的下拉框？这个功能有必要在所有对比页里复用。

**原因**

五个带「对比」步的流程共用同一个 `CompareStep.vue`，下拉框只有一个，渲染条件是 `isStill || isRelight`。于是 patchimg、fullRedrawImg、relight 有下拉，patch 与 fullredraw 没有，右路固定取 `outputs` 最后一项。最初迁移的对比页（`e7947c9`）下拉是无条件的；`76e473d` 改 360 单窗口查看器时收成 `isStill && !isRelight`，视频流程被一起关掉；`025eb5b` 放开给 relight 后仍把 patch/fullredraw 留在外面（条目 26 的「后续入口」）。

放开下拉还暴露两个既存问题。第一，fullredraw 的 `_output_files` 直接取 `out/*.mp4`，`out/` 里混进的散件也会被当成成片。第二，默认选中取 `outputs` 最后一项，前提是列表按文件名升序等于时间升序；fullredraw 的成片名是轮次哈希（如 `360-closure-4c9b4b42.mp4`），字母序与 mtime 并不一致，真实 case `ship_01` 的字母序最后一项反而是 10 月 19 日最旧的一份。

**决策**

- 「右路成片」下拉对所有流程渲染：`CompareStep.vue` 去掉 `isStill || isRelight` 条件，patch/fullredraw 复用同一套 `selectedFile` / 代理重置机制。
- 成片只认流程自己写出的产物，`out/` 散件不展示：patch 继续用 `<版本>_space.mp4` / `<版本>_frame.mp4` 命名链（frame 优先）；fullredraw 只收旁边有 recompose 报告 `<轮次>_recompose.json` 的 mp4；gen 的采用结果在 `case/result.mp4`，`out/` 直接返回空。
- `_output_files` 统一按 mtime 升序、文件名兜底返回，对比页的「最后一项即最新」对哈希命名的轮次同样成立。

**排除的方案**

- 把下拉抽成独立组件：所有流程本来就共用一个 `CompareStep`，当前只有一个消费者；抽出组件不减少重复，只增加一层 props/事件。等生成页「最近成片」或合并页成片列表也要切换时再抽。
- 按文件名排序并取最后一项：fullredraw 的轮次名是哈希，字母序与生产顺序无关，会把最旧的一份当成最新。
- 用「文件名匹配 `*_recompose.json`」以外的目录规则筛 fullredraw：`out/` 里的散件可以起任何名字，只有 recompose 自己写下的报告能证明该 mp4 是裁回产物。
- 要求 sidecar 的 mtime 不早于 mp4：用户重新拷贝合法成片会把 mp4 改新，反而被筛掉；当前只校验存在，把边界留给命名与写入约定。

**验证**

- 新增后端两条：fullredraw 的 `outputs` 排除无 `_recompose.json` 的散件并按 mtime 排序；patch 版本名与 mtime 逆序时仍按 mtime 升序返回。`uv run pytest` 全绿、`uv run ruff check .` 通过。
- 新增前端两条：fullredraw 对比页出现「右路成片」下拉且默认最新；切旧成片后右路 video src 跟随。vitest 26 个文件 149 条用例全绿，`npm run typecheck`、`npm run lint` 通过。
- 真实 case 复核：`ship_01`、`vf_dance_walk_02` 的输出按 mtime 升序、最后一项为最新；`ship_01` 的 zip 与无报告的 mp4 不入列表；`walk_02` 只有 `_space` 时仍标「仅中间段」，`dance_move` 的 `_space` 在 `_frame` 出现后被隐藏；`simple_gen_01` 返回空。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py` 的 `_output_files` / `_output_sort_key`、`vrstudio/frontend/src/views/wizard/CompareStep.vue`、`vrstudio/tests/test_web_console.py`、`vrstudio/frontend/tests/unit/compare-step.spec.ts`。

**后续入口**

- 若 relight 的 `out/` 也出现散件，按条目 26 的办法收紧到 `*_relit.*`，先把命名规则立项再改 `_output_files`。
- 生成页「最近成片」与合并页「成片」列表仍各自取数；要接同一个选择器时，先把 `_output_files` 的「最新一份」语义复用过去，再考虑抽组件。

## 29. 2026-11-05 · 视频全幅重绘页按步骤拆分，扩充件增加上传副本

**问题**

> 我希望在视频抽取这一步开发一下前端接口……在「扩充画面输出」下面的文件列表里，针对 seedance_input.mp4 这一项提供一个额外的前端交互按钮，能够下载这个"被正确转换后"的 input 视频。……另外我还希望美化一下 视频全画幅重绘 页面的前端交互逻辑，目前扩充和裁回原尺寸这两边不仅共用 ui（实际上他们之间已经有一些不通用的按钮了，比如裁切才会需要用户上传，扩充则不用）另外各种按钮也堆积在几行里，难以阅读。

**原因**

`WizardView.vue` 只按步骤切换高亮，`MergeStep.vue` 没有 `step` prop，fullredraw 的扩充与裁回在同一个模板分支里同时渲染：两个主按钮、输出模式下拉、拼接输入控件与两组产物清单挤在一条面板里。反过来，用户真正需要的外部交接文件——按平台限额缩放过的 pad 视频——只在 vrgen 的轮次目录里存在，页面拿不到。`1105-01` 直接把 4480×1920 的 pad 件交 mglc，被 8,295,044 像素上限拒绝，就是这条缺口的真实后果。

**决策**

- `MergeStep` 增加 `step` prop，由 `WizardView` 传当前步骤；fullredraw 分支按步骤只渲染本步内容，patch / patchimg / fullRedrawImg 三个分支不动。
- 扩充步：主按钮「扩充画面/重新扩充」、pad 门控提示、扩充产物与上传件两组文件；右列只留最近任务。
- 裁回步：拼接输入控件、输出模式、主按钮「裁回原尺寸」、门控提示、裁回产物；右列成片与最近任务。拼接输入的上传/素材库入口只出现在这一步。
- 上传件组头写清来源与上限（`model 37 · videoEdit · scale auto`，上限 8,295,044 像素），每行在原有播放/打开之外加「下载」，空态给「生成上传件」，与当前生成参数不一致时提示重新生成。
- 全尺寸产物与上传件分两组：前者是几何契约与裁回输入，后者是送平台的副本，尺寸与用途都不同。
- `FileRow` 增加可选 `#actions` 插槽，props 仍只有 `{ entry }`，现有七个调用方的行为与测试不变。

**排除的方案**

- 保留单面板、用分隔线分两段：步骤切换仍然不改变内容，扩充步依旧看到裁回的全部控件。
- 把缩放实现放进前端或 vrstudio：要按模型 validator 算，复制一份必然与 vrgen 漂移。
- 把上传件混进「扩充画面输出」：同一列表出现两份不同尺寸的 mp4，用户分不清哪份能交平台。
- 除顺带转码外再提供「手填尺寸」：等于让用户自己记住 8,295,044 与偶数对齐规则。

**验证**

原型见 `vrstudio/.tmp_prototype/merge-step.html`（现状 / 方案两个标签，上传件四态，1280 与 1440 两个宽度），用户确认后落地。浏览器实测用 `1105-01`（已有 pad、无素材，正好是外部交接场景）走扩充步两组文件、重新扩充后上传件出现、下载得到 4398×1884 的 mp4 与 mask，再切到裁回步确认只剩拼接输入与裁回按钮。后端与前端门禁见 `docs/plan/pad-upload-export-plan.md` §9。

**涉及文件**

`vrstudio/frontend/src/views/wizard/MergeStep.vue`、`WizardView.vue`、`components/common/FileRow.vue`、`types/case-info.ts`、`api/case.ts`、`vrstudio/src/vrstudio/web/app.py`、`vrstudio/src/vrstudio/cli/generate.py`、`vrgen/src/vrgen/prep/uploads.py`、`vrgen/src/vrgen/cli.py`。

**后续入口**

- 其它流程若也要导出上传件，先确认它有「母版 + 画布」这一对尺寸；patch 的 clip 在 `firstLastFrame` 下不是母版，不能直接复用。
- 上传件按 `<W>x<H>` 命名，改参数会多出一份；若要自动清理，先定「保留几份」的规则再动后端。

## 30. 2026-11-06 · patch 选区页增加剪贴板导入导出范围

**问题**

同一场景的多个 patch case 经常要复用同一套取景，选区页只能在当前 case 里点全景、拖 inner、调 fov；跨 case 要么重做一遍，要么手改 `case.toml`。

**原因**

选区草稿（viewport/inner/frames）是 per-case 的，页面没有跨 case 搬运入口；`set_draft` 只接受调用方传进来的段，没有任何「从别处整段复制」的路径。

**决策**

- 右栏「重置选区」下面单独一行放「导出范围」「导入范围」两个并列按钮，只对 `flow = "patch"` 显示。
- 剪贴板是 `vrstudio.patch.region` v1 JSON：`viewport`（yaw/pitch/fov/width/height）、`inner`、`frames`，以及来源 `fps` 与 `frame_count`；另带来源 `case` 与 `exported_at` 仅供溯源，导入忽略。
- 导出走 `GET /api/case/{name}/region/export` 读 `case.toml` 已保存值，不用前端可能尚未落盘的 ref。
- 导入走 `POST /api/case/{name}/region/import`：先整段校验，再一次性写 viewport（只改角度，目标视口尺寸不变）、inner 与 frames；来源与目标视口尺寸不同时 inner 按宽高各自比例缩放并钳制，应答的 `scaled` 决定提示文案。
- 帧号不直接搬：来源与目标 fps 相同时保留原帧号；不同时按来源 fps 换成秒、再乘目标 fps 还原。结束帧超出目标末尾就截到最后一帧并返回 `frames_clamped`，提示「帧范围已按目标时长截到 …」；起点已超过目标时长才 400。
- 导入应答沿用轻量 `_geometry_payload` 并附 `frames`、`scaled`、`frames_clamped`，页面调现有 `applyGeometry()` 刷新预览与文字，同时向 `WizardView` 发出 `geometry` 事件把 `frames` 一并写进 `caseInfo`，切步回来不会看到旧帧范围。
- 浏览器不支持 `navigator.clipboard` 或拒绝权限时：写失败先用 `document.execCommand('copy')` 兜底，仍失败弹「手动复制」框；读失败弹「手动粘贴」框，粘贴后走同一导入路径。

**排除的方案**

- 前端直接从 `props.info` 导出：fov 滑杆拖动中、其他标签页刚写入时拿到的不是 `case.toml` 的已保存值。
- 只让前端 `POST /draft` 再自己拼预览：`/draft` 返回完整 case info（数秒），且不会刷新 `previews.vp` 的缓存 key。
- 不带视口尺寸、inner 直接写像素：跨 1920×1080 与 3840×2160 时越界或错位。
- 导入时把目标视口尺寸改成来源尺寸：会悄悄改掉目标 case 已定的采样密度与后续 merge 口径。
- 帧号直接写入、只做越界钳制：目标 fps 与来源不同时帧号仍然错位，只解决越界不解决换算；按全片比例映射又会把同一段动作挪到别的秒数，因此选按时间换算。

**验证**

`tests/test_web_console.py` 覆盖导出、同尺寸/不同尺寸导入、跨 fps 时间换算、目标更短截断、起点超时长拒绝、非法 payload、409 与 revision 递增；`frontend/tests/unit/pick-step.spec.ts` 覆盖按钮显隐、导出写剪贴板、导入后页面状态与 `geometry` 事件、截断提示、非 JSON 不调接口、手动粘贴；浏览器端到端待人工执行（本会话没有浏览器工具），步骤见 `docs/test-runs/20261106-patch-region-clipboard.md`。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py`、`web/render.py`、`frontend/src/views/wizard/PickStep.vue`、`views/WizardView.vue`、`api/workflow.ts`、`utils/clipboard.ts`、`types/case-info.ts`、`tests/test_web_console.py`、`frontend/tests/unit/pick-step.spec.ts`、`frontend/tests/unit/clipboard.spec.ts`。

**后续入口**

- patchimg 若也要复制选区，先补 fov 与帧范围的缺省语义，复用同一 payload 时必须把 `frames` 标成可选，不要另起一套格式。
- 若将来要复制到完全不同的源视频，`inner` 的像素意义只由视口尺寸决定，与源 ERP 分辨率无关；需要「按 ERP 覆盖区域」复制时另立字段，不要改现有三段的含义。

## 31. 2026-11-06 · 裁回失败后给出「还是出片（诊断）」

**问题**

裁回（recompose）的几何前提闸门判 `fail` 时，CLI 故意不出片并退出 1。前端只能看到一条报错，既没有传 `--force` 的手段，也没有任何提示说明「什么时候值得强制看一眼」；运维或美术想让用户先确认内容时，只能去命令行手动跑。

**原因**

`--force` 从搬入以来只有 CLI 开关，web 的 `_op_argv` 没有把它翻出来；任务视图只有 `error` 原文，前端无法判断这次失败是不是「渲染被闸门拒绝」这一类。直接加一个常驻开关，用户在正常流程里勾上就会拿到一张接缝重复、绕一圈接不上的成片，而且它覆盖同名文件。

**决策**

- 入口跟着报错出现：只在最近一次裁回失败、且失败原因是几何前提闸门时，在「最近任务」的报错下面给出「还是出片（诊断）」按钮。不做常驻开关，也不给 patch 的 merge/拼接加这个入口（`vrstudio merge` 没有 `--force`）。
- 按钮上方常驻两段说明：第一段写利害（接缝出现重复或错位、最后一段接回开头时接不上、只能用来先看画面不能交付、会覆盖同名成片），第二段写适用范围（只有「几何前提校验失败」值得点；文件缺失、参数错、编码失败之类的报错点它没有意义）。
- 点击先走 `ElMessageBox.confirm`，确认框里重复利害与适用范围；确认后以 `{ force: true }` 重新提交 `recompose`，取消则不发请求。
- 任务视图新增 `error_kind` 字段，由服务端按报错原文里的稳定片段归类（`web/tasks.py` 的 `ERROR_KINDS`，当前只有 `geometry premise failed` → `geometry`）。前端只认类别名，不匹配报错原文；文案变化只改服务端一处。
- `POST /api/case/{name}/run` 的 recompose 分支在 `force` 为真时追加 `--force`；闸门判定与 `verdict` 语义完全留在 CLI，web 不做第二套判定。

**排除的方案**

- 常驻开关：误点概率最高，用户不需要报错也能勾上，违背「入口出现即说明原因」。
- 常驻开关 + 失败后才可勾选：多一层状态判断，视觉上仍是一个平时就在的控件，说明文字与报错分离。
- 前端直接匹配 `latest.error` 里的英文前缀：CLI 文案一改前端就静默失效，且文案知识会散落到两处。
- 给 `force` 单开一个接口：现有 `/run` 已经是 op + body 的唯一入口，多一个端点等于多一份转发逻辑。
- 强制出片后改文件名（加 `_forced` 后缀）：会让成片列表出现两份同名来源，`_output_files`、对比页与代理缓存都要跟着加例外；覆盖同名是既有语义，确认框里已经写明。

**验证**

`tests/test_recompose_force.py` 覆盖 `_op_argv` 带/不带 `force`、与 `--follow-input` 同时出现、`error_kind` 只认几何闸门原文、`Task.view()` 输出 `error_kind`；`frontend/tests/unit/merge-step.spec.ts` 覆盖按钮只在 `error_kind = "geometry"` 时出现、其它报错不出现、确认后调用 `runOperation('p1', 'recompose', { force: true, output_mode: 'case' })`、取消时不发请求。`uv run pytest` 与 `uv run ruff check .`、`vue-tsc -b`、`eslint`、`prettier --check` 全绿；浏览器端到端待人工执行（需要一次真实的几何闸门失败）。

**涉及文件**

`vrstudio/src/vrstudio/web/app.py`、`web/tasks.py`、`frontend/src/views/wizard/MergeStep.vue`、`types/task.ts`、`tests/test_recompose_force.py`、`frontend/tests/unit/merge-step.spec.ts`。

**后续入口**

- 若以后还有别的「拒绝出片但想先看一眼」的闸门（例如图片拼接的 `stitch_image`），先给那条 CLI 加显式 `--force`，再在 `ERROR_KINDS` 里登记一个类别，页面按类别复用同一个确认框，不要为每条流程各写一个按钮。
- `error_kind` 是任务视图的字段，不是冻结契约；新增类别不改变已有取值。

## 待决与未做

### fullredraw 的 pad 不自动进提交清单（2026-10-27，待决）

问题：条目 18 之后，pad 已经能在素材库的「流程文件」组里看到，并标出「已加入本次提交 / 未加入本次提交」；但 pad 任务本身不会写 `[submit]`，`walk_01` 与 `ship_01` 的 `selected = ["pad"]` 都是人工点出来的。

原因：`submit_selected` 只有三处写入——生成页手动改清单、首尾帧交接写两帧 id、删除素材后的清理；`pad` 任务本身（`app.py` 的 `_op_argv`）只跑 CLI，不碰提交清单。

当前立场：仍不自动选中。pad 完成后母版身份是确定的（一个 case 只有一份 manifest 与一份 padded 文件），技术上安全；但这条只适用于 fullredraw，patch 的 `clip` 只在 `videoEdit` 下才是母版，`firstLastFrame` 只提交两张定帧，所以不能做成一条通用规则。要做就按 `(flow, mode)` 分流写在 pad 任务完成的后端路径上，不做成前端按钮回调。

触发条件：如果素材库已经标出「未加入本次提交」之后仍然出现漏提交，或 fullredraw 的真实提交因为漏选 pad 失败，就实现自动选中，并把 `_submit_entries` 的装配顺序（pad 固定第一位）一并测到。

### 选区与对比页的播放卡顿（2026-10-26，已实施配置方案）

排查与方案见条目 17：`web.proxy_max_w` 已配置化（本机设 2048），已有代理按新宽度自动重建。若重建后对比页仍卡（WebGL 画布路径的额外成本），下一步考虑对比页分辨率独立或交互降载；目前先观察 2048 的实际效果。

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
