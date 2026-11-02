# 素材角色：设置与运行机制

适用读者：要新增一个素材角色、给流程加新约束、或者排查“角色不生效 / 保存被拒 / 提交被拒”的人。读完应该能回答三件事：词表在哪、每个字段谁消费、新约束该落在哪一层。

## 0. 一句话模型

角色是**素材在提示词里的职责声明**，外加两条硬约束：允许的素材种类、是否由流程提供。

它不决定流程，也不决定生成模式：

- 流程（patch / fullredraw / gen）决定**有哪些候选**（clip、pad、`[[assets]]`）。
- 生成模式（videoEdit / allMediaRef / videoExtend / firstLastFrame）决定**平台怎么生成**。
- 角色只决定**这张素材在提示词里承担什么、能不能这么用**。

## 1. 权威与副本

| 位置 | 角色 | 说明 |
|---|---|---|
| `docs/roles.json` | 权威 | 契约快照，字段见 §2 |
| `vrgen/src/vrgen/roles.json` | 副本 | 与权威逐字节相同 |
| `vrstudio/src/vrstudio/roles.json` | 副本 | 与权威逐字节相同 |
| `vrgen/src/vrgen/roles.py` | 读取方 | 派生 `ROLES` / `ROLE_PROMPT` / `ROLE_KINDS` / `RESERVED_ROLES` / `RAW_ROLES` |
| `vrstudio/src/vrstudio/roles.py` | 读取方 | 派生 `ROLES` / `ROLE_LABELS` / `ROLE_KINDS` / `RESERVED_ROLES`，并提供 `roles_payload()` 给网页 |
| `docs/case-model.md` §2 | 人读说明 | 角色职责与 `case.toml` 契约 |

两个仓库是独立 clone、独立 CI，跨仓库只允许走 CLI 契约（`AGENTS.md` 硬规则 1），所以不能共享一个 Python 模块，只能共享这份 JSON。三份文件必须逐字节相同；两个仓库各有一条 `tests/test_roles_contract.py`：

- 断言本地派生词表与快照逐项相等（漏改代码会红）；
- 断言快照的 SHA256 等于测试里钉住的常量（改 JSON 不改摘要会红）。

当前摘要：`4c7a53dde440e76a9208ea898e7bfb442dab092f8b4265c2df15b4b8bc451a1f`。

**已知边界**：单仓库 CI 看不到对端，所以“两个副本互相不一致”只能靠摘要保持一致这条纪律约束；改角色时三份 JSON + 两个测试常量一起改。

## 2. 字段语义与消费方

`roles.json` 的每一项：

| 字段 | 示例 | 谁消费 | 语义 |
|---|---|---|---|
| `name` | `lighting_ref` | 两仓库的 `ROLES`、`case.toml`、`[submit]`、refs JSON | 唯一标识，写进契约 |
| `label` | `光照参考` | 前端下拉、素材库“用途”行 | 短名 |
| `help` | `光照参考（只提供光源位置…）` | 网页 tooltip（`/api/case` 的 `role_help` 与 `roles[].help`） | 长说明 |
| `prompt` | `光照参考，只提供光源位置…` | **仅 vrgen** | 拼进提示词【素材清单】的职责句 |
| `kinds` | `["image"]` 或 `null` | 两仓库校验、前端过滤 | `null` 表示不限种类；非空表示只能是列出的种类 |
| `modes` | `["videoEdit", …]` | 前端过滤 | 允许出现该角色的生成模式；`[]` 表示任何提交都不出现 |
| `open` | `true` / `false` | 前端过滤 | 是否出现在生成页下拉；`false` 只用于当前值补“旧角色” |
| `reserved` | `true` / `false` | 两仓库校验、前端过滤 | 由流程产物或工作台提供，用户不能给文件素材指定 |

两种“特殊角色”的写法：

- `reserved: true`（`mask`、`first_frame_raw`、`last_frame_raw`）：由流程或工作台产生，不进用户候选。vrgen 另外按名字后缀 `_raw` 派生 `RAW_ROLES`，用于“只用于关键帧工作台”的专门报错。
- `open: false`（`scene_ref`、`space_ref`、`mid_frame`）：词表里有、旧 case 能读，但普通下拉不展示；当前行仍是这个角色时，前端会用 `label` 补一条「（旧角色）」。

## 3. 运行链路

```
case.toml ──写/读──▶ vrstudio/case.py ──校验(roles.py 词表 + kinds)──▶ 提交清单
                                                                        │
                         vrstudio generate submit（assemble）            │
                         [[assets]] 选中的 + clip/pad + 自动追加 mask   │
                                                                        ▼
                                                     vrgen submit --refs refs.json
                                                     load_refs / validate_mode
                                                     validate_counts（模型 validator）
                                                                        │
                                                                        ▼
                                                    提示词：asset_list（roles.json 的 prompt）
                                                    模板固定块：<视频1>、最后一张图是 mask
                                                                        │
                                                                        ▼
                                      /api/case 下发 roles + role_help ──▶ 前端下拉
                                      optionsFor：open → kinds → modes
```

逐段落点：

1. **case.toml 读写**：`vrstudio/src/vrstudio/case.py` 的五处校验——加载 `[[assets]]`（`_validate_asset`，约 :366）、加载 `[submit].roles`（`_parse_submit`，约 :350）、添加素材（`add_assets`，约 :439）、改素材角色（`set_asset_role`，约 :495）、保存提交角色（`set_submit_selected`，约 :578）。五处都调用同一个 `_require_role_kind`（约 :301），规则来自 `roles.py` 的 `check_kinds`。流程产物 `clip`/`pad` 按视频处理（`_flow_asset_kinds`，约 :296）。
2. **装配提交清单**：`vrstudio/src/vrstudio/cli/generate.py` 的 `candidates` / `assemble`。提交集只认 `[submit] selected`；mask 由装配器追加在所有用户图片之后，不参与 `@ImageN` 编号。
3. **vrgen 校验**：`vrgen/src/vrgen/refs.py` 的 `load_refs`（角色必须属于 `ROLES`）与 `validate_mode`（约 :129：RAW 不能进清单、`check_kinds`、至多一个 `edit_master` 且必须是第一条视频、firstLastFrame 恰好首尾一对）。数量/时长/比例/像素交给模型详情 validator（`validate_counts`）。
4. **提示词渲染**：`asset_list`（约 :195）按“视频在前、图片在后、组内保持清单顺序”生成 `@VideoN` / `@ImageN`，每行取 `prompt`；mask 不编号，模板用固定文案“最后一张图片是区域标注”。模式任务句在 `_ROLE_RULES`（约 :33），模板正文在 `vrgen/templates/`。
5. **前端**：`/api/case` 在 `vrstudio/src/vrstudio/web/app.py`（约 :1318）下发 `role_help` 与 `roles`；下拉过滤在 `frontend/src/utils/roles.ts` 的 `optionsFor`——`open && !reserved` → `kinds` → `modes`，当前值不在结果里时由同一份词表补“旧角色”。默认角色仍是前端一条规则：`frontend/src/constants/assetRoles.ts` 的 `defaultRole`（视频 `motion_ref`、图片 `subject_ref`）。

## 4. 新增一个角色的标准路径

目标：只改词表与测试，**不改前端**（下拉来自服务端）。

1. 在 `docs/roles.json` 增一项，填全 `name/label/help/prompt/kinds/modes/open/reserved`。
2. 复制到两个仓库，保持逐字节相同：
   ```
   copy /b E:\VRAIGC\docs\roles.json E:\VRAIGC\vrgen\src\vrgen\roles.json
   copy /b E:\VRAIGC\docs\roles.json E:\VRAIGC\vrstudio\src\vrstudio\roles.json
   ```
3. 重算摘要并同步两个测试常量：
   ```
   uv run --no-project python -c "import hashlib;print(hashlib.sha256(open(r'E:\VRAIGC\docs\roles.json','rb').read()).hexdigest())"
   ```
   两个 `tests/test_roles_contract.py` 里的 `CONTRACT_SHA256` 一起改。
4. 如果模式的 task/timeline 句子需要为它补话（例如 `lighting_ref` 要在 videoEdit 的任务句里写“或提供光照参考”），改 `vrgen/src/vrgen/refs.py` 的 `_ROLE_RULES`。
5. 如果它要成为某类素材的默认角色，改前端 `defaultRole`；否则前端不动。
6. 如果它由流程提供（用户不能选），把 `reserved` 设为 `true`，并确认装配器真的会附上它（今天的例子只有 mask）。
7. 跑测试与预演：
   ```
   cd E:\VRAIGC\vrgen && uv run pytest -q && uv run ruff check .
   cd E:\VRAIGC\vrstudio && uv run pytest -q && uv run ruff check .
   cd E:\VRAIGC\vrstudio\frontend && npm run typecheck && npm test && npm run build
   cd E:\VRAIGC\vrstudio && uv run vrstudio generate submit --case <名> --check
   ```
   `--check` 会打印展开后的提示词，重点看【素材清单】那一行和 `@VideoN/@ImageN` 编号。

新增**视频**角色时多看一步：模板固定块默认“第一条视频是待编辑母版”，母版回退链在 `vrgen/src/vrgen/refs.py` 的 `master`（约 :169）与 `vrstudio/src/vrstudio/cli/generate.py` 的 `_master`。新视频角色若可能排在母版之前，要确认回退链与模板措辞，否则会静默换错母版。

新增**图片**角色时确认 mask 仍是最后一张：装配器已固定追加，别在模板里把“最后一张图片”改成按编号指代。

## 5. 新约束该落在哪一层

| 约束类型 | 落点 | 说明 |
|---|---|---|
| 某角色只能用于某类素材 | `roles.json` 的 `kinds` | 两仓库校验 + 前端过滤，接口直调也拦得住 |
| 某角色只在某些生成模式出现 | `roles.json` 的 `modes` + `open` | 注意：后端目前不逐条校验 `modes`，见 §7 |
| 某角色由流程提供、用户不能选 | `roles.json` 的 `reserved` | 两仓库都拒；装配器负责真正附上 |
| 角色写进提示词的职责句 | `roles.json` 的 `prompt` | 只影响 vrgen |
| 模式的任务/时间线规则 | `vrgen/src/vrgen/refs.py` `_ROLE_RULES` | 例如“图片只定义外观或提供光照参考” |
| 提示词固定约束、禁止项 | `vrgen/templates/*.md` | 改模板属于内容改动，跑模板测试 |
| 数量/时长/比例/像素上限 | 模型详情 validator；`validate_mode` 只留平台接不住的语义规则 | 不要把可配置上限写进本地常量 |
| 首尾帧成对、母版位置 | `vrgen/src/vrgen/refs.py` `validate_mode` | 跨角色的组合规则 |
| 页面按钮可用/禁用与提示 | 后端 `gates` + 前端 `runBlockReason` | 权威判断必须在后端，前端只做提示 |
| 流程步骤、几何、文件命名 | `vrstudio` 的 `redraw/`、`patch/`、`cli/` | 与素材角色无关，别塞进词表 |

判断口诀：**“这张素材能不能用”进词表，“这次提交能不能做”进后端校验，“这句话怎么写”进模板/模式规则。**

## 6. 风险与排查

| 症状 | 先查 | 常见根因 |
|---|---|---|
| 下拉里没有新角色 | `serve` 是否重启；`/api/case` 的 `roles` 是否含它 | 旧进程没加载新词表；`open=false`；`modes` 不含当前模式 |
| 下拉是空的 | 浏览器是否加载了新包；接口是否报错 | 前端已改为只认服务端 `roles`，旧 `serve` 不下发就空 |
| 保存 case 报“角色 x 只能用于 image 素材” | 该素材的 `kind` | `kinds` 与素材种类冲突；`pad`/`clip` 是视频 |
| 旧 case 打不开 | 报文里的素材 id 与角色 | 新收紧的 `kinds` 误伤历史数据；先扫 `cases/*/case.toml` 再收紧 |
| 提交报同一条种类错 | `refs.json` 里该条目的 `kind/role` | 前端拦住了但接口直调/旧数据绕过了；这正是五处校验存在的理由 |
| 提示词【素材清单】行不对 / 编号跳号 | `[submit] selected` 顺序；mask 是否在清单末 | 视频在前图片在后；mask 不参与编号 |
| 切到 firstLastFrame 后普通角色显示“（旧角色）” | 当前行的角色 | 正常：该角色不在这个模式，只是保留当前值，不是数据损坏 |
| 改了 `roles.json` 但契约测试红 | 两个 `CONTRACT_SHA256` | 摘要未同步；三份文件不一致 |
| 装成 wheel 后找不到 `roles.json` | `roles.py` 的 `Path(__file__).with_name(...)` | 快照必须留在包目录内，依赖构建后端收包内数据文件 |
| 两个仓库行为不一致 | 两侧 `test_roles_contract.py` 的摘要 | 副本漂移；单仓 CI 看不到对端 |

## 7. 已知边界

1. **`modes` 目前只约束界面**。后端不逐条校验“角色 × 模式”；模式专属角色靠各模式的语义规则兜底（firstLastFrame 要求恰好一对首尾帧、不能带视频）。若未来要硬校验，在 `validate_mode` 里按已传入的 `mode` 逐条比对每个 ref 的 `modes` 即可，不需要扩展 refs 清单。
2. **没有流程（flow）维度**。`modes` 是生成模式，不是流程；一个 `open` 的角色只要模式匹配，在 patch / fullredraw / gen 三个生成页都会出现。需要“只在 fullredraw 出现”这类角色时，要加 `flows` 字段并同时扩 payload 与前端过滤。
3. **跨仓库漂移无法在单仓 CI 发现**。只能依靠逐字节副本 + 两个测试里的同一摘要，属于纪律性约束。
4. **关键帧图片步是另一份小词表**：`subject_ref` / `detail_ref` 只存在于 `vrstudio/src/vrstudio/keyframe.py`（:25）与前端 `KEYFRAME_ROLE_OPTIONS`，服务于 `keyframe.toml`，不进入视频提交清单与 `roles.json`。改它不要动角色快照。
5. **“旧角色”标签语义偏宽**：既表示“历史上用过、现在不开放”，也表示“当前模式不可用”。排查时先看该角色在当前 `modes` 里是否成立。
6. **默认角色仍是前端规则**：新增角色不会自动成为默认；要改默认必须改 `defaultRole` 并跑前端测试。
7. **快照内容与文档可能不同步**：`docs/case-model.md` §2 是人读说明，`roles.json` 是机器契约。改词表时两处一起改；契约测试只保证代码与快照一致，不保证文档同步。

## 8. 验证命令

```
# 契约与词表
cd E:\VRAIGC\vrgen && uv run pytest tests/test_roles_contract.py tests/test_refs.py -q
cd E:\VRAIGC\vrstudio && uv run pytest tests/test_roles_contract.py tests/test_casemodel.py -q

# 全量门禁（vrstudio 的本机 vrstudio.toml 若覆盖了 web.proxy_max_w，
# 先临时挪开再跑，否则 test_web_proxy 会按内置默认 4096 失败）
cd E:\VRAIGC\vrgen && uv run pytest -q && uv run ruff check .
cd E:\VRAIGC\vrstudio && uv run pytest -q && uv run ruff check .

# 前端
cd E:\VRAIGC\vrstudio\frontend && npm run typecheck && npm test && npm run build

# 免额度预演：看展开后的提示词【素材清单】与编号
cd E:\VRAIGC\vrstudio && uv run vrstudio generate submit --case <名> --check
```

## 9. 相关文件与决策

| 位置 | 内容 |
|---|---|
| `docs/roles.json` | 角色契约快照（权威） |
| `vrgen/src/vrgen/roles.py`、`vrstudio/src/vrstudio/roles.py` | 两侧读取与派生 |
| `vrgen/src/vrgen/refs.py` | 提交清单解析、语义校验、提示词素材块 |
| `vrstudio/src/vrstudio/case.py` | case.toml 读写与五处角色校验 |
| `vrstudio/src/vrstudio/web/app.py` | `/api/case` 下发 `roles` / `role_help`，角色修改接口 |
| `vrstudio/frontend/src/utils/roles.ts` | 下拉过滤（open / kinds / modes / 旧角色） |
| `vrstudio/frontend/src/constants/assetRoles.ts` | 默认角色与关键帧小词表 |
| `docs/case-model.md` §2 | 角色职责声明、`case.toml` 与 `--refs` 契约 |
| `docs/decisions.md` 决策 44 / 45 | 光照参考角色的由来；词表单一化与 kind 数据化 |
