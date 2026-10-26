# 前端 Agent 浏览器验收运行记录（第二轮）

记录时间：2026-10-25。
对应计划：`docs/plan/frontend-agent-test-plan.md`；本轮执行 2026-10-24 记录（`20261024-frontend-agent.md` §6）排定的三项收尾：提示词输入/保存测试、fullredraw 门控覆盖、单次付费提交的准备。
执行方式：Playwright MCP 驱动真实 Chromium，无人工点击；付费提交本轮未执行，等待单独批准。
结论：测试 1 五个场景全部通过；测试 2 两个门控分支验证通过；测试 3 准备就绪。新发现问题 6 条（F1–F6），其中 F5 是 fullredraw 首次扩充被 UI 锁死的功能缺陷。

## 1. 环境

- vrstudio：`main`，HEAD `ac81c74`（含 10-25 上传取消修复）。
- 前端构建：`npm run build` 通过，产物 `index-Bh5p_hPy.js`。
- 服务：10-25 上午启动的旧服务（10:45，PID 24764）已停止；本次用当前代码与新构建重启
  `uv run vrstudio serve --host 127.0.0.1 --port 8763 --cases-dir E:\VRAIGC\vrstudio\cases_qa`。
- 浏览器：Playwright MCP Chromium。启动前发现上午会话的 MCP 浏览器仍占用
  `mcp-chrome-2e8d960` profile（进程树 `cmd(38504) → node(35860) → chrome(40276)`，8:50–10:46 启动）；
  按 `docs/lessons-learned.md` §1 的判断标准确认残留后 `taskkill /PID 38504 /T /F`，当前会话浏览器正常启动。
- cases：`qa_firstlast_1023`、`qa_videoedit_1023`（只读）、本轮新建 `qa_prompt_agent_1024`（patch）、
  `qa_fullredraw_agent_1025`（fullredraw）。
- 截图目录：`E:\VRAIGC\.playwright-mcp\frontend-agent-20261025\`，不进 git。

## 2. 测试数据准备

- `qa_prompt_agent_1024`：`uv run vrstudio case new qa_prompt_agent_1024 --flow patch --source
  E:\VRAIGC\vrstudio\sources\Mono_dance_4k.mp4 --cases-dir E:\VRAIGC\vrstudio\cases_qa`。
- 变量播种：`case new` 只写 generation.toml（mode=videoEdit），不写 prompt-vars.toml；新 case 的
  `prompt.vars` 为空，新前端抽屉显示"没有可编辑的提示词变量"（见 F3）。测试用 vrgen CLI 播种
  6 个空变量（等价于旧版"＋ 添加变量"入口做的事）：
  `vrgen prompt save --job qa_prompt_agent_1024 --template character-repaint --set subject= --set target=
  --set plot= --set motion_rule= --set preserve= --set allowed_changes= --workdir …\vrgen_runs`。
  播种后生成页摘要正确显示 6 个别名字段（原主体/重绘结果/情节/动作重演规则/必须保持/允许变化）。
- `qa_fullredraw_agent_1025`：`case new --flow fullredraw --source Mono_dance_4k.mp4`；
  禁用分支验证后用 CLI 跑了一次 pad（本地免费，590 帧、画布 9334×4000）制造可用分支。

## 3. 测试 1：提示词输入/保存（qa_prompt_agent_1024）——全部通过

保存链路事实（代码依据）：`schedulePromptSave` 在每次 input 入队并捕获 case 名
（`GenerateStep.vue:311`）；队列 `delayMs: 400` 防抖自动 flush（`GenerateStep.vue:69`）；
"保存并关闭"强制 flush 后再关抽屉（`:432`）；卸载时全量 flush（`:715`）。
接口契约：`POST /api/case/<name>/prompt`，body `{"set": key, "value": …}`。

### 场景 1 失焦：通过

- 动作：抽屉内"原主体"逐字输入"失焦测试：画面中央的白色素体人偶"，点击帮助文字触发失焦，等 1.5 秒。
- 结果：网络出现且仅出现一次 POST（几十次按键合并成一次）；服务端
  `vars.subject` 与输入一致；revision 2→3；页头状态回到"已保存"。
- 证据：网络请求 #33；`T1a-blur-saved.png`。

### 场景 2 连续输入：通过

- 动作："重绘结果"逐字连续输入 20 字，不等待立即切"情节"再连续输入 15 字，停手等 1.2 秒。
- 结果：每个字段各只发一次 POST（#57 target、#71 plot），服务端两个键都是最终值；
  #71 请求体 `{"set":"plot","value":"连续输入测试：约六秒的单人独舞"}`；revision 3→5。
- 结论：400ms 防抖按键合并、按 key 合并条目，无中间值落盘。

### 场景 3 关闭抽屉：通过（两条路径）

- 有改动：一次调用内完成"填入动作重演规则 + 立即点保存并关闭"（落在 400ms 防抖窗口内）。
  按钮 flush 先于关抽屉：POST #249 发出、抽屉关闭、服务端 `motion_rule` 落盘、revision 5→6。
- 无改动：重新打开抽屉直接点"保存并关闭"，出现"提示词没有改动"提示，抽屉关闭，
  无新 POST（总数保持 4 次），预演状态不变。
- 证据：`T1b-drawer-close.png`。

### 场景 4 切步骤：通过

- 动作："必须保持"填入后用"关闭"合上抽屉（不走保存按钮），切到"1 选区"，再切回"4 生成"。
- 结果：填入值经防抖落盘（revision 6→7）；跨步骤往返后 GenerateStep 重建，抽屉内
  `preserve` 从服务端回显原值；选区页→生成页无数据残留。
- 补充：GenerateStep 卸载时的 `onUnmounted` 全量 flush 路径由 `case-save-queue.spec.ts` 与
  组件测试覆盖，浏览器层验证的是"跨步骤不丢数据"契约。
- 证据：`T1c-step-switch.png`。

### 场景 5 切 case：通过（核心竞态场景）

- 基线：`qa_videoedit_1023` revision 15，六个变量为 10-23 的原值。
- 动作一（防抖路径）：A 页"允许变化"填入后立即点侧栏切走。结果：A revision 9→10、
  值落 A；B revision 仍 15。
- 动作二（卸载 flush 路径）：一次调用内完成"填入新值 + 关闭抽屉 + 点 Case 列表"，
  让条目在路由切换时仍待保存。结果：A revision 9→10（新值"切case测试二：卸载flush路径，值只写回本case"），
  B revision 仍 15、vars 逐字未动；B 页面全文不含 A 的任何测试文本。
- 任务隔离：A 生成页期间全部请求为 `/api/tasks?scope=all&case=qa_prompt_agent_1024`，
  切到 B 后全部为 `?case=qa_videoedit_1023`；全程没有一次无 case 参数的全量任务请求。
- 证据：`T1d-case-switch-B.png`、两侧 `/api/case` JSON、任务请求清单。

### 控制台

- 全程唯一错误是 F1 的 vp.png 500（两次，均在 `qa_prompt_agent_1024` 选区页）；无 JS 未处理异常。

## 4. 测试 2：fullredraw pad 门控（qa_fullredraw_agent_1025）——两分支通过，另有 F5/F6

- 禁用分支：全新 case，`/api/case` 返回
  `pad: {ok:false, reason:"先把两侧画面扩充好，再送生成"}`；页面"扩充画面"按钮 `[disabled]`，
  与 gate 一致。截图 `T2a-pad-disabled.png`。
- 可用分支：CLI 跑一次 pad（`vrstudio pad --in …Mono_dance_4k.mp4 --out …seedance_input.mp4 --quiet`，
  本地免费）后，gate 变为 `{ok:true, evidence:"在 …seedance_input_pad.json 检测到扩充画面的记录文件…"}`；
  按钮解除禁用，"裁回原尺寸"仍正确禁用（等采用结果），输出区列出 seedance_input.mp4。
  截图 `T2b-pad-enabled.png`。
- 遗留：UI 无法完成第一次 pad（F5），本次可用分支靠 CLI 制造；pad 原因不显示（F6）。

## 5. 测试 3 准备：完成，付费提交待单独批准

- 服务即本轮新启实例（当前 HEAD + 新构建），无需再次重启。
- `qa_videoedit_1023` 状态：`submit_selected=[clip, i1]`；`gates.generate={ok:true, ready:true}`；
  提示词六变量为 10-23 原值（revision 16）；轮次仍为 2 条（checked/yes、failed/no）。
- 10-25 重新执行了一次"预演检查（不扣费）"：任务 `62dfb5a92efa`（dry_run、done），
  页面状态"预演通过"；无新增轮次。截图 `T3-prep-preview-passed.png`。
- 待执行：打开生成页确认"预演通过"后只点一次"提交生成"；不执行 adopt/merge/compare；
  记录任务 ID、轮次 ID、输出文件与失败原文；不读取 API Key；扣费会话沿用 case 当前配置
  （项目 `2060150527854528` / 第 1 集 / 会话 `2062569522605504`）。

## 6. 发现的问题

1. **F1（P2）新建 patch case 的选区页 vp.png 500。**
   `render.py:217 _reproject` 直接取 `vp["width"]`；case 无 `[viewport]` 段时 KeyError →
   `/img/<case>/vp.png` 500。页面整体可用（"还没有选区"文案正常），但预览图裂、控制台报错。
   上轮未踩到是因为 QA case 建立时就有 viewport。
2. **F2（P3 观察项）新 case 生成页直出英文 render_error。**
   提示词区显示 `prompt template uses {asset_list}, which nothing defines…` 原文。
   符合"按真实原因报错"的设计（未抽取、无 manifest 时 `{asset_list}` 无法展开），
   但英文原文直接面向用户，可读性差；是否要中文化/友好化待定。
3. **F3（P1 功能缺口）新前端没有"添加变量"入口，新 case 无法从零编辑提示词。**
   vrgen 的 `prompt save --set` 允许新键（草稿编辑器语义），旧版前端有"＋ 添加变量"抽屉
   （`templates/partials/prompt.html:17`）；新前端 `buildPromptVariables` 只渲染 vars 已有键，
   新建 case 的 vars 为空 → 抽屉空态，UI 上没有任何办法创建第一个变量。
   本轮用 vrgen CLI 播种绕过。两条 QA case 的 vars 当年是经旧版前端播种的。
4. **F4（P3 可访问性）顶栏已完成步骤的按钮没有可访问名。**
   当前步骤之前的步骤按钮在可访问性树里无名（生成页 1–3 无名、对比页 1–5 无名），
   当前及之后的步骤正常（"4 生成"、"6 对比"）。影响读屏与按名定位。
5. **F5（P1 功能缺陷）fullredraw 新 case 的"扩充画面"按钮永远禁用，UI 无法开始第一次 pad。**
   fullredraw 流程第一步就是 pad（`steps.ts`：PAD/GENERATE/RECOMPOSE/COMPARE）；pad 命令
   直接吃源视频、无前置（`app.py:2305`）。但 pad gate 只有 `ok`（=已扩充过）没有 `ready`
   （`app.py:1050`），`MergeStep.vue:139` 用 `gateBlocked(padGate)` → 未扩充即禁用 →
   死锁：不跑 pad 按钮不可点，按钮不可点就没法跑 pad。旧版前端从未暴露 pad 按钮
   （模板里 0 处引用），历史上 pad 全靠 CLI。`merge-step.spec.ts:55` 把该语义固化成了预期
   （照实现写的测试）。修复方向（任选其一，需立项）：pad gate 增加 `ready`（源视频在即可），
   或按钮禁用改为"仅任务运行中"。
6. **F6（P3）pad 禁用时页面不显示 pad 自己的原因。**
   `MergeStep.vue:154` 告警只渲染 `recomposeGate.reason`；新 case 进入 pad 页看到的是
   "采用结果后才能裁回原尺寸"（recompose 的原因），而 pad 的"先把两侧画面扩充好，再送生成"
   不出现，用户不知道扩充按钮为什么灰。

自动化操作备注（非缺陷）：提示词抽屉是模态的，打开时侧栏与顶栏不可点；这是预期交互，
自动化时必须先关抽屉再导航。

## 7. 过程文件（暂不清理）

- 截图：`E:\VRAIGC\.playwright-mcp\frontend-agent-20261025\`（T0/T1a–T1d/T2a/T2b/T3 共 8 张）。
- 临时 case：`qa_prompt_agent_1024`（含测试提示词值与 revision 10）、`qa_fullredraw_agent_1025`
  （含 pad 产物 seedance_input.mp4/mask/manifest，约数百 MB）。
- 10-24 遗留：`cases_qa/.uploads/dbfb977b66af440c8cf01830815abcd0/` 仍保留。
- vrgen 台账：`vrgen_runs/qa_prompt_agent_1024/`（prompt-vars.toml + generation.toml + models.json）。

## 8. 修复实施（2026-10-25/26，用户批准后执行）

六项发现全部修复，前后端门禁与浏览器验证均通过。验证环境：vrstudio 工作区
（修复代码未提交），服务用新构建重启，新增临时 case `qa_fullredraw_fix_1026`
（fullredraw）、`qa_patch_fix_1026`（patch，用于验证 CLI 播种）。

| 项 | 修复 | 测试 |
|---|---|---|
| F1 | `case.py` 新增 `patch_default_draft()`，web 抽屉与 CLI `case new` 共用默认草稿；`render.py _reproject` 视口缺字段时抛带原因的 ValueError（路由转 400）；PickStep 无视口时显示占位、不发图请求 | `test_casemodel.py`、`test_cli.py`（播种/探针失败兜底）、`test_web_preview.py`（防御）、`test_web_console.py` |
| F5 | pad gate 增加 `ready`（源视频在即 true）；按钮语义变为“ready 即可点”，首次扩充不再死锁 | `test_web_console.py`（gate 断言）、`merge-step.spec.ts`（重写语义） |
| F6 | MergeStep 增加 pad 自身原因的 info 告警（与 recompose 告警并存） | `merge-step.spec.ts`（断言两条原因都显示） |
| F4 | 步骤按钮加稳定 `aria-label`（`"N 名称"`，不随完成态变化） | 浏览器验证六按钮标签 |
| F3 | 提示词抽屉增加"添加变量"卡（key 校验：字母数字下划线、不与现有重名）；GenerateStep 接 `add-var` 走既有 `savePromptVar` 保存 | `generate-prompt.spec.ts`（新文件，3 用例） |
| F2 | render_error 告警加中文前缀“提示词暂时无法完整展开：”，原文保留 | `generate-prompt.spec.ts` |

门禁结果：

- 后端：`uv run ruff check .` 通过；`uv run pytest` 365 passed（新增 5 用例）。
- 前端：`npm run typecheck`、`npm run lint` 通过；`npm run test` 49 passed
  （14 文件，新增 `generate-prompt.spec.ts` 3 用例、`merge-step.spec.ts` 重写为 4 用例）。

浏览器逐项验证：

- F1：`qa_prompt_agent_1024`（无 viewport 的旧 case）选区页显示占位
  “先在左侧全景图上点一下、再选视口尺寸”，无 img 请求，控制台 0 错误；
  直接请求 vp.png 返回 400 与中文原因（原来是 500）。CLI 新建的
  `qa_patch_fix_1026` 的 case.toml 已带默认 [viewport]/[inner]/[frames]。
- F5：`qa_fullredraw_fix_1026` pad 页按钮可点（gate `ok=false, ready=true`）。
- F6：页面同时显示“还没有扩充过画面…”与“采用结果后才能裁回原尺寸”。
- F4：六个步骤按钮 aria-label 为 `1 选区`…`6 对比`，含已完成步骤。
- F2：生成页告警为“提示词暂时无法完整展开：prompt template uses {asset_list}…”。
- F3：抽屉添加 `style_ref=胶片质感，颗粒细腻` → 变量卡出现（8 卡）、
  提示“已添加变量 style_ref”、服务端 revision 12 落盘。

截图：`T4-fix-F5F6-pad-enabled.png`、`T5-fix-F3-add-var.png`。

## 9. 下一步

1. 等待用户确认后分两笔提交：vrstudio 一笔（F1–F6 代码与测试）、根仓库一笔
   （本记录文档更新）。
2. 等待用户单独批准后执行一次真实提交（qa_videoedit_1023，只提交，
   不 adopt/merge/compare；预演已通过，服务已在修复后的代码上运行）。
