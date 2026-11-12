# 首尾帧图片输入重排与 10 张上限验收

日期：2026-11-12。范围：`docs/plan/keyframe-input-cap-plan.md` 的 WP1–WP3；前端输入区改为卡片带，参考图允许0 张，新增 `lighting_ref`，单次最多10 张，提示词按结构条件渲染并在参考图变化后刷新。

## 1. 代码落点

提交：vrgen `ccf96f3`，vrstudio `56c93e0`。

- vrgen：`round/image.py` 新增 `image_role_variables` 与 `image_roles_section` / `detail_rule` / `lighting_rule`；`jobs.py` 的 `COMPUTED_KEYS` 扩三项；`cli.py` 的 `image submit` 与 `_prompt_preview` 改用统一变量；两个首尾帧模板改用新键，并更新 `figure` / `subject_last` 的填写说明。
- vrstudio 后端：`keyframe.py` 加 `lighting_ref`、`refs_explicit` 与显式空 `refs = []`；`app.py` 的 `_keyframe_refs` / `_keyframe_state` 只在「没有 refs 键」时自动绑定唯一三视图；`_keyframe_inputs` 按清单顺序生成 pairs、允许0 张 `subject_ref`、锚点追加最后；`_keyframe_argv` 提交前按10 张校验；`_gates` 去掉「必须有三视图」。
- vrstudio 前端：新增 `components/keyframe/KeyframeInputCards.vue`；`KeyframeStep.vue` 换卡片带、加10 张上限与超限禁用、`saveRefs` 后刷新提示词（请求序号防竞态）；角色选项加 `lighting_ref`；新增参考图默认 `detail_ref`。
- 测试：vrgen `test_image.py`；vrstudio `test_keyframe.py`、`test_web_console.py`；前端 `keyframe-step.spec.ts`。

## 2. 自动化门禁

- `cd vrgen && uv run pytest -q`：全绿。
- `cd vrgen && uv run ruff check .`：干净。
- `cd vrstudio && uv run pytest -q`：除两条已知的临时目录环境失败外全绿。失败是 `test_step_file_entries_open_url_does_not_depend_on_repo_rel` 与 `test_external_source_has_path_but_no_open_url`，原因是本机 `pytest` 的 `tmp_path` 落在仓库内，`file_entry` 算出了相对路径；与本次改动无关，前一轮验收 `docs/test-runs/20261112-keyframe-submit-bar.md` §4 已记录。
- `cd vrstudio && uv run ruff check .`：干净。
- `cd vrstudio/frontend && npm run lint`：干净。
- `cd vrstudio/frontend && npm run typecheck`：通过。
- `cd vrstudio/frontend && npm run test`：31 个文件、233 条通过。
- `cd vrstudio/frontend && npx vite build --outDir <临时目录>`：构建通过（1755 个模块，约680 ms）。没有写 `src/vrstudio/web/static/next`，8760 的静态产物未变。

## 3. 浏览器验收

环境：本机临时 `vrstudio serve --host 127.0.0.1 --port 8761`，前端用 Vite dev（5173，代理指向8761）；8760 不重启、不重建。测试 case 由 `walk_4k` 复制为 `kf-e2e`，9 张参考图（三视图 + 7 细节 + 1 氛围光影），首帧 `i27`、尾帧 `i28`；验收后删除。

Chrome CDP 共21 条断言，全部通过：

1. 首帧 9 张参考图：`本次提交 10 / 10 张`，添加按钮禁用；提示词含图1..图10。
2. 切尾帧：`本次提交 11 / 10 张`，红色提示「参考图最多8 张，当前9 张，共11 张」；锚点为图11 并标「超出上限」；生成与交接禁用。
3. 尾帧提示词含图11 锚点与【光线保持】。
4. 移除 1 张后：`10 / 10`，超限提示消失，锚点回到图10，生成恢复可用；提示词刷新为图10，不再有图11。
5. 通过 API 清空参考图并刷新：`1 / 10`，黄色「没有人物三视图」提示，生成仍可用；提示词不再有【参考图分工】，也没有图2。
6. 提示词刷新：删除参考图后 `fetchKeyframePrompt` 重新请求，预览从图11 变为图10；真机上「删图3 后预览仍显示图3」的旧问题在实现里由 `saveRefs` 后 `loadPrompt` 修掉。

截图（不随仓库提交）：`.tmp_prototype/keyframe-refs/shots/e2e-first-9.png`、`e2e-tail-over.png`、`e2e-tail-10.png`、`e2e-zero-refs.png`。

## 4. 已知边界

- 10 张是固定值；模型44 的详情写13 张、模型25 写6 张，`params show` 还没下发参考图上限。本轮不按模型动态收窄。
- 8760 的静态产物没有重建，服务也没有重启；审查后需要在 `vrstudio/frontend` 执行 `npm run build`，并重启8760 的 `vrstudio serve`，才能在实际地址看到新页面与新后端。
- 参考图拖拽、按模型上限预检、批量编辑表不在本轮。
- 真实图片生成与扣费提交未跑；本轮只验证输入区、上限与提示词，不点生成按钮。
