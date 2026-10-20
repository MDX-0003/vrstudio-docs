# 首尾帧管线开发计划（WP0–WP4）

本文是 `docs/first-last-frame-pipeline.md` §8 定稿设计的实施计划：每个工作包给出实现目标、代码切入点（文件、函数、现行行为与目标行为）、pytest 验收方案与免额度验证命令。状态：待用户批准后开工；凡消耗平台额度的步骤都单独标注"需批准"。实施顺序 WP0 → WP1 → WP2 → WP3 → WP4，WP1/WP2 可并行，WP3 依赖 WP1 的契约与 WP2 的图片任务，WP4 收尾。

依据与范围：

- 设计定稿：`docs/first-last-frame-pipeline.md` §8（三轮讨论：case 内工作台与素材通用化；派生条目与提交集侧边栏；fullredraw 互斥与路线分流）。
- 本计划不改动 fullredraw 的任何行为；不实现派生条目勾选提交（扩展位）；不实现 mid_frame 的生成入口（只进词表）。
- 每个仓库的提交门禁沿用 AGENTS 硬规则 6：`uv run pytest` 全绿 + `uv run ruff check .` 干净；提交信息中文、动词开头。

## WP0：契约文档先行（根仓库，不写代码）

按 AGENTS 硬规则 1/2，`docs/case-model.md` 先行修改，两侧代码与测试跟随。修改条目：

1. case.toml（§2）：
   - `[[assets]]` 从 gen 专属改为三条流程通用；patch/fullredraw 的既有段（`[source]`、viewport/frames、`*_pad.json`）不变。
   - 角色词表扩展：新增 `first_frame`（首帧定稿图）、`last_frame`（尾帧定稿图）、`mid_frame`（中间过渡帧，预留）、`first_frame_raw`、`last_frame_raw`（工作台输入底图，从视频抽取的原始帧）。
   - 新增可选段 `[submit]`：`selected = ["i2", "i3"]`，本 case 的提交集（素材 id 子集）；缺省表示按模式默认集（默认集规则见 WP3-3b）。
2. vrgen CLI 契约（§4）：
   - `MODE_ROLES` 增加 `firstLastFrame`：`{"video": (), "image": ("first_frame", "last_frame")}`；allMediaRef 的 image 角色集合并上述五个新角色。
   - master 回退链：第一条 edit_master 视频 → 第一条视频 → 第一条 space_ref/scene_ref 图片 → 第一条 first_frame 图片 → 第一条图片。
   - 时长规则（用户 2026-10-20 拍板，原文："时长我觉得需要设计成cli参数，因为前端有必要支持一个4~30s的下拉框来决定生成时长，因此这里的逻辑在此需求下也变得简单，默认4，有视频就设置成视频长度max即可"）：时长是 CLI 参数（`--duration`，前端 4–30s 下拉）；解析顺序为显式 `--duration` > 素材含视频时取最长视频时长向上取整（下限 4，现行为）> 纯图片默认 4。显式值按当前模式的 duration 范围（模型详情，模型 37 为 4–30）校验，越界报参数错。不做 generation.toml 持久化。
   - 新增命令 `vrgen image submit`（图片生成任务，走 mglc image generate；参数 `--job --prompt --model-id --image(可重复) --ratio --resolution --num --session-id --workdir --dry-run`；图片模型不需要 SD 合规素材 id）。`vrgen submit` 保持视频入口不动（vrstudio 现有调用契约不变）。
   - 解耦结构声明：vrgen 以**任务种类注册表**承载 mglc 的多种生成能力（video/image，未来 upscale/audio/storyboard 等），每种能力一个 `TaskKind` 声明（子命令、参数词表、素材登记需求、结果形状、闸门语义），管线与 CLI 按注册表分发；详见 WP2。
   - `vrgen result` 增加 `--index N`（图片轮次多候选时取第 N 张；缺省取第一张，兼容旧轮次）。
3. 台账格式（runs/&lt;轮次&gt;/run.json，冻结契约扩字段需在此声明）：
   - 新增可选字段 `results`（字符串数组）：图片轮次的多候选结果文件清单；视频轮次不写该字段，`result` 单值字段语义不变。
   - 新增可选字段 `params.kind`（`"video"` | `"image"`，缺省视为 `"video"`）；`backend` 字段语义不变。
   - 轮次目录前缀新增 `img-`（图片轮次 label 固定为 `img`）。
4. 首尾图合规性待验证点声明：mglc `video generate` 的 `--first-image`/`--last-image` 在 CLI 帮助中无对应 asset-id 参数，首期按"直接传路径不登记"实现；若平台在真实提交时拒绝，回落方案与结论记入台账并在本文档更新（见 §风险表 R1）。

验收：用户评审确认本节条目；两侧代码不得先于本提交动工。

## WP1：vrgen 接入 firstLastFrame 模式与时长持久化

### 实现目标

1. `--refs` 清单支持纯图片（0 视频）的 allMediaRef 与 firstLastFrame 两种提交；firstLastFrame 把两张定稿图映射到 mglc 的 `--first-image`/`--last-image`。
2. 时长解析收敛为三条规则：显式 `--duration`（按模式 duration 范围校验）> 最长视频时长（现行为）> 纯图片默认 4；空视频序列不再崩溃。
3. 无视频轮次不传 `--keep-original-sound`。
4. allMediaRef 的 task_rule 文案不再点名"参考视频"。

### 切入点（文件 → 现行行为 → 目标行为）

- `src/vrgen/refs.py`
  - `ROLES`：现五角色 → 追加五个新角色。
  - `MODE_ROLES`：现三模式 → 增加 `firstLastFrame`；`allMediaRef["image"]` 并入五个新角色。与 `vrstudio/case.py` 的镜像必须同步（两处注释互相指认）。
  - `validate_mode()`：现行"模式 {mode} 至少需要 1 个视频素材"（refs.py:137-139）→ allMediaRef 允许 0 视频；videoEdit/videoExtend 校验不变；新增 firstLastFrame 校验：不允许任何视频素材，恰好 1 条 first_frame + 1 条 last_frame，出现其他角色报错（refs 清单即提交集，槽位只有 2）。
  - `master()`：现行"没有视频即报错"（refs.py:168-176）→ 按 WP0 回退链；first_frame 图片优先于"第一条图片"兜底。
  - `ROLE_PROMPT`：追加五条文案——`first_frame`："首帧定稿图，视频的第一帧，锁定起点构图与人物外观。"；`last_frame`："尾帧定稿图，视频的最后一帧，锁定终点位置、大小与朝向。"；`mid_frame`："中间过渡帧，仅在首尾间距过大时补充。"；`first_frame_raw`/`last_frame_raw`："工作台输入底图（原始抽取帧），只提供场景与占位，不是生成素材。"
  - `_ROLE_RULES`：追加 firstLastFrame 的 `task`（"以首帧为起点、尾帧为终点生成中间表演；镜头与两端的构图锁定。"）与 `timeline`（沿用动作段写法）；allMediaRef 的 `task` 文案"锁定参考视频的空间"→"锁定参考素材的空间"。
- `src/vrgen/round/pipeline.py`（`_prepare_gen`）
  - 时长选择（pipeline.py:319-322）：现行"longest 取最长视频"分支对空视频序列会崩 → 三条规则：`conf["mglc.duration_s"]` 大于 0 时用显式值并按 `limits.duration`（min/max）校验，越界抛 `UsageError` 且文案写明该模式的合法区间；否则素材含视频取最长视频时长（现行为不变）；否则纯图片取 4。
  - `params["keep_sound"]`（pipeline.py:348）：refs 无视频时强制 False。
  - master 为图片时几何推导路径已天然成立（`canvas = pkg.canvas_size or master_plan 尺寸`），补注释说明。
- `src/vrgen/round/task.py`
  - `build_generate_argv()`：现行 `if not videos: raise`（task.py:81-82）→ 改为"videos 与 images 至少一项非空"；新增参数 `first_image`/`last_image`（`(path, asset_id|None)` 或 None）：mode 为 firstLastFrame 时按 first_frame 在前映射到 `--first-image`/`--last-image`，不产生 `--image`/`--asset-id` 对；asset_id 当前恒 None（不登记），preview 模式占位符同现有约定。素材到 flag 的映射做成 mode→策略表（数据驱动），不在函数体里堆 mode 分支。
  - `submit()`：refs 分支按 mode 分派——firstLastFrame 取 first_frame/last_frame 两条组装 first/last 参数，其余模式走现有 videos/images。
- `src/vrgen/cli.py`
  - `_apply_generation_params()`（cli.py:59-111）：校验保持"0=自动、或 ≥4"，上限不在此处写死（由 `_prepare_gen` 按模式 limits 校验）；`--duration` 是唯一时长入口，不做 generation.toml 持久化。
  - `params_show` 的 `modes` 列表（cli.py:551-567）：过滤条件从 `m.takes_video and m.mode in SUPPORTED_MODES` 改为 `m.mode in SUPPORTED_MODES`（firstLastFrame 不吃视频但要出现在列表）；`video_required` 从写死 True 改为映射 `{videoEdit: True, videoExtend: True, allMediaRef: False, firstLastFrame: False}`。

### pytest 验收（vrgen/tests/）

新增：

- `test_refs.py::test_first_last_frame_role_matrix`：firstLastFrame 接受恰好 1 first_frame + 1 last_frame；混入视频或第三素材报 `UsageError` 且文案含模式名。
- `test_refs.py::test_allmediaref_accepts_image_only`：0 视频 + N 图通过 `validate_mode`（回归"至少 1 个视频"已删除）。
- `test_refs.py::test_master_fallback_chain`：四段回退各取一例（edit_master 视频 / 首条视频 / space_ref 图片 / first_frame 图片），兜底"第一条图片"单独一例。
- `test_refs.py::test_new_role_prompt_wording`：`asset_list()` 对五个新角色输出预期首句。
- `test_mglc.py::test_build_generate_argv_first_last_frame`：argv 含 `--first-image`（first_frame 路径在前）与 `--last-image`，不含 `--video`/`--image`/`--asset-id`。
- `test_mglc.py::test_build_generate_argv_requires_any_reference`：videos 与 images 皆空时报 `AigcError`。
- `test_mglc.py::test_duration_resolution_rules`：三分支各一例——显式 `--duration 13` 取 13；无显式 + 双视频取最长；纯图片无显式取 4。附带 `test_duration_explicit_out_of_range`：显式 31 对 limits 4–30 报 `UsageError`，文案含合法区间。
- `test_mglc.py::test_prepare_round_gen_image_only`：纯图片 + duration=13 → run.params 的 `duration_s==13`、`keep_sound is False`、canvas 来自图片母版尺寸、`master` 为图片素材 id；不传 duration → `duration_s==4`。

修改（受文案与放行影响的既有断言）：

- `test_refs.py::test_counts_and_prompt_block`：`task_rule` 断言改"锁定参考素材的空间"。
- `test_mglc.py::test_prepare_round_gen_multi_assets`（:587）与 `test_cli.py::test_prompt_show_renders_with_refs_and_geometry`（:131）：同上文案替换。

### 免额度验收命令

```bash
# 两图清单 refs.json（id=i1/i2，role=first_frame/last_frame）后：
vrgen submit --job <case> --refs refs.json --mode firstLastFrame \
  --duration 13 --resolution 1080p --dry-run
# 期望：argv 含 --first-image 与 --last-image、无 --video/--image、--duration 13；
# 去掉 --duration 重跑期望 --duration 4（纯图片默认）；传 --duration 31 期望报参数错退出码 2
```

## WP2：vrgen 任务种类注册表与图片生成能力

### 接口事实与解耦决策

用户问题按原文记录：

> 图片生成使用的和视频模型是一个mglc接口吗？我希望这个拓展设计得足够解耦，不要用粗暴的if做切换，以免未来还需要调用mglc的其他模型。反之如果是一个接口那么是不是只需要调用时换一个参数即可？

事实核查结论（2026-10-20，本机 `--help` 与 vrgen 源码）：

- 不是同一个子命令：`mglc video generate` 与 `mglc image generate` 平级，参数词表互不通用——视频用 `--type/--duration/--aspect-ratio/--resolution 480p|720p|1080p`，图片无 `--type/--duration`、用 `--ratio` 与 `--resolution 1K|2K|4K`（同名 flag、两套词表）；视频参考素材要 `--video/--video-asset-id`、`--image/--asset-id` 成对登记，图片 `--image` 可重复直传无登记。"换一个参数即可"不成立。
- 生命周期同构：同一信封 `{code,data,msg}`、同一 `task status --task-id` 轮询与状态码、同一登录态与会话计费；`Mglc.call()`（client.py:86-115）本就是通用执行器，`generate()`（client.py:161-171）只是 `call("video","generate",...)` 加额度确认门的薄包装。

决策：引入**任务种类注册表（task-kind registry）**。每种 mglc 生成能力声明为一个 `TaskKind` 实现，管线与 CLI 按注册表分发（字典查表，无 if 链）；未来接入 `image upscale`、`audio *`、`storyboard` 等能力时新增一个 kind 模块注册即可，核心零改动。CLI 面保持每 kind 一个子命令入口（`vrgen submit`=视频、`vrgen image submit`=图片）：子命令入口不是 if 切换，且两套 `--resolution` 词表天然隔离在各自的 argv 构建器里。

### 实现目标

`vrgen image submit` 完成一次图片生成的完整生命周期（提交→轮询→下载全部候选→闸门→台账），候选清单可被 `vrgen result --index` 逐张取出；视频与图片轮次共用台账结构与 `vrgen status`；轮次类型识别读注册表声明而非字符串分支。

### 切入点

- 新建 `src/vrgen/round/kinds.py`：

  ```python
  @dataclass(frozen=True)
  class TaskKind:
      kind: str                        # "video" | "image"
      quota_command: tuple[str, ...]   # ("video","generate") | ("image","generate")
      build_argv: Callable             # 该子命令参数词表的唯一归属地
      needs_virtual_ip: bool           # 视频参考素材要登记；图片不要
      multi_result: bool               # 单文件（视频）| 多候选（图片 --num）
      gate: Callable                   # 闸门语义：视频解码/尺寸 vs 图片解码
  KINDS: dict[str, TaskKind] = {"video": ..., "image": ...}
  ```

  video kind 本工作包只做"注册化收口"——包住现有 `task.py`/`pipeline.py` 的函数，不重写视频路径；image kind 为新实现。
- `src/vrgen/platform/client.py`：把 `generate()` 的额度确认门一般化为私有 `_spending(subcommand_args, confirm, timeout)`；`generate()` 与新增的 `image_generate(args, confirm)` 都调它——"花钱必须 confirm"的规则全局只有一份。
- 新建 `src/vrgen/round/image.py`（image kind 实现本体）：
  - `build_image_argv(*, prompt, model_id, images, ratio, resolution, num, session_id)`：产出 `--prompt/--model-id/--image(可重复)/--ratio/--resolution/--num/--session-id`；`--resolution` 白名单 `1K|2K|4K` 在此校验（与视频档位词表的隔离点）。
  - `prepare_image_round(conf, ...)`：label 固定 `img`，`params.backend="mglc"`、`params.kind="image"`；无 virtual-ip 环节（读 `KINDS["image"].needs_virtual_ip`）。
  - `execute_image_round(...)`：提交 → `wait_task` 轮询 → `fetch_all`（task status 的多 URL 全部下载为 `result_1.png`…`result_N.png`，复用 `result_urls()`——其 `"url" in key` 兜底对图片 URL key 成立，测试钉住）→ 闸门（每张 `probe_image` 解码成功即 ok）→ `run.results = [...]`。
- `src/vrgen/round/ledger.py`：`Run` 增加 `results: list[str] | None`；轮次类型以 `params.kind` 为准，读旧 run.json 缺省补 `"video"`（`backend` 字段保留原语义不动）。
- `src/vrgen/cli.py`：`image submit` 子命令走 `KINDS["image"]`；`result --index` 与 `status` 的展示差异（img 标记、多候选计数）读 `KINDS[kind]` 的声明字段，不写 backend/kind 字符串分支。

### pytest 验收（vrgen/tests/）

- `test_kinds.py::test_registry_declares_both_kinds`：KINDS 键集、quota_command、needs_virtual_ip、multi_result 声明与预期一致（视频：要登记、单结果；图片：不登记、多候选）。
- `test_mglc.py::test_build_image_argv_shape`：flag 顺序与 `--image` 可重复；resolution 白名单外报错。
- `test_mglc.py::test_client_image_generate_requires_confirm`：`image_generate()` 不带 `confirm=True` 抛 `MglcError`（与 `generate()` 同一道门）。
- `test_mglc.py::test_result_urls_accepts_image_payload`：构造 key 为 `imageUrl`/`imgUrlList` 的伪 payload，断言 `result_urls()` 收齐且水印变体排后。
- `test_mglc.py::test_image_round_lifecycle`：注入 mock client（提交返回 task id、两次轮询后 succeeded、payload 含 4 个 URL、opener 返回伪 PNG 字节）→ 断言 `run.results` 长度 4、gate verdict ok、stage 推进到 checked。
- `test_cli.py::test_image_submit_dry_run`：dry-run 打印 argv、不产生平台调用（transcript 为空）。
- `test_cli.py::test_result_index_copies_nth_candidate`：`--index 3` 拷贝 `result_3.png`；不带 `--index` 拷第一张。
- `test_cli.py::test_status_lists_image_rounds`：img 轮次在 `status` 输出中带 img 标记。
- 回归：`test_cli.py` 现有 `result`/`status` 测试全绿（旧轮次 run.json 无 `kind`/`results` 字段不炸，按 video 单结果处理）。

### 免额度验收命令

```bash
vrgen image submit --job <case> --model-id 44 --ratio 16:9 --resolution 2K --num 4 \
  --image <i2.png> --image <i1.png> --prompt "<§4.1 首帧提示词>" --dry-run
```

真实提交一次（需批准）：确认 mglc 接受本地路径直传、task status 返回 4 个 URL。

## WP3：vrstudio 侧（case 通用化、提交集、patch 分支、web）

### 3a case 模型（`src/vrstudio/case.py`）

- `load()`：现行 `flow != "gen" and assets` 报错（case.py:193-194）→ 删除该限制；`save()` 的 assets 写块从 gen 分支提出，任意 flow 都写。
- `MODE_ROLES`、`ROLES`/`ROLE_LABELS`：与 vrgen refs.py 同步（含 firstLastFrame 与五个新角色；LABELS 补中文说明）。
- `Case.master()`：同步 WP0 回退链。
- 新增 `submit_selected`（`list[str] | None`）字段 + `[submit] selected` 的读写与校验（id 必须存在于 assets）。
- 测试（`tests/test_case.py`）：
  - `test_assets_allowed_for_all_flows`：patch/fullredraw case 写入并读回 assets。
  - `test_submit_selected_roundtrip`：保存/读取/非法 id 报错。
  - `test_master_image_fallback`：无视频时回退链行为。

### 3b 生成入口（`src/vrstudio/cli/generate.py`）

- `resolve_package` gen 分支（generate.py:92-106）：`master()` 可能是图片 → 不再 `probe(video)`、canvas/source 返回 None；`submit` 组装 argv 时不带 `--canvas/--source`（vrgen 从图片母版自推）。报错文案"至少需要 1 个视频素材"改为按模式的说法。
- refs payload（generate.py:200-210）：现行全量 assets → 按 `case.submit_selected` 过滤；未设置时按模式默认集——videoEdit/videoExtend：edit_master 视频 + 全部 subject_ref；allMediaRef：全部素材；firstLastFrame：恰有一对 first_frame/last_frame 时默认选之，多于一对报"请手动选择"。
- patch 分支新增 firstLastFrame 变体：`resolve_package` 检测透传的 `--mode firstLastFrame` 时，走 refs 路径（canvas/source 仍取 clip.json viewport，模板用 `gen-multi`，不传 `--input`）；videoEdit 路径原样。
- 测试（`tests/test_generate.py`）：
  - `test_resolve_gen_image_master_omits_canvas`：图片母版 → argv 无 `--canvas/--source`、refs 含两图。
  - `test_submit_refs_filtered_by_selected`：`[submit] selected` 只含两 id → refs JSON 只装两条。
  - `test_submit_firstlast_default_selection`：恰一对定稿帧默认选中；两对时报错。
  - `test_patch_firstlast_branch_builds_refs`：patch case + mode=firstLastFrame → argv 走 `--refs`、`--canvas` 为 clip.json viewport 尺寸、模板 gen-multi。

### 3c web 后端（`src/vrstudio/web/app.py`）

- 素材 API（`/api/case/<name>/assets`）从 gen 限定放开到三流程；派生条目接口 `GET /api/case/<name>/derived`（返回源视频与当前 clip/pad 产物的只读描述，不进 assets）。
- `[submit]` 读写：`GET/PUT /api/case/<name>/submit`。
- 抽帧接口：`POST /api/case/<name>/extract-frames`（body 可选 `{t_first, t_last}` 秒，缺省取 clip 首尾时刻）→ ffmpeg 抽两帧（**不做任何缩放，按源分辨率导出**）→ `add_assets` 以 `first_frame_raw`/`last_frame_raw` 角色入素材。仅 patch 流可用。
- 工作台接口：`POST /api/case/<name>/keyframe/run`（body：step=first|last、model_id、prompt、参考图 asset id 列表 → 组装 `vrgen image submit` 子进程，走现有任务队列）；`GET /api/case/<name>/keyframe/rounds`（读台账 run.json 的 `results` 列举候选缩略图）；`POST /api/case/<name>/keyframe/pick`（round + index + 目标角色 → `vrgen result --index` 拷出 + `add_assets` 写 first_frame/last_frame）。
- 生成闸门（app.py:589-595）：`has_video` 判定改按模式——videoEdit/videoExtend 需视频；allMediaRef 需 ≥1 素材；firstLastFrame 需恰一对定稿帧；fullredraw 额外不出现工作台与新模式入口。
- `_op_argv`（app.py:1011-1025）：submit 增加可选 duration 透传（前端下拉框选中值；"自动"不传该字段）。
- 测试（`tests/test_web_console.py`）：上述每个端点一条（沿用现有 mock `_vrgen_json`/子进程 的测试风格），加 `test_generate_gate_mode_aware`。

### 3d web 前端（static/ + templates/partials）

- 素材侧边栏组件（由 assets.js 演化）：三流程生成页统一挂载、可展开；区块一"流程产物（派生·只读）"、区块二"文件素材"（增删/角色/排序沿用现功能）；提交集勾选 + 模式感知校验提示；勾选变化触发 `@VideoN/@ImageN` 重编号（旧号→新号映射改写 prompt-vars 变量值，被移除素材的标记标红不删）与 `prompt show` 实时预览；变量值就地编辑（复用 prompt save）。
- gen 向导步骤定义：由"素材→生成"改为"生成"一步（素材并入侧边栏），`STEPS` 数据驱动表同步。
- 关键帧工作台页（新 partial + keyframe.js）：输入区（派生 clip 抽帧按钮 / 上传帧 + 三视图引用）、两步重绘（首帧→尾帧链式，参考图顺序 UI 明示 图1/图2/图3 对应 §4 提示词）、候选网格（4 张，点击放大）、挑选落素材（角色 first_frame/last_frame）、提示词编辑器预填 `first-last-frame-pipeline.md` §4 模板。
- 生成参数面板增加时长下拉框（WP0 时长规则的前端面）：选项 = "自动" + 4…30 整数；"自动"不传 `--duration`，后端按规则推导（含视频取最长视频时长，纯图片取 4）；纯图片模式下拉缺省落在 4 并显示推导说明，避免无感默认。
- wizard.js 校验文案按模式替换（"至少 1 个视频"仅对 videoEdit/videoExtend 出现）。
- 验收：浏览器手测清单——① patch case 建好选区并 extract；② 生成页展开侧边栏看到派生产物；③ 工作台从 clip 抽帧成功且帧分辨率等于 clip；④ 首帧 4 候选出图、挑选入素材；⑤ 尾帧带首帧产物重绘、挑选；⑥ 勾选两定稿帧时提示词预览的 `@ImageN` 编号正确联动；⑦ 提交模式切 firstLastFrame 后"检查提交命令"（免额度 `--check`）通过；⑧ fullredraw 生成页无工作台与新模式入口。

### 3e 抽帧 helper（`src/vrstudio/media/`）

- 新建 `frames.py::extract_frame(video, t_seconds, out_png)`：调 bin\ffmpeg `-ss <t> -frames:v 1`，不缩放。
- 测试：合成 2 秒测试视频抽帧，断言输出尺寸等于源分辨率、PNG 可被 `_imread` 读取（复用 web 层 cv2 断言风格）。

## WP4：几何对齐与端到端验收

1. **merge 尺寸行为核查（先读后改）**：读 `vrstudio/patch/merge` 对结果视频尺寸的假设。若假定 result 尺寸 == clip 尺寸，则在 merge 前增加归一步骤（成片等比缩放至 clip 尺寸，宽高比不一致时按几何中心裁切），归一逻辑放进现有归一模块并补像素基线测试（合成 crf 0 视频、maxdiff==0 断言，满足 AGENTS 硬规则 4）。
2. **定稿帧几何裁切**：工作台挑选落素材时按 case 几何裁切（patch 用 clip.json viewport 比例；gen 整幅按帧自身比例不裁），裁切用 ffmpeg 精确像素裁剪，测试断言输出宽高比与契约一致。
3. **端到端免额度回归**：
   - gen firstLastFrame：`vrstudio generate submit --case <纯图片case> --check`（argv 三条 `--image` 场景换成 `--first-image/--last-image`）。
   - patch firstLastFrame：同上走 clip 几何。
   - 旧路径回归：现有 gen allMediaRef 与 patch videoEdit 的 `--check` 输出与改造前一致（防行为漂移）。
4. **真实提交验收（需批准，逐轮确认）**：按 §8.1 路线分流各跑一轮——gen 整幅帧一条、patch 区域帧一条；验收表沿用 `first-last-frame-pipeline.md` §7；每轮台账记录提示词与结果对照。

## 风险与未验证点

- R1 首尾图合规性：`--first-image/--last-image` 是否需要 SD 合规登记未知（CLI 无对应 flag，首期直传路径）。首次真实提交验证；若平台拒绝，登记 virtual-ip 后重试，仍拒绝则升级为平台工单并暂停该模式真实提交（`--dry-run` 不受影响）。
- R2 图片 URL 提取：mglc image generate 的 task status payload 形状未实测，`result_urls()` 的 key 兜底规则需在首次真实提交时钉住（WP2 已有伪 payload 测试，真实形状以台账为准修正）。
- R3 默认图片模型：首期默认 专业图片-2.5（id 44，局部编辑强、13 参考图），备选 Seedream 4.5（id 25，customWH 可出精确宽高）；工作台模型下拉开放两档。
- R4 成本：图片步 `--num 4` ×2 帧 + 视频步 1 次；工作台 UI 在提交按钮上明示本次消耗构成。
- R5 `@标记` 自动重编号的边界：仅做同类型内重号（Video/Image 各自连续），跨类型不变；无法映射的标记保留原文并标红。

## 提交切分与门禁

1. 根仓库：`docs: 立项首尾帧管线契约变更`（WP0）。
2. vrgen：`vrgen: 接入 firstLastFrame 模式与时长规则收敛`（WP1）；`vrgen: 增加任务种类注册表与图片生成`（WP2）。
3. vrstudio：`vrstudio: 素材列表通用化与提交集`（WP3a+3b）；`vrstudio: 首尾帧工作台与素材侧边栏`（WP3c+3d+3e）；`vrstudio: 成片几何归一对齐`（WP4-1/2）。
4. 每笔提交前：对应仓库 `uv run pytest` 全绿 + `uv run ruff check .` 干净；WP3 起另跑 WP4-3 的三条免额度 `--check` 回归。
