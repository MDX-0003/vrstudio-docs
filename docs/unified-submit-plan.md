# 生成提交统一化方案（三流程一条 prepare 路径）

状态：审查稿，2026-10-21 由 dacne case 接入角色三视图的讨论升级而来，待批。
设计依据见 `AGENTS.md`「设计原则」（能删就删、共用优先、不为临时需求加长期成本、
用机制替代禁令）。批准后第一步是重写 `docs/case-model.md` 的提交契约，然后才动
两侧代码与测试（硬规则 1 的顺序）。

## 1. 问题来源：生成提交存在两条并行路径与四条人为限制

生成提交这一步在两仓库里被写成了两套形状，多素材需求出现后这个分叉开始挡路。

- vrgen 本地半场有两条 prepare 路径：`_prepare_single`（`vrgen/round/pipeline.py`）
  吃「单一输入视频 + mask」的固定形状，服务 patch 与 fullredraw；`_prepare_gen`
  吃素材清单，服务 gen。「single」的形状在「母版之外还要带任意素材」的组合面前
  装不下：dacne 想给 patch 流带一张角色三视图（`vrstudio/sources/dancer.jpg`）
  时被挡住，图片加进 case 也只是躺在素材列表里，提交链路不会带上它。
- 挡路的限制共四条，位置如下：
  - `--refs 与 --input 互斥`：vrgen `cli.py` submit 的参数校验；
  - patch 非 firstLastFrame 不组装提交集：vrstudio `cli/generate.py` 的
    `refs_needed` 判定，提交 argv 只有 `--input clip.mp4 --mask clip_mask.png`；
  - videoEdit 手写矩阵只认「恰好 1 个视频 edit_master + subject_ref 图片」：
    两侧镜像的 `MODE_ROLES`（`vrgen/refs.py` 与 `vrstudio/case.py`）；
  - fullredraw 素材面板只读锁：前端 `assets.js` 的 `_canEditAssets()`。

## 2. 平台能力核查：限制来自本地契约，不来自平台

平台侧的调用形态本来就是统一的：mglc 只收 `--video`×N + `--image`×N + prompt +
mode，平台不知道「流程」的存在；mask 在这条调用里本来就占一个 `--image` 位置。

- 模型详情缓存（`vrgen_runs/<job>/models.json`）里 Seedance 2.5 的数据：
  videoEdit 接受 1–10 段视频、最多 30 张图片；allMediaRef 接受最多 10 段视频、
  最多 30 张图片。mask 与三视图并存、乃至「母版 + 动作参考视频」的组合，都在
  平台限制之内。
- 结论：四条限制属于本地契约选择，可以重写；真正要保留的平台边界只有
  firstLastFrame 的独立参数通道，与各模式的分辨率、时长、宽高比 validator。

## 3. 三流程在生成步骤的真实差异：只剩装配时填的值

三流程在生成步骤共用同一套执行链——上传缩放、SD 合规素材登记、提交、轮询、
下载、gate、台账（vrgen `execute_round` 已经三流程共用）；差别全部出现在
「装配提交集」这一层填什么值。

- fullredraw 与 gen 的差别共四处：
  - 母版来源：pad 产物 `seedance_input_pad.mp4` 对用户素材列表里的母版；
  - 几何：canvas≠source（21:9 画布对原始比例，band 宽度由 manifest 权威记录、
    模板吃 band_w 等几何变量）对 canvas=source、band 退化为 0；
  - mask：带一张 pad mask 对没有 mask；
  - 参数默认：输出比例固定 21:9（画布本身是 21:9）对比例跟随所选模式。
- patch 的形状与 fullredraw 相同，只是母版与 mask 换成 extract 产物，且后半程
  多一步 merge 回 8K 源；后半程不属于生成步骤，不在本方案范围内。

## 4. 目标

- 生成提交只有一条执行路径：一个 prepare 函数、一个素材登记循环、一处 argv 组装。
- 三个流程的差异收敛为装配差异：每个流程一个装配函数，产出统一的提交资产列表；
  prepare 不感知流程。
- 删除第 1 节列出的四条限制与 `--input`、`--mask` 独立参数；数量、格式、时长、
  比例校验交给平台返回的 validator 数据。
- 前端不新增页面、不为流程或模式新增组件分支（见第 11 节）。

## 5. 统一输入包（契约核心）

提交 = 资产列表 + 几何基准 + 模板 + 变量 + 参数。

- 资产列表条目的字段：id、kind（video|image）、role、path、sha256、derived
  （是否流程产物）。
- 母版 = role 为 edit_master 的条目；缺失时按回退链取（沿用现有 `refs.master()`
  的回退语义）。
- mask 是 kind=image、role=mask 的派生条目：由装配器生成、与母版同源、只读、
  数量 0 或 1；缩放规则是强制缩放到画布尺寸，不按图片预算 fit。
- first_frame/last_frame 角色照常进入清单，argv 组装时映射到
  `--first-image/--last-image` 独立通道；这是唯一按角色分流的位置（见第 7 节）。
- 几何基准（canvas/source）由装配器给出：gen 取母版探测值；patch 取 clip.json
  的 viewport；fullredraw 取 manifest，band 几何变量同步代入模板。prepare 不重
  推导几何（硬规则 3 唯一权威点不变）。
- run_key 覆盖：列表全部条目（含派生条目）+ 几何 + 模板 + 变量 + 参数，幂等
  复用语义不变。

## 6. mask 进清单的立场修正

> 2026-10-21 讨论前半段的结论（后被修正）：「mask 语义上不是用户素材，建议继续
> 走独立参数，不进清单。」
>
> 修正（同日讨论后段）：mask 改为清单内的派生角色条目。修正原因：按「接口能删
> 就删」的设计原则衡量，独立参数会让 vrgen 的 CLI 表面多出一条路径与一个互斥
> 校验；清单化之后素材登记循环合一、前端「流程产物（只读）」层级天然承载它、
> 提示词编号与 argv 顺序自然对齐。清单化要守住的语义只有一条：mask 与母版同源、
> 由装配器生成，用户不能手选任意图当 mask，也不能只删 mask 留母版。将来做手绘
> mask 编辑时再开用户 mask 角色，扩展点保留。

## 7. firstLastFrame 的处理

平台把首尾帧放在 `--first-image/--last-image` 独立 flag，且该模式禁止普通视频与
普通图片参考；这是平台边界，不是本地限制。

- 机制上的吸收方式：首尾帧照常以 first_frame/last_frame 角色进入清单，prepare
  把它们当普通图片条目做探测与预算，仅在 argv 组装时按角色映射到独立 flag。
- 统一后清单机制覆盖全部模式，不存在「gen 走清单、patch 走参数」的模式分叉。

## 8. 四条限制的退役方式：每条禁令由一个机制接住

删禁令的原则是每条删掉的校验都要回答「错了在哪一层报错」。

- `--refs 与 --input 互斥`：只剩一条清单路径，校验对象自然消失。
- patch 不组装提交集：装配器统一后，patch 的提交集 = 派生条目 + 勾选的用户
  素材，与 gen 走同一段代码。
- videoEdit 手写数量矩阵：数量、格式、时长、比例改读模型详情的 validator
  （`load_models` 已有缓存，`params show` 已回显）；超限时按 validator 返回的
  具体项报错。两侧 `MODE_ROLES` 数量规则退役，角色词表保留「职责 → 提示词
  声明」的映射用途（`ROLE_PROMPT` / `mode_variables`）。
- fullredraw 素材只读锁：解锁；派生条目照旧只读，用户素材区开放。

## 9. vrgen 侧改造

- 合并 `_prepare_single` 与 `_prepare_gen` 为单一 prepare，步骤：探测 → 按 kind
  预算 → 缩放 → 渲染提示词（几何变量 + asset_list + 模式规则）→ run_key →
  登记 → argv。
- CLI：`submit` 只保留 `--refs` 清单入口与 `--template`、变量、参数 flags；删除
  `--input`、`--mask` 与互斥校验。是否给旧参数保留一个废弃周期的语法糖（自动
  折叠进清单 + 打废弃告警）待拍板（第 14 节）。
- `build_generate_argv` 保持现状（已支持 videos/images 列表与首尾帧通道）。
- 台账 run.json 增记条目的 derived 标记：run.json 是冻结契约（硬规则 2），按
  程序在本文批准后同步改两侧测试。
- `docs/case-model.md` §4 重写为统一输入包契约（迁移第一步）。

## 10. vrstudio 侧改造

- `resolve_package` 的三分支改写为按 flow 分派的装配函数，统一产出：提交资产
  列表 + 几何基准 + 模板 id；此后共用同一段「写清单 → 调 vrgen」的代码。
  `refs_needed` 判定删除。
- `selected_assets` 统一为：用户勾选优先；默认集 = 派生条目 + 通过当前模式能力
  过滤的用户素材。
- patch 装配器：母版 = `extracts/<current>/clip.mp4`，mask = `clip_mask.png`，
  均为派生条目；fullredraw 装配器：母版与 mask 来自 manifest。
- 两侧镜像的 `MODE_ROLES` 退役；页面角色选项改从能力数据渲染。

## 11. 前端：三种面板继续各只有一份，组件不为流程分叉

> 用户引用的原句与疑问（2026-10-21）：「前端不加任何页面：素材面板、提示词面板、
> 生成参数面板继续各一份，模式与角色选项从能力数据渲染，patch/fullredraw 与 gen
> 的页面差异只剩装配器填的只读条目不同。」——「是意味着前端依然为不同的mode维护
> 独立的前端组件吗？为什么？明明后端功能上都一致了」
>
> 澄清：「各一份」指每种面板只有一份代码、三个流程共用——素材面板、提示词面板、
> 生成参数面板在现状就已经是共用组件（`assets.js` 等是全流程同一个文件），不是
> 每个 mode 一份。本方案不新增页面、不为流程或模式复制组件；变化只有两处：删除
> 组件内部残留的按流程分支（fullredraw 只读锁），模式与角色选项从能力数据渲染
> 而非手写常量。后端统一后，前端组件数量不变、分支减少。

- 具体变化点：
  - fullredraw 解锁素材编辑，派生条目仍只读；
  - 素材区展示派生条目（含 mask），派生条目不可勾掉、不可删除；
  - 角色下拉与数量提示来自 `params show` 的能力数据；
  - 模式选择器是否向 patch/fullredraw 开放待拍板（能力数据已支持，属产品决策；
    开放则 mask 条目按所选模式的能力显隐）。
- 提示词面板：character-repaint 与 360-closure 增加素材清单段（asset_list 计算
  键开放到这两个模板），mask 的职责声明用固定文案（编辑区域标注，不作为画面
  内容参考）。

## 12. 提示词编号与 argv 顺序对齐（契约测试点）

- 编号规则：视频按清单顺序在前、图片按清单顺序在后；派生条目（母版、mask）
  参与编号。
- 生成的提示词素材块必须与 mglc argv 的 `--video`/`--image` 顺序逐一对齐；
  此对齐写入两侧契约测试，防止提示词引用的 @VideoN/@ImageN 与平台实际收到的
  素材错位。

## 13. 迁移步骤与验收

1. 重写 `docs/case-model.md` §4 提交契约（本文批准后的第一步）。
2. vrgen：合并 prepare、CLI 收敛、validator 校验切换；pytest 覆盖统一清单、
   mask 派生条目、首尾帧映射、母版回退链。
3. vrstudio：装配器统一、`selected_assets` 统一、前端解锁与数据驱动渲染；pytest。
4. 验收：dacne（patch 母版 + mask + 三视图 subject_ref + character-repaint）与
   gen、fullredraw 各一个现有 case 的免额度 dry-run 回归全部走通。
- 像素基线不受影响（生成步骤不碰像素），编码档不变；提交门禁仍是
  `uv run pytest` 全绿 + `uv run ruff check .` 干净（硬规则 6）。

## 14. 待拍板项

2026-10-21 契约重写（`case-model.md` §2/§4/§5）时按设计原则取了如下默认；每条都
可以推翻，推翻时改契约再改代码。

1. `--input`/`--mask` **直接删除**，不留废弃语法糖：vrgen CLI 的唯一调用方是
   vrstudio（硬规则 1 的子进程关系），同批改造，无外部消费者。契约已按删除写。
2. 模式选择器是否对 patch/fullredraw 开放：**维持待定**，不影响契约文本；能力
   数据已支持，属产品决策。
3. mask 的角色命名取 **`mask`**；派生条目的 id 前缀取 **`x`**（`xv1`、`xi1`），
   与用户素材的 `v`/`i` 前缀区分，避免 id 分配冲突；清单顺序固定为母版 → mask →
   用户素材。契约已按此写。
4. validator 报错 **不在 CLI 层建中文翻译表**：vrgen 按平台 validator 返回的
   具体超限项报参数错，字段名原样透传（最小实现，与 fail loud 风格一致）。契约
   已按此写。
