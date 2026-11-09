# 源文件上传同名冲突：按内容复用、不同内容改号、删 case 回收

状态：已实施，验收见本文「验收」一节。
涉及：`vrstudio/src/vrstudio/web/app.py`、`vrstudio/src/vrstudio/case.py`、
`vrstudio/frontend/src/views/CaseListView.vue`、`vrstudio/tests/test_create_with_upload.py`。

## 背景

`sources/` 是仓库级共享目录（`REPO_ROOT/sources`），不是 case 私有；`case.toml` 的
`[source] path` 指向它，多个 case 可以引用同一个源文件。新建 case 时上传源视频的
分支把完成的上传 `move` 进 `sources/<原文件名>`，目标存在就返回 409
「请重命名后重新上传」。

这条 409 打断了用户的实际循环：上传 → 新建 case → 效果不满意 → 删除 case →
重新上传同一个视频 → 撞名。删除 case 只删 `cases/<name>/` 与 vrgen 台账，
`sources/` 不动，所以源文件永远留在原地。

三条事实决定改法：

- **不能改成覆盖**。patch / patchimg / fullRedrawImg 后续会重读源文件；覆盖会
  静默改掉其他 case 的输入，`case.create()` 建 case 时钉 sha256 正是为了防这件事。
- **素材库那条上传路径已经按 sha256 去重**（`add_assets`），只有 `sources/` 按
  文件名判重。两条路径的机制不一致，应以内容为准。
- **上传完成时 sha256 已经算好**并存进会话的 `meta.json`，比对旧文件只多一次
  `file_sha256(旧文件)`，不需要用户额外等一次哈希。

## 决策

1. **同名且内容相同 → 复用**：不落第二份，`source_path` 指向已有文件，上传会话
   目录随即删除。
2. **同名但内容不同 → 自动改号**：落成 `<stem> (1).<ext>`、`(2)`…，取第一个空闲
   序号。永不覆盖，也不再返回 409。
3. **删除 case 时回收无人引用的源文件**：删除前记下该 case 的 `source_path`；
   删除成功后重扫其余 `case.toml` 的 `[source] path`，没有任何 case 引用、且文件
   位于 `sources/` 下时，把它移进 `sources/.trash/<原名>-<时间戳>`。移动而不是
   删除，保留可恢复性；`.trash` 不参与 `GET /api/sources` 的列表。
4. **共用源文件不回收**：任一其他 case 仍引用同一路径时保持不动。
5. **前端只补提示**：后端返回实际落点与是否复用/改号，新建弹窗按结果显示
   「已复用 sources/ 里的同名文件」或「源文件已另存为 <名>」。前端现有
   `lastUploaded.name === form.source` 判定在复用语义下不再有害：同名同内容时
   两条路指向同一个文件；同名不同内容时用户拖进来的就是新文件。

## 改动清单

### 1. `app.py::api_cases` 的 `upload_id` 分支

```text
meta   = 会话 meta.json（含 size 与 sha256）
target = sources_dir() / uploaded.name
same   = target 存在 and target.size == meta.size and file_sha256(target) == meta.sha256
name   = same ? target.name : 第一个空闲的 "<stem> (n)<ext>"
same   ? 不 move : move(uploaded -> sources/name)
删除上传会话目录（成功、复用、改号三条路都删）
raw_source = name
```

默认 case 名仍取**原上传文件名**的 stem，不取改号后的名字：用户没填 case 名时,
`1106无桌子 (1).mp4` 不该变成 `1106无桌子 (1)` 的 case 名。

响应新增 `source`：`{"name": 实际落点文件名, "reused": bool, "renamed_from": 原名|null}`。

### 2. 409 分支清理上传会话

原本失败时文件留在 `.uploads/complete/` 到 24 小时 TTL；改号后不再有该分支，
清理统一放在成功路径收尾。

### 3. `_delete_case`：回收无人引用的源

- 删除前 `case_mod.load` 已经拿到 case，记 `source_path`；
- 新增 `case_mod.source_references(root)`：轻量读每个 `case.toml` 的 `[source] path`
  （tomllib 直读，不走 `load`，避免被无关 case 的校验/迁移拖累），路径用
  `_stored_path()` 解析后 `resolve()` 并 `normcase` 归一，返回
  `{归一路径: [case 名]}`；
- 删除成功后：源路径在 `sources_dir()` 之下、且 `source_references` 里没有
  其他 case 引用它 → `sources/.trash/<stem>-<YYYYmmddHHMMSS><ext>`；
- 移动失败只告警，不影响删除结果（case 已经删掉的事实优先）。

### 4. 前端

`createCaseRequest` 的返回类型加 `source`；`CaseListView.createCase` 在
`reused` 为真时提示复用，`renamed_from` 非空时提示另存名。列表下拉不做本地
插入改号名——下次打开弹窗由 `GET /api/sources` 给出。

## 不做

- 不改 `sources/` 为内容寻址（会改 `case.toml` 的 `source_path` 语义，属冻结契约）。
- 不提供「覆盖已有源文件」入口（共享引用下是破坏性操作）。
- 不做 `.trash` 的自动过期清理；体积可见、恢复靠人工。

## 实施记录

- 后端按上文落地：`api_cases` 的 `upload_id` 分支调 `_same_content()`（先比
  `size` 再比已算好的 `sha256`）与 `_free_source_name()`；响应加 `source`。
- 删除回收落在 `_delete_case` 之后的 `_reclaim_source()`，路径解析与新函数
  `case.source_file()` / `case.source_key()` / `case.source_references()` 在
  `case.py`，不复制 `_stored_path` 的规则。
- 与方案的差异一处：**前端没有改同名判定**。`lastUploaded.name === form.source`
  在复用语义下不再有害（同内容指向同一文件；不同内容用户拖的就是新文件），
  所以只保留提示，删掉了原计划的"修误判"。
- `.trash` 文件名是 `<stem>-<YYYYmmdd-HHMMSS><ext>`，同一秒重复时追加 `-2`、`-3`。

## 验收

- 删 case 后重传同名同内容视频 → 创建成功，`sources/` 不新增第二份，响应
  `reused = true`。
- 同名不同内容 → 创建成功，旧文件字节不变，新文件为 `<stem> (1).<ext>`，
  响应 `renamed_from` 非空。
- 两个 case 共用同一源 → 删其中一个，源文件仍在 `sources/`。
- 409 不复存在；上传会话在成功路径上被删除。
- `uv run pytest` 全绿，`uv run ruff check .` 干净。

2026-11-09 验证：pytest 全绿（`tests/test_create_with_upload.py` 覆盖复用、改号、
两种删除回收与 sources 外不碰），ruff 干净，前端 `vue-tsc` 与 vitest 210 条通过。
