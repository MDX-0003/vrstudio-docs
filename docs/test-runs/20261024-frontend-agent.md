# 前端 Agent 浏览器验收运行记录

记录时间：2026-10-25。
对应计划：`docs/plan/frontend-agent-test-plan.md`。
执行方式：Playwright MCP 驱动真实 Chromium，无人工点击。
结论：A/B/D/F/G/I 通过；C/E 覆盖不足；H 发现的问题已修复并复测通过。

## 1. 环境

- vrstudio：`main`，HEAD `aff30e5`。
- 前端构建：`npm run build` 通过，产物 `index-Bx2XJzct.js` / `index--h_fgdLs.css`。
- 服务：`uv run vrstudio serve --host 127.0.0.1 --port 8763 --cases-dir E:\VRAIGC\vrstudio\cases_qa`。
- cases：`qa_firstlast_1023`、`qa_videoedit_1023`，都是 patch 流程且已完成历史生成。
- 浏览器：Playwright MCP Chromium；初始视口 2560，随后切到 1280×900、1440×900、1920×1080。
- 截图目录：`E:\VRAIGC\.playwright-mcp\frontend-agent-20261024\`，不进 git。
- 执行前处理：发现 10-23 19:19 启动的旧 Playwright MCP 浏览器仍占用 `mcp-chrome-2e8d960` profile；关闭旧进程树后，当前 MCP server 正常启动浏览器。

## 2. 用例结果

### A. 启动与 case 列表：通过

- `/next/cases` 正常渲染，2 个 case 都显示。
- `qa_firstlast_1023` 与 `qa_videoedit_1023` 的“下一步”都是“可以对比”，与两个 case 已有成片的 gate 一致。
- 控制台错误 0。
- 证据：`A-cases.png`。

### B. 生成页结构与提示词别名：通过

- `qa_firstlast_1023` 生成页渲染 5 个面板，提交条 `position: fixed`。
- 提示词显示“主体与最终结果”“动作段”“目标外观”“场景、镜头与声音锁定”“允许变化”等别名。
- 页面正文没有 `subject`、`target`、`plot` 原始 key。
- 生成记录没有 `stage`、`gate`、轮次 ID。
- `bodyScrollWidth == innerWidth == 2560`，无横向溢出。
- 控制台错误 0。
- 证据：`B-generate.png`。

### C. 提示词编辑、自适应与保存语义：部分通过

- 抽屉宽度 1100px，当前视口 2560，符合 `min(1100px, 92vw)`。
- 5 个变量卡都显示别名；内部 key 只在 `title` 里。
- 文本域高度随内容变化：95 字的“动作段”高度 94px，短字段高度 73px；`max-height` 约 499.7px（40vh）。
- 点击“保存并关闭”且没有改动时，出现“提示词没有改动”，预演状态保持“未预演”。
- 未执行长文本实际输入与保存，因为该用例要求只读使用 `cases_qa` 的 case；长文本的输入高度与保存链路目前由组件测试和 CSS 断言覆盖。
- 未覆盖“已有预演通过状态时无改动保存”的分支，因为两个 QA case 当前都是“未预演”。
- 证据：`C-prompt-drawer.png`。

### D. 切换 case 隔离与任务过滤：通过

- `qa_firstlast_1023` 页面不出现 `qa_videoedit_1023` 的提示词内容；切到 B 后也不出现 A 的内容。
- 生成页任务请求是 `/api/tasks?scope=all&case=qa_firstlast_1023` 和 `/api/tasks?scope=all&case=qa_videoedit_1023`，没有无 case 的全量请求。
- 切回 A 后 A 的提示词内容恢复，B 的内容不残留。
- 未执行“输入未保存文本后立刻切 case”的真实浏览器路径，避免修改只读 case；该路径由 `useCaseSaveQueue` 的 case 捕获测试覆盖。
- 证据：`D-switch-B.png`、网络请求记录。

### E. 合并页门控按钮：部分通过

- `qa_firstlast_1023` 合并页的“开始合并”可用，与 `/api/case` 的 `merge.ready=true` 一致。
- `cases_qa` 里没有 fullredraw case，无法在浏览器里验证 `pad` 未完成时“扩充画面”禁用、完成后可用的两条分支。
- `MergeStep` 的 pad/recompose 按钮禁用条件已有组件测试覆盖。
- 证据：合并页按钮状态、`gates.merge`。

### F. 轮次与任务技术详情：通过

- `qa_videoedit_1023` 生成记录显示“可用”与“生成失败”，失败轮次没有显示为可选用。
- 页面没有出现 `prepared` 字符串。
- 在付费测试准备的 dry-run 之后，出现任务 `5b815279f8f8`（`dry_run`、`done`）；“最近任务”显示“dry_run · 已完成”。
- 点击“查看技术详情”后出现 tail，按钮变为“收起技术详情”；tail 包含提示词尾部与 `--model-id 37 --type videoEdit --duration 7` 等命令参数。
- 证据：`F-rounds.png`、`prep-dry-run.png`。

### G. 设置页显示名：通过

- 原显示名 `MDX`。
- 改为 `MDX-TEST` 保存，页面提示“显示名已保存”，`/api/me` 返回 `MDX-TEST`。
- 刷新页面后输入框仍为 `MDX-TEST`。
- 已恢复为 `MDX`，`/api/me` 再次确认。
- 证据：`G-settings.png`。

### H. 上传取消：修复后通过

原始失败：

- 第一次小文件上传因本地速度太快直接完成，无法判断取消。
- 第二次用 Playwright 给 `PUT` 增加 5 秒延迟，确保切页时上传仍在进行。
- 用 `page.goto()` 整页导航后捕获到的请求只有：
  - `POST /api/uploads`
  - `PUT /api/uploads/dbfb977b66af440c8cf01830815abcd0?offset=0`
- 没有 `DELETE`，也没有 `complete`；`cases_qa/.uploads/dbfb977b66af440c8cf01830815abcd0/` 在测试后仍存在。
- 根因：整页导航会销毁 JavaScript 上下文，Vue 的 `onUnmounted` 不会执行；普通 `fetch` 的 DELETE 也会被浏览器中止。

修复：

- `AssetUploadDialog.vue` 增加 `pagehide` 监听；页面卸载时对仍在进行的上传调用 `cancelUploadKeepalive()`。
- `api/uploads.ts` 新增 keepalive DELETE，请求可在文档销毁后继续发出。
- `onUnmounted` 保留 SPA 卸载路径；`canceledUploads` 防止 pagehide 与 unmount 重复取消。
- 服务端 `_cleanup_uploads()` 除了启动时执行，也在创建新上传会话时惰性执行，作为 TTL 兜底。

复测：

- 延迟 PUT 5 秒，整页导航到 `/next/cases`。
- 上传 ID `119b578a92b44771aea6b5cf89c2d74d`。
- 复测后 `cases_qa/.uploads/119b578a92b44771aea6b5cf89c2d74d` 不存在，keepalive DELETE 到达服务端。
- 旧的 `dbfb977b66af440c8cf01830815abcd0/` 是修复前产生的残留，按要求暂不清理。
- 组件测试新增 `pagehide` 分支：`cancelUploadKeepalive` 被调用，`onUnmounted` 不重复调用普通取消。
- 证据：网络请求、服务端 `.uploads` 目录、`asset-upload-dialog.spec.ts`。

### I. 响应式与控制台：通过

- 1280×900：`scrollWidth=1270`，无横向溢出；提交条高 152.7px。
- 1440×900：`scrollWidth=1430`，无横向溢出；提交条高 116.7px。
- 1920×1080：`scrollWidth=1910`，无横向溢出；提交条高 80.7px。
- 三个宽度控制台错误 0。
- 证据：`I-1280.png`、`I-1440.png`、`I-1920.png`。

## 3. 接口契约证据

- `/api/case/qa_firstlast_1023`：`prompt.labels` 与页面别名一致；`rounds` 两条都是 `stage=checked`、`result=yes`。
- `/api/case/qa_videoedit_1023`：`rounds` 包含一条 `stage=failed`、`result=no`，页面显示“生成失败”。
- `/api/tasks?scope=all&case=<name>`：返回任务均属于当前 case。
  - `qa_firstlast_1023` 当前任务列表为空。
  - `qa_videoedit_1023` 在 dry-run 后有一条 `dry_run`/`done` 任务 `5b815279f8f8`。
- `/api/me`：设置页保存前后分别为 `MDX-TEST` 和 `MDX`。
- `/api/uploads`：创建与分片成功；整页卸载后 keepalive DELETE 到达，测试上传目录被删除。

## 4. 发现的问题

1. **已修复：切换页面时上传取消没有到达服务端。**
   - 原因：整页导航不会执行 Vue `onUnmounted`，普通 `fetch` DELETE 被中止。
   - 修复：`pagehide` + keepalive DELETE；服务端 TTL 改为启动时与创建上传时惰性清理。
   - 复测：上传 `119b578a...` 在整页导航后目录被删除。
   - 残留：修复前的 `dbfb...` 目录暂不清理。

2. **覆盖不足：没有 fullredraw case。**
   - 影响：`pad` 未完成时的“扩充画面”禁用分支没有在浏览器里验证。
   - 现状：组件测试覆盖按钮条件，但缺少真实 case 的 gate 证据。
   - 建议：在 `cases_qa` 增加一个 fullredraw 临时 case，或在付费测试准备阶段一并创建。

3. **覆盖不足：两个 QA case 当前没有任务。**
   - 影响：“查看技术详情”与 tail 展开没有在浏览器里验证。
   - 建议：真实提交后会产生任务，届时补这一条。

4. **覆盖不足：C 没有做真实长文本输入与保存。**
   - 原因：计划要求只读使用 `cases_qa`，避免修改现有 case。
   - 现状：CSS 高度与组件逻辑已覆盖；长文本保存可在付费测试或临时 case 上补。

## 5. 付费测试准备

本轮没有执行任何付费提交，也没有读取或使用 API Key。

已完成的准备：

- case：`qa_videoedit_1023`（patch，videoEdit，2 项素材已勾选，已有可用成片）。
- 在页面上执行了一次“预演检查（不扣费）”。
- 结果：状态“预演通过，当前选择未改动”；任务 `5b815279f8f8`（`dry_run`、`done`）；没有新增生成轮次，现有 rounds 仍是 `checked/yes` 与 `failed/no` 两条。
- 这证明提示词、素材、模式、项目、剧集与会话在真实准备链路上可用。

尚未执行：

- 单次真实提交（会消耗额度）。
- 采用、合并、对比。

建议的单次付费操作：

- 打开 `qa_videoedit_1023` 生成页 → 确认“预演通过” → 只点一次“提交生成”。
- 不执行采用、合并、对比，避免把一次付费测试扩成多次操作。
- 记录任务 ID、轮次 ID、`result.mp4`、任务状态与失败原文（如有）。
- 不读取 API Key；沿用 case 当前的扣费会话。

过程文件暂时保留：

- 截图与测试图片在 `E:\VRAIGC\.playwright-mcp\frontend-agent-20261024\`。
- 不完整上传 `cases_qa/.uploads/dbfb977b66af440c8cf01830815abcd0/` 保留，等后续确认是否清理。
- 设置显示名已恢复为 `MDX`。

## 6. 下一步

1. H 的代码修复已完成并通过前端、后端与浏览器复测；等待代码提交确认。
2. 运行记录的 H 段已更新；等待文档提交确认。
3. 执行已批准的提示词输入/保存测试（临时 case `qa_prompt_agent_1024`）。
4. 补齐 fullredraw case 的覆盖。
5. 在你明确批准后，执行上面这一次付费提交；只做一次，不连带 adopt/merge/compare。
