# 生成提交统一化方案（三流程一条 prepare 路径）

状态：审查稿，2026-10-21 由 dacne case 接入角色三视图的讨论升级而来，同日按决策 33
修订提交集与流程产物的口径，待批。设计依据见 `AGENTS.md`「设计原则」（能删就删、
共用优先、不为临时需求加长期成本、用机制替代禁令）。批准后第一步仍是重写
`docs/case-model.md` 的提交契约，然后才动两侧代码与测试（硬规则 1 的顺序）。

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

## 3. 三流程在生成步骤的真实差异：只剩候选与装配时填的值

三流程在生成步骤共用同一套执行链——上传缩放、SD 合规素材登记、提交、轮询、
下载、gate、台账（vrgen `execute_round` 已经三流程共用）；差别全部出现在
「候选有哪些、装配时填什么值」这一层。

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
- 提交集只由用户勾选决定：没有默认集，不按流程或模式自动补素材。三个流程的差异
  收敛为「候选清单」与「几何基准」两处装配结果，prepare 不感知流程。
- 流程产物与文件素材在提交契约里同等对待：都能出现在候选里，勾选就提交。
- 删除第 1 节列出的四条限制与 `--input`、`--mask` 独立参数；数量、格式、时长、
  比例校验交给平台返回的 validator 数据。
- 前端不新增页面、不为流程或模式新增组件分支（见第 11 节）。

## 5. 统一输入包（契约核心）

提交 = 勾选的候选清单 + 几何基准 + 模板 + 变量 + 参数。

### 5.1 候选从哪来

- `[[assets]]` 里的文件素材：三个流程共用，用户可增删、改角色、排序。
- 当前流程产物：由流程状态决定路径，不写进 `[[assets]]`，避免与
  `[source]` / `[extract] current` / `*_pad.json` 形成双重真源。
  - patch：`extracts/<current>/clip.mp4`（id `clip`，role `edit_master`）是候选；
    `clip_mask.png`（id `mask`，role `mask`）是内部控制图，由装配器自动附带，
    不作为用户素材；`first_frame_raw.png` / `last_frame_raw.png`（id `first_raw` /
    `last_raw`）只进关键帧工作台输入区，不是提交候选。
  - fullredraw：manifest 指向的 pad 画布（id `pad`，role `edit_master`）是候选；
    `seedance_input_mask.png`（id `pad_mask`，role `mask`）是内部控制图，由装配器
    自动附带。
  - gen：没有流程产物，候选就是 `[[assets]]`。
- 面板里可勾选的只有 `[[assets]]` 文件素材与 clip/pad；mask 与 raw 帧不出现。
  提交契约不区分来源，也没有 `derived` 字段；没有默认集，勾选才提交。

### 5.2 清单条目与顺序

- 条目字段：id、kind（video|image）、role、path、可选 sha256。`sha256` 用于
  用户素材的完整性校验；流程产物没有预先给出的 sha256 时，由 vrgen 读取文件计算
  内容哈希，供 run_key 与台账使用，不再额外复制文件或加标记。
- id 统一为「字母开头、其余为字母数字下划线连字符」的字符串：用户素材沿用
  `v1`、`v2`… / `i1`、`i2`…；进入 refs 的流程产物用固定名 `clip`、`mask`、
  `pad`、`pad_mask`；`first_raw`/`last_raw` 只用于工作台输入，不进入 refs。
- 清单顺序：用户素材与 clip/pad 按 `[submit] selected` 的顺序，mask 固定追加
  在所有用户图片之后。提示词编号与 argv 都按「视频在前、图片在后」分组，组内
  保持清单顺序；**mask 不参与 `@ImageN` 编号**。
- 母版 = 清单里第一条 `edit_master`；没有时按回退链取（沿用 `refs.master()`：
  第一条视频 → 第一条 `space_ref`/`scene_ref` 图片 → 第一条 `first_frame` 图片
  → 第一条图片）。
- `mask` 是内部控制图，role 为 `mask`，role 固定、不可由用户改；由装配器在提交时
  追加，不写进 `selected`。缩放规则是强制缩放到母版的上传画布，不按图片预算 fit；
  仍按图片 validator 的宽高、比例、体积校验。

### 5.3 几何与幂等

- 几何基准（canvas/source）由装配器给出：gen 取母版探测值；patch 取 clip.json
  的 viewport；fullredraw 取 manifest，band 几何变量同步代入模板。prepare 不重
  推导几何（硬规则 3 唯一权威点不变）。
- run_key 覆盖：清单全部条目（按内容哈希）+ 几何 + 模板 + 变量 + 参数，幂等
  复用语义不变。

### 5.4 firstLastFrame 与 patch 的首尾原始帧

- patch 的 extract 在冻结 `clip.json`、`clip.mp4`、`clip_mask.png` 的同时，导出
  clip 首帧与末帧的原始图 `first_frame_raw.png` / `last_frame_raw.png`。这两张图
  从**写完的 `clip.mp4`** 读取，不从原始 360 视频抽帧；按 clip 原始分辨率导出，
  不缩放。准备工作在 extract 阶段一次完成，firstLastFrame 不再依赖工作台里的
  「从 clip 抽帧」按钮。
- 原始帧只在关键帧工作台输入区出现，不是提交候选；`--refs` 清单拒绝 `*_raw`
  角色，因此不能靠手动勾选或直接调 CLI 把它们当首尾帧提交。工作台生成的
  `first_frame` / `last_frame` 定稿图作为 `[[assets]]` 素材进入候选。
- firstLastFrame 的提交集只取勾选里恰好一张 `first_frame` 和一张 `last_frame`，
  按首帧在前、尾帧在后组清单；其余勾选项不参与本次提交，视频也不参与，该模式
  不附带 mask。
- 前端在点击生成时检查这一对：不足或超出就弹出错误提示，不发起后端请求。
  vrgen 保留同样的提交前校验，供 CLI 直接调用时兜底。

## 6. 四条限制的退役方式：每条禁令由一个机制接住

删禁令的原则是每条删掉的校验都要回答「错了在哪一层报错」。

- `--refs 与 --input 互斥`：只剩一条清单路径，校验对象自然消失。
- patch 不组装提交集：三流程都产出候选清单，patch 的提交集就是用户勾选的候选，
  与 gen 走同一段代码。
- videoEdit 手写数量矩阵：数量、格式、时长、比例改读模型详情的 validator
  （`load_models` 已有缓存，`params show` 已回显）；超限时按 validator 返回的
  具体项报错。两侧 `MODE_ROLES` 的按模式角色矩阵退役，保留四条语义规则：
  firstLastFrame 恰好一对首尾帧、至多一个 `edit_master` 且必须是第一条视频、
  `mask` 只能是图片、`first_frame_raw`/`last_frame_raw` 不能进入 `--refs`。
  角色词表继续承担「职责 → 提示词声明」的映射（`ROLE_PROMPT` /
  `mode_variables`）。模型详情缓存缺失、过期或刷新失败时直接报配置错，提示
  `vrgen models --refresh`；不在提交时回退内置限额。
- fullredraw 素材只读锁：解锁；pad 与用户素材作为候选，mask 由装配器自动附带。

## 7. 前端提交门禁

- 勾选集合为空时，生成按钮禁用或点击后提示「没有勾选任何素材」，不发请求。
- firstLastFrame 下，勾选里没有恰好一张 `first_frame` 加一张 `last_frame` 时，
  点击生成弹出具体缺什么或多什么，不发起后端请求。
- 这两条是交互层的提前拦截，不替代 vrgen 的提交前校验；直接调用 CLI 的路径
  仍由 vrgen 报参数错。

## 8. vrgen 侧改造

- 合并 `_prepare_single` 与 `_prepare_gen` 为单一 prepare，步骤：探测 → 按 kind
  预算 → 缩放 → 渲染提示词（几何变量 + asset_list + 模式规则）→ run_key →
  登记 → argv。
- CLI：`submit` 只保留 `--refs` 清单入口与 `--template`、变量、参数 flags；删除
  `--input`、`--mask` 与互斥校验。`--input`/`--mask` 直接删除，不留废弃语法糖：
  vrgen CLI 的唯一调用方是 vrstudio，同批改造，无外部消费者。
- `build_generate_argv` 保持现状（已支持 videos/images 列表与首尾帧通道）。
- 台账 run.json 不新增 `derived` 字段；`params.refs` 只记录 id/kind/role/path/
  sha256/upload/width/height。run.json 仍是冻结契约，本方案不改它的字段集。
- `docs/case-model.md` §2/§4/§5 按本方案重写（迁移第一步）。

## 9. vrstudio 侧改造

- `resolve_package` 的三分支改写为按 flow 分派的候选装配函数，统一产出：
  候选清单（`[[assets]]` + clip/pad）+ 几何基准 + 模板 id；此后共用同一段
  「按 selected 过滤 → 追加 mask → 写清单 → 调 vrgen」的代码。`refs_needed`
  判定删除。
- 提交集只取 `[submit] selected`；缺省为空集，不再按模式取默认集。删除素材时
  同步从 `selected` 移除；重排不改 id，`selected` 不动。
- patch 装配器：候选 = 当前 extract 的 clip + `[[assets]]`；videoEdit 等需要
  区域控制的模式再追加 mask；firstLastFrame 下只取勾选的首尾定稿图，不追加 mask。
  fullredraw 装配器：候选 = manifest 的 pad + `[[assets]]`，再追加 mask。
- `vrstudio extract` 增加首尾原始帧导出（见 5.4），文件名与位置写入契约；这两张
  图只给工作台，不进入 refs 清单。
- 两侧镜像的 `MODE_ROLES` 按模式矩阵退役；角色选项从全局角色词表渲染，数量提示
  来自 validator 数据。

## 10. 提示词编号与 argv 顺序对齐（契约测试点）

- 编号规则：视频按清单顺序在前、图片按清单顺序在后；勾选的用户素材与 clip/pad
  参与编号，mask 不参与。
- 生成的提示词素材块必须与 mglc argv 的 `--video`/`--image` 顺序逐一对齐；
  此对齐写入两侧契约测试，防止提示词引用的 @VideoN/@ImageN 与平台实际收到的
  素材错位。mask 固定追加在所有图片之后，模板用固定文案说明最后一张图是区域
  标注，不写编号；提示词面板按当前勾选集合预览编号。

## 11. 前端：三种面板继续各只有一份，组件不为流程分叉

- 素材面板、提示词面板、生成参数面板在现状就已经是共用组件（`assets.js` 等是
  全流程同一个文件），不是每个 mode 一份。本方案不新增页面、不为流程或模式
  复制组件。
- 具体变化点：
  - fullredraw 解锁素材编辑；clip/pad 显示为可勾选候选，mask 与 raw 帧不显示；
  - 新增素材不自动进入提交集，面板提供全选/反选与当前提交数量；
  - 角色下拉来自全局角色词表，数量提示来自 `params show` 的能力数据；
  - 模式选择器：patch 提供 videoEdit/allMediaRef/videoExtend/firstLastFrame
    （firstLastFrame 仅 16:9）；fullredraw 维持 videoEdit；gen 维持现有列表。
- 提示词面板：character-repaint 与 360-closure 增加素材清单段（asset_list 计算
  键开放到这两个模板）；mask 的说明用固定文案（最后一张图为编辑区域标注，
  不作为画面内容参考），不占 `@ImageN`。360-closure 里现有的 `<图片1>` 同步改为
  「最后一张图片」，character-repaint 增加同一句固定说明。

## 12. 迁移步骤与验收

1. 重写 `docs/case-model.md` §2/§4/§5 的提交契约。
2. vrgen：合并 prepare、CLI 收敛、validator 校验切换；pytest 覆盖统一清单、
   mask 自动附带与不编号、raw 角色拒绝、首尾帧映射、母版回退链。
3. vrstudio：extract 产出首尾原始帧、候选装配器统一、`selected` 无默认集、
   前端解锁与门禁；pytest。
4. 验收：dacne（patch 母版 + mask + 三视图 subject_ref + character-repaint）与
   gen、fullredraw 各一个现有 case 的免额度 dry-run 回归全部走通。
- 像素基线不受影响（生成步骤不碰像素），编码档不变；提交门禁仍是
  `uv run pytest` 全绿 + `uv run ruff check .` 干净（硬规则 6）。

## 13. 待拍板项

1. `--input`/`--mask` 直接删除，不留废弃语法糖；契约按删除写。
2. `params show` 的 `--input` 改为 `--refs`，与 `prompt show` 对齐：从清单里取
   母版计算输入档位，母版是图片时 `input` 为空。契约按此写。
3. id 命名：用户素材 `v1`/`i1`，进入 refs 的流程产物 `clip`/`mask`/`pad`/
   `pad_mask`；raw 帧的 `first_raw`/`last_raw` 只用于工作台，不进入 refs。不再
   使用 `x` 前缀；mask 是内部控制条目，id 固定。
4. validator 报错不在 CLI 层建中文翻译表：vrgen 按平台 validator 返回的具体
   超限项报参数错，字段名原样透传。模型详情缓存缺失、过期或刷新失败时直接报
   配置错，提示 `vrgen models --refresh`；CI 与免额度测试用固定的 `models.json`
   fixture，不依赖平台登录。
5. 旧 case 没有 `[submit]` 段时按空集处理，升级后首次打开需要重新勾选一次；
   不提供「缺省全选」的兼容默认。若需要迁移，另开一次性脚本，不在提交时隐式
   补全。
