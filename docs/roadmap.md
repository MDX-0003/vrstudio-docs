# 实施路线图

每个里程碑有明确验收标准；M1 起"全绿"指 `uv run pytest` + `uv run ruff check .` 干净。

## M0 脚手架（本次交付）

- [x] E:\VRAIGC 工作区：AGENTS.md + docs/（architecture / case-model / decisions / roadmap）
- [x] vrgen、vrstudio 两仓库：git init（main）、uv 工程（3.11 + src layout）、pytest + ruff、CI workflow
- [x] CLI 骨架按契约声明全部子命令（stub），冒烟测试断言命令面
- [x] `uv sync --extra dev` 可装、`uv run pytest` 全绿、首提交完成

## M1 vrgen 最小可用

- [ ] 迁入 vrpad `aigc/platform|prep|round`（原样），重写 `jobs.py` + `cli.py` 的 submit
- [ ] `vrgen submit --job t --input x.mp4 --mask m.png` 完成一次真实 mglc 调用并落台账
- [x] `vrgen register --file` 手动后端写同构台账（M3 提前交付：`manual.py` 内容寻址注册 + run.json 契约 + `jobs.py` prompt-vars 自适应）
- [ ] 断点续跑：submit 中断后重发不重复扣额度（task_id 防重发回归测试）
- 验收：用 fullredraw 的输入包（pad 画布 + mask）真实出一轮结果

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

- [ ] pick/extract/merge/restore 接入统一 case 模型（ai-clip 注册改调 `vrgen register`）
- [ ] web 骨架迁入，按 architecture.md §3 页面流逐页接两条流程
- 验收：两条流程各跑通一个真实 case，全程不离开浏览器

## M5 收尾

- [ ] 两仓库 README 交接规范（输入/输出/必须保留/规矩，沿用 vrpad 风格）
- [ ] 知识文档随迁归位；旧仓库（E:\360AIGC\vrpatch、vrpad）冻结归档并加指向
- 验收：新人（或 AI）只凭新仓库 README + AGENTS.md 能跑通两条流程
