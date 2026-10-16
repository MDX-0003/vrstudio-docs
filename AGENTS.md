# E:\VRAIGC 工作区规范（对 AI 与人类开发者同等生效）

本工作区包含两个仓库，前身是 `E:\360AIGC` 下的 vrpatch（局部重绘）与 vrpad（全景重绘 + 生成调用）。
旧仓库已冻结归档，只读参考；一切新工作在这里进行。

```
E:\VRAIGC\              ← 根 git 仓库：只追踪 AGENTS.md 与 docs\（规划文档）
  AGENTS.md        ← 本文件：跨仓库硬规则
  docs\            ← 规划与决策的权威位置（改架构先改文档，再动代码）
  vrgen\           ← 生成服务仓库（独立 git，根仓库已 ignore）
  vrstudio\        ← 流程仓库（独立 git，根仓库已 ignore）
```

## 两仓库的关系（一句话）

vrstudio 组装"输入包"（视频 + mask + 提示词 + 分辨率档），以 **CLI 子进程**调 vrgen，
vrgen 负责对平台的一切交互并写台账，结果被"采用"（adopt）时拷回 case。

## 硬规则（违反任何一条都打断 Review）

1. **跨仓库只走 CLI 契约**：vrstudio 不得 `import vrgen`，vrgen 不得 `import vrstudio`。
   交互界面 = argv + 退出码（0 成功 / 2 参数配置错 / 1 运行失败）+ 台账文件。
   契约变更先改 `docs/case-model.md`，再改两侧代码与测试。
2. **冻结契约不扩字段**：`clip.json`（单段、version=1）、`_pad.json`、`runs/<轮次>/run.json`
   的字段集是对外契约；要改先在 `docs/` 立项，同步改两侧测试。
3. **唯一权威点**：时间重采样只在 `vrstudio/patch/framealign.index_map`；ERP↔rectilinear
   投影只在 `vrstudio/patch/projection`；全景几何只在 `vrstudio/redraw/geometry`；
   画布↔源映射只在 `_pad.json` manifest。别处不得复制这些规则。
4. **像素基线**：几何/编码相关改动必须 pytest 全绿（含随迁的恒等式与 maxdiff==0 基线测试）
   才能提交。编码语义以 `vrstudio/media` 的显式 profile 为准（lossless444 / ai14 / delivery）。
5. **流式逐帧**：视频处理一帧一帧过，禁止整片驻留内存（6K/8K 素材是硬约束）；
   禁止模块级可变缓存。
6. **提交门禁**：提交前 `uv run pytest` 全绿 + `uv run ruff check .` 干净。
   提交信息中文、动词开头（沿用旧仓库风格，如 `aigc: 修掉…`）。
7. **数据不进 git**：`cases/`、`sources/`、`runs/`、`logs/`、`bin/` 全部 gitignore；
   仓库里只进代码、配置模板、文档、测试。

## 环境

- Python 3.11，uv 管理：`uv sync --extra dev` 装环境，`uv run <cmd>` 执行。
- CI：GitHub Actions（`.github/workflows/ci.yml`），本地门禁等价于 CI 的 test job。
- 本地工具是 Windows 优先（bin\ffmpeg.exe、mglc），CI 上只跑不依赖外部二进制的单测。

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/architecture.md` | 总架构、模块树、拷贝映射表、默认决策 |
| `docs/case-model.md` | case.toml 格式、vrgen CLI 契约、台账格式（两仓库的唯一接口权威） |
| `docs/decisions.md` | 决策记录（已拍板 + 待确认默认） |
| `docs/web-stack.md` | web 控制台技术栈三路线对比（决策 11 的论证） |
| `docs/roadmap.md` | 实施里程碑与验收标准 |
