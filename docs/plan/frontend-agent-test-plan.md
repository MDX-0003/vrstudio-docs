# Agent 浏览器验收计划（前端审查修复）

记录时间：2026-10-24。
状态：方案已确认，待执行。执行前需要逐次确认服务启动、文件写入与提交。
关联文档：

- `docs/plan/frontend-review-fixes.md`：本次要验收的修复项与实施状态。
- `docs/plan/patch-browser-acceptance-plan.md`：Patch 流程浏览器验收计划，提供两条真实路径、证据格式与选择器约定。
- `docs/test-runs/20261023-patch-browser.md`：上一次 Playwright MCP 实际执行记录。
- `docs/plan/frontend-refactor-plan.md`：前端测试与门禁的总体计划。
- `docs/plan/frontend-workflow-and-skills.md`：开发流程、MCP 工具与 skill 留档。

## 1. 目标

用 MCP Agent 在真实浏览器里验收本次前端审查修复，而不是只靠人工点击或纯函数单测。重点回答四件事：

1. 生成页拆分后能否正常加载、编辑、保存、切换 case。
2. 提示词别名、输入框自适应、保存状态与预演失效语义是否符合预期。
3. 任务接口是否只请求当前 case，切换 case 时是否还会串数据。
4. 合并页门控、轮次显示、上传取消、设置保存这些边界是否仍然可用。

## 2. 范围与非范围

本轮无额度验收包含：

- 页面加载、步骤切换、提示词编辑与保存、case 切换、任务过滤、合并页门控、轮次/日志显示、设置显示名、上传取消、响应式与控制台错误。

本轮不做：

- 不执行真实 `dry_run`、`submit`、`adopt`、`merge`、`compare` 付费链路。
- 不修改 `dacne`、`walk_4k` 等现有 case 的提示词、提交集、素材与轮次。
- 不读取、打印或写入 API Key；服务沿用现有进程或现有配置。
- 不把截图、测试上传文件、日志、生成媒体提交进 git。
- 不把 MCP Agent 测试伪装成 CI；CI 仍只跑 Vitest、pytest、lint、typecheck、build。

## 3. 复用过往方案的方式

- 复用 `patch-browser-acceptance-plan.md` 的证据格式：每条用例记录通过/失败/阻塞、实际结果、截图、接口证据与失败原文。
- 复用 `patch-browser-acceptance-plan.md` 第 7 节的原则：页面文字之外，同时断言 `/api/case`、`/api/tasks` 与文件/任务状态。
- 复用 `frontend-workflow-and-skills.md` 第 3.1 节的 Playwright MCP 工具组合：
  `browser_navigate`、`browser_snapshot`、`browser_click`、`browser_fill_form`、
  `browser_file_upload`、`browser_network_requests`、`browser_console_messages`、
  `browser_evaluate`、`browser_take_screenshot`。
- 复用 `docs/test-runs/` 的运行记录格式，但本次记录文件名使用
  `docs/test-runs/YYYYMMDD-frontend-agent.md`。

## 4. 测试环境与隔离

- 前端构建：执行前先 `cd vrstudio/frontend && npm run build`。
- 服务命令：
  `uv run vrstudio serve --host 127.0.0.1 --port 8763 --cases-dir E:\VRAIGC\vrstudio\cases_qa`
- 页面入口：`http://127.0.0.1:8763/next/`
- 浏览器：Playwright MCP；如果 MCP 浏览器实例被占用，先释放实例或使用隔离 profile，不在共享实例上直接跑。
- 截图：`E:\VRAIGC\.playwright-mcp\frontend-agent-YYYYMMDD\`，该目录不进 git。
- 测试上传文件：使用临时小文件，放在系统临时目录；测试结束后删除 `.uploads` 中对应上传记录。
- 设置页显示名：测试前记录原值，测试后恢复。
- case 数据：只读使用 `cases_qa` 中的 case；不修改 `cases/` 下的现有 case。

执行前检查：

1. 8763 端口空闲。
2. `cases_qa` 中存在可用于生成页和合并页的 case；如果不存在，先报告，不自行创建。
3. Playwright MCP 浏览器可用。
4. 浏览器控制台与网络记录可读取。

## 5. 测试用例

### A. 启动与 case 列表

步骤：

1. 打开 `/next/cases`。
2. 截图。
3. 读取控制台错误。
4. 检查 case 行、流程标签与“下一步”文案。

预期：

- 页面正常渲染，无未处理异常。
- 至少有一个 patch case 和一个 fullredraw case 可见。
- “下一步”文案与 case 的 gate 不矛盾；打开 case 后进入该步骤。

证据：

- 截图 `A-cases.png`。
- `browser_console_messages` 输出。
- 至少一条 case 的 `/api/cases` 返回片段。

### B. 生成页结构与提示词别名

步骤：

1. 打开 `dacne` 的生成页。
2. 检查素材区、提示词区、最近成片、生成记录、最近任务、固定提交条。
3. 读取提示词摘要文本。
4. 检查页面是否出现 `subject`、`target`、`plot` 原始 key。
5. 用 `browser_evaluate` 请求 `/api/case/dacne`，读取 `prompt.labels`、`prompt.help`、`prompt.vars`。

预期：

- 摘要显示“原主体”“重绘结果”“情节”等别名，而不是原始 key。
- `labels` 与页面别名一致。
- 生成记录不显示 `stage`、`gate`、轮次 ID。
- 提交条固定底部，不随页面滚动消失。

证据：

- 截图 `B-generate.png`。
- 页面文本与 `/api/case/dacne` 的 `prompt` 片段。

### C. 提示词编辑、自适应与保存语义

步骤：

1. 点击“展开编辑”。
2. 检查抽屉宽度。
3. 在一个变量里输入长文本，观察输入框高度。
4. 等待自动保存，刷新页面，确认值仍在。
5. 不作修改直接点“保存并关闭”。
6. 如果页面已有“预演通过”状态，记录保存前后状态。

预期：

- 抽屉宽度约为视口的 92%，不超过 1100px。
- 输入框随内容增高，超过 40vh 后内部滚动。
- 保存后服务端 `prompt.vars` 与页面一致。
- 无改动保存不改变预演状态。

证据：

- 截图 `C-prompt-drawer.png`、`C-prompt-longtext.png`。
- 输入前后 `/api/case/<name>` 的 `prompt.vars` 片段。
- 保存前后状态文本。

### D. 切换 case 隔离与任务过滤

步骤：

1. 在 case A 的生成页输入一段未保存提示词。
2. 立刻切换到 case B。
3. 检查 B 页面提示词、参数与任务列表。
4. 读取网络请求。
5. 切回 A，检查 A 的保存结果。
6. 用 `browser_evaluate` 请求 `/api/case/B`。

预期：

- B 页面不出现 A 的未保存文本。
- 生成页任务请求是 `/api/tasks?scope=all&case=B`，不是无 case 的全量请求。
- B 的任务列表只包含 B 的任务。
- A 的未保存文本写回 A，而不是 B。

证据：

- 网络请求列表。
- 截图 `D-switch-B.png`。
- A/B 两个 `/api/case` 的 `prompt.vars` 片段。

### E. 合并页门控按钮

步骤：

1. 找到 `pad` 未完成的 fullredraw case，打开合并页。
2. 检查“扩充画面”按钮状态。
3. 找到 `pad` 已完成的 case，重复检查。
4. 用 `/api/case/<name>` 读取 `gates.pad`。

预期：

- `gates.pad.ok=false` 时按钮禁用，且有原因。
- `gates.pad.ok=true` 时按钮可用。
- 页面状态与接口 gate 一致。

证据：

- 截图 `E-merge-pad-blocked.png`、`E-merge-pad-ready.png`。
- `gates.pad` JSON 片段。

### F. 轮次与任务技术详情

步骤：

1. 找有 `stage=prepared` 轮次的 case。
2. 检查生成记录列表。
3. 找失败轮次，检查状态文案。
4. 打开“最近任务”的“查看技术详情”。

预期：

- 预演轮次不出现在生成记录。
- 失败轮次显示“生成失败”，不显示为可选用。
- 完整 tail 只有在点击“查看技术详情”后才出现。

证据：

- 截图 `F-rounds.png`、`F-task-details.png`。
- `/api/case/<name>` 的 `rounds` 片段。

### G. 设置页显示名

步骤：

1. 打开 `/next/settings`，记录原显示名。
2. 改成临时名称并保存。
3. 刷新页面，确认名称仍在。
4. 恢复原显示名并保存。

预期：

- 保存成功提示出现。
- 刷新后临时名称仍在。
- 恢复后原名称生效。
- 测试结束不留下临时显示名。

证据：

- 截图 `G-settings.png`。
- `/api/me` 返回片段。

### H. 上传取消

步骤：

1. 在生成页打开上传弹窗。
2. 选择一个临时小文件。
3. 等上传开始后直接切换页面。
4. 检查网络请求。
5. 清理测试上传。

预期：

- 离开页面后出现 `DELETE /api/uploads/<id>`。
- 不出现该上传的 `complete` 请求。
- 不留下临时素材。

证据：

- 网络请求中的上传创建、分片、DELETE。
- 截图 `H-upload-cancel.png`。

### I. 响应式与控制台

步骤：

1. 在 1280、1440、1920 三个宽度分别打开生成页与合并页。
2. 截图。
3. 用 `browser_evaluate` 断言页面无横向溢出。
4. 收集控制台错误。

预期：

- `document.documentElement.scrollWidth <= window.innerWidth`。
- 固定提交条不遮挡最后一行内容。
- 除已知外部资源错误外，控制台没有未处理异常。

证据：

- 六张截图。
- `scrollWidth` / `innerWidth` 数值。
- 控制台错误列表。

## 6. 接口契约断言

每个用例至少同时检查一项接口证据：

- `/api/case/<name>`：`meta.revision`、`submit_selected`、`gates`、`prompt.vars`、`prompt.rendered`、`rounds`、`outputs`、`adopt_round`。
- `/api/tasks?scope=all&case=<name>`：任务 `case` 字段全部等于当前 case。
- `/api/me`：设置页显示名保存后一致。
- `/api/uploads/<id>` 或网络请求：上传取消确实发生。

不允许只用页面文字判断通过。

## 7. 选择器策略

当前 Vue 源码没有 `data-testid`。第一轮 MCP 测试优先使用：

- 可访问角色与按钮文字，例如“提交生成”“预演检查（不扣费）”“展开编辑”。
- 输入框标签与 `aria-label`。
- 页面稳定文本，例如“生成记录”“最近任务”“查看技术详情”。

如果某个元素在测试中反复定位不稳定，先报告，再单独申请一笔代码提交，补充以下选择器：

- `data-testid="case-row-<name>"`
- `data-testid="generate-prompt-open"`
- `data-testid="generate-prompt-drawer"`
- `data-testid="generate-prompt-var-<key>"`
- `data-testid="generate-submit"`
- `data-testid="generate-dry-run"`
- `data-testid="generate-adopt"`
- `data-testid="generate-asset-<id>"`
- `data-testid="merge-pad"`
- `data-testid="merge-recompose"`
- `data-testid="settings-nickname"`
- `data-testid="settings-save"`
- `data-testid="task-tech-details"`

选择器改动不得改变页面行为；提交前需要单独确认。

## 8. 付费路径（本轮不执行）

以下用例标记 `@paid`，只有在单独确认额度、项目、剧集与会话后才执行：

- `dry_run` 预演。
- `submit` 真实提交。
- `adopt` 采用成片。
- `merge` 空间合并与时间拼接。
- `compare` 双路对比。

付费执行时：

- 不读取、打印或写入 API Key。
- 记录提交前后的会话额度状态。
- 记录任务 ID、轮次 ID、输出文件与失败原文。
- 失败是否扣费必须写进运行记录。

## 9. 执行协议与提交确认

1. 每次执行前，先确认服务、端口、case 根与浏览器可用。
2. 每次写文件、启动服务、执行测试或提交前，向用户说明具体动作并取得同意。
3. 一次同意只对当前一笔提交有效；下一笔重新确认。
4. 发现代码问题先报告，不擅自修复；修复需要新的提交确认。
5. 不读取、不打印、不写入 API Key。
6. 不执行付费生成，除非用户单独批准。
7. 测试结束后恢复设置页显示名，清理临时上传与临时文件。
8. 如果 MCP 浏览器不可用，报告阻塞，不静默改为人工测试。

## 10. 通过标准

无额度层全部满足才算本轮 Agent 验收通过：

- A–I 全部通过，或失败项有明确证据与复现步骤。
- 生成页无控制台未处理异常。
- 提示词别名、长文本自适应与保存语义符合预期。
- 切 case 不串数据，任务请求带当前 case。
- 合并页按钮状态与 `/api/case` gate 一致。
- 预演轮次不显示为成片，失败轮次有明确文案。
- 设置显示名可保存并恢复。
- 上传离开页面会被取消。
- 1280/1440/1920 无横向溢出，提交条不遮挡内容。

付费层单独判定，不影响无额度层结论。

## 11. 风险

- Playwright MCP 浏览器实例被占用或 Chrome 远程调试未开启：执行前必须先解决；否则按阻塞记录。
- 当前没有 `data-testid`：文本或角色定位可能受文案调整影响；必要时单独提交选择器。
- `cases_qa` 的 case 状态可能不足以覆盖所有 gate 分支：先枚举可用 case，再决定是否补临时 case；创建 case 需要单独确认。
- 上传取消会产生服务端临时上传：测试后必须清理。
- 设置页修改显示名会影响当前使用者：测试后必须恢复。

## 12. 首次执行清单

- [ ] 确认 8763 端口空闲。
- [ ] `cases_qa` 中有生成页与合并页需要的 case。
- [ ] `npm run build` 完成。
- [ ] 启动 8763 服务。
- [ ] Playwright MCP 浏览器可用。
- [ ] 记录当前 commit、浏览器版本、视口尺寸。
- [ ] 按 A–I 顺序执行，A/B/C/D 优先，E/F/G/H/I 随后。
- [ ] 生成 `docs/test-runs/YYYYMMDD-frontend-agent.md`。
- [ ] 报告结果，等待下一次提交确认。
