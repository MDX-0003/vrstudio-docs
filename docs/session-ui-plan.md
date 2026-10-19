# 前端项目会话选择器的实现方案

本文记录“在 web 生成页选择项目生成会话”的实现方案，供日后复查。会话本身是什么、如何取得、额度如何扣减，见 `docs/sessions.md`；本文只讨论前端与 vrgen 之间如何传递和刷新这份信息。

状态：已实施（2026-10-19），浏览器验收通过。验收记录见文末第 12 节。

## 1. 目标与约束

目标有三条：

1. 用户可以在生成页看到项目、剧集、生成会话三层选项，并选择本次生成使用的会话。
2. 选择结果随 case 保存，页面重新打开后仍然存在。
3. 页面刷新时重新向 mglc 获取会话列表，不用浏览器缓存或长期服务端缓存。

约束来自既有架构：

- vrstudio 的 web 层不得直接调用 mglc，也不得 `import vrgen`；跨仓库只走 CLI 契约（`AGENTS.md` 硬规则 1）。
- 项目、剧集、会话的查询属于平台交互，应当留在 vrgen。
- 会话 ID 绑定具体项目与账号，不能写进源码、配置模板或测试。
- 现有 submit 参数优先级保持不变：命令行显式参数 > `generation.toml` > 配置默认值。

## 2. 数据通路

浏览器只与 vrstudio web 通信，vrstudio 只与 vrgen 的 CLI 通信，vrgen 再调用 mglc：

```text
浏览器
  → GET /api/sessions                （vrstudio web）
  → vrgen sessions list              （CLI 子进程）
  → mglc project/episode/session     （只读查询）
```

选择后的保存路径：

```text
浏览器
  → POST /api/case/<名字>/params     （vrstudio web）
  → vrgen params save                （CLI 子进程）
  → runs/<job>/generation.toml       （job 级草稿）
```

提交时浏览器不传会话 ID，vrgen 从 `generation.toml` 读取并拼进 mglc 命令。这样会话信息只有一个存放位置，前端不需要参与生成参数的最终解析。

## 3. vrgen 的只读命令

新增命令：

```bash
vrgen sessions list [--project-id <id>] [--episode <n>]
```

行为：

- 不带参数：列出当前账号可访问的全部项目，并展开每个项目的全部剧集与每个剧集的全部会话。
- 只给 `--project-id`：只展开该项目的剧集与会话。
- 同时给 `--project-id` 与 `--episode`：只返回该集及其会话。
- 只给 `--episode` 不给 `--project-id` 是参数错误，退出码 2。
- 命令只调用只读接口，不消耗额度。

实现位置：

- `vrgen/src/vrgen/platform/client.py` 增加 `project_list()`、`episode_list(project_id)`、`session_list(project_id, episode)`，与现有 `model_list()`、`asset_list()` 同一层。
- `vrgen/src/vrgen/sessions.py` 负责三层查询的组装与空值处理。
- `vrgen/src/vrgen/cli.py` 增加 `sessions` 子命令，只做参数校验与 JSON 输出。

## 4. JSON 输出契约

`vrgen sessions list` 输出单个 JSON 对象：

```json
{
  "fetched_at": "2026-10-19T06:30:00Z",
  "projects": [
    {
      "id": 2060150527854528,
      "name": "2026大秦寻仙VR",
      "episodes": [
        {
          "no": 1,
          "id": 2040714108516707,
          "name": "秦宫夜宴",
          "sessions": [
            {"id": 2060150528006080, "name": "未命名"}
          ]
        }
      ]
    }
  ]
}
```

字段说明：

- `fetched_at` 是本次查询完成的 UTC 时间，页面可显示“刚刚获取”。
- `projects[].id/name` 来自 `mglc project list`。
- `episodes[].no/id/name` 来自 `mglc episode list`；`no` 是提交时使用的剧集序号。
- `sessions[].id/name` 来自 `mglc session list`。
- 任何一层为空时输出空数组，不把缺失当成错误。

错误处理：

- mglc 未登录、命令失败或返回非 JSON：沿用 vrgen 的退出码契约，失败信息写 stderr。
- 页面收到错误时显示提示，并保留 `generation.toml` 里已保存的会话信息，不自动清空。

## 5. 保存字段

`generation.toml` 在现有 `resolution`、`scale`、`session_id` 之外增加两个只用于回显的字段：

```toml
resolution = "1080p"
scale = "auto"
project_id = 2060150527854528
episode = 1
session_id = 2060150528006080
```

- `project_id` 与 `episode` 不参与 mglc 命令，只用于页面恢复两个上级下拉框。
- 真正提交时仍然只把 `session_id` 传给 mglc。
- 旧文件只有 `session_id` 时保持兼容；页面在会话树里反查项目和剧集，找不到时显示“已失效”。
- 选择“个人额度”时写 `session_id = 0`，并清空 `project_id` 与 `episode`。

`vrgen params save` 增加 `--project-id` 与 `--episode` 选项；不传时保留已有值。`vrgen params show` 的 `current` 返回三项，前端据此恢复下拉框。

## 6. 前端交互

生成页的“生成参数”区域增加一组“生成额度”控件：

- 项目下拉框：列出全部项目。
- 剧集下拉框：显示“第 N 集 · 名称”，随项目变化重新填充。
- 会话下拉框：显示“名称（ID 后 6 位）”，随剧集变化重新填充；额外提供“个人额度（不使用项目会话）”选项。
- “刷新会话”按钮：重新请求 `/api/sessions`，不改变已保存的选择。

页面加载顺序：

1. `loadInfo()` 取得 case 信息与 `generation_params.current`。
2. 同时请求 `/api/sessions` 取得会话树。
3. 用 `current.project_id` 选中项目，用 `current.episode` 选中剧集，用 `current.session_id` 选中会话。
4. 如果保存的会话不在树里，追加一个标红的“已失效：<ID>”选项并选中它，提示用户重新选择。

保存时机：

- 用户切换项目时，只更新剧集下拉框，不立即写入 `generation.toml`，避免把尚未选完的中间状态保存。
- 用户切换剧集时，只更新会话下拉框，不立即保存。
- 用户选中具体会话或“个人额度”时，把 `project_id`、`episode`、`session_id` 与当前的分辨率、缩放一起提交，调用 `POST /api/case/<名字>/params`。

## 7. 实时刷新

- `/api/sessions` 每次被请求都执行 `vrgen sessions list`，vrgen 默认不缓存。
- vrstudio 现有 `NoStoreMiddleware` 已经禁止浏览器缓存响应，刷新页面必然重新请求。
- 页面加载、重新打开 case、点击“刷新会话”都会重新获取。
- 不设置固定间隔轮询；会话列表不是高频变化数据，轮询只会增加 mglc 调用。
- 如果未来项目或剧集数量增长到每次全量查询明显变慢，再加入短期缓存与 `--refresh` 绕过开关；届时页面刷新会带 `refresh=1` 强制更新。

## 8. 失效与异常状态

- 会话 ID 不在最新树里：显示“已失效”，保持旧 ID 选中，不自动改回个人额度，避免静默切换计费上下文。
- 会话名为空或重复：选项文字必须带项目名、剧集序号与 ID 后几位。
- mglc 未登录或查询失败：下拉框显示错误文案与“重试”按钮；提交仍按已有草稿执行。
- 多标签页同时修改：沿用“最后写入为准”，不额外加锁；多用户阶段再按决策 17 的 case 锁处理。

## 9. 测试与验收

- vrgen：用假的 mglc 客户端覆盖三层查询、项目/剧集过滤、空列表、查询失败；断言命令不调用生成接口。
- vrstudio web：覆盖 `/api/sessions` 的 JSON 透传、参数保存携带三项字段、mglc 缺席时的降级显示。
- 浏览器验收：
  1. 打开 `simple_gen_01`，项目、剧集、会话三层显示已保存的值。
  2. 刷新页面，网络请求重新发出，下拉框仍保持已保存的选择。
  3. 切换到其他项目/剧集/会话，`generation.toml` 三个字段同步更新。
  4. 选择一个已不存在的会话，页面显示“已失效”而不静默回退。
  5. 提交时 `run.json` 的 `params.session_id` 与页面选择一致。

门禁保持两仓库 `uv run pytest` 全绿与 `uv run ruff check .` 干净。

## 10. 实施顺序与回退点

每一步单独提交，任何一步出问题都可以回到上一提交：

1. 文档与契约：本文、`case-model.md`、`sessions.md`、`AGENTS.md` 索引。
2. vrgen：客户端方法、`sessions list` 命令、`generation.toml` 的 `project_id`/`episode` 字段、测试。
3. vrstudio：`/api/sessions` 端点、参数保存扩展、生成页三个联动下拉框、测试。
4. 浏览器验收：刷新、切换、保存、失效提示，最后更新本文状态与路线图。

## 11. 备选方案与取舍

- 单层会话下拉框：把所有项目和剧集的会话压成一个列表。实现简单，但会话名重复时无法区分，且项目名与剧集信息会挤在选项文字里，不如三层联动清楚。
- 手动填写会话 ID：当前已经可用，不需要前端开发。它把查找项目、剧集、会话的成本留给用户，且容易填错，只适合临时排查。
- 一次性全量树与懒加载：当前规模是 1 个项目、5 个剧集，一次取全的调用量可以接受，页面逻辑也最简单。项目数增长后再改成“先项目、后剧集、再会话”的懒加载。

## 12. 浏览器验收记录（2026-10-19）

在 `simple_gen_01` 上完成以下检查：

- 打开 case 后，三个下拉框显示项目「2026大秦寻仙VR」、第 1 集「秦宫夜宴」、会话「未命名（2060150528006080）」；此时 `generation.toml` 只有 `session_id`，页面在会话树里反查出了项目与剧集。
- 选择“个人额度”后，`generation.toml` 的 `session_id`、`project_id`、`episode` 三项被清空，页面提示“已切换为个人额度”。
- 重新选择项目会话后，三个字段写回 `generation.toml`，页面提示“已保存项目会话 2060150528006080；下次提交扣项目额度”。
- 刷新页面后 `/api/sessions` 重新请求，`fetched_at` 从 `06:24:51` 变为 `06:25:14`，三个下拉框仍保持已保存的选择。
- 点击“刷新会话”按钮后，`fetched_at` 更新为 `06:25:27`，已选会话不变。
- 临时把 `session_id` 改成不存在的 `999999` 并刷新：会话下拉框显示“⚠ 已失效：999999”，没有静默回退到个人额度；重新选中有效会话后保存恢复。
- 测试规模：vrgen 81 个、vrstudio 237 个，合计 318 个全绿；两仓库 `ruff check` 干净。
