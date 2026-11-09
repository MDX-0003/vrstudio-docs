# Pick 选区范围预设与合并输入方案

状态：2026-11-09 用户确认总体方案与四项选择；WP0 静态原型待评审。
关联：决策 97、`docs/case-model.md` 的 patch/patchimg 段与 `[merge]` 段、`docs/plan/video-merge-input-plan.md`、`docs/plan/patch-region-clipboard-plan.md`。

## 1. 问题与目标

pick 页现在把每一次点全景、拖 inner、改视场角、换视口尺寸、摇杆微调都直接写进 `case.toml` 的 `[viewport]/[inner]`；只有开始/结束帧需要点“保存范围”才写 `[frames]`。这带来三个问题：

- `case.toml` 被高频改动，文件不再是“最可能被使用的静态事实”的集中处。
- 旧范围没有前端入口可找回；`extracts/<版本>/clip.json` 虽然已经保存了完整几何，但 pick 页读不回来，`reset-draft` 也只恢复 viewport/inner、不恢复 frames。
- patch 的合并只认 `extracts/<current>/result.mp4`，平台外重绘的结果没有入口回到 case 内合并。

本方案的目标：

- pick 页高频操作只写工作草稿，显式保存的范围写进 `case.toml`。
- 一个 case 可以有多个可命名的范围（preset），保存、另存、载入、改名、删除都由用户控制。
- 抽取按选中的 preset 运行；合并按冻结的抽取版本运行，并支持外部重绘结果。
- 旧 case 平滑迁移，`clip.json` / `image.json` / `_pad.json` 的字段集不变。

## 2. 非目标

- 不改 `clip.json` / `image.json` / `_pad.json` 的字段集。
- 不改生成流程与 vrgen 契约。
- 不把 fullredraw 的 pad 纳入选区 preset；fullredraw 没有 viewport/inner/frames。
- 不做多人同时编辑同一 case 的新机制；继续用现有 case 锁与单队列。
- 第一版不按抽取版本分别记录外部输入；`[merge] input` 仍是一个全局指针。
- 不做 preset 或抽取版本的自动清理。

## 3. 数据模型

### 3.1 `case.toml`

patch 与 patchimg 的选区改成“preset 列表 + 当前指针”：

```toml
schema = 1
flow = "patch"

[source]
path = "..."
sha256 = "..."

[pick]
active = "r2"

[[range_preset]]
id = "r1"
created_at = "2026-11-09T16:30:00+08:00"
updated_at = "2026-11-09T17:05:00+08:00"

[range_preset.viewport]
yaw_deg = -49.4
pitch_deg = -8.8
fov_h_deg = 94.5
width = 1920
height = 1080

[range_preset.inner]
x = 102
y = 304
width = 1295
height = 658

[range_preset.frames]
start = 0
end = 56
```

规则：

- `[[range_preset]]` 是数组表；每条必须有 `id`、`created_at`、`updated_at`、`viewport`、`inner`，patch 还要有 `frames`；patchimg 没有 `frames`。
- preset 不写名字；界面标题用 `created_at`（首次保存时间），另起一行显示 `updated_at`（最近保存时间）。同一分钟有多条时标题补秒或序号。
- `id` 用 `r1`、`r2` 递增，删除后不复用；`id` 只做内部主键，不显示给用户。
- `[pick] active` 指向当前选中的 preset；没有 preset 时可以为空。
- preset 的 geometry 可以随时改：`POST /range-presets/{id}/save` 用当前 draft 覆盖它并刷新 `updated_at`；没有 rename。
- 列表按 `created_at` 倒序；`updated_at` 只显示，不参与排序，避免保存后条目跳位。
- 顶层 `[viewport]/[inner]/[frames]` 不再写入新文件；`Case.viewport/inner/frames` 从 active preset 投影，供 CLI 的 extract、`draft_ready` 与门控继续使用。
- 新格式与旧格式不能同时存在：加载时如果同时看到 `[[range_preset]]` 和顶层三段，按真实原因报错，不猜哪一份为准。

### 3.2 `derived/pick/draft.toml`

pick 页的工作草稿放在 case 目录的 `derived/pick/draft.toml`：

```toml
source_sha256 = "1638e032c4dd442c35fa5bacd952f1313a703edaa8dab8edd6545baa84f202bf"
updated_at = "2026-11-09T16:30:00+08:00"

[viewport]
yaw_deg = -49.4
pitch_deg = -8.8
fov_h_deg = 94.5
width = 1920
height = 1080

[inner]
x = 102
y = 304
width = 1295
height = 658

[frames]
start = 0
end = 56
```

规则：

- 它是 Web 私有工作草稿，不是契约，CLI 不直接读。
- 带 `source_sha256`；与当前 `case.sha256` 不一致时忽略旧草稿，回退 active preset，避免把旧几何套到新素材上。
- 文件不存在、损坏或读不出时回退 active preset，并记一条日志；`/api/case` 不能因此 500。
- 写入用临时文件替换，避免读到半截文件。
- 点全景、拖 inner、改 fov、换视口尺寸、摇杆、改帧范围都只写这个文件。
- 双击 preset 载入时也写这个文件，并同时把 `[pick] active` 指向该 preset；旧抽取版本不提供回填入口。

### 3.3 迁移

- 旧 case 只有顶层 `[viewport]/[inner]/[frames]`：加载时合成一条 `r1`，`created_at` 与 `updated_at` 都用 `case.toml` 的修改时间；`[pick] active = "r1"`。
- 迁移只在内存中完成；第一次显式写 `case.toml` 时落新格式。写之前把旧文件备份成 `case.toml.bak-<时间戳>`，备份留在 case 目录里，随 `cases/` 一起被 gitignore。
- 旧抽取版本的 `clip.json` / `image.json` 不改；它们仍然是合并的真实几何。
- 迁移后旧版程序不能读新格式；回滚时用备份恢复。验收里要覆盖“旧 case 加载 → 保存 → 数值不变”。

### 3.4 不再有 `meta.json`

抽取版本不记录它来自哪个 preset。原因：

- preset 的 `created_at/updated_at` 与 `viewport/inner/frames` 都可变，preset id 不是稳定的历史键；把它写进版本只会随着 preset 改动而失真。
- 版本真正需要的数据已经在 `clip.json`（`frame_start/end`、`viewport`、`inner`、`fps`、`erp` 尺寸）与 `image.json` 里。
- 合并页只列抽取记录；preset 只在几何匹配时作为标签出现，不参与查找。

### 3.5 `[merge] input` 扩到 patch

- `_MERGE_INPUT_KINDS` 增加 `patch: "video"`；`merge_input` 角色已经支持视频，不改 `roles.json`。
- `case.merge_input_file()` 对 patch 的回退是 `extracts/<current>/result.mp4`；有指针时优先用素材库里的外部结果。
- `vrstudio merge --case` 对 patch 也走 `merge_input_file()`；显式 `--input/--ai/--sidecar/--output` 保持原样。
- 外部结果必须是视口视频；比例不一致仍由 `AiFrameSource` 拒绝，或在用户勾选“允许裁切”后按 cover 处理。
- 第一版一个 `[merge] input` 指针；同一 case 同时保留多份外部结果时，切换版本要提示用户确认输入对应关系。

## 4. 操作链路

### 4.1 pick 页

- 页面加载：读 `pick.draft`；没有 draft 就复制 `pick.presets` 里 active 的那条；没有 preset 时显示空草稿。
- 点全景、拖 inner、改 fov、换尺寸、摇杆：只写 draft，返回轻量几何应答。
- 改开始/结束帧：在输入框的 `change`/失焦时写 draft；不在按键中间态写。
- 左侧“保存的范围”列表：
  - 顶部按钮“保存”：更新当前选中的 preset 的 geometry 与 `updated_at`；没有选中时按“另存为”处理。
  - 顶部按钮“另存为”：不弹名称，直接按当前时间新建一条 preset，并把 active 指到它。
  - 行内容：标题是 `created_at`（首次保存时间），下面是 `yaw/pitch/fov`、inner 尺寸、帧范围，再下面一行是 `updated_at`（最近保存时间）；当前条带 `当前` 标记。
  - 单击行：只选中，不改变草稿；双击行：把该 preset 的 viewport/inner/frames 应用到当前 draft，并把 active 指到它；draft 有未保存改动时先确认“会丢弃当前改动”。
  - 行尾只留一个“删除”按钮；删除 active 时自动载入剩下的第一条，没有剩下就清空 active 并保留 draft。
  - 列表按 `created_at` 倒序；`updated_at` 只显示，不参与排序。
- 原来的“保存范围”按钮从帧号输入旁删除；原来的“重置选区”按钮删除。
- “导出范围/导入范围”保留，读写的都是当前 draft。
- pick 页不再提供“从旧抽取版本回填”的入口；旧抽取版本的几何只用于合并。若以后确实需要，再以右键菜单“复制为新范围”的形式加，不放在行内。

### 4.2 抽取页

- 顶部放一份与 pick 页同款的“保存的范围”列表，数据源是 `case.toml` 的 preset；不再有下拉框。点击行只选中本次抽取的 preset，不改变 draft；默认选中 active。
- 运行抽取时把选中的 preset id 传给后端，CLI 用 `--preset` 读该 preset 的几何。
- 抽取只在 preset 上运行，不读 draft；draft 有未保存改动时页面提示“先保存再抽取”。
- 下面“抽取版本”列表的数据源是 `extracts`，只读展示；行内显示版本时间、几何摘要、按时间匹配到的 preset 标签、是否有结果。最新一版标“最新”，表示 generate 使用它；不再有“设为当前”“载入到当前范围”按钮，也不可点击。
- 抽取页与 pick 页共用同一个行组件与样式，区别只在数据源与动作：preset 行可删除，版本行不可删除。
- 抽取完成后 `[extract] current` 指到新版本，与现有行为一致。

### 4.3 合并页

- patch 分支新增“合并范围”卡片，只列抽取记录，不列未抽取的 preset。
- 抽取记录按几何分组去重：
  - 分组键是 `viewport` + `inner` + `frames`；角度按写入精度比较，inner 与帧号按整数比较。
  - 组头显示一次几何摘要，并显示来源标签：匹配到当前 preset 时按首次保存时间写“与 11-09 16:30 的范围相同”，没有匹配写“仅抽取记录”。
  - 组内每个版本一行：时间戳、fps、是否有结果、是否已选；点击行只决定“本次合并用哪版”，不写 `[extract] current`，行内不放“载入”“设为当前”按钮。
  - 合并页与抽取页共用同一个行组件与样式，但数据源是 `extracts`；版本行不可删除。
- 新增“合并输入”卡片，复用 `MergeInputControls`（`kind="video"`），文案改成“外部重绘的视口视频”；只保留“上传并用作拼接输入”一个按钮。存在外部输入时，在输入名旁显示“改用采用结果”条件链接，用来清除 `[merge] input` 指针；不再有“从素材库选择”和并列的“用回生成结果”按钮。
- 合并门控：所选版本存在，且有采用结果或外部拼接输入；没有输入时给出具体原因。
- 换版本时提示“请确认拼接输入是用所选版本的 clip 生成的”；第一版不做按版本绑定。

### 4.4 剪贴板

- 导出范围读当前 draft，不再读 `case.toml` 的 active preset。
- 导入范围写当前 draft，不再直接写 `case.toml`；导入后可以“保存”或“另存为”。
- 剪贴板格式 `vrstudio.patch.region` v1 不变。

## 5. HTTP 接口

- `GET /api/case/{name}`：
  - 新增 `pick = {draft, active, presets, dirty}`；`draft` 是当前工作草稿，`presets` 是全部已保存范围（每条含 `id`、`created_at`、`updated_at`、`viewport`、`inner`、`frames`），`dirty` 表示 draft 与 active preset 不一致。
  - `extracts` 增加 `viewport`、`inner`、`frames`、`fps` 几何摘要。
  - patch 增加 `merge_ranges`：只含抽取版本的分组，结构见下。
- `POST /api/case/{name}/pick-draft`：更新 draft 的 viewport/inner/frames；高频，不推进 revision。
- `POST /api/case/{name}/range-presets`：从 draft 新建 preset（另存为）；不收名称；服务端写 `created_at` 与 `updated_at`；推进 revision。
- `POST /api/case/{name}/range-presets/{id}/save`：用当前 draft 覆盖该 preset 的 geometry 并刷新 `updated_at`；推进 revision。
- `POST /api/case/{name}/range-presets/{id}/load`：把 preset 复制进 draft 并设 active；推进 revision。
- `DELETE /api/case/{name}/range-presets/{id}`：删除；推进 revision。
- `POST /api/case/{name}/region/import`：改为写 draft；从 revision 写端点列表移除。
- `POST /api/case/{name}/run`：`extract` 接受 `preset` 字段，转成 CLI `--preset`；`merge` 接受 `extract` 字段，转成 merge/assemble 的 `--extract`。合并页选版本不改 `[extract] current`。
- 删除 `POST /api/case/{name}/draft` 与前端 `saveDraft`。

`merge_ranges` 的结构：

```json
[
  {
    "viewport": {"yaw_deg": -49.4, "pitch_deg": -8.8, "fov_h_deg": 94.5, "width": 1920, "height": 1080},
    "inner": {"x": 102, "y": 304, "width": 1295, "height": 658},
    "frames": {"start": 0, "end": 56},
    "presets": [{"id": "r2", "created_at": "2026-11-09T16:30:00+08:00", "updated_at": "2026-11-09T17:05:00+08:00"}],
    "versions": [
      {"version": "20261109-160000", "fps": 30.0, "has_result": true},
      {"version": "20261109-161000", "fps": 30.0, "has_result": false}
    ]
  }
]
```

- 只返回 `versions` 非空的分组；未抽取的 preset 不出现在 `merge_ranges`。
- `presets` 只用于按 `created_at` 显示时间标签；没有匹配时是空数组。
- 分组键与精度只在后端 `_merge_ranges()` 一处算，前端不重复浮点比较。

## 6. CLI

- `vrstudio extract name --case X [--preset ID]`：缺省用 active；preset 不存在或不完整时报参数错并列出可用 id。
- `vrstudio case draft --file ...`：默认更新 active preset；加 `--new` 时按当前时间新建一条。
- `vrstudio merge --case X [--extract VERSION]`：patch 也认 `[merge] input`；没有外部输入时回退所选版本的 `result.mp4`；缺省 `--extract` 时用 `[extract] current`。
- `vrstudio assemble --case X [--extract VERSION]`：时间拼接与 merge 使用同一个版本，避免合并了旧版、拼接却拿新版。
- `[extract] current` 由 extract 自动指向新版本；generate 与首尾帧用它。合并页选版本不写这个指针。
- `vrstudio case show`：显示 `presets=N active=ID`，便于排查。

## 7. 前端布局与交互

### 7.1 pick 页

- 左栏在现有全景面板下方新增“保存的范围”面板；列表过长时面板内滚动。
- 面板头部：“保存”“另存为”两个按钮；旁边显示“未保存改动”标记。
- 行内容：标题是首次保存时间，下面是几何摘要，再下面一行是最近保存时间；当前条带 `当前` 标记；行尾只留一个删除按钮。
- 单击行只选中；双击行把该 preset 应用到 draft，这是替代原“重置选区”的主要入口。
- 右栏保留视口尺寸、视场角、视口预览、inner 拖框、摇杆、帧范围；帧范围不再有单独的保存按钮。
- 页面底部保留导出/导入范围按钮，位置可放在“保存的范围”面板内或右栏底部，原型确认。

### 7.2 抽取页

- 顶部放一份与 pick 页同款的“保存的范围”列表，数据源是 `case.toml` 的 preset；不再有下拉框。点击行只选中本次抽取的范围，默认选中 active。
- 下面“抽取版本”列表的数据源是 `extracts`，只读；最新一版标“最新”，行内不放“设为当前”“载入到当前范围”，也不可点击。
- 两份列表共用同一个行组件与样式；preset 行可删除，版本行不可删除；徽标分别写“本次抽取”与“最新”。
- dirty 提示放在运行抽取按钮上方。

### 7.3 合并页

- “合并范围”卡片按几何分组列版本；组头是几何摘要与按首次保存时间写的 preset 标签；组内版本整行点击即“本次合并选这版”，行内不放按钮；选版本不写 `[extract] current`。
- “合并输入”卡片放在合并范围下方；只保留“上传并用作拼接输入”一个按钮；存在外部输入时在输入名旁显示“改用采用结果”链接，不再有“从素材库选择”。
- 选中版本与当前输入不匹配的风险用文案提示，不做硬校验。

### 7.4 原型

WP0 先做静态可点击原型，覆盖：

- pick 左栏的时间标签范围列表、保存/另存为、单击选中/双击载入、行尾删除；
- 抽取页的 preset 列表点击选中本次抽取范围，版本列表只读标“最新”，不再有下拉框；
- 合并页的几何分组、整行点击选版本、合并输入。

原型只做布局与状态，不接后端；用户确认后再写业务代码。原型与截图放在 `vrstudio/.tmp_prototype/`，不提交业务代码库。

## 8. 工作包

### WP0：文档与原型

- 写本文件与决策 97。
- 更新 `docs/case-model.md` 的 patch/patchimg 段、`[merge]` 段与 CLI `extract --preset`。
- 更新 `docs/plan/video-merge-input-plan.md`，说明 patch 也走 `[merge] input`。
- 更新 `docs/patch-videoedit-example.md` 里“点保存范围只写 case.toml”的旧描述。
- 更新 `AGENTS.md` 文档索引。
- 做静态原型并交用户评审。
- 提交：根仓库一笔 `docs:`。

### WP1：case 模型与 CLI

- `case.py`：`RangePreset`、`range_presets`、`active_range`、旧格式迁移、增删改查、`draft_ready`、`merge_input` 扩 patch。
- `cli/extract.py`：`--preset`。
- `cli/case.py`：`case draft` 的更新/新建（新建不写名称，按当前时间）、`case show`。
- `cli/merge.py`：patch 外部输入。
- 测试：旧格式迁移、roundtrip、patchimg 无 frames、active 校验、merge input patch、extract preset。
- 提交：vrstudio 一笔 `aigc:` 或 `case:`。

### WP2：Web 草稿与 API

- 新增 `web/pick_draft.py`；`PreviewStore` 改为读写 draft，缓存键加入 draft mtime。
- `web/app.py`：`pick` 对象、preset 新建/保存/载入/删除、`pick-draft`、`merge_ranges`、`_gates`、revision 正则、删除 `/draft`；`merge` / `assemble` op 接受选中的 `extract` 版本。
- 测试：draft 不写 `case.toml`、源哈希守卫、损坏回退、preset CRUD、`merge_ranges` 去重、合并门控、merge/assemble 使用显式版本。
- 提交：vrstudio 一笔 `web:`。

### WP3：pick 页

- 类型与 API 客户端；左栏时间标签范围面板、保存/另存为、单击选中、双击载入、行尾删除、dirty、帧范围即时保存。
- 共用行组件：pick 与抽取页面用同一个 `RangeRow`，数据源为 preset；合并页复用同一行样式，数据源为 extract。
- 测试：列表交互、dirty、切换确认、双击应用、删除。
- 提交：vrstudio 一笔 `前端：` 或 `web:`。

### WP4：抽取页与合并页

- 抽取页 preset 列表（复用行组件）与 `--preset` 传参；版本列表只读，最新一版标“最新”。
- 合并页几何分组版本列表、整行点击只设置本次合并的局部版本、`MergeInputControls` 只留上传按钮、存在外部输入时显示“改用采用结果”链接、门控。
- 测试：preset 选择、局部版本选择、外部输入、条件链接、门控、切换提示。
- 提交：vrstudio 一笔 `前端：`。

### WP5：验收与收尾

- 浏览器验收与迁移回归。
- `uv run pytest`、`uv run ruff check .`、前端 lint/test/build。
- 文档验收记录与索引收尾。
- 提交：根仓库验收文档一笔；vrstudio 如无代码改动则不提交。

## 9. 测试与验收

### 9.1 后端与 CLI

- 旧 case 顶层三段加载为 `r1`，保存后 `[[range_preset]]` 数值不变，`clip.json` 不被改写。
- 新建 patch case 写默认 preset；patchimg preset 没有 frames；active 指向不存在的 id 报错。
- `vrstudio extract --preset` 使用指定 preset 的几何；缺 preset 或不完整时报参数错。
- patch 的 merge 用 `[merge] input` 指向的视频；没有指针时回退所选版本的 `result.mp4`；`--extract` 显式指定版本时不用 `[extract] current`。
- `_merge_ranges` 对同几何的多个版本只出一组，对仅抽取记录给空 preset 列表，对未抽取 preset 不出现。
- 写 draft 的端点不改 `case.toml` mtime；preset 写端点会推进 revision；合并页选版本只在前端局部生效，不写 case.toml。

### 9.2 前端

- pick 页左栏列表显示 preset 的首次保存时间与最近保存时间；保存更新 active 与最近保存时间；另存为新建；单击选中、双击载入；删除生效；dirty 标记正确。
- 帧范围改动只写 draft；刷新后 draft 还在，active 不变。
- 抽取页顶部 preset 列表只选中本次抽取范围，不改变 draft；版本列表只读，最新一版标“最新”，点击不改变任何状态。
- 合并页只列抽取记录；同几何版本合并成组；组头标签按首次保存时间；点击版本行只决定本次合并用哪版；merge 用对应 `clip.json`；上传外部视频后 merge 门控放行；有外部输入时出现“改用采用结果”链接。

### 9.3 浏览器验收

在 `1109-test-region` 上：

1. 保存 preset A（当前几何，帧 0–56）；把视口与帧改成 B，另存为 preset B。
2. 分别用 A、B 抽取，确认生成两个抽取版本。
3. 合并页出现两个几何组；组头按 A/B 的首次保存时间显示匹配标签；上传一份外部视口视频，选中 A 的版本合并，确认输出用的是 A 的 `clip.json`。
4. 切换到 B 的版本，确认合并输入提示与门控正确。
5. 刷新 pick 页，确认 draft、active、dirty 状态正确；双击 preset 能载入。
6. 点全景、拖 inner、改 fov、摇杆、改帧号时，`case.toml` mtime 不变；保存/载入/删除 preset 时变；合并页切换版本不改 `case.toml`。

### 9.4 门禁

- `uv run pytest` 全绿。
- `uv run ruff check .` 干净。
- 前端 `npm run lint`、`npm run test`、`npm run build` 全绿。
- 合并输出的字节一致性对照：同一输入与同一版本，走 `[merge] input` 与走显式 `--ai` 的结果一致。

## 10. 迁移与回滚

- 迁移前备份 `case.toml` 为 `case.toml.bak-<时间戳>`；备份不提交。
- 旧格式加载只读；第一次显式写入才改文件。
- 回滚方式：停止使用新前端，恢复备份的 `case.toml`；`clip.json` / `image.json` 从未被改，旧抽取版本可直接用。
- `derived/pick/draft.toml` 可随时删除，删除后回退 active preset，不影响 case 数据。

## 11. 风险与边界

- **PreviewStore 改造是最大风险**：预览原来按 `case.toml` 几何渲染，改成按 draft 渲染后，缓存键、`vp.png`、`get_store` 失效逻辑都要同步测；保留“draft 缺失回退 active preset”。
- **迁移风险**：旧 case 首次写入改格式；先备份，并用真实旧 case 做回归。
- **去重精度**：角度、fov、inner、帧号按写入精度比较；规则只在后端一处，前端不重复。
- **全局拼接输入**：第一版一个 `[merge] input` 指针；同一 case 多份外部结果需要后续按版本绑定。
- **preset 列表增长**：保存更新、另存为新建、支持改名与删除；不做自动清理。
- **v1 范围**：preset 与抽取选择覆盖 patch 与 patchimg；合并页版本列表与外部输入先做 patch，patchimg 的“贴回”保持现状。

## 12. 提交计划

1. 根仓库：`.gitignore` 清理、本计划与决策 97、case-model 与关联文档更新；一笔或多笔 `docs:`。
2. vrstudio：WP1 case 模型与 CLI；一笔 `aigc:` 或 `case:`。
3. vrstudio：WP2 Web 草稿与 API；一笔 `web:`。
4. vrstudio：WP3 pick 页；一笔 `前端：`。
5. vrstudio：WP4 抽取/合并页；一笔 `前端：`。
6. 根仓库：验收记录与索引；一笔 `docs:`。

每一笔提交前先跑对应测试；根仓库与子仓库分开提交，不混文档与代码。
