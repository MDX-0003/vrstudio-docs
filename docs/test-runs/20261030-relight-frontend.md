# 重打光前端接入的实施与验收

记录时间：2026-10-30。背景：决策 59/60/61，方案见 `docs/plan/relight-frontend-plan.md`。
结论：`relight` 一条流程（素材 → 重打光 → 对比）已在 CLI 与 web 两端跑通；图像与视频两条
CLI 收成一个 `vrstudio relight`；8K 真实素材（8192×4096）在 CLI 与页面上各跑完一轮小样与
整段，未消耗平台额度。

## 1. 落点

- `vrstudio/src/vrstudio/cli/relight.py`：`relight` 改为按 GT 的媒体类型派发（图片走单帧、
  视频走整段）；新增 `--sample N`（只渲染采样帧 PNG）与 `--case`（以 case 为单位，产物写
  case 的 `out/` 并回写 `[relight] current`）；类型专属参数用错按参数错退出 2。`relight-video`
  退役，`resolve_reference` 增加 `check_hold` 开关（小样跳过整段同位检查）。
- `vrstudio/src/vrstudio/cli/__init__.py`：只注册一个 `relight`。
- `vrstudio/src/vrstudio/cli/case.py`：新增 `case relight`（`--gt/--atmo` 加候选并选中，
  `--gt-id/--atmo-id` 只改指针，另可写 `[relight]` 参数）；`case new --flow relight` 不要求
  `--source`；`case show` 打印两个槽位与成片指针。
- `vrstudio/src/vrstudio/case.py`：`FLOWS` 加 `relight`；`create` 对 relight 拒绝 `--source`；
  `master()` 对 relight 取底版；新增 `relight_slots()`、`[relight]` 解析与校验、
  `add_relight_candidate`、`set_relight_pick`、`set_relight`；`_kind_of` 改为公开的 `kind_of`。
- `vrstudio/src/vrstudio/web/app.py`：`_relight_step_files` / `_relight_current` /
  `_relight_samples` / `_relight_payload`；`_gates` 与 `_step_files` 加 relight 分支；
  `_outputs` 收 mp4 与 png；`_op_argv` 加 `relight`（只拼 flag，交给 `--case`）；
  `api_cases` 接受无源建 relight case；`api_assets` 加 `op: slot`；新增
  `POST /api/case/{name}/relight`（草稿）；`video_source` 对 relight 发底版视频；
  `api_proxy` 对 relight 明确拒绝（无源片代理）；`_prompt` 与 `_generation_params` 对 relight
  中央短路。
- `vrstudio/frontend/src`：`Flow` 加 `relight`；`FLOW_STEPS` 加 `[素材, 重打光, 对比]`；
  `flowMeta` 加「重打光」；`nextStepForFlow` 加 relight 分支；新建弹窗加「重打光」且不要求源
  文件；新增 `RelightAssetsStep.vue`、`RelightStep.vue`；`CompareStep.vue` 按底版媒体分流
  （图片底版走静态并排，视频底版走 360 对比器，左路改指底版）；`AssetPickerDialog` 增加
  `title/hint/confirmText` 三个可选文案；`AssetUploadDialog` 增加 `destination="slot"`。
- `docs/roles.json` 与两个仓库的副本：新增 `relight_gt`（不限种类）与 `relight_atmo`
  （只图片），两者 `open=false`、`modes=[]`、`reserved=false`；契约摘要同步为
  `4c7a53dde440e76a9208ea898e7bfb442dab092f8b4265c2df15b4b8bc451a1f`。

## 2. CLI 契约（合并后）

```text
vrstudio relight --case NAME [--sample N] [--ref-frame N] [--crf 0..51]
                 [--scene night|day] [--strength 0..1] [--local-shading 0..1]
                 [--highlight-clip] [--clip-knee 0.72] [--clip-max 0.98]
                 [--report JSON] [--config TOML] [--set k=v]... [--quiet]
# 或不吃 case 的文件模式
vrstudio relight --gt GT --atmo ATMO --out OUT [...同上]
```

- `--case` 与 `--gt/--atmo/--out` 只能选一种：一份文件两个来源会让「case 里记的是哪张」含糊。
- 派发看 GT 的扩展名（`case.kind_of` 的视频集合），不看内容探测；图片 GT 配 `--ref-frame`
  /`--sample`/`--crf`、视频 GT 配 `--dump-light` 都是参数错并指名原因。
- `--sample N` 把 `--out` 当目录，只写 `sample_<帧号>.png`，不编码视频，并跳过整段同位检查
  （那要解码全片，而预览的全部意义是快）。报告里多一个 `sample: {count, frames}` 键；整段报告
  仍保持决策 56 定的字段集。

## 3. 实施中改掉的三个设计与两个缺陷

**槽位从「角色即槽位」改成「候选库 + 指针」。** 初版把两个槽位直接等同于两个角色，并限制每种
角色只能一条素材。做到前端素材步时发现后果：「从素材库选」的候选列表永远是空的——因为 case
里除了这两个槽位不许有别的东西。这与用户要求的「case 素材库里的已上传文件就是候选」直接冲突，
而且美术迭代氛围图（改一版传一份、再挑一版）根本没有地方放。改成：`[[assets]]` 是候选池，
同角色可以多条；`[relight]` 的 `gt`/`atmo` 是两把素材 id 指针。同一个文件重复加入会复用已有
候选（按 sha256 判重），指针可以来回切换而不重新上传。

**web 侧的产物命名与槽位解析收回 CLI。** 初版由 `_op_argv` 自己拼 `--gt/--atmo/--out` 并生成
时间戳文件名，同一套规则在 web 与 CLI 各写一份。改成 `relight --case` 后，槽位在哪里、产物叫
什么、`current` 怎么回写只有一处权威，web 只把面板参数翻成 flag。

**`_prompt` / `_generation_params` 对 relight 中央短路。** 前端第一次点「先看 5 帧小样」时
`POST /api/case/{name}/relight` 返回 500，服务日志是 `KeyError: 'relight'`：新加的草稿端点回头
调了 `_info_with_generation`，而它无条件构造提示词，`template_for` 里没有 relight 模板。修法
不是给每个调用方加 `if`，而是在这两个函数内部按流程短路，所有调用方一次覆盖。已补两条回归
测试（断言 `prompt == {}`、`generation_params == {}`）。

**素材选择器文案。** 通用选择器把标题写死成「添加素材到本次视频提交」、副标题讲「加入后在
提交清单里设置角色」，用在 relight 槽位上误导。给 `AssetPickerDialog` 加三个可选文案参数，
relight 传「选择重打光底版 / 选作底版」与对应说明。

**对比页的代理状态英文泄漏。** 右路标签直接显示内部状态 `missing`。改成中文映射：代理未就绪
时显示「原始分辨率」（relight 没有源片代理，按原分辨率播是预期行为）。

## 4. 门禁

- `vrstudio`：`uv run pytest` 全量通过；`uv run ruff check src tests scripts` 干净。
  新增/改写的测试：`tests/test_relight.py`（类型专属参数拒绝、未知后缀、合并后的 CLI）、
  `tests/test_relight_video.py`（`--sample` 不产视频、`--case` 的槽位/混用/非 relight 拒绝、
  小样落 `out/samples/` 且不改 `current`、`relight-video` 已退役）、
  `tests/test_casemodel.py`（无源建 case、候选累积与指针、同文件去重、指针角色校验、
  `[relight]` 未知键与 `current` 路径、`[relight]` 只属 relight）、
  `tests/test_web_relight.py`（15 条：建 case、槽位 op、两条门链、payload、op argv、
  草稿端点、选区端点拒绝）。
- `vrgen`：`uv run pytest` 全量通过；`uv run ruff check .` 干净（词表副本与摘要同步）。
- `frontend`：`typecheck` / `lint` / `test`（118 条）/ `build` 全绿。
- 注：仓库根目录上一轮遗留的未跟踪 `.tmp_*.py` 草稿仍会让 `ruff check .`（不带路径参数）
  报 4 条，与本次改动无关，未处理。

## 5. CLI 真实验收（8K）

素材：底版取 `sources/dance_move.mp4` 前 20 帧（8192×4096、30fps），氛围图取
`cases/dance_move/out/20261030-120614_frame.mp4` 的第一帧（同尺寸 AI 重绘）。case：
`cases/relight_cli_01`。

- `case new relight_cli_01 --flow relight`：建出无源 case，`case.toml` 无 `[source]`。
- `case relight --gt <570 帧全片> --atmo atmo.png --scene night` → `case relight --sample 5`：
  在 570 帧素材上按 seek 只解采样帧，5 张 PNG（帧号 57/171/285/399/513），对齐
  内点 1295、结构重合度 0.968 → 0.969；`[relight]` 未写 `current`（小样不钉指针）。
- 换底版为 20 帧小样后再跑整段：20 帧进出、8192×4096、h264 yuv420p、30fps，
  37.3 秒（0.5 fps，含选帧与同位检查）；报告 `min_hold 0.9759`（≥0.94，确认固定机位）、
  `gain_mean 0.711`（p05 0.52 / p95 0.949）、`visibility_mean 0.858`、
  `seconds 53.2`；`[relight] current` 回写为 `out/20261030-192824_relit.mp4`。
- 这两组光学指标与 `20261030-relight-video.md` 的 20 帧小样（0.711 / 0.858）逐位一致，
  说明合并后的命令没有改变引擎行为。

## 6. 前端真实验收（浏览器）

case：`cases/relight_web_01`，素材库预置三条候选（`v1` 底版、`i1` 原氛围图、`i2` 提亮后的
氛围图），两个槽位初始为空，用来验证「先选再跑」的完整链路。

- 列表页：`relight_web_01` 显示「重打光 / 等待选定底版与氛围图」，`relight_cli_01` 显示
  「可以对比」。
- 新建弹窗：流程多了「重打光」，选中后源文件选择整块消失，改为一段「建完进入素材步」的说明；
  通过界面新建 `relight_ui_01` 成功并直接落在素材步（验证后删除该临时 case）。
- 素材步：两个槽位初始「未选」，门控提示「还缺底版」；「从素材库选（1）」与「（2）」分别
  显示候选数；选择器标题为「选择重打光底版 / 选择氛围图」，确认按钮为「选作底版 /
  选作氛围图」，氛围图选择器只列两张图片。
- 选完底版后门控变「还缺氛围图」，选完氛围图后门控放行、「去重打光」可用，卡片显示文件名、
  相对路径、体积与打开链接。
- 重打光步：参数面板（场景预设、整体施加量、局部明暗、参考帧、crf、高光软裁切、小样帧数）；
  「先看 5 帧小样」→ 任务 `relight · 已完成`，小样条显示 5 张真实重打光帧
  （`sample_000002/000006/000010/000014/000018`），帧号是按 20 帧均匀采样。
- 「开始重打光（整段）」→ 队列执行，日志尾部显示 `20 frames in 37.7s` 与
  `[relight] current = out/20261030-193327_relit.mp4`；「上次运行」面板读出报告：
  对齐内点 1282 / 匹配 1327、缩放 0.99998、旋转 0.0004°、重合度 0.968 → 0.969、
  增益 3.675（p05 1.702 / p95 10.569）、可见度 0.958、参考帧 0、同位检查 19 帧最低 0.9759、
  耗时 54.1s。
- 对比步：左路「底版」、右路成片选中 `20261030-193327_relit.mp4`、右路标注
  「原始分辨率」；360 对比器正常播放，分割线左右两路画面同时可见——左路是偏冷的 GT，
  右路明显被提亮偏暖，与选中的 `i2_atmo_warm.png`（原氛围图 +25）一致。
  截图见 `C:\Users\Administrator\.zcode\cli\artifacts\session_...\call_00_HS9JFWA*.png`。
- 增益从 CLI 那轮的 0.711 变成这里的 3.675，是换氛围图导致的（`i2` 比原图整体亮 25 级），
  正好说明「用户手选氛围图」这条需求在链路上真的生效。

## 7. 已知限制与未做

- **浏览器内的上传没有被驱动。** 当前 in-app 浏览器不支持文件选择器（IAB 明确
  `capability_unsupported`），所以素材步走的是「从素材库选」；上传路径由
  `AssetUploadDialog` 的 `destination="slot"` 调 `op: slot` + `upload_ids`，只有接口级测试
  覆盖（`tests/test_web_relight.py`），没有在真实浏览器里点过「上传 → 放进槽位」。
- 视频底版按原分辨率播放，没有代理；8K 源在对比页里可播，但时间读数停在 `0:00 / 0:00`
  （沿用既有对比器在 `quality=original` 下的行为，本次未改动）。
- 未跑真实平台生成：氛围图复用已有的 AI 重绘产物，`fullRedrawImg → 手工加工 → 上传`
  这条链在外部工具里完成，本次只验证「上传结果能被选成氛围图」。
- 机位移动、多张氛围图随时间切换、跨 case 导入氛围图、成片回填为素材都仍在本期范围外
  （与方案 §2.5 一致）。

## 8. 额度

两轮验收（CLI 与前端各一轮小样 + 整段）全部是本地计算，未调用平台，额度消耗为 0。
用户允许的两次 4 图生成没有被使用。
