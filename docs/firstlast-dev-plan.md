# 首尾帧管线开发计划（WP0–WP4）

本文是 `docs/first-last-frame-pipeline.md` §8 定稿设计的实施计划：每个工作包给出实现目标、代码切入点（文件、函数、现行行为与目标行为）、pytest 验收方案与免额度验证命令。状态：2026-10-20 按审查结论修订，并增加全链路 16:9 几何基线（见 §修订记录）；同日用户批准整体方案，WP0 契约文档与 WP1–WP4 代码均已实现并通过两侧 pytest 与 ruff，真实图片/首尾帧提交仍待用户批准。2026-10-21 按决策 33 修订提交集与流程产物口径：只认用户勾选、没有默认集、clip/pad 为候选、mask 自动附带、raw 帧仅工作台，patch 的 extract 直接产出 clip 首尾原始帧（见 §2026-10-21 修订）。凡消耗平台额度的步骤都单独标注"需批准"。实施顺序 WP0 → WP0.5 → WP1 → WP2 → WP3 → WP4，WP1/WP2 可并行，WP3 依赖 WP1 的契约与 WP2 的图片任务，WP4 收尾。

依据与范围：

- 设计定稿：`docs/first-last-frame-pipeline.md` §8（三轮讨论：case 内工作台与素材通用化；流程产物与提交集侧边栏；fullredraw 互斥与路线分流）。
- 本计划不改动 fullredraw 的流程行为；流程产物按决策 33 作为可勾选候选（不再只读）；不实现 mid_frame 的生成入口（只进词表）。
- 每个仓库的提交门禁沿用 AGENTS 硬规则 6：`uv run pytest` 全绿 + `uv run ruff check .` 干净；提交信息中文、动词开头。

## 修订记录（2026-10-20，审查后）

上一轮审查指出八处会在实施中返工或直接报错的问题，本次修订逐条落在下面的工作包里。修订的同时同步了父文档 `first-last-frame-pipeline.md` §8.4、§8.5、§8.6、§8.7 与 `docs/case-model.md` §2 的冲突段落。

| # | 问题 | 结论（落点） |
|---|---|---|
| 1 | 时长持久化表述三处互相矛盾 | 统一为"时长规则收敛"，不存在持久化（WP0-2、WP1 标题） |
| 2 | 提交集存放层与默认集规则两份文档各写一套 | 定为 case.toml `[submit]`，默认集只认"恰一对"（2026-10-21 由决策 33 改为没有默认集）；角色覆盖首期不做（WP0-1、WP3-3a、R6） |
| 3 | `params show` 的 `takes_video` 闸门会挡住 firstLastFrame | WP1 把它拆成"列表过滤"与"传了含视频的 `--refs` 却不接受"两件事（WP1-7） |
| 4 | 图片提交会被视频的 `--resolution` 白名单拒绝 | 参数校验按 task kind 分派词表（WP2-6） |
| 5 | `resolve_package` 返回 None 会打穿 web | 图片母版照常返回宽高，只有送生成的视频位置为 None；`_generation_params` 同步降级（WP3-3b、3c） |
| 6 | patch firstLastFrame 的模板选择没落到所有入口 | `resolve_package` 收 mode，模板按 (flow, mode) 选（WP3-3b） |
| 7 | `TaskKind` 注册表缺生命周期入口 | 注册表收 prepare/execute，CLI 只查表分发（WP2-1） |
| 8 | assets 通用化的改动面被低估 | 增删改排与 check 一并放开，测试覆盖（WP3-3a） |
| 9 | merge 的比例隐患与上游几何没有统一契约 | 首期全链路固定 16:9；比例一致只做等比缩放、不裁切，比例不一致直接报错；裁切只留给历史/外部导入（WP0.5、WP4） |

## 2026-10-21 修订（决策 33）

上一版把提交集写成「用户勾选优先，未显式选择时按模式取默认集」，并把流程产物当作只读派生条目。2026-10-21 讨论推翻这两点，下面六条覆盖对应工作包里的旧写法：

| # | 旧写法 | 新做法（落点） |
|---|---|---|
| 1 | `[submit] selected` 缺省按模式取默认集 | 没有默认集，缺省等于空集；旧 case 首次打开重新勾选（WP0-1、WP3-3b） |
| 2 | 流程产物只读，装配器自动带上母版/mask | clip/pad 与文件素材同为候选，勾选才提交；mask 自动附带但不进候选；没有 `derived` 标记（WP3-3a/3c/3d） |
| 3 | patch firstLastFrame 靠"从 clip 抽帧"按钮 | `vrstudio extract` 直接导出 `first_frame_raw.png`/`last_frame_raw.png`，工作台直接使用（WP3-3e、CLI extract） |
| 4 | firstLastFrame 的不足由后端报错 | 前端在点击生成时检查勾选里是否恰有一对首尾帧，不足或超出就弹错、不发请求；vrgen 保留同样的提交前校验（WP3-3c/3d） |
| 5 | refs 清单用 `xv1`/`xi1` 区分派生条目 | id 统一为字母开头的字符串，流程产物用 `clip`/`mask`/`pad`/`pad_mask`（WP3-3a/3b） |
| 6 | videoEdit 自动用流程视频，不需要勾选 | 三流程都只提交勾选项；patch 的 clip 要用户勾选，mask 自动附带，空选集由前端拦截（WP3-3b/3d） |

## WP0：契约文档先行（根仓库，不写代码）

按 AGENTS 硬规则 1/2，`docs/case-model.md` 先行修改，两侧代码与测试跟随。修改条目：

1. case.toml（§2）：
   - `[[assets]]` 从 gen 专属改为三条流程通用；patch/fullredraw 的既有段（`[source]`、viewport/frames、`*_pad.json`）不变。
   - 角色词表扩展：新增 `first_frame`（首帧定稿图）、`last_frame`（尾帧定稿图）、`mid_frame`（中间过渡帧，预留）、`first_frame_raw`、`last_frame_raw`（工作台输入底图，由 extract 从 clip 首尾导出）。
   - 新增可选段 `[submit]`：`selected = ["i2", "i3"]`，本 case 的提交集（候选 id 子集）；没有默认集，缺省等于空集，勾选才提交（规则见 WP3-3b）。
     - **存放层定为 case.toml，理由三条**：
       ① 提交集描述的是本 case 素材里哪几项参与提交，属于 case 自己的事实；跟着 case 目录走，复制目录或迁移机器时不丢。
       ② 放 `runs/<job>/generation.toml` 是另一个仓库（vrgen）的台账目录，清空台账或换机器就丢，而 case.toml 与 `[[assets]]` 同文件，材料与选择在同一个可审计位置。
       ③ 写入只发生在 vrstudio（侧边栏勾选），vrgen 只读 refs JSON；契约上不需要 vrgen 认识这个字段，也不会出现两处真源。
     - **角色覆盖首期不做**（R6，待拍板）：`selected` 只存素材 id，提交时沿用素材自身角色。临时改角色会让"素材列表是什么角色"和"这次提交用什么角色"分成两套事实，`@ImageN` 编号与角色矩阵校验要同时读两份；现有素材卡片的角色下拉（`set_asset_role`）已经能改角色，够用。若后续需要，再立项把字段扩成 `selected = ["i2:first_frame"]` 形式。
2. vrgen CLI 契约（§4）：
   - `firstLastFrame` 加入支持模式，并保留它自己的语义规则：不允许视频，恰好一张 `first_frame` 加一张 `last_frame`，首帧在前。按模式的角色数量矩阵在统一提交改造中退役（决策 33）；2026-10-21 之前的实现仍保留 `MODE_ROLES` 作为过渡。
   - master 回退链：第一条 edit_master 视频 → 第一条视频 → 第一条 `space_ref`/`scene_ref` 图片 → 第一条 first_frame 图片 → 第一条图片。第三级里 `space_ref` 与 `scene_ref` 同级，按清单顺序取第一个，不设角色优先级（避免镜像出第三种排序规则）。
   - 时长规则（用户 2026-10-20 拍板，原文："时长我觉得需要设计成cli参数，因为前端有必要支持一个4~30s的下拉框来决定生成时长，因此这里的逻辑在此需求下也变得简单，默认4，有视频就设置成视频长度max即可"）：时长是 CLI 参数（`--duration`，前端 4–30s 下拉）；解析顺序为显式 `--duration` > 素材含视频时取最长视频时长向上取整（下限 4，现行为）> 纯图片默认 4。显式值按当前模式的 duration 范围（模型详情，模型 37 为 4–30）校验，越界报参数错。
   - **不做 generation.toml 持久化**。这是本条的唯一口径：`generation.toml` 不再保存"希望下次还用这个时长"的草稿；运行时长的唯一入口是 `--duration`，实际采用值只记在轮次台账 `run.json` 的 `params.duration_s`（审计事实，不是偏好），前端下拉每次提交显式传值。`_apply_generation_params` 的 `duration_s` 键保留，只承接本次调用的显式值。
   - 新增命令 `vrgen image submit`（图片生成任务，走 mglc image generate；参数 `--job --prompt --model-id --image(可重复) --ratio --resolution --num --session-id --workdir --dry-run`；图片模型不需要 SD 合规素材 id）。`vrgen submit` 保持视频入口不动（vrstudio 现有调用契约不变）。
   - 解耦结构声明：vrgen 以**任务种类注册表**承载 mglc 的多种生成能力（video/image，未来 upscale/audio/storyboard 等），每种能力一个 `TaskKind` 声明（子命令、参数词表、素材登记需求、结果形状、闸门语义、本地与远程生命周期入口），管线与 CLI 按注册表分发；详见 WP2。
   - `vrgen result` 增加 `--index N`（图片轮次多候选时取第 N 张；缺省取第一张，兼容旧轮次）。
3. 台账格式（runs/&lt;轮次&gt;/run.json，冻结契约扩字段需在此声明）：
   - 新增可选字段 `results`（字符串数组）：图片轮次的多候选结果文件清单；视频轮次不写该字段，`result` 单值字段语义不变。
   - 新增可选字段 `params.kind`（`"video"` | `"image"`，缺省视为 `"video"`）；`backend` 字段语义不变。
   - 轮次目录前缀新增 `img-`（图片轮次 label 固定为 `img`）。注意 `run_key` 目前以母版文件哈希与渲染后提示词算键（`ledger.py:100`），纯图片轮次母版是图片，`run_key` 的签名与实现同步放宽为"任意参考素材"，否则图片轮次无法创建。
4. 首尾图合规性待验证点声明：mglc `video generate` 的 `--first-image`/`--last-image` 在 CLI 帮助中无对应 asset-id 参数，首期按"直接传路径不登记"实现；若平台在真实提交时拒绝，回落方案与结论记入台账并在本文档更新（见 §风险表 R1）。
5. `docs/case-model.md` §2 表格下方"三种模式都要求至少 1 个视频素材"改为按模式表述（videoEdit/videoExtend 恰好 1 视频；allMediaRef 至少 1 素材、视频可为 0；firstLastFrame 恰好 2 图片、0 视频）；母版与时长说明同步改成 WP0-2 的回退链与三条时长规则。同时声明首期几何基线：firstLastFrame 仅接受 16:9 的 patch viewport（规范像素 1920×1080）与 16:9 的 gen 图片；非 16:9 的 patch case 继续用 videoEdit，切 firstLastFrame 时提交前报参数错（WP0.5）。

验收：2026-10-20 用户批准本节条目；`docs/case-model.md` 已在 WP0 中修改，两侧代码从 WP1 起可以动工。

## WP0.5：全链路几何基线（首期固定 16:9）

首期 firstLastFrame 的几何只认一条规则：**clip / 首尾定稿帧 / 视频成片 / merge 目标全部按 16:9**。任何一环不是 16:9，流程在提交前停下来，而不是让 merge 在生成后裁切补救。这条规则同时覆盖 gen 与 patch；fullredraw 不接入 firstLastFrame，不受约束。

### 角色与目标尺寸

- **patch viewport（firstLastFrame）**：宽高比必须是 16:9；首期规范像素尺寸为 1920×1080（1080p 档）。clip 按该 viewport 抽取，天然是 16:9。
- **gen**：没有 viewport，图片步固定 `--ratio 16:9`，视频成片按首尾图输出 16:9。上传底图不强制 16:9（图片模型会按目标比例重绘），但需要精确构图时应在进入工作台前按 16:9 取景。
- **图片工作台**：`--ratio` 由上下文推导（patch 取 viewport，gen 固定 16:9），首期不在 UI 暴露其它比例；`--resolution` 默认取模型详情里的最高档（当前专业图片-2.5 与 Seedream 4.5 都是 4K），允许用户下调。首帧与尾帧必须同模型、同 ratio、同 resolution，落素材时断言宽高一致。
- **firstLastFrame**：`--resolution 1080p`，不传 `--aspect-ratio`（模型详情里该模式 `ratios` 为空，输出跟随首尾图）。
- **merge（规范组合）**：目标 1920×1080；AI 成片预期也是 1920×1080，正常路径是 identity。平台若返回同比例的其它尺寸，只做等比缩放；返回非 16:9 则直接报错，不静默拉伸。图片用 4K 不会改变成片档位——firstLastFrame 最高只到 1080p，4K 提高的是关键帧精度，不是最终视频分辨率。16:9 只保证不变形；identity 只在 viewport 与成片都是 1920×1080 时成立，其它 16:9 尺寸走等比缩放（source ERP 不足时会放大），不裁切。

### 为什么不是让 clip 对齐图片模型的输出

图片模型只负责出同比例的关键帧，不负责匹配 clip 的绝对像素：

- **对齐对象是视频成片，不是图片。** merge 只读取视频模型返回的文件；图片模型的 4K 输出（如 3840×2160）不会被 merge 直接看到。把 viewport 做成图片尺寸反而会让 1920×1080 的成片在 merge 多一次上采样。
- **比例相同即可，绝对尺寸可以不同。** 2048×1152 → 1920×1080 是均匀缩放，不会变形；1920×1080 → 1920×1052 才会因为比例不同被压扁。
- **图片模型无法保证任意比例。** 专业图片-2.5 只支持 `1:1、9:16、16:9、3:2、2:3、3:4、4:3、21:9`；Seedream 4.5 虽然有 `customWH`，但 mglc CLI 没有暴露宽高参数。因此首期只取 16:9，不承诺任意比例。
- **图片 CLI 不存在“输出精确等于 clip”的手段。** 图片只有 `--ratio` 与 `--resolution`，没有 `--width/--height`；反过来让 viewport 去追图片尺寸，也只会把问题从比例变成分辨率档位。

### 首期规则

1. **patch 选区**：新建 case 的默认选区为 16:9，首期首尾帧工作台只在 16:9 选区下开放；`extract args` 仍接受任意 `vpw/vph`，以兼容历史与 videoEdit 流程，进入 firstLastFrame 前再校验。首期规范像素 1920×1080；source ERP 分辨率不足时按实际可用尺寸，但比例必须保持 16:9。
2. **非 16:9 的历史 case**：videoEdit 原样可用，不迁移、不自动裁切；要试 firstLastFrame，就重新选区为 16:9 并 extract 新版本，旧 extract 与旧轮次保留。
3. **图片步**：`--ratio` 由后端推导，前端传入的其它比例被忽略或报错；首期固定 16:9。`--resolution` 默认取模型详情里的最高档（当前两个模型都是 4K），允许下调；比例保持不变，图片实际像素尺寸不要求等于 clip。4K 仍受平台参考图限制（300–6000 px、30MB，见模型详情），超限时由 vrgen 的 fit 处理或改用压缩后的 JPEG，比例不变（R9）。
4. **首尾帧一致性**：同一对 `first_frame` / `last_frame` 的宽高必须相同；不一致时报错并要求重出图，不做自动裁切。
5. **firstLastFrame 提交**：`--resolution 1080p`，不传 `--aspect-ratio`；首尾图路径分别映射 `--first-image` / `--last-image`。
6. **merge**：先校验 `ai_aspect` 与 `vp_aspect`，相对容差 0.1%（约等于 1080p 下 1 像素的取整误差）；超差报错并打印期望/实际宽高。比例一致时只做等比缩放；首期 16:9 + 1080p 的组合应命中 identity。中心裁切归一仅保留给历史非 16:9 case 或外部导入视频，且必须显式开启并记录原因；firstLastFrame 正常路径不触发裁切。
7. **父文档同步**：`first-last-frame-pipeline.md` §8.5 与 §8.6 按本节改写，删除“工作台按 clip 比例裁切”作为主路径的表述；裁切降级为历史/外部导入的兜底。

### 需要真实验证的一点

`mglc model --type video --model-id 37` 只声明 firstLastFrame 支持 480p/720p/1080p，**没有输出宽高字段**。因此首期必须真实提交一次 16:9 首尾帧 + 1080p（需批准），记录平台返回的实际 `width/height`：

- 返回 1920×1080：规范落地，merge 走 identity。
- 返回同比例的其它尺寸：把规范像素改成实际尺寸，或接受一次等比缩放；二者都不裁切。
- 返回非 16:9：暂停 firstLastFrame 真实提交，回到设计重新确认平台行为，不在 merge 里用裁切掩盖。

### 验收（免额度，WP3/WP4 完成后统一跑）

- `test_patch_firstlast_requires_16_9_viewport`：1920×1080 的 patch case 通过；1920×1052 报 `GenError`，文案要求重新选区/抽取。
- `test_keyframe_ratio_derived_16_9`：patch 工作台请求的 `--ratio` 等于 viewport 推导值（16:9）；gen 固定 16:9；前端传 4:3 被忽略或报错。
- `test_keyframe_pick_rejects_mismatched_pair`：首尾帧宽高不一致时报错，不进入提交。
- `test_keyframe_defaults_to_highest_resolution`：工作台请求不传分辨率时，`--resolution` 取当前模型 `resolutions` 的最高档（当前 4K）；前端显式传 2K 时按 2K 发起，比例不变。
- `test_merge_rejects_aspect_mismatch`：viewport 16:9 + AI 成片 4:3 → 报错，不产出文件。
- `test_merge_identity_16_9`：viewport 1920×1080 + AI 1920×1080 → 像素基线 `maxdiff==0`（合成 crf 0 视频）。
- `test_merge_uniform_scale_same_aspect`：viewport 1920×1080 + AI 1280×720 → 输出 1920×1080，无裁切；用合成标记点断言几何位置按比例缩放。
- 旧路径回归：patch videoEdit 在 1920×1052 上仍按原行为输出，不受 16:9 约束。

## WP1：vrgen 接入 firstLastFrame 模式与时长规则收敛

### 实现目标

1. `--refs` 清单支持纯图片（0 视频）的 allMediaRef 与 firstLastFrame 两种提交；firstLastFrame 把两张定稿图映射到 mglc 的 `--first-image`/`--last-image`。
2. 时长解析收敛为三条规则：显式 `--duration`（按模式 duration 范围校验）> 最长视频时长（现行为）> 纯图片默认 4；空视频序列不再崩溃。
3. 无视频轮次不传 `--keep-original-sound`。
4. allMediaRef 的 task_rule 文案不再点名"参考视频"。

### 切入点（文件 → 现行行为 → 目标行为）

- `src/vrgen/refs.py`
  - `ROLES`：现五角色 → 追加五个新角色。
  - `MODE_ROLES`：现三模式 → 增加 `firstLastFrame`；`allMediaRef["image"]` 并入五个新角色。与 `vrstudio/case.py` 的镜像必须同步（两处注释互相指认）。
  - `validate_mode()`：现行"模式 {mode} 至少需要 1 个视频素材"（refs.py:137-139）→ allMediaRef 允许 0 视频；videoEdit/videoExtend 校验不变；新增 firstLastFrame 校验：不允许任何视频素材，恰好 1 条 first_frame + 1 条 last_frame，出现其他角色报错（refs 清单即提交集，槽位只有 2）。`validate_counts` 对 firstLastFrame 直接放行（模式自身就是 2 槽）；`load_refs` 的"assets 非空"不构成障碍。
  - `master()`：现行"没有视频即报错"（refs.py:168-176）→ 按 WP0 回退链；first_frame 图片优先于"第一条图片"兜底。
  - `duration_source(mode)`（refs.py:179）：现返回 `longest`/`master` 二值 → 改为返回模式的时长基准（`longest` | `master` | `none`），firstLastFrame 为 `none`，`_prepare_gen` 据此跳过"取母版时长"。
  - `ROLE_PROMPT`：追加五条文案——`first_frame`："首帧定稿图，视频的第一帧，锁定起点构图与人物外观。"；`last_frame`："尾帧定稿图，视频的最后一帧，锁定终点位置、大小与朝向。"；`mid_frame`："中间过渡帧，仅在首尾间距过大时补充。"；`first_frame_raw`/`last_frame_raw`："工作台输入底图（原始抽取帧），只提供场景与占位，不是生成素材。"
  - `_ROLE_RULES`：追加 firstLastFrame 的 `task`（"以首帧为起点、尾帧为终点生成中间表演；镜头与两端的构图锁定。"）与 `timeline`（沿用动作段写法）；allMediaRef 的 `task` 文案"锁定参考视频的空间"→"锁定参考素材的空间"。
- `src/vrgen/round/pipeline.py`（`_prepare_gen`）
  - 时长选择（pipeline.py:319-322）：现行"longest 取最长视频"分支对空视频序列会崩 → 三条规则：`conf["mglc.duration_s"]` 大于 0 时用显式值并按 `limits.duration`（min/max）校验，越界抛 `UsageError` 且文案写明该模式的合法区间；否则素材含视频取最长视频时长（现行为不变）；否则纯图片取 4（firstLastFrame 恒走此支）。`duration_source` 为 `none` 时不构造 `duration_ref`。
  - `params["keep_sound"]`（pipeline.py:348）：refs 无视频时强制 False。
  - `_prepare_gen` 的 validator 读取（pipeline.py:256）：firstLastFrame 没有 `refVideoValidator`，`limits.ref_video_limits()` 会抛 `AigcError`；改为 `video_validator = limits.ref_video or {}`（或 `if limits.takes_video`），`max_pixels`/`max_bytes` 缺省 0。`ref_image_limits()` 对无 validator 的模式已返回 `{}`。
  - `execute_round` 的素材登记（pipeline.py:430-446）：firstLastFrame 跳过 `ensure_assets`。模型详情对 firstLastFrame 标了 `supportVirtualIp: 是`，但 CLI 的 `--first-image`/`--last-image` 没有对应的 asset-id 参数，登记出的 id 无处可传；首尾图直接按路径提交。若真实提交因未登记被拒，按 R1 回退，不在首期自建登记流程。
  - master 为图片时几何推导路径已天然成立（`canvas = pkg.canvas_size or master_plan 尺寸`），补注释说明；`refs_params[].upload` 仍是素材自身路径。
- `src/vrgen/round/task.py`
  - `build_generate_argv()`：现行 `if not videos: raise`（task.py:81-82）→ 改为"videos、images、first_image/last_image 至少一项非空"；新增参数 `first_image`/`last_image`（`(path, asset_id|None)` 或 None）：mode 为 firstLastFrame 时按 first_frame 在前映射到 `--first-image`/`--last-image`，不产生 `--image`/`--asset-id` 对；asset_id 当前恒 None（不登记），preview 模式占位符同现有约定。素材到 flag 的映射做成 mode→策略表（数据驱动），不在函数体里堆 mode 分支。firstLastFrame 强制不写 `--aspect-ratio`（模型详情 `ratios` 为空，输出跟随首尾图；调用方即使传了非 auto 值也忽略并记一条 warning）。
  - `submit()`：refs 分支按 mode 分派——firstLastFrame 取 first_frame/last_frame 两条组装 first/last 参数，其余模式走现有 videos/images。
  - `result_urls()`：`_URL_HINTS`（task.py:37）加入 `.png`/`.jpg`/`.jpeg`/`.webp`，并接受 key 含 `image` 的结果 URL。这是 WP2 图片轮次能列出候选的前提，放在 WP1 是因为它只改一处判定，与视频路径无关。
- `src/vrgen/cli.py`
  - `_apply_generation_params()`（cli.py:59-111）：校验保持"0=自动、或 ≥4"，上限不在此处写死（由 `_prepare_gen` 按模式 limits 校验）；`--duration` 是唯一时长入口，不做 generation.toml 持久化（口径见 WP0-2）。
  - `submit` 的 dry-run 预览（cli.py:245-261）：同样按 mode 从台账 refs 里取 first_frame/last_frame 调 `build_generate_argv`，不能只组装 videos/images；首尾帧的免额度验收走的就是这里。
  - `params_show` 的 `takes_video` 闸门（cli.py:546-547）：现行"`not limits.takes_video` 一律报错"→ 只在**传了含视频的 `--refs`** 而模式不接受视频时报错；不传 `--refs` 或清单里没有视频时，无论当前模式是什么都返回 `modes` 与 `current`。
    - 理由：这道闸门原本防的是"给不吃视频的模式传视频"，但 `limits.mode` 读的是 `generation.toml` 里保存的当前模式。纯图片 case 一旦把当前模式存成 firstLastFrame，页面连模式列表和时长范围都拿不到，用户也就无法切回吃视频的模式——闸门把"读模式列表"误伤成了"提交视频"。
  - `params_show` 的 `modes` 列表（cli.py:551-567）：过滤条件从 `m.takes_video and m.mode in SUPPORTED_MODES` 改为 `m.mode in SUPPORTED_MODES`（firstLastFrame 不吃视频但要出现在列表）；`video_required` 从写死 True 改为映射 `{videoEdit: True, videoExtend: True, allMediaRef: False, firstLastFrame: False}`；`max_videos` 在 `takes_video=False` 时返回 0（firstLastFrame 的 `max_count=2` 不应显示成允许 2 个视频）。

### pytest 验收（vrgen/tests/）

新增：

- `test_refs.py::test_first_last_frame_role_matrix`：firstLastFrame 接受恰好 1 first_frame + 1 last_frame；混入视频或第三素材报 `UsageError` 且文案含模式名。
- `test_refs.py::test_allmediaref_accepts_image_only`：0 视频 + N 图通过 `validate_mode`（回归"至少 1 个视频"已删除）。
- `test_refs.py::test_master_fallback_chain`：五段回退各取一例（edit_master 视频 / 首条视频 / 同级的 space_ref 与 scene_ref 图片按清单顺序 / first_frame 图片 / 兜底第一条图片）。
- `test_refs.py::test_new_role_prompt_wording`：`asset_list()` 对五个新角色输出预期首句。
- `test_refs.py::test_raw_roles_rejected`：refs 含 `first_frame_raw`/`last_frame_raw` 时报 `UsageError`，文案说明 raw 帧只作工作台输入。
- `test_mglc.py::test_models_cache_missing_fails_loud`：`models.json` 缺失或过期时 `prepare_round` 报配置错，提示 `vrgen models --refresh`，不静默放行。
- `test_mglc.py::test_build_generate_argv_first_last_frame`：argv 含 `--first-image`（first_frame 路径在前）与 `--last-image`，不含 `--video`/`--image`/`--asset-id`/`--aspect-ratio`。
- `test_mglc.py::test_build_generate_argv_requires_any_reference`：videos 与 images 皆空时报 `AigcError`。
- `test_mglc.py::test_duration_resolution_rules`：三分支各一例——显式 `--duration 13` 取 13；无显式 + 双视频取最长；纯图片无显式取 4（含 firstLastFrame 一例，不触达空视频分支）。附带 `test_duration_explicit_out_of_range`：显式 31 对 limits 4–30 报 `UsageError`，文案含合法区间。
- `test_mglc.py::test_prepare_round_gen_image_only`：纯图片 + duration=13 → run.params 的 `duration_s==13`、`keep_sound is False`、canvas 来自图片母版尺寸、`master` 为图片素材 id；不传 duration → `duration_s==4`。
- `test_mglc.py::test_result_urls_accepts_image_suffix`：`.png` URL 在无 `url` 关键字的 key 下也能被收齐（补 WP2 伪 payload 的前置）。
- `test_cli.py::test_params_show_duration_saved_any_mode`：`generation.toml` 的当前模式存成 firstLastFrame（合成一个 `takes_video=False` 的模式即可）时，不带 `--refs` 的 `params show` 不报错且返回 `modes`；带含视频的 `--refs` 时报 `UsageError`。

修改（受文案与放行影响的既有断言）：

- `test_refs.py::test_counts_and_prompt_block`：`task_rule` 断言改"锁定参考素材的空间"。
- `test_mglc.py::test_prepare_round_gen_multi_assets`（:587）与 `test_cli.py::test_prompt_show_renders_with_refs_and_geometry`（:131）：同上文案替换。
- `test_cli.py` 中涉及 `duration_s` 写入 `generation.toml` 的断言：改为只验证本次调用的 `params.duration_s`，不验证草稿持久化。

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
- 图片没有自定义宽高参数：`mglc image generate --help` 只有 `--ratio` 与 `--resolution`，没有 `--width/--height`（Seedream 4.5 的 customWH 是否可用 CLI 暴露待验证，首期不依赖）。
- 生命周期同构：同一信封 `{code,data,msg}`、同一 `task status --task-id` 轮询与状态码、同一登录态与会话计费；`Mglc.call()`（client.py:86-115）本就是通用执行器，`generate()`（client.py:161-171）只是 `call("video","generate",...)` 加额度确认门的薄包装。

决策：引入**任务种类注册表（task-kind registry）**。每种 mglc 生成能力声明为一个 `TaskKind` 实现，管线与 CLI 按注册表分发（字典查表，无 if 链）；未来接入 `image upscale`、`audio *`、`storyboard` 等能力时新增一个 kind 模块注册即可，核心零改动。CLI 面保持每 kind 一个子命令入口（`vrgen submit`=视频、`vrgen image submit`=图片）：子命令入口不是 if 切换，且两套 `--resolution` 词表天然隔离在各自的 argv 构建器里。

### 实现目标

`vrgen image submit` 完成一次图片生成的完整生命周期（提交→轮询→下载全部候选→闸门→台账），候选清单可被 `vrgen result --index` 逐张取出；视频与图片轮次共用台账结构与 `vrgen status`；轮次类型识别读注册表声明而非字符串分支。

### 切入点

1. 新建 `src/vrgen/round/kinds.py`：注册表同时声明**静态词表**与**生命周期入口**。

   ```python
   @dataclass(frozen=True)
   class TaskKind:
       kind: str                        # "video" | "image"
       quota_command: tuple[str, ...]   # ("video","generate") | ("image","generate")
       build_argv: Callable             # 该子命令参数词表的唯一归属地
       prepare_round: Callable          # 本地半程：建轮次、写台账、准备上传件
       execute_round: Callable          # 远程半程：提交→轮询→下载→闸门
       needs_virtual_ip: bool           # 视频参考素材要登记；图片不要
       multi_result: bool               # 单文件（视频）| 多候选（图片 --num）
       result_glob: str                 # 结果文件命名模式，result --index 按它取第 N 张
       resolution_tiers: tuple[str, ...]  # 该子命令自己的分辨率词表
       gate: Callable                   # 闸门语义：视频解码/尺寸 vs 图片解码
   KINDS: dict[str, TaskKind] = {"video": ..., "image": ...}
   ```

   - 只声明静态字段而不声明 `prepare_round`/`execute_round` 的话，`execute_round` 仍要按 kind 分支，CLI 与管线会重新长出 `if kind == "image"`，注册表就只剩展示作用。这是本轮修订第 7 条的直接原因。
   - `resolution_tiers` 让 `_apply_generation_params` 的视频白名单只在视频 kind 生效（第 4 条）：校验时从当前 kind 读词表，图片拿 `1K|2K|4K`，视频仍拿 `480p|720p|1080p`。
   - video kind 本工作包只做"注册化收口"——包住现有 `task.py`/`pipeline.py` 的函数，不重写视频路径；image kind 为新实现。
2. `src/vrgen/platform/client.py`：把 `generate()` 的额度确认门一般化为私有 `_spending(subcommand_args, confirm, timeout)`；`generate()`（`("video","generate")`）与新增的 `image_generate(args, confirm)`（`("image","generate")`）都调它——"花钱必须 confirm"的规则全局只有一份。
3. 新建 `src/vrgen/round/image.py`（image kind 实现本体）：
   - `build_image_argv(*, prompt, model_id, images, ratio, resolution, num, session_id)`：产出 `--prompt/--model-id/--image(可重复)/--ratio/--resolution/--num/--session-id`；`--resolution` 白名单 `1K|2K|4K` 在此校验（与视频档位词表的隔离点）。首期调用方固定传 `ratio="16:9"`；vrgen 只校验它属于模型详情声明的比例表，不自行推导。
   - `prepare_image_round(conf, ...)`：label 固定 `img`，`params.backend="mglc"`、`params.kind="image"`；无 virtual-ip 环节（读 `KINDS["image"].needs_virtual_ip`）。模型详情用 `Mglc.model_detail(model_id, model_type="image")` 读取（client.py 已有 `model_type` 参数），不复用视频的 `load_models`/`model_list_url`。
   - `execute_image_round(...)`：提交 → `wait_task` 轮询 → `fetch_all`（task status 的多 URL 全部下载为 `result_1.png`…`result_N.png`，复用 WP1 已放宽的 `result_urls()`）→ 闸门（每张 `probe_image` 解码成功即 ok）→ `run.results = [...]`。
4. `src/vrgen/round/ledger.py`：`Run` 增加 `results: list[str] | None`；轮次类型以 `params.kind` 为准，读旧 run.json 缺省补 `"video"`（`backend` 字段保留原语义不动）；`run_key` 的母版参数允许图片路径（WP0-3 的延伸）。
5. `src/vrgen/cli.py`：`image submit` 子命令走 `KINDS["image"]`；`result --index` 与 `status` 的展示差异（img 标记、多候选计数）读 `KINDS[kind]` 的声明字段，不写 backend/kind 字符串分支。

### pytest 验收（vrgen/tests/）

- `test_kinds.py::test_registry_declares_both_kinds`：KINDS 键集、quota_command、needs_virtual_ip、multi_result、resolution_tiers 声明与预期一致（视频：要登记、单结果、480p/720p/1080p；图片：不登记、多候选、1K/2K/4K）；每个 kind 的 `prepare_round`/`execute_round` 可调用。
- `test_kinds.py::test_cli_dispatches_without_kind_branch`：用假 kind 注册一个测试入口，`image submit` 与 `submit` 都经注册表拿到各自的 argv 构建器（证明新增 kind 不需要改 CLI 主流程）。
- `test_mglc.py::test_build_image_argv_shape`：flag 顺序与 `--image` 可重复；resolution 白名单外报错。
- `test_mglc.py::test_image_args_accept_image_resolution`：`vrgen image submit --resolution 2K` 不被视频白名单拒绝；同一命令传 `--resolution 1080p` 报参数错。
- `test_mglc.py::test_client_image_generate_requires_confirm`：`image_generate()` 不带 `confirm=True` 抛 `MglcError`（与 `generate()` 同一道门）。
- `test_mglc.py::test_result_urls_accepts_image_payload`：构造 key 为 `imageUrl`/`imgUrlList`/`images` 的伪 payload，断言 `result_urls()` 收齐且水印变体排后（覆盖 R2 的两种形状：带 `url` 关键字与只带 `image` 关键字）。
- `test_mglc.py::test_image_round_lifecycle`：注入 mock client（提交返回 task id、两次轮询后 succeeded、payload 含 4 个 URL、opener 返回伪 PNG 字节）→ 断言 `run.results` 长度 4、gate verdict ok、stage 推进到 checked。
- `test_cli.py::test_image_submit_dry_run`：dry-run 打印 argv、不产生平台调用（transcript 为空）。
- `test_cli.py::test_result_index_copies_nth_candidate`：`--index 3` 拷贝 `result_3.png`；不带 `--index` 拷第一张。
- `test_cli.py::test_status_lists_image_rounds`：img 轮次在 `status` 输出中带 img 标记。
- 回归：`test_cli.py` 现有 `result`/`status` 测试全绿（旧轮次 run.json 无 `kind`/`results` 字段不炸，按 video 单结果处理）。

### 免额度验收命令

```bash
vrgen image submit --job <case> --model-id 44 --ratio 16:9 --resolution 4K --num 4 \
  --image <i2.png> --image <i1.png> --prompt "<§4.1 首帧提示词>" --dry-run
```

真实提交一次（需批准）：确认 mglc 接受本地路径直传、task status 返回 4 个 URL。

## WP3：vrstudio 侧（case 通用化、提交集、patch 分支、web）

### 3a case 模型（`src/vrstudio/case.py`）

- `load()`：现行 `flow != "gen" and assets` 报错（case.py:193-194）→ 删除该限制；`save()` 的 assets 写块从 gen 分支提出，任意 flow 都写（`[submit]` 段紧随 `[[assets]]` 之后写在同一个文件里）。
- 素材增删改排的 flow 守卫一并放开（第 8 条）：`add_assets`（case.py:332）、`remove_asset`（case.py:385）、`set_asset_role`（case.py:399）、`reorder_assets`（case.py:409）、`check_assets`（case.py:514）都硬编码 `flow == "gen"`。只改 `load`/`save` 的话，patch case 一调素材 API 就报 "没有素材列表"，WP3c 的侧边栏无法落地。
  - `add_assets` 对 patch/fullredraw 的源视频仍走 `[source]`，素材列表不需要源视频条目；流程产物作为候选由装配器解析路径，不写进 `[[assets]]`（见父文档 §8.3）。
  - `check_assets` 的路径解析与哈希校验逻辑对三流程相同，只有守卫删除。
  - `_next_asset_number`（case.py:432）与 id 规则不变。
- `MODE_ROLES`、`ROLES`/`ROLE_LABELS`：与 vrgen refs.py 同步（含 firstLastFrame 与五个新角色；LABELS 补中文说明）。
- `Case.master()`：同步 WP0 回退链。
- 新增 `submit_selected`（`list[str] | None`）字段 + `[submit] selected` 的读写与校验（id 必须存在于当前可勾选候选：`[[assets]]` 或 clip/pad；mask 不写进 `selected`；**不存角色覆盖**，口径见 WP0-1）。没有默认集，缺省等于空集。删除素材或重排时：素材被删则同步从 `selected` 移除；重排不改 id，`selected` 不动；clip/pad 的 id 固定，不因重新 extract 变化。
- 测试（`tests/test_case.py`）：
  - `test_assets_allowed_for_all_flows`：patch/fullredraw case 写入并读回 assets。
  - `test_asset_crud_all_flows`：patch case 上 add/remove/reorder/set_role/check_assets 各一条（第 8 条的回归防线）。
  - `test_submit_selected_roundtrip`：保存/读取/非法 id 报错；删除已选素材后 `selected` 同步收窄。
  - `test_master_image_fallback`：无视频时回退链行为。

### 3b 生成入口（`src/vrstudio/cli/generate.py`）

- `resolve_package` 增加 `mode: str | None = None` 参数（第 6 条），模板按 `(flow, mode)` 选：
  - gen + firstLastFrame → `gen-multi`（与现 gen 默认模板相同，但显式声明，避免以后 gen 默认模板变化时首尾帧跟着变）。
  - patch + firstLastFrame → `gen-multi`；patch + 其它 → `character-repaint`（现行为）。
  - fullredraw 不受影响。
  - 调用点同步：`generate.py:196` 传 CLI 的 `--mode`；`app.py:209`（提示词预览）与 `app.py:260`（`_generation_params`）传 `generation.toml` 的当前模式（与 `params show` 读的是同一个值）。
- `resolve_package` gen 分支（generate.py:92-106）：`master()` 可能是图片（第 5 条）。
  - 图片母版时不再 `probe(video)`，用 vrstudio 本地的 cv2 读取图片拿宽高（或新增 `media/` 下的小 helper；不得 import vrgen）；**canvas/source 照常返回 `(宽, 高)`，不返回 None**。
    - 理由：`app.py:213` 与 `app.py:273` 都直接做 `canvas[0]`，且异常捕获只有 `CaseError/GenError/KeyError/ValueError/OSError`，None 会抛 `TypeError` 变成 500。返回 None 还要改返回类型、三个调用点和测试，而调用方拿到的 `canvas` 本来就有合法值（图片宽高）。
  - 送生成的"视频"位置返回 None：`(None, None, template, canvas, source)`，`submit` 组装 argv 时据此**不带 `--input/--mask`**，而是走 `--refs`。报错文案"至少需要 1 个视频素材"改为按模式的说法（gen 的校验留给 vrgen 的模式矩阵，这里只拦"没有任何素材"）。
- refs payload（generate.py:200-210）：只装 `case.submit_selected` 的素材，没有默认集，缺省等于空集：
  - 可勾选候选 = `[[assets]]` + clip/pad（patch 的 `clip`，fullredraw 的 `pad`）；mask 不在候选里，由装配器在提交时追加到所有用户图片之后。
  - firstLastFrame：只取勾选里恰好一张 `first_frame` 加一张 `last_frame`，按首帧在前组清单；其余勾选项、视频与 mask 都不参与，也不追加 mask。
  - 其他模式：勾选什么就装什么，再追加 mask；勾选为空时 vrstudio 直接报错，不进入后端。
  - `--refs` 清单拒绝 `first_frame_raw`/`last_frame_raw` 角色；raw 帧只给工作台，不能靠手动勾选或直接调 CLI 提交。
  - 不采用"最新定稿的一对"：定稿时间靠文件 mtime 判断，素材被重新添加、复制目录或用 git 检出都会改 mtime，顺序不可复现。
- patch 分支新增 firstLastFrame 变体：`resolve_package` 检测透传的 `--mode firstLastFrame` 时，先校验 viewport 宽高比为 16:9（相对容差 0.1%，约等于 1080p 下 1 像素取整误差），非 16:9 报 `GenError`（文案要求重新选区/抽取）；通过后走 refs 路径，清单只装勾选的首尾定稿图（canvas/source 仍取 clip.json viewport，模板用 `gen-multi`，不传 `--input`，clip/mask 不进入清单）；videoEdit 路径原样。
- 测试（`tests/test_generate.py`）：
  - `test_resolve_gen_image_master_omits_canvas`：图片母版 → 返回的 canvas/source 等于图片宽高、视频位置为 None、`submit` 的 argv 无 `--input` 且含 `--refs` 与 `--first-image/--last-image`（由 vrgen 侧生成，此处断言 vrstudio 不传 `--input`）。
  - `test_submit_refs_filtered_by_selected`：`[submit] selected` 只含两 id → refs JSON 只装两条。
  - `test_submit_firstlast_selection_requires_pair`：勾选里恰一对首尾帧时只装这两条；两对或一对都没有时报错；clip 即使勾选也不进入 firstLastFrame 清单，mask 不追加。
  - `test_submit_refs_rejects_raw_roles`：refs 里出现 `first_frame_raw`/`last_frame_raw` 时 vrgen 报参数错，不能作为首尾帧提交。
  - `test_mask_appended_not_numbered`：patch/fullredraw 提交时 mask 追加在所有用户图片之后；`asset_list` 的 `@ImageN` 从用户图片开始编号，不因 mask 顺延。
  - `test_patch_firstlast_branch_builds_refs`：patch case + mode=firstLastFrame → argv 走 `--refs`、`--canvas` 为 clip.json viewport 尺寸、`--template gen-multi`。
  - `test_patch_firstlast_requires_16_9_viewport`：1920×1080 的 patch case 通过；1920×1052 的 case 报 `GenError`，不组装 argv。
  - `test_prompt_template_follows_mode`：patch case 当前模式为 firstLastFrame 时，提示词预览与 `_generation_params` 用的模板都是 `gen-multi`。

### 3c web 后端（`src/vrstudio/web/app.py`）

- 素材 API（`/api/case/<name>/assets`）从 gen 限定放开到三流程；流程产物接口 `GET /api/case/<name>/derived`（返回当前 clip/pad 等可勾选候选；mask 与 raw 帧不作为候选返回，不进 `[[assets]]`；接口名保留）。
- `[submit]` 读写：`GET/PUT /api/case/<name>/submit`。
- 抽帧接口：默认路径由 `vrstudio extract` 直接产出 `extracts/<版本>/first_frame_raw.png` 与 `last_frame_raw.png`（**不做任何缩放，按 clip 分辨率导出**），工作台直接读取这两张图，不再需要点按钮。`POST /api/case/<name>/extract-frames` 只保留给自定义时刻（body 可选 `{t_first, t_last}` 秒），写回工作台输入区，不再重复往 `[[assets]]` 增加 raw 角色条目。仅 patch 流可用。
  - 时刻边界：`t` 先按 clip 时长 clamp 到 `[0, duration]`；`t_last` 取 `min(t_last, duration - 1/fps)` 避免落在末尾抽不到帧；要求 `t_last > t_first`，不满足报参数错。
- 工作台接口：`POST /api/case/<name>/keyframe/run`（body：step=first|last、model_id、prompt、参考图 asset id 列表、可选 resolution → 后端按 case 推导 `--ratio`（patch 取 viewport，gen 固定 16:9，忽略前端传入的其它比例）；`--resolution` 未传时取该模型 `resolutions` 的最高档（当前 4K），显式传入时只接受模型声明的档位；然后组装 `vrgen image submit` 子进程，走现有任务队列）；`GET /api/case/<name>/keyframe/rounds`（读台账 run.json 的 `results` 列举候选缩略图）；`POST /api/case/<name>/keyframe/pick`（round + index + 目标角色 → `vrgen result --index` 拷出 + `add_assets` 写 first_frame/last_frame；落素材前校验该对宽高一致且比例为 16:9，不一致报错要求重出图）。
- 生成闸门（app.py:589-595）：前端点击生成时先检查提交集——空选集直接提示"没有勾选任何素材"；firstLastFrame 需勾选里恰有一对定稿帧且 viewport 为 16:9，不足或超出就弹错、不发请求；videoEdit/videoExtend 不因没有勾选流程视频而静默通过，空选集同样拦截；fullredraw 额外不出现工作台与新模式入口。vrgen 保留同样的提交前校验，供 CLI 直接调用时兜底。
- `_generation_params`（app.py:252-276）与 `_prompt_preview_args`（app.py:199-231）：
  - 送生成的清单为空（图片母版）或当前模式是 firstLastFrame（patch 的 clip 只用于 canvas/source，不作为生成输入）时，`params show` 不带 `--refs`，只取 `modes` 与 `current`（`output/input` 为空数组，前端据此禁掉分辨率与缩放下拉）；否则会触发 `takes_video=False` 的闸门。
  - 其他模式下 `_generation_params` 用与提示词预览同一份 refs 临时文件调用 `params show --refs`，由 vrgen 从母版算输入档位。
  - `_prompt_preview_args` 的 refs 临时文件对三流程都要生成：统一提交后 patch/fullredraw 也走 refs，提示词展开与提交使用同一份勾选清单。
  - 两处都按 `(flow, mode)` 选模板（第 6 条）。
- `_op_argv`（app.py:1011-1025）：submit 增加可选 duration 透传（前端下拉框选中值；"自动"不传该字段）。`_op_argv` 读不到 `generation.toml` 的当前模式时，由调用方把模式作为 body 字段传入。
- 测试（`tests/test_web_console.py`）：上述每个端点一条（沿用现有 mock `_vrgen_json`/子进程 的测试风格），加：
  - `test_generate_gate_mode_aware`
  - `test_generation_params_image_case_omits_refs`：纯图片 case 的 `params show` 不带 `--refs`，页面 `generation_params.modes` 可读；母版是图片时 `input` 为空。
  - `test_prompt_preview_image_case_no_crash`：纯图片 case 下 `/api/case` 返回 200，`info.prompt.rendered` 或 `render_error` 二者有其一，不出现 500。
  - `test_keyframe_ratio_derived_16_9`：patch 工作台的图片请求 `--ratio` 等于 viewport 推导值（16:9）；gen 固定 16:9；前端传 4:3 被忽略或报错。
  - `test_keyframe_pick_rejects_mismatched_pair`：首尾帧宽高或比例不一致时 pick 报错，不写入素材。
  - `test_keyframe_defaults_to_highest_resolution`：未传 resolution 时取图片模型 `resolutions` 的最高档（当前 4K）；传 2K 时按 2K 发起，`--ratio` 仍为 16:9。

### 3d web 前端（static/ + templates/partials）

- 素材侧边栏组件（由 assets.js 演化）：三流程生成页统一挂载、可展开；区块一"流程产物（可勾选）"只列 clip/pad，区块二"文件素材"（增删/角色/排序沿用现功能）；提交集只取勾选项，没有默认集，缺省为空；mask 不显示、由装配器自动附带，首尾原始帧只在关键帧工作台输入区出现。勾选变化触发 `@VideoN/@ImageN` 重编号（旧号→新号映射改写 prompt-vars 变量值，被移除素材的标记标红不删）与 `prompt show` 实时预览；变量值就地编辑（复用 prompt save）。勾选状态通过 `PUT /api/case/<name>/submit` 立即落盘。
- 解锁提示：fullredraw 生成页的文件素材区可编辑，pad 作为可勾选候选，mask 自动附带；patch 的 videoEdit 模式不再自动带 clip，用户需要勾选 clip（mask 自动附带），面板显示当前提交数量并在空选集时禁用生成。
- gen 向导步骤定义：由"素材→生成"改为"生成"一步（素材并入侧边栏），`STEPS` 数据驱动表同步。
- 关键帧工作台页（新 partial + keyframe.js）：输入区（extract 已产出的首尾原始帧 / 自定义时刻重抽 / 上传帧 + 三视图引用）、两步重绘（首帧→尾帧链式，参考图顺序 UI 明示 图1/图2/图3 对应 §4 提示词）、候选网格（4 张，点击放大）、挑选落素材（角色 first_frame/last_frame）、提示词编辑器预填 `first-last-frame-pipeline.md` §4 模板。生成首尾定稿帧后默认勾上这一对并替换旧对，用户仍可取消。
- 工作台比例与分辨率固定：首期不提供比例下拉；patch 由 viewport 推导为 16:9，gen 固定 16:9，候选图的 `--ratio` 全部由后端传入。`--resolution` 默认取模型最高档（当前 4K），前端可下调；比例不变。首尾帧落素材时宽高不一致直接报错，不做自动裁切。
- 生成参数面板：firstLastFrame 模式下“输出比例”显示为只读的 `16:9` 并说明“首期全链路固定”；其它模式维持现有可选比例。时长下拉仍按 WP3-3d 的模式元数据生成。
- 生成参数面板增加时长下拉框（WP0 时长规则的前端面）：选项由**模式元数据**生成——`generation_params.modes[]` 里每一项都带 `duration`（`{type, min, max}`，来自模型详情，模型 37 为 4–30）；`type == "range"` 时渲染"自动" + min…max 整数，`type` 为空（videoEdit/videoExtend，时长跟随母版）时只显示"自动"并说明时长由母版决定，不给下拉。不硬编码 4–30。
  - "自动"不传 `--duration`，后端按规则推导（含视频取最长视频时长，纯图片取 4）；纯图片模式下拉缺省落在 4 并显示推导说明，避免无感默认。
  - `params.js:85` 现在把 `fixed.duration_s || "按输入自动"` 显示在参数行上，改为显示"本模式下时长由输入/素材推导"或当前选择值，不再暗示时长是保存的草稿。
- wizard.js 校验文案按模式替换（"至少 1 个视频"仅对 videoEdit/videoExtend 出现；`wizard.js:186-188` 的硬编码 alert 同步改）。
- 验收：浏览器手测清单——① patch case 建好选区并 extract；② 生成页展开侧边栏看到 clip 候选，mask 不显示；③ extract 后 `extracts/<版本>/first_frame_raw.png` 与 `last_frame_raw.png` 已存在且分辨率等于 clip；④ 首帧 4 候选出图、挑选入素材；⑤ 尾帧带首帧产物重绘、挑选；⑥ 勾选两定稿帧时提示词预览的 `@ImageN` 编号正确联动；⑦ 提交模式切 firstLastFrame 后"检查提交命令"（免额度 `--check`）通过；⑧ fullredraw 生成页无工作台与新模式入口，pad 与文件素材可勾选，mask 自动附带；⑨ 纯图片 case 打开生成页，模式下拉与时长范围正常显示，不出现"生成参数暂时读不到"；⑩ 非 16:9 的 patch case 切 firstLastFrame 时提交按钮置灰并显示原因，16:9 case 正常通过；⑪ firstLastFrame 下少勾或多勾首尾帧时点击生成，前端弹错且网络面板没有 submit 请求。

### 3e 抽帧 helper（`src/vrstudio/media/`）

- 新建 `frames.py::extract_frame(video, t_seconds, out_png)`：调 bin\ffmpeg `-ss <t> -frames:v 1`，不缩放。首期 clip 为 16:9，抽出的原始帧天然 16:9；helper 不做裁切/缩放。
- 2026-10-21 起由 `vrstudio extract` 在写完 `clip.mp4` 后直接调用两次：输入是 `clip.mp4`（不是原始 360 视频），t=0 写出 `first_frame_raw.png`，t=clip 末帧时刻写出 `last_frame_raw.png`，与 clip.json/clip.mp4/clip_mask.png 同目录。工作台默认读这两张图；web 的自定义时刻抽帧接口只作为补充入口。
- 测试：合成 2 秒测试视频抽帧，断言输出尺寸等于源分辨率、PNG 可被 `_imread` 读取（复用 web 层 cv2 断言风格）；另加一条 `extract` 端到端测试，断言两个 raw 文件存在且尺寸等于 clip viewport。

## WP4：几何对齐与端到端验收

首期正常路径是 16:9 全链路 identity；本工作包负责把这条契约落成代码与测试，裁切只作为历史/外部导入的显式兜底。

1. **merge 尺寸契约（替换现有硬拉伸）**：
   - 在 `cli/merge.py` 的 `AiFrameSource` 取帧前校验 `ai_aspect` 与 viewport 比例，相对容差 0.1%；超差抛 `typer.Exit`，文案打印期望/实际宽高，不静默 `cv2.resize`。
   - 严格校验对所有 merge 生效，不按模式开例外：比例一致只做等比缩放；比例不一致默认报错，只有显式 `--allow-crop` 才做中心裁切。历史非 16:9 的 videoEdit 若平台精确跟随输入，不受影响；若平台归一到标准档，用 `--allow-crop` 显式继续，不再静默拉伸。
   - 比例一致时只做等比缩放：目标尺寸直接取 viewport 的 `(vp.width, vp.height)`，同比例下宽高缩放因子相同，因此没有裁切。首期 16:9 + 1080p 的组合应命中 identity。
   - 历史非 16:9 或外部导入视频：显式开启 `--allow-crop` 后才允许“等比缩放覆盖 + 中心裁切”（`scale = max(target_w/src_w, target_h/src_h)`，再按中心裁二维），并把裁切区域记入日志/台账；默认关闭。`--allow-crop` 的参数名与落点实现时定，语义固定为“允许丢弃画面边缘”。
   - 统一归一实现只保留一份：`composite.align_ai_clip` 当前在 src/tests 无调用者，`AiFrameSource` 是实际路径；把几何归一抽成共享函数，二者都调用它，避免两份规则漂移。
2. **像素基线测试**（满足 AGENTS 硬规则 4）：
   - identity：viewport 1920×1080 + AI 1920×1080 → `maxdiff==0`。
   - 同比例缩放：viewport 1920×1080 + AI 1280×720 → 输出 1920×1080，断言尺寸与合成标记点位置；这条不能断言 `maxdiff==0`，均匀缩放下逐像素必然有差异。
   - 比例不一致：viewport 16:9 + AI 4:3 → 默认报错、不产出文件；开启允许裁切后才产出，并断言中心裁切区域。
   - 旧 videoEdit：viewport 1920×1052 + 同比例 AI 成片 → 不报错；若 AI 是 1920×1080，默认不产出，只有显式 `--allow-crop` 才走裁切。
3. **首尾帧几何**：16:9 路径不做任何裁切；工作台只在出图前锁定 `--ratio 16:9`，落素材时校验同宽高。历史非 16:9 的定稿帧不进入 firstLastFrame，提示重新出图。
4. **端到端免额度回归**：
   - gen firstLastFrame：16:9 纯图片 case，`vrstudio generate submit --case <case> --check`，argv 含 `--first-image/--last-image`、不含 `--input`。
   - patch firstLastFrame：16:9 viewport case，`--check` 的 `--canvas/--source` 为 1920×1080，模板 `gen-multi`。
   - 非 16:9：patch case + firstLastFrame 的 `--check` 预期在 vrstudio 侧报错退出。
   - 旧路径回归：现有 gen allMediaRef 与 patch videoEdit 的 `--check` 输出与改造前一致（防行为漂移）。
5. **真实提交验收（需批准，逐轮确认）**：按 §8.1 路线分流各跑一轮——gen 整幅帧一条、patch 区域帧一条，均为 16:9 + 1080p；记录平台返回的实际宽高与提示词/结果对照，写入台账并回填 WP0.5 的规范像素。若平台返回非 16:9，暂停真实提交并回到设计，不在 merge 里用裁切掩盖。

## 风险与未验证点

- R1 首尾图合规性：`--first-image/--last-image` 是否需要 SD 合规登记未知。模型详情（`mglc model --type video --model-id 37`）对 firstLastFrame 标了 `supportVirtualIp: 是`，但 CLI 没有对应的 asset-id 参数；首期仍按直传路径实现，并跳过 `ensure_assets`。首次真实提交验证；若平台拒绝，登记 virtual-ip 后重试（需找到可传 id 的接口或升级工单），仍拒绝则暂停该模式真实提交（`--dry-run` 不受影响）。
- R2 图片 URL 提取：mglc image generate 的 task status payload 形状未实测。`result_urls()` 的判定已在 WP1 放宽（`.png/.jpg/.webp` 后缀 + key 含 `image`），WP2 的伪 payload 测试覆盖"key 带 `url`"与"key 只带 `image`"两种形状；真实形状以首次提交的台账为准修正。
- R3 默认图片模型：首期默认 专业图片-2.5（id 44，局部编辑强、13 参考图），备选 Seedream 4.5（id 25，customWH 可出精确宽高）；工作台模型下拉开放两档。图片分辨率默认取模型详情里的最高档（当前两者都是 4K），允许下调；CLI 是否支持 Seedream 的 customWH 未验证，首期不依赖。
- R4 成本：图片步 `--num 4` ×2 帧（默认 4K，成本高于 2K/1K）+ 视频步 1 次；4K 只提高关键帧精度，成片仍是 1080p。工作台 UI 在提交按钮上明示本次消耗构成，并允许在单次运行里下调图片分辨率。
- R5 `@标记` 自动重编号的边界：仅做同类型内重号（Video/Image 各自连续），跨类型不变；无法映射的标记保留原文并标红。
- R6 提交集角色覆盖（待拍板）：首期 `[submit] selected` 只存素材 id，临时改角色靠素材卡片上的角色下拉（`set_asset_role`），这会改素材本身。如果用户需要"同一素材在不同提交里担任不同角色"，需在 `selected` 字段里加角色后缀，属契约扩展，单独立项。
- R7 firstLastFrame 输出宽高未实测：模型详情只声明 480p/720p/1080p，没有输出宽高字段。首期用 16:9 + 1080p 真实提交一次，记录平台返回的 `width/height`；同时比对返回首帧与输入首帧的画面边界，区分"16:9 内容 + 编码 padding"和真实拉伸：前者窄范围裁切可接受，后者才暂停并回到设计（WP0.5），不在 merge 里用裁切掩盖。
- R8 历史非 16:9 case：首期不迁移、不自动裁切；videoEdit 原样可用，切 firstLastFrame 需重新选区为 16:9 并 extract 新版本（旧版本保留）。
- R9 4K 图片与参考图上限：模型详情给视频参考图的限制是 300–6000 px、单文件 30MB。4K（3840×2160）在像素范围内，但复杂场景的 PNG 可能超过 30MB，触发 vrgen 的 fit 降采样。真实提交时记录图片格式与体积；超限时优先改导出 JPEG 或压缩 PNG，仍超限再降分辨率，始终保持 16:9。

## 提交切分与门禁

1. 根仓库：`docs: 立项首尾帧管线契约变更`（WP0，已完成）。
2. vrgen：`vrgen: 接入 firstLastFrame 模式与时长规则收敛`（WP1）；`vrgen: 增加任务种类注册表与图片生成`（WP2）。
3. vrstudio：`vrstudio: 素材列表通用化与提交集`（WP3a+3b）；`vrstudio: 首尾帧工作台与素材侧边栏`（WP3c+3d+3e）；`vrstudio: 成片几何归一对齐`（WP4-1/2）。
4. 每笔提交前：对应仓库 `uv run pytest` 全绿 + `uv run ruff check .` 干净；WP3 起另跑 WP4-3 的三条免额度 `--check` 回归。
5. 实施过程中按小步提交：每个可独立验证的小步完成并跑通对应 pytest 后，立即在对应仓库做一次本地 commit，不把多个工作包攒成一次提交；是否推送与是否整理历史由用户决定。
