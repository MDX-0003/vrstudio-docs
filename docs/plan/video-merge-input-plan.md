# 视频拼接输入计划

状态：2026-11-04 用户确认功能与文案，方案待实施；2026-11-09 扩展到 patch（外部重绘的视口视频）。
关联：决策 66、67、78、97，`docs/case-model.md` 的 `[merge]` 段与角色词表，`docs/roles.json`，`docs/plan/pick-range-presets-plan.md`。

2026-11-09 补记：patch 的 `merge --case` 也认 `[merge] input`，指针指向本 case 素材库里 `kind = video` 的外部重绘视口视频；缺省或清空后回退 `extracts/<current>/result.mp4`。前端在合并页复用 `MergeInputControls`（`kind = "video"`），文案改成“外部重绘的视口视频”；patchimg 的贴回仍只接受 adopt 结果。

## 1. 现状

图片 fullRedraw 的「拼接」页已经支持三种输入来源：采用结果（默认）、外部工具改完的 21:9 画布图、素材库里已有的图片。机制是 `case.toml` 的 `[merge] input` 指针加 `merge_input` 素材角色：`case.merge_input_file()` 先看指针、没有再回退 `extracts/<current>/result.png`；web 的 `merge-input` op 一次完成入库与设置指针。

视频 fullRedraw 没有这条路径：

- `web/app.py` 的 `recompose` op 固定把 `cases/<case>/result.mp4` 传给 `--in`。
- `case.py` 在加载时拒绝非 fullRedrawImg 的 `[merge]` 段。
- `merge_input` 角色的 `kinds` 只有 `image`。
- 前端 `MergeStep.vue` 只在图片分支渲染上传与选择按钮。

## 2. 目标

视频 fullRedraw 的「裁回原尺寸」接受与图片流同样的三种输入：采用结果、上传外部改完的 21:9 画布视频、从素材库选一个视频。指针、素材角色、web op 与前端控件都复用图片流已有的那一套。

已确认的边界：

- 页面统一叫「拼接输入」，素材角色不改名。
- 不新增宽高比硬校验：错比例的输入由 recompose 现有的冗余带相关性闸门在渲染前拒绝。
- 没有采用结果、只靠上传的拼接输入也必须能出片。

## 3. 设计

### 3.1 契约

`[merge] input` 扩展为两条流程共用，指向的素材种类由 flow 决定：

- `fullRedrawImg`：`kind = image`，缺省回退 `extracts/<current>/result.png`。
- `fullredraw`：`kind = video`，缺省回退 case 根目录的 `result.mp4`。
- 删除指针指向的素材时清空指针并回退采用结果；悬空指针在加载时报错。

`merge_input` 角色改为 `kinds = ["image", "video"]`，仍然 `modes = []`、`open = false`、`reserved = false`，不进入生成提交与生成页下拉。`docs/roles.json` 与 `vrstudio/src/vrstudio/roles.json` 逐字节相同，改完同步 `tests/test_roles_contract.py` 的 SHA256。

### 3.2 后端

- `case.py` 新增 `merge_input_kind(case)`，作为「这条 flow 的拼接输入该是什么种类」的唯一判定点。`_check_merge_input`、`set_merge_input`、`add_merge_input` 都按它校验；`merge_input_file` 的回退按 flow 区分。
- `web/app.py` 新增与 `_stitch_input_file` 对称的解析：recompose 的输入取 `case.merge_input_file()`，没有指针才回退 `result.mp4`；指针文件缺失时抛 `CaseError`，门控不放行，步骤页仍然显示指针文件并标注缺失。
- `merge-input` op 不改：`add_merge_input` 按 flow 收对应种类后，视频流的指针自然生效。

### 3.3 前端

- 新增 `components/assets/MergeInputControls.vue`：展示当前输入、上传并用作拼接输入、从素材库选择、用回生成结果、提示文案；复用现有 `AssetUploadDialog` 与 `AssetPickerDialog`，向上 emit `updated`。
- `MergeStep.vue` 的图片分支改用这个组件，行为不变；视频分支在「裁回原尺寸」按钮旁渲染同一个组件，`kind = "video"`。
- `AssetUploadDialog.vue` 的 `destination="merge-input"` 增加 `mergeInputKind` prop，收件后缀、种类校验、标题与按钮文案按它取值。
- `AssetPickerDialog.vue` 增加 `onlyKind` prop：现有 `mode="video"` 会同时列出图片，拼接输入需要只列目标种类。

## 4. 验收

1. 后端：`uv run pytest` 全绿、`uv run ruff check .` 干净。
2. 前端：`npm run lint`、`npm run format:check`、`npm run test`、`npm run build` 全绿。
3. 免额度端到端：临时 cases 目录建 fullredraw case，先 `pad` 出 21:9 画布视频，再把它作为拼接输入上传并选中；确认 `case.toml` 写入 `[merge] input`、步骤页输入显示该素材、`recompose` 参数使用它而不是 `result.mp4`，最后能出片。全程不调用生成接口。
4. 图片流程回归：fullRedrawImg 的拼接输入用例全部保持通过。

## 5. 提交

1. 根仓库一笔 `docs:`：`case-model.md`、两份 `roles.json`、决策 78、本文与 `AGENTS.md` 索引。
2. vrstudio 后端一笔：`case.py`、`web/app.py`、`roles.json` 与 SHA、后端测试。
3. vrstudio 前端一笔：共用控件、上传对话框、素材选择器与前端测试。
