# 8K 静图重绘的两条路线：分段局部链式 vs 全幅 4K + 氛围参考（审查稿，待批）

状态：待批。记录时间 2026-10-29。方向已由用户提出（决策 47）：同一张 8192×4096 ERP 静图、同一张氛围参考图，用两条不同的生成路径各跑一遍，按指标与主观观感选型。本文写两条路线的数据流、必须的开发前置与 CLI 工作包；两条路线的步骤页本轮不做，前端只补「子目录 case 的识别」这一项（A 的前置），其余等选型结论。

实验输入固定：`sources/360erp_test.png`（8192×4096）、`sources/palace_light_ref_01.png`、session `2062569522605504`；两条路线用同一句 `edit` / `preserve` 提示词变量，只有输入形态不同。

## 0. 结论

- 路线 A（**分段局部链式**）：模型每次只重绘一个 16:9 视口，4K 输出落进 ERP 里约 0.7 Mpx 的 inner 区域，2 倍以上过采样，8K 细节保住；视口沿 360 分段覆盖，段间重叠，链式把上一段贴回后的 8K 结果作为下一段的源图。代价是 N 个 case、N 轮额度与内容漂移风险。
- 路线 B（**全幅 4K + 氛围参考**，`fullRedrawImg`）：一次提交整幅 21:9 padded 基图 + 冗余带 mask + X 张氛围参考图，模型输出一张 4K 21:9，`stitch_image` 还原成 2:1 的 8192×4096（内部含约 2.1× 的重采样）。单轮成本低，mask 把接缝锚点冻住、结果无接缝；代价是整幅线性分辨率只有源图的 0.47 倍，且横跨接缝的约 16.7% 不参与重绘。
- 两条路线的差别不在参考图，而在**这一次生成的 4K 像素预算摊在多宽的画布上**：A 只服务一个视口，B 覆盖整幅。
- 先用同一 source、同一 reference、同一 session 各跑一遍，再决定是否需要把其中一条做成正式流程。

## 0.1 实施状态（2026-10-29）

- 路线 B 已按新形态实现为 `flow = fullRedrawImg`（峰谷命名法，不用符号）：整幅 21:9 pad + 必交 mask + X 张 `lighting_ref`，无关键区块、无视口。改动在 vrstudio（`case.py`、`cli/extract.py`、`cli/generate.py`、`cli/merge.py`）与 vrgen（`templates/fullRedrawImg.md`、`IMAGE_ROLE_TEXT["lighting_ref"]`）。
- 抛弃的旧形态（`stillfull` + 10 张 detail_ref + 不交 mask）做过一轮真实生成，结论见 §3.3：区块没买到细节，且不交 mask 时 4 张候选只有 1 张过接缝闸门。
- 新形态的真实额度一轮待跑（先 1 张 1K 验证「基图 + mask + X 张灯光参考」的请求格式，再 4 张 4K）。
- 路线 A（case 分组 + 分段链式）未开始。

## 1. 分辨率算术（两条路线的根本差异）

| | 模型输出 | 落在哪里 | 相对源图的线性比例 | 细节上限 |
|---|---|---|---|---|
| A 分段局部 | 3840×2160（16:9 视口） | ERP 的 inner，约 980×740 px | 约 2.2× 过采样 | ERP 自身（8K） |
| B 全幅 | 3840×1648（21:9 画布） | 整幅 8192×4096 | 约 0.47× | 模型输出（4K） |

已有实测支持 A 的结论：2026-10-29 的 8K 验收里，同一视口 footprint 上视口局部成片的 Laplacian 方差 98.5，旧全幅方案 57.0（`docs/test-runs/20261029-patchimg-viewport-local.md`）。B 的 0.47× 是算术结果，本轮实测用来确认它在新模板与关键区块参考下会不会比旧全幅好一些。

A 的分辨率上限由 ERP 决定，所以**加轮次不会提升锐度**；链式的价值在接缝与光照一致性。

## 2. 路线 A：分段局部链式

### 2.1 数据与步骤

一个组目录装 N 个 case，每个 case 一段视口：

```text
cases/<组名>/
  tiles.json                 # 分段计划：每段的 yaw/pitch/fov/视口尺寸/inner/顺序
  chain01/                   # 第 1 段：源图 = 原始 8K
    case.toml                # flow = patchimg；assets 里挂 lighting_ref
    extracts/<版本>/clip.png clip_mask.png image.json result.png report.json
    out/<版本>_image.png     # 贴回后的 8K，下一段的源图
  chain02/ ... chain06/
```

每段的命令与现有 patchimg 五步完全一致，只有 source 不同：

```text
vrstudio case new <组名>:chainNN --flow patchimg --source <上一段 out | 原始 8K>
vrstudio case draft --case <组名>:chainNN --file draft.json
vrstudio extract name --case <组名>:chainNN
vrstudio generate submit --case <组名>:chainNN --num N --resolution 4K --session-id <id>
vrstudio generate adopt  --case <组名>:chainNN --index <人工挑>
vrstudio merge          --case <组名>:chainNN
```

段序按 yaw 递增，最后一段与第一段重叠，用它自己的重绘吃掉第一段留下的边；ERP 接缝（yaw 180 附近）落在某一段的视口内部，由投影的环绕采样拼成连续图像。

### 2.2 前置（必须开发）

1. **case 分组（子文件夹）**——见 §4 WP1。这是 A 的硬前置，也是通用能力。
2. **分段计划命令** `vrstudio img tiles`：按 fov/step 生成 `tiles.json`。纯算术，不花额度。
3. **链式编排脚本** `scripts/img_chain.py`：建 case（含挂 `lighting_ref`）、写草稿、跑 extract、打印 submit 命令、adopt 后跑 merge、校验选区外逐位一致、把 out 交给下一段。挑片必须人工，所以脚本在 adopt 处停下。
4. **vrgen 的 `lighting_ref` 提示词文本**——见 §4 WP0。

### 2.3 验收

- 每段：`np.array_equal(out[~support], src[~support])` 为真，`outside maxdiff 0`。
- 全部段跑完后：源图中未被任何视口覆盖的像素与最终成片逐位相等。
- 重叠区：跨段边界的梯度不高于视口内部同位置分布的 p95（无硬接缝），并附 2× 特写。
- 关键区块（6 个固定位置）的 Laplacian/Sobel 不低于单段基线，用于观察逐段有没有变软。
- 氛围距离：与参考图的 Lab 均值/色度分布距离逐段收敛。
- 额度记账：段数 × 候选数，写进验收记录。

### 2.4 风险

- 内容漂移：mask 只是提示，模型会重绘整个 inner；段与段的重叠区被后一段重画，构图可能轻微变化，累计到闭环处最明显。
- 闭环段：最后一段要覆盖第一段的边，若模型在重叠区改动过大，闭环处会出现接缝；需要人工挑片时重点看这里。
- 成本：6 段 × 2–4 张；额度与壁钟时间都是 B 的数倍。
- 只有在交付是 8K 时 A 才成立；交付 4K 时 A 的过采样是浪费。

## 3. 路线 B：全幅 4K + 氛围参考（fullRedrawImg）

### 3.1 数据与步骤

```text
cases/<名>/
  case.toml                     # flow = fullRedrawImg；assets 里挂 lighting_ref
  extracts/<版本>/
    padded.png                  # 21:9 冗余画布，源分辨率（8K 源约 117 MB）
    padded_mask.png             # redundant_white：两条冗余带白、主内容黑
    image_pad.json              # 全幅几何唯一权威（复用 WP1）
    upload.png                  # 基图上传副本（长边 ≤ 4096）
    upload_mask.png             # mask 上传副本（同一尺寸）
    result.png                  # 采用的 4K 21:9 结果
    report.json                 # 配准、接缝闸门与 aspect drift
  out/<版本>_image.png          # stitch 还原的 2:1 成片（8192×4096）
```

```text
vrstudio case new <名> --flow fullRedrawImg --source <8K ERP 图>
vrstudio extract name --case <名>        # pad + mask + image_pad.json
vrstudio generate submit --case <名> --num N --resolution 4K --session-id <id>
vrstudio generate adopt  --case <名> --index <人工挑>
vrstudio merge           --case <名>     # stitch_image 还原 2:1
```

提交装配：基图与 mask 各取一份上传副本，后面按 `[submit] selected` 追加 X 张氛围参考，全部角色 `lighting_ref`；`--ratio 21:9`。参考图上限 13 张（基图 + mask 占 2），所以 X ≤ 11，由 `generate.image_max_refs` 在装配时断言。

### 3.2 平台事实（mglc 2026-10-29 查询）

`mglc model --type image --model-id 44`（专业图片-2.5）：

- `maxReferenceCount = 13`：一次提交最多 13 张参考图。
- `ratios` 没有 2:1，最宽是 21:9，所以整幅 360 只能 pad 成 21:9 再 stitch。
- `resolutions = 1K / 2K / 4K`，`generateCountOptions = 1..4`，`maxPromptLength = 2000`。
- 13 个图片模型的详情都没有 `refImageValidator`，输入图的像素/字节上限未公布。已实测：117.6 MB 单张被 403；7.5 MB 的 4096×1755 上传副本正常。

### 3.3 为什么放弃关键区块、并且必交 mask

旧形态（10 张 `detail_ref`、不交 mask）跑过一轮真实生成，两条结论直接决定了现在的设计：

- **区块没买到细节**：成片在 10 个区块 footprint 上的 Laplacian 只有源图的 **9%**；把源图缩到 4K 再放回 8K 的对照组是 **19%**。模型是做整幅重绘，不是保结构地换光，细节参考图改变不了这一点。
- **不交 mask 时接缝立不住**：模型把两条重复带各自重画，四张候选的 band correlation 是 0.777 / 0.642 / 0.841 / 0.574，只有 1 张过 0.80 闸门；采用的那张接缝段是两份不同重绘的交叉淡化，出现重影。

所以现在：去掉区块，必交 `redundant_white` mask，用像素级锚点换接缝稳定。代价要写清楚——横跨接缝的那条带（源图 `[6826,8192)`，占 ERP 的 16.7%）不参与重绘。

> 2026-11-02 更新：闸门默认值已按决策 69 从 0.80 降到 0.60。上表的失败数据保留为历史依据；降到 0.60 后，0.642 那类候选也会被放行，重影风险由人工看片承担。

### 3.4 前置（已实现）

1. `case.py`：`FLOWS` 加 `fullRedrawImg`，该 flow 只允许 `[extract]`，源图 2:1 校验与 sha256 守卫同 patchimg。
2. `cli/extract.py`：`plan_image` + `pad_image` 写 `padded.png`、`padded_mask.png`、`image_pad.json`。
3. `cli/generate.py`：`assemble_full` 交 基图 → mask → 氛围参考，`image_max_refs` 断言；`adopt` 支持该 flow。
4. `cli/merge.py`：`stitch_image` 还原 2:1 并回到源图尺寸，闸门拒绝重构图。
5. vrgen：`templates/fullRedrawImg.md`、`IMAGE_ROLE_TEXT["lighting_ref"]`。

### 3.5 验收

- 先用 `--resolution 1K --num 1` 验证请求格式（花 1 张），再跑 `4K --num 4`。
- 五步跑通，输出 8192×4096。
- 交 mask 后 band correlation 应接近 1（锚点冻结），`gate` 至少 warn、接缝 `verdict` 为 ok。
- 与 A 在同一组关键区块上比锐度与氛围距离。
- 单轮额度 ≤ 4 张（外加 1 张 1K 验证）。

## 4. 共同的开发前置

实施顺序：WP0 → WP1 → WP2（先跑 2 段 pilot）→ WP4 → WP5。两条路线的正式实测在 WP4 里各跑一次。

参考图的挂载（两条路线共用）：CLI 没有 `case asset add`，由链式脚本调 `case_mod.add_assets` + `set_submit_selected` 写入 case.toml：

```toml
[[assets]]
id = "i1"
kind = "image"
path = "assets/i1_palace_light_ref_01.png"
role = "lighting_ref"

[submit]
selected = ["i1"]
```

提交顺序固定为 底图 → mask（仅 B）→ 用户参考；模板的 `{image_roles}` 按这个顺序展开成「图1/图2/…」。A 的底图是 `clip.png`，B 的底图是 `padded.png`。

### WP0：文档、契约与提示词（部分已完成）

- 已完成：`docs/decisions.md` 决策 47、`docs/architecture.md` 的两条路线说明、`AGENTS.md` 索引本文。
- `docs/case-model.md`：等 WP1 落地时再补 `组名:` 标识，避免文档先于代码描述不存在的契约。
- vrgen role 文本与模板：已完成（`lighting_ref`、`fullRedrawImg.md`）。

### WP1：case 分组（子文件夹）——A 的硬前置，也是通用能力

- 标识形式：`组名:case名`。`组名` 与 `case名` 各自沿用现有字符集（`^[A-Za-z0-9][A-Za-z0-9._-]*$`）。
- `Case` 保持 `name` = 叶子名（继续作 vrgen 的 job 名，vrgen 的 job 正则不接受 `/`），新增 `group` 与 `id` 属性；`case_dir(id)` 解析成 `<cases 根>/<组>/<叶子>`。
- `case new` 接受带组的 id，自动建目录；叶子名跨组唯一（否则 vrgen 台账同名 job 会撞在一起），创建时扫描校验。
- `case list` / `case show` 显示 id；列表扫两层（`*/case.toml` 与 `*/*/case.toml`）。
- web `/api/cases` 同样扫两层并返回 id；30 条 `{name}` 路由与 2 条正则规则**不改**（id 里没有 `/`，冒号在 URL 路径段里合法）；meta/lock 经 `case_dir(id)` 落到组目录内。
- 需要审计的调用点：所有把 `case.name` 当身份传给 meta/lock/URL 的地方改成 `case.id`；所有 `--job case.name` 保持叶子名不变。
- 验收：分组 case 的新建/读取/列表/演练；`case_dir` 拆分；web 列表包含子目录 case；meta 落在正确目录；`--job` 仍是叶子名；现有 case 不受影响。

### WP2：A 的分段与链式

- `vrstudio img tiles`：按 `--fov 70 --step 60 --width 1920 --height 1080` 生成 6 段计划，写 `tiles.json`；包含每段的 yaw、inner（默认整幅视口）、与上一段的重叠角度。
- `scripts/img_chain.py`：按 §2.2 的职责编排；只调 CLI 与 case 模型，不新增长期契约；A 若被选为正式路线，再收成 `vrstudio` 子命令。
- 测试：分段计划的角度与回绕；链式脚本用合成图跑 2 段（不调平台），断言第二段 source 就是第一段 out、选区外逐位一致。

### WP3：B 的全幅流程（已实现）

- 见 §3.4；测试见 `tests/test_fullredraw_img.py`（case 规则、extract 产物、submit 3 张、上限断言、identity merge）。

### WP4：对比评测

- `scripts/img_compare.py`：对两条路线的成片计算同一组指标并把对比图写到 `cases/<组>/out/`（cases/ 不进 git）。
- 指标：选定区块的 Laplacian/Sobel；与参考图的 Lab 均值、色度直方图距离；跨段边界梯度与视口内部 p95 的比值；ERP 接缝两侧的列差；额度与壁钟。
- 产出：`docs/test-runs/<日期>-still-routes-ab.md`，含并排图、特写与结论草案。

### WP5：选型

- 按 WP4 的结果写 `docs/decisions.md`：哪条做成正式流程、另一条是否保留为特殊用途。
- 前端接入另立计划，本文不含。

## 5. 契约与不动的东西

- `clip.json`、`image.json`、`image_pad.json`、`run.json` 字段集不变。
- 新增：case 标识的 `组名:` 前缀（case.toml 内容不变，只变目录位置）。
- vrgen 的 CLI 契约不变：job 名仍是叶子名，`image submit` 的 `--image-role` 仍是自由文本。
- 视频 patch / fullredraw / gen 不受影响。

## 6. 成本估算

| 路线 | 轮次 | 候选/轮 | 图片张数 | 参考图 | 说明 |
|---|---|---|---|---|---|
| A（6 段） | 6 | 2（pilot 4） | 12–24 | 每轮 3 张（clip + mask + lighting_ref） | 每段人工挑片 |
| B | 1 | 4 | 5 | 基图 + mask + X 张 lighting_ref | 4 张 4K + 1 张 1K 验证请求格式 |

## 7. 风险

- **A 的内容漂移**：每段整幅 inner 被重绘，重叠区被后一段覆盖；闭环处最容易暴露。缓解：挑片时看闭环特写；必要时把 inner 内缩 5–10% 留锚。
- **A 的接缝**：段间重叠 10°（fov 70、step 60）在 8192 宽的 ERP 上约 227 px，够不够让下一段吃掉接缝需要实测；不够就加大重叠、增加段数。
- **B 的 4K 上限**：算术约束；实测区块细节只有源图的 9%，其中一半来自 4K 上限本身（对照组 19%）。
- **B 的冻结带**：mask 保住接缝，但横跨接缝的 16.7% 保持源图像素；氛围变化在这一条带上会断。
- **B 的上传体积**：输入图上限未公布，117.6 MB 单张被 403；默认用 4096 长边的基图副本与 mask 副本。
- **B 的提示词**：上一轮模型会自行添加烛台等物件并整体铺暖光，偏离参考图「暗部为主」的调性；模板已禁止新增人物与建筑构件，仍需要实测压一压。
- **额度**：A 的 24 张是上限，按 2 张/段起步。
- **评测主观性**：指标只能筛掉明显失败，最终仍要看并排图；验收记录里必须同时留数字与图。

## 8. 待确认

1. A 的段数与重叠：默认 fov 70、step 60（6 段、重叠 10°）。要不要先只跑 2 段验证链式，再扫全周？
2. A 的每段候选：默认 2 张，pilot 用 4 张。
3. B 的氛围参考图张数 X：默认 1；上限 11。
4. 评测主指标：默认「区块锐度 + 氛围距离 + 接缝连续性」，人工目视一票否决。
