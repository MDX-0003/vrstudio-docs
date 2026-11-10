# 保存冲突的三条修复：覆盖出口、冲突收敛、几何落定校验

状态：已实施，Playwright 端到端验证通过（2026-10-27）。
2026-11-10 修订：**改动三「几何草稿落定帧带 revision 校验」已退役**。
几何端点写的是 `derived/pick/draft.toml`，不再进入 revision 中间件，
也不由前端带 revision 头；快速连点不再互相 409。revision 只守护
`case.toml` 的显式保存。原因见决策 98，回归测试见
`vrstudio/tests/test_revision_geometry.py`。

涉及：`vrstudio/src/vrstudio/web/app.py`（revision 中间件）、
`vrstudio/frontend/src/api/client.ts`、`views/WizardView.vue`。

实施备注（与原计划的差异与验证结果）：

- **几何落定校验只需服务端改动**：核查发现前端几何请求本来就是离散的
  （`useInnerDrag` 只在 pointerup 提交一次，没有拖动帧请求），且
  `client.ts` 对所有 `/api/case/*` 已自动带 revision 头——所以前端零改动，
  中间件把 `viewport|inner|nudge|viewport-size` 纳入"带头才校验"即可。
- 端到端（web_demo，三个身份接力制造过期 revision）：409 弹出三选弹窗
  （确认=仍要保存（覆盖对方）、取消=重新加载（丢弃本地修改）、×=保留当前
  页面，三个后果都写在消息里）；点「仍要保存」后覆盖落盘（owner 变回
  e2e、revision 推进）、成功提示出现、冲突横幅消失。
- 已知小瑕疵（可接受，记录在案）：覆盖重发在 client 层完成，原始调用方
  已收到过第一次 409 的异常，页面上的部分展示（如归属行）要刷新才反映
  覆盖后的状态；服务端数据是正确的。

## 背景结论（与用户对齐的事实）

- revision 机制身份无关：归属用户与普通用户在 409 面前完全平等，**不引入
  归属豁免**——豁免即静默覆盖回归（决策记录见对话，2026-10-27）。
- 409 后选「保留当前页面」= 冻结：本地改动存不进去（revision 仍旧，后续
  保存持续 409），但也夺不走别人的改动。缺口是用户没有知情覆盖的出口，
  且重复 409 会反复弹窗。
- `viewport` / `inner` / `nudge` 三个高频几何端点被有意排除在 revision
  检查外（拖选区不能被打断），代价是几何草稿按最后写入者胜出、无提示。

## 改动一：冲突弹窗加第三选项「仍要保存（覆盖对方改动）」

- 弹窗三选（Element Plus `distinguishCancelAndClose`）：
  - 确认键：**仍要保存（覆盖对方改动）**；
  - 取消键：**重新加载（丢弃本地修改）**；
  - 右上角 ×：**保留当前页面（本次会话无法保存）**；消息文本把三个后果写明。
  - 文案随身份微调：当前用户是 case 归属人时，确认键前后缀提示
    「你是负责人」——只影响措辞，不影响行为。
- 机制：`client.ts` 记录最近一次 409 请求（path + init，全局单槽即可，
  弹窗本身有 `conflictDialogOpen` 互斥）；新增 `retryOverwrite()`：去掉
  `X-Case-Revision` 头重发该请求。成功后响应头带回新 revision，
  `noteRevision` 自动恢复后续正常保护。用户不选覆盖时槽位随弹窗关闭清空。
  原始调用方仍会收到第一次 409 的异常（可能有一条错误提示），覆盖成功后
  由弹窗补一条成功提示，可接受，不在本轮打磨。

## 改动二：409 收敛，同一轮冲突只弹一次

- `client.ts` 维护 per-case 的 `conflicted` 标记：某 case 首次 409 时派发
  `case-conflict` 事件并置位；置位期间的后续 409 不再派发事件（照旧抛错）。
- 解除条件：`fetchCase` 成功（重新加载后 revision 刷新）或 `retryOverwrite`
  成功。`forgetRevision` 同时清标记。
- 效果：卡在旧页面的人只看到一次弹窗 + 归属行上方的持续冲突横幅
  （横幅由 WizardView 在 `conflicted` 时显示一行弱化文字），不再弹窗轰炸。

## 改动三：几何草稿落定帧带 revision 校验

- 服务端：中间件新增第二组正则（`viewport|inner|nudge`）。这组路径的特点是
  **可选校验**：请求带 `X-Case-Revision` 时执行检查（不一致 409，一致则
  2xx 后照常 touch 推进 revision——草稿变了，别人的下次保存就该重新对齐）；
  不带头（拖动过程帧）完全照旧放行。
- 前端：选区/几何的「落定」请求（拖拽结束后的最后一次）带上 revision 头。
  实施时确认 PickStep / api 层是否已有区分拖动帧与落定帧的信号；没有则在
  pointerup 后补一个显式的 settle 请求。

## 改动四（顺带，文案）：锁提示改为用户已确认的措辞

`WizardView` 的锁告警标题改为：
「访客」可能正在编辑此 case；同时修改会互相覆盖，请先向对方确认。
（锁是 30s 心跳，"可能"比"正被"诚实；多访客重名的展示去重另立后续。）

## 测试

- 中间件：几何路径带头 + revision 一致/不一致（409 不写盘/一致后 touch）；
  不带头放行且不 touch。
- client：`retryOverwrite` 重发不带 revision 头、成功后 revision 刷新；
  `conflicted` 期间二次 409 不派发事件；解除条件各一条。
- 既有用例回归：`tests/test_web_console.py` 的 revision 用例。

## 验收

1. 两人同开一个 case：后保存者弹三选弹窗，选覆盖后他的改动落盘、对方
   下次保存收到新的 409。
2. 选「保留当前页面」后反复触发自动保存，不再重复弹窗，仅横幅提示。
3. 两人同时拖选区：后落定者收到 409（带头的落定帧被拦），拖动过程无人被打断。
4. `uv run pytest`、`ruff check .`、`npm run typecheck` 全绿。
