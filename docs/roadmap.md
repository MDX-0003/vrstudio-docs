# 实施路线图

每个里程碑有明确验收标准；M1 起"全绿"指 `uv run pytest` + `uv run ruff check .` 干净。

## M0 脚手架（本次交付）

- [x] E:\VRAIGC 工作区：AGENTS.md + docs/（architecture / case-model / decisions / roadmap）
- [x] vrgen、vrstudio 两仓库：git init（main）、uv 工程（3.11 + src layout）、pytest + ruff、CI workflow
- [x] CLI 骨架按契约声明全部子命令（stub），冒烟测试断言命令面
- [x] `uv sync --extra dev` 可装、`uv run pytest` 全绿、首提交完成

## M1 vrgen 最小可用

- [ ] 迁入 vrpad `aigc/platform|prep|round`（原样），重写 `jobs.py` + `cli.py`
- [ ] `vrgen submit --job t --input x.mp4 --mask m.png` 完成一次真实 mglc 调用并落台账
- [ ] `vrgen register --file` 手动后端写同构台账
- [ ] 断点续跑：submit 中断后重发不重复扣额度（task_id 防重发回归测试）
- 验收：用 fullredraw 的输入包（pad 画布 + mask）真实出一轮结果

## M2 vrstudio 契约搬运

- [ ] `patch/`（vrpatch 核心库）、`redraw/`（vrpad 核心库）原样迁入，测试随迁
- [ ] `media/` 合并（三档编码 profile），旧像素基线测试（maxdiff==0、恒等式）全绿
- [ ] 分层 config + progress 合并
- 验收：随迁测试全绿；对同一素材，新仓库 CLI 输出与旧仓库逐字节一致（或差异可解释为编码 profile 文档化语义）

## M3 generate 接线（first end-to-end）

- [ ] `cli/case.py`（new/list/show）+ `cli/generate.py`（组装输入包 → subprocess 调 vrgen → adopt 落 case）
- [ ] fullredraw 全流程 CLI 跑通：case → pad → generate → adopt → recompose → out/
- 验收：复现 vrpad 的 ship_01 案例（同源视频、同 brief，出一版成片，接缝指标达闸门）

## M4 patch 流程 + web 控制台

- [ ] pick/extract/merge/restore 接入统一 case 模型（ai-clip 注册改调 `vrgen register`）
- [ ] web 骨架迁入，按 architecture.md §3 页面流逐页接两条流程
- 验收：两条流程各跑通一个真实 case，全程不离开浏览器

## M5 收尾

- [ ] 两仓库 README 交接规范（输入/输出/必须保留/规矩，沿用 vrpad 风格）
- [ ] 知识文档随迁归位；旧仓库（E:\360AIGC\vrpatch、vrpad）冻结归档并加指向
- 验收：新人（或 AI）只凭新仓库 README + AGENTS.md 能跑通两条流程
