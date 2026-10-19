# 实施路线图

每个里程碑有明确验收标准；M1 起"全绿"指 `uv run pytest` + `uv run ruff check .` 干净。

## M0 脚手架（本次交付）

- [x] E:\VRAIGC 工作区：AGENTS.md + docs/（architecture / case-model / decisions / roadmap）
- [x] vrgen、vrstudio 两仓库：git init（main）、uv 工程（3.11 + src layout）、pytest + ruff、CI workflow
- [x] CLI 骨架按契约声明全部子命令（stub），冒烟测试断言命令面
- [x] `uv sync --extra dev` 可装、`uv run pytest` 全绿、首提交完成

## M1 vrgen 最小可用（代码完成，真实额度下的一轮提交待验收）

- [x] 迁入 vrpad `aigc/platform|prep|round`（原样），重写 `jobs.py` + `cli.py` 的 submit（a35ee41）
- [ ] `vrgen submit --job t --input x.mp4 --mask m.png` 完成一次真实 mglc 调用并落台账
  —— 调用链已真实化并有回归覆盖；受配额限制，真实素材的一轮完整提交还没跑过
- [x] `vrgen register --file` 手动后端写同构台账（M3 提前交付：`manual.py` 内容寻址注册 + run.json 契约 + `jobs.py` prompt-vars 自适应）
- [x] 断点续跑：submit 中断后重发不重复扣额度（a35ee41，task_id 防重发回归测试）
- 验收：用 fullredraw 的输入包（pad 画布 + mask）真实出一轮结果（与 M4 的 fullredraw 验收合并进行）

## M2 vrstudio 契约搬运（2026-10-16 完成，e2032f1）

- [x] `patch/`（vrpatch 核心库）、`redraw/`（vrpad 核心库）原样迁入，测试随迁（test_aigc 除外——属 vrgen；test_web_* 除外——属 M4）
- [x] `media/` 合并（videoio/binres ← vrpad，ffmpeg.py ← vrpatch；三档 profile 文档化于 media/__init__）
- [x] 分层 config（去 [aigc] 段）+ progress 合并（vrpatch 系改名 PhaseLog/PhaseRateMeter）
- 验收达成：随迁测试 170 个全绿。逐字节一致由 M3 的 ship_01 复现代偿——同源同配置下
  接缝指标与 vrpad 历史成片逐位一致（wrap 0.8928 / percentile 81.2 / worst 9.1598）。

## M3 generate 接线（2026-10-16 完成，vrgen c07b327 + vrstudio 4d1452c）

- [x] `cli/case.py`（new/list/show）+ 统一 case 模型库 `src/vrstudio/case.py` + `cli/generate.py`（输入包解析 → vrgen CLI 子进程 → adopt 落账）
- [x] fullredraw 全流程 CLI 跑通：case → pad → register/submit → adopt → recompose → out/
- 验收达成：合成素材 e2e（pytest，比例错的返回件也重组回源尺寸）+ ship_01 真实复现
  （同源 ship_ue.mp4，register vrpad 历史返回件，recompose 后 wrap/worst/帧数与历史
  报告逐位一致）。注意：submit 走 mglc 属 M1，本次验收以 manual 后端完成。

## M4 patch 流程 + web 控制台

- [x] patch 后端接线（2026-10-16）：统一 case 草稿 API（`set_draft`/`draft_ready`）、
  `vrstudio extract name --case`（草稿冻结进 extracts/，老式 case.toml 入口保留）、
  `vrstudio merge --case`（源哈希守卫 + extracts/<current> 自动定位 + out/ 默认落点；
  自动 restore/scalefit 本就内置于 merge）；ai-clip 注册即 `generate register/adopt`
  （M3 已交付，web 将直接调用）。测试 196 绿。
- [x] web 技术栈对比文档（决策 11）：`docs/web-stack.md`，推荐路线 A（沿用
  Starlette + jinja2 + 原生 JS），预留升 HTMX 的让步通道，否决前后端分离
- [x] web 骨架迁入与软向导（2026-10-16）：`src/vrstudio/web/`（app/tasks/render ← vrpatch
  迁入并接统一 case 模型；`serve` 命令落地，`--host 0.0.0.0` 支持局域网）。页面：case
  列表 + 向导（软向导门控判据全在服务端）；pick 交互原样迁入（点击定视口/拖框 inner/
  摇杆/逐帧）；generate 页轮次列表 + mglc.log tail；对比页同步播放 + 滑动分割线。
  patch 流程已浏览器验收（合成素材：建 case → pick → 队列抽取 → register → adopt →
  merge → out/ 成片对比，全程不离开浏览器）；fullredraw 向导页已实现（pad/recompose
  入队），待真素材验收。web 单测 14 个，总计 210 绿。
- [x] M4 后续迭代（2026-10-16 至 2026-10-19，依次落地）：
  - 提示词面板：模板正文只读 + 变量即改即存 + 自定义增删（995e700，决策 18）
  - 对比页改 360° 全景观看（erp360.js 双路共视角）与统一进度条/播放键（5954505）
  - 编码统一为浏览器可播的 H.264 420，废弃 444 与播放时转码（eddce06，决策 19）
  - 生成页输出/输入分辨率下拉并透传 submit 参数（e85828a，决策 20）
  - 文件信息显示仓库内相对路径、生成步骤拆分生成/采用两组（cdb7cdb、b42e4b9）
  - 任务栏每行带提交时间、历史扩到 10 条并分节（995e700）
- [x] gen 简单生成流程（2026-10-19，决策 21）：新增 `flow = "gen"`，向导只有生成一步；
  源视频直接上传，模板 `gen-edit`，采用结果落 `case/result.mp4`；参考图字段已预留。
- [x] gen 流程用 Simple_Anima_Test.mp4 做浏览器操作与 1080p 真实提交验收（2026-10-19）：
  浏览器建 case、填提示词、提交 1080p、采用结果全流程跑通；成片 1944×1066、
  289 帧、12.0 秒，白膜人物被替换为写实人物，背景与编辑器界面保持原样。
  首次提交因个人额度为 0 被拒；改用项目生成会话 `--session-id` 后成功（决策 22）。
- [x] 项目/剧集/会话选择器（2026-10-19，决策 22）：vrgen 新增 `sessions list` 只读命令，
  生成页三层联动下拉框，页面加载与刷新时重新获取会话树；选择结果写 `generation.toml`。
  方案与验收记录见 `docs/session-ui-plan.md`。
- 当前测试规模：vrgen 81 个 + vrstudio 237 个（含 web 35 个），合计 318 个，全绿；
  `uv run ruff check .` 两仓库干净（2026-10-19 核对）。
- [ ] fullredraw 向导页真素材浏览器验收（与 M1 配额解决后的真实 submit 一并做）
- 验收：两条流程各跑通一个真实 case，全程不离开浏览器

## M5 收尾

- [ ] 两仓库 README 交接规范（输入/输出/必须保留/规矩，沿用 vrpad 风格）
- [ ] 知识文档随迁归位；旧仓库（E:\360AIGC\vrpatch、vrpad）冻结归档并加指向
- 验收：新人（或 AI）只凭新仓库 README + AGENTS.md 能跑通两条流程
