# Case 负责人归属行与「归属到我的名下」方案

状态：已实施，Playwright 端到端验证通过（2026-10-27）。
涉及：`vrstudio/src/vrstudio/web/case_meta.py`、`web/app.py`、
`vrstudio/frontend/src/api/case.ts`、`views/WizardView.vue`。

## 实施记录与两处偏差

- **归属行做在 case 详情页（WizardView）而不是列表页**：归属是 per-case
  状态，且用户引用的「case 正被 … 使用」提示也在 WizardView；归属行就在
  该提示上方常驻显示。
- **`set_owner()` 不自己推进 revision**：revision 的检查与推进统一由现有的
  `CaseRevisionMiddleware` 负责（`/owner` 已加入 `_REVISION_WRITES`），
  端点只做纯写入——避免与中间件的 touch 双重推进。冲突检查也复用中间件
  （客户端带 `revision` 或 `X-Case-Revision`），409 走前端现有的全局
  `case-conflict` 弹窗，前端零新增冲突处理代码。

## 背景与决策

现状：负责人在第一次从 Web 打开 case 时由 `_meta().ensure()` 隐式落定
（第一个打开者成为 owner），之后没有任何变更入口，想换只能手改
`case-meta.json`。已拍板的决策：

1. **不做「认领」按钮、不做指派下拉**。切换 owner 的唯一动作是
   「归属到我的名下」——把 owner 设为当前用户自己。理由：免登录体系下
   没有用户名录可选，指派会引入同名用户歧义（身份 = `vrstudio_uid`
   cookie，显示名可重复、可随时改）；"我来接管"语义简单且天然无歧义。
2. **归属信息常驻显示**：Case 列表页顶部提示区常驻一行
   `当前归属 = xxx`（xxx 为 `owner_name`，无主时显示"未定（首次打开时自动归属）"）。
   当当前用户 uid ≠ owner_id 时，该行追加提示与「归属到我的名下」按钮。
3. **并发防冲突用现有 revision 乐观锁**：改主请求携带
   `expected_revision`，对不上返回 409 + 当前 meta，前端提示后刷新，
   不自动覆盖。不引入锁或队列。

身份事实（`web/identity.py`）：用户 = `vrstudio_uid` cookie（随机 uuid，
一年有效）；显示名 = `vrstudio_name` cookie，纯装饰。同名≠同人，
同浏览器改名仍是同一 uid。

## 改动清单

### 1. `case_meta.py`：`set_owner()` 与改名联动

```python
def set_owner(self, case: str, user, expected_revision: int | None = None) -> CaseMeta:
    # 读 meta → expected_revision 不符抛 RevisionConflict（现有异常，端点转 409）
    # → owner_id/owner_name 置为当前用户 → revision + 1
    # → 记 updated_by/at；owner_changed_at/by 与 updated 复用同值，不另设字段
```

`touch()` 顺带修一个现存瑕疵：owner 已是当前用户时刷新 `owner_name`
（现在改名后 meta 里永远留旧名字）。改动一行：
`owner_name=meta.owner_name if meta.owner_id != uid else 当前显示名` 的
补缺逻辑保持，另加自我刷新。

`ensure()` 行为不变（首个打开者预归属），归属从此变成可显式修正的状态。

### 2. `app.py`：一个端点

```
POST /api/case/{name}/owner   body: {"expected_revision": int | null}
```

- 把 owner 设为 `current_user(request)`（不接受指定他人，与决策 1 一致）。
- `RevisionConflict` → 409，body 带当前 `meta.as_dict()`。
- 返回 200 + 新 meta。
- 挂在现有 case 路由组，风格对齐 `runOperation` / 保存端点。

### 3. 前端 `CaseListView.vue`：归属行与切换按钮

列表页顶部提示区（即"case 正被 XX 使用；保存仍会写入，请先沟通"
所在位置）常驻一行：

- 无冲突时：`当前归属 = <owner_name>`（弱化文字样式）。
- `owner_id` ≠ 我的 uid 时追加：
  「归属到我的名下」按钮 + 一行解释
  `点后此 case 的负责人变为 <我的显示名>；若他人刚改过会提示冲突`。
  精确文案实施时定稿，保持一行。
- 点击 → 调端点；409 时用现有保存竞态的提示方式告知"负责人刚被
  <owner_name> 修改"，刷新列表后让用户重新决定。
- 成功后刷新列表数据（复用现有 `fetchCases` / 列表刷新路径）。
- uid 前端可得（`/api/me` 返回 `id`，见 `app.py:2680`），列表接口需把
  `meta.owner_id` 带出来（现列表已带 `meta`，核对字段即可）。
- **不展示裸 uid**：归属行只显示名字；万一两个用户同名，按钮行为仍是
  "归属到我的名下"，歧义不影响操作正确性，留待真实遇到再优化展示。

### 4. 测试（pytest，随迁）

- `set_owner` 正常路径：owner 更新、revision +1、留痕字段写入。
- revision 冲突：过期 `expected_revision` 抛 `RevisionConflict` 且不写盘。
- `touch()` 自我刷新：owner 是自己时改名后 `owner_name` 跟随。
- 端点级：409 返回体含当前 meta；未登录/无 uid 的兜底（`anonymous`）
  行为与现有写操作一致。
- 归属为空（从未打开过）时端点可直接设置，`expected_revision: null` 合法。

## 验收

1. 用户 A 打开列表，无主 case 显示"未定"；打开过一次后显示 A。
2. 用户 B 看到归属行 + 按钮；点击后归属变 B，revision +1。
3. A、B 同时点按钮（基于同一 revision）：先到者成功，后者收到
   冲突提示，刷新后看到新归属，再点一次即接管。
4. A 改显示名后保存任一 case，归属行显示新名字。
5. `uv run pytest` 与 `ruff check .` 全绿；前端 `npm run typecheck` 通过。

## 验证记录（2026-10-27）

- pytest：`tests/test_case_owner.py` 6 条全过（set_owner 落盘、touch 显示名
  自我刷新、他人写入不动 owner、端点归属、409 冲突不写盘、老客户端无
  revision 照旧写入）；全量套件中仅 `tests/test_web_proxy.py` 9 条失败，
  经 stash 验证在 HEAD 上同样失败，属历史遗留（`web.proxy_max_w` 默认值
  已改 2048 而测试仍断言 4096），与本次改动无关，待另行处理。
- ruff 全绿、`vue-tsc` 全绿。
- Playwright 端到端（walk_4k，测试身份 tester/uid test-uid-zzz）：归属行
  常驻显示；非 owner 看到「归属到我的名下」按钮与解释文案；点击后归属
  变 tester、按钮消失，`case-meta.json` 的 owner_id/revision 正确落盘
  （revision 31）。
- 注意：验证把 walk_4k 的归属改成了测试身份；从你自己的浏览器打开该
  case 点一次「归属到我的名下」即可拿回。
