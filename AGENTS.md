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
   重打光的对齐相似变换只在 `vrstudio/relight/align`；
   画布↔源映射只在 `_pad.json` manifest。别处不得复制这些规则。
4. **像素基线**：几何/编码相关改动必须 pytest 全绿（含随迁的恒等式与 maxdiff==0 基线测试）
   才能提交。编码语义以 `vrstudio/media` 的显式 profile 为准（决策 99 起帧泵是 16-bit、
   交付档是 HEVC Main10 yuv420p10le；只有浏览器预览代理保留 H.264 8-bit yuv420p；
   像素基线测试自行钉 crf 0）。
5. **流式逐帧**：视频处理一帧一帧过，禁止整片驻留内存（6K/8K 素材是硬约束）；
   禁止模块级可变缓存。
6. **开发与提交门禁**：开工前先确认根仓库与相关子仓库 `git status` 干净；
   有未提交改动就先把它们处理掉，或在开工前向用户说明。
   开发顺序固定为「先改 `docs/` 的决策与计划 → 再改代码 → 最后补字节一致性与测试」。
   提交前 `uv run pytest` 全绿 + `uv run ruff check .` 干净。
   开发完成后单独提交 git：根仓库的文档提交与子仓库的代码提交各自独立，
   不把文档改动和代码改动混进同一笔；提交信息中文、动词开头
   （沿用旧仓库风格，如 `aigc: 修掉…`）。
7. **数据不进 git**：`cases/`、`sources/`、`runs/`、`logs/`、`bin/` 全部 gitignore；
   仓库里只进代码、配置模板、文档、测试。
8. **只维护 main 分支**：根仓库、vrgen、vrstudio 的长期进度只写在 `main`；
   不创建长期功能分支，也不为阶段性工作保留旁支。临时实验分支在验收后必须
   合并或删除；提交、文档与验收记录都落在 `main`。当前没有远程分支，后续也不
   新增长期远程分支。

## 设计原则（Review 按此把关，与硬规则同效）

1. **能删就删**：接口、函数、参数能删就删；新增 CLI 参数、API 端点、配置键、
   模板变量之前，先证明现有接口装不下这个需求。
2. **共用优先**：两条执行路径出现重叠就合并成一条；只有共用会导致大量 if 分支
   时才允许拆分，且拆分边界落在数据（装配产物）上，不落在机制上。
3. **不为临时需求加长期成本**：为单个 case 或单次实验开的口子，合入前要回答
   「其余流程是否也要跟着维护它」；答案是否就不许合入。
4. **用机制替代禁令**：不靠禁止性校验挡需求；让错误状态无法构造，或在最底层
   按真实原因报错（如平台 validator 返回具体哪一项超限）。

## 环境

- Python 3.11，uv 管理：`uv sync --extra dev` 装环境，`uv run <cmd>` 执行。
- CI：GitHub Actions（`.github/workflows/ci.yml`），本地门禁等价于 CI 的 test job。
- 本地工具是 Windows 优先（bin\ffmpeg.exe、mglc），CI 上只跑不依赖外部二进制的单测。

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/architecture.md` | 总架构、模块树、拷贝映射表、默认决策 |
| `docs/deployment-new-host.md` | 新 host 设备部署手册：工具链、bootstrap.ps1、验收清单、踩坑排查 |
| `docs/plan/exe-packaging-plan.md` | 离线安装版打包计划：路径与数据根约定、WP0–WP6、打包脚本与验收（WP0–WP5 已实施） |
| `docs/deployment-packaged.md` | 打包版分发文档：安装器与便携版的构建、安装、升级、卸载与排错 |
| `docs/case-model.md` | case.toml 格式、vrgen CLI 契约、台账格式（两仓库的唯一接口权威） |
| `docs/decisions.md` | 决策记录（已拍板 + 待确认默认） |
| `docs/spec/asset-roles.md` | 素材角色的设置与运行机制：词表快照、kind/modes 规则、新增角色的步骤、约束分层与排查表 |
| `docs/sessions.md` | 项目、剧集与生成会话的层级、额度扣减与 vrgen 接法 |
| `docs/session-ui-plan.md` | 前端项目会话选择器的实现方案与回退顺序 |
| `docs/prompt-rules.md` | Seedance 提示词规则（编辑模式、参考模式、角色替换） |
| `docs/video-edit-motion-issue.md` | VideoEdit 动作锁定问题与解决路线（审查稿） |
| `docs/multi-asset-plan.md` | case 无视频创建与多素材模型方案（审查稿） |
| `docs/unified-submit-plan.md` | 生成提交统一化方案：三流程一条 prepare 路径、mask 进清单、四条限制退役（审查稿，待批） |
| `docs/first-last-frame-pipeline.md` | 首尾帧两段式生成方案：图片关键帧 + firstLastFrame，含工具链接入设计（定稿） |
| `docs/firstlast-dev-plan.md` | 首尾帧管线开发计划：WP0–WP4 工作包、切入点与 pytest 验收（待批） |
| `docs/patch-videoedit-example.md` | 例子：只重绘中间动作段的 patch + videoEdit 流程，位置/时间一致性原理与段成片边界 |
| `docs/patch-time-assembly-plan.md` | 草案：空间合并后自动拼接原片前后段的时间合并计划与待确认项 |
| `docs/generate-page-plan.md` | 生成页可读性优化方案：主题折叠、模板内别名、提示词自适应、底部提交条（待批） |
| `docs/keyframe-workbench-plan.md` | 首尾帧重绘工作台方案：两帧展示、图片步提示词框架、两批手动生成与到视频步的交接（patch 已实施） |
| `docs/plan/keyframe-page-layout-plan.md` | 首尾帧页排布重做（A2 通栏）与抽取页产物条：四格输入、三视图抽屉、候选与提示词通栏（已实施，验收见 `docs/test-runs/20261026-keyframe-extract-layout.md`） |
| `docs/plan/asset-library-separation-plan.md` | 素材库独立页面与步骤内引用清单：文件库、视频提交集、图片参考集三层分离，选择器、旧版兼容与迁移（审查稿，待原型确认） |
| `docs/plan/keyframe-input-cap-plan.md` | 首尾帧图片输入重排与 10 张上限：图1 进清单、0 张放行、三类角色、首帧9/尾帧8、结构条件计算键与提示词刷新（已实施，验收见 `docs/test-runs/20261112-keyframe-input-cap.md`） |
| `docs/plan/unified-file-view-plan.md` | 统一文件视图方案：/file 按根寻址的白名单直开路由 + FileRow 组件，所有展示资产可查名查路径可单独打开（已实施，验收见 `docs/test-runs/20261026-unified-file-view.md`） |
| `docs/plan/frontend-perf-compare-playback.md` | 对比页 360 视频播放卡顿排查与修复：B 路从未播放只靠 seek 挪进度（Playwright 实测实锤）、隐藏视频元素失去 GPU 上传快路径、每帧强制布局、播放画质下拉框（代理/原始分辨率，已实施，待真实浏览器验证） |
| `docs/plan/case-owner-transfer-plan.md` | Case 负责人归属行与「归属到我的名下」方案：改主端点 + revision 乐观并发，不做认领/指派（已实施，Playwright 验证通过） |
| `docs/plan/save-conflict-resolution-plan.md` | 保存冲突三条修复：弹窗加「仍要保存（覆盖对方）」出口、同轮冲突收敛为一次、几何草稿落定帧带 revision 校验（已实施，Playwright 端到端验证通过） |
| `docs/plan/upload-source-video-plan.md` | 新建 case 支持上传源视频：复用分片上传管线，`api_cases` 加 `upload_id` 分支，上传弹窗解耦终点，入口在新建弹窗源视频旁（已实施；同名冲突处理见决策 95） |
| `docs/plan/source-upload-reuse-plan.md` | 源文件上传同名冲突：按 sha256 复用已有文件、内容不同自动改号、删 case 回收无人引用的源（决策 95，已实施） |
| `docs/plan/360-img-gen-flows-plan.md` | 360 静图的两条新流程：patchimg 走视口局部（与视频 patch 同构，复用投影/合成），img2video 走全幅 pad/stitch（槽位模型统一三种首尾帧组合，链上关键帧不 recompose），CLI 先行工作包与像素基线（决策 46 已定稿；WP1/WP2 已实施，WP3–WP7 待做） |
| `docs/plan/360-img-ab-routes-plan.md` | 8K 静图重绘的两条路线：分段局部链式（多 case 沿 360 传递、需 case 分组与子目录识别）vs 全幅 4K + 氛围参考（`fullRedrawImg` 流程，21:9 pad + mask + X 张 lighting_ref），含开发前置、CLI 工作包、评测指标与成本（决策 47；审查稿，待批） |
| `docs/plan/patch-4k-region-plan.md` | patch 4K 大区域重绘：fov 与分辨率的分工、firstLastFrame / allMediaRef 两条 4K 路线、全流程操作、验收与失败处理（决策 49；P1 CLI 试点与 P2 Web 全链路待实施） |
| `docs/plan/patch-region-clipboard-plan.md` | patch 选区范围的剪贴板导出/导入：`vrstudio.patch.region` v1 格式、视口尺寸与 inner 缩放、帧范围校验、两个端点与选区页按钮（决策 92） |
| `docs/plan/pick-range-presets-plan.md` | pick 选区范围预设与合并输入：`[[range_preset]]` 列表与 active 指针、`derived/pick/draft.toml` 工作草稿、preset 按首次保存时间命名、保存/另存/单击选中双击载入、抽取页复用 preset 列表且抽取版本只读、合并页按几何分组列抽取版本并局部选版、patch 的 `[merge] input`（决策 97） |
| `docs/plan/relight-video-plan.md` | 视频重打光最小方案：固定机位下一张氛围图打一段 GT 视频，对齐与光照场只估一次整段复用、参考帧来源、适用边界与验收（决策 56；已实施，验收见 `docs/test-runs/20261030-relight-video.md`；后续优化见 `relight-decode-cache-plan.md`） |
| `docs/plan/relight-frontend-plan.md` | 重打光前端接入：一条 `relight` flow 按 GT 媒体派发、建 case 不绑源、素材库多候选 + 两把槽位指针、视频 N 帧小样预览、CLI 合并与 `--sample`/`--case`、三个子页与 WP0–WP5（已实施，验收见 `docs/test-runs/20261030-relight-frontend.md`） |
| `docs/plan/relight-decode-cache-plan.md` | 视频重打光消除重复解码与固定光照缓存：删除同位检查、单遍取参考帧、按 GT/氛围图/参考帧缓存全精度相似变换、运行时间与分段计时（决策 64/65；代码已实施，8K 冷/热验收待补） |
| `docs/plan/relight-atmo-video-plan.md` | 视频氛围重打光：氛围源从单张图扩成图或视频，固定相似变换 + 逐帧光场、按归一化进度对齐、允许分辨率/帧率不同、1080p 氛围与 fullredraw 成片交接、WP0–WP5（审查稿，四项关键选择已确认） |
| `docs/plan/recompose-perf-plan.md` | 视频 recompose 性能：4K/8K 的逐阶段实测与瓶颈根因、R 区直通、缓冲复用、闸门最多分析 48 帧三项改动、预期收益与字节一致性验收（决策 77） |
| `docs/plan/video-merge-input-plan.md` | 视频拼接输入：复用图片流的 `[merge] input` 指针与 `merge_input` 角色，视频「裁回原尺寸」可用采用结果或上传的 21:9 画布视频；前端抽共用控件，只留上传入口与条件式“改用采用结果”（决策 78，2026-11-09 简化） |
| `docs/plan/follow-input-resolution-plan.md` | 输出跟随输入分辨率：视频 recompose 与图片 merge 共用 `--follow-input` 的缩放规则、两条流程的输出命名、web `output_options` 与前端下拉框，含对比页识别与缩放闭合恒等式验收（决策 79；§3 的缩放规则已由决策 90 取代） |
| `docs/plan/follow-input-upload-size-plan.md` | 跟随输入改为按上传件自身尺寸派生：输出高取输入件高、带宽由输入件宽高比算出，取消「不小于源宽就不跟随」的闸门，配准曲线平坦时 `d*` 归零，含测试与 110503 实测验收（决策 90） |
| `docs/plan/relight-8k-compose-perf-plan.md` | 8K 重打光合成性能：日志拆分（compose 占 85%）、`apply` 与 `soft_clip` 的逐项实测、四项像素等价改动与排除方案、优化前后对照与验收（决策 80） |
| `docs/plan/relight-compose-threads-plan.md` | 8K 重打光合成读取与多线程：64 KB `os.read` 传输（298→62 ms/帧）、行带线程化 `apply`/`soft_clip`/引导滤波/求幂、内存实例生命周期七条、像素等价论证与验收（决策 82） |
| `docs/plan/relight-tone-fidelity-plan.md` | 重打光强度区间与色彩保真：暗部置信权重让 strength 全区间可用、色度差低通压掉彩色台阶、交付统一 BT.709 标签；含锯齿来源判定、编码影响实测、行带并行加速与 WP0–WP5 验收（决策 84/85/86） |
| `docs/plan/relight-regions-plan.md` | 重打光区域参数覆盖：球面多边形区域 + 逐参数覆盖（strength/local_shading/软裁切）、360 工作台与区域列表、逐像素参数场与零区域逐位一致、时间区间拆第二阶段、含极点盖帽第三阶段（决策 88/89；第一阶段与盖帽已实施） |
| `docs/plan/relight-region-boolean-plan.md` | 重打光区域选区的挖空渲染与几何式布尔：重叠语义不变（上层独占），画布按列表顺序叠色做到所见即引擎所得、区域排序操作、PS 式减去/相交为选中区域 `verts` 的几何裁剪（决策 100；已实施，浏览器验收待做） |
| `docs/plan/relight-regions-time-plan.md` | 重打光区域时间区间（决策 91）：`ranges` 并集与校验、微秒级帧换算与分段、三条渲染路径的按段缓存与内存释放、时间轴交互与同轨不重叠、图片底版隐藏与兜底拒绝、WP0–WP6 与逐位基线（已实施，验收见 `docs/test-runs/20261106-relight-regions-time.md`） |
| `docs/plan/video-10bit-plan.md` | 视频链路 16-bit 帧泵与 10-bit 交付档（决策 99）：色带实测依据、影响面清单、WP0–WP6 与验收；帧泵、recompose、patch 域（WP3）与 relight 域（WP4）均已 16-bit，验收见 `docs/test-runs/20261113-video-10bit-wp3-wp4.md`；WP1a 平台接受度与 WP2 真实 case 对照待做 |
| `docs/test-runs/20261113-video-10bit-wp3-wp4.md` | WP3/WP4 实施与验收记录：patch 读写下 16-bit 帧泵、`FfmpegSink` 接 `[video]`、relight LUT 改 65536 项与 65535 满量程、8-bit 输入的行为等价论证、8K 整段 378 帧实测（374.8 s / 2737 MiB）、未做项 |
| `docs/test-runs/20261105-relight-regions.md` | 区域覆盖阶段一验收：19 个区域单测与 web/前端单测、8K 素材单帧小样的区域内外差异、浏览器画区/覆盖/拖动与刷新持久化、未做的整段渲染与时间轴 |
| `docs/test-runs/20261105-relight-pole-regions.md` | 区域盖帽（决策 89）实施与验收：`pole` 契约、引擎接缝/极点合成、前端唯一几何与「包含上方/下方」确认框；已做单测与 CLI 对照，浏览器端到端与 8K 整段待补 |
| `docs/test-runs/20261106-relight-regions-time.md` | 重打光区域时间区间（决策 91）验收：8K 小样区间内外像素、378 帧整段 9 段耗时与内存、默认 crf 的前瞻差异归因、crf 0 短片段逐帧一致、浏览器新建/保存/刷新回读 |
| `docs/test-runs/20261106-patch-region-clipboard.md` | patch 选区范围剪贴板导入导出验收：8 条接口测试、9 条前端测试、构建产物与待人工执行的浏览器步骤 |
| `docs/test-runs/20261109-pick-range-presets.md` | 选区范围预设与合并选版验收：真实旧 case 迁移、preset/draft 接口与前端测试、Chrome headless 的 pick/抽取/合并页面验收与未覆盖边界 |
| `docs/test-runs/20261112-keyframe-submit-bar.md` | 首尾帧页复用生成页固定底栏验收：候选标题栏参数行删除、图片底栏字段、共用外壳与额度行、225 条前端测试与 Chrome headless 1440 宽验证；第二轮补图片模型名称与按模型收窄的比例/分辨率/候选数（228 条前端测试）、2 条与本轮无关的 pytest 环境失败 |
| `docs/test-runs/20261112-keyframe-input-cap.md` | 首尾帧图片输入重排与 10 张上限验收：0/9/10 张、图11 超限、提示词结构条件与刷新、233 条前端测试、8761 临时环境 21 条 CDP 断言 |
| `docs/test-runs/20261105-follow-input-upload-size.md` | 跟随输入改为按上传件尺寸派生（决策 90）的实施与 110503 实测：下拉框消失与 43 px 残影两处根因、1892×946 与 1440×720 两次 CLI 结果、`d*=0` 对照与未做项 |
| `docs/test-runs/20261030-relight-frontend.md` | 重打光前端接入的实施与验收：落点、合并后的 CLI 契约、槽位模型从「角色即槽位」改成「候选库 + 指针」的原因、8K 真实素材的 CLI 与浏览器两轮验收指标、`prompt` 短路修掉的 500、未做的浏览器上传与代理限制 |
| `docs/test-runs/20261030-relight-space-e2e.md` | 视频重打光闭环验收：视频首帧 → 一次 4 张 4K 生成 → 画布闸门与拼接选型 → 整段重打光；含三处修复（提示词带宽只有白带一半、选帧前置闸门误杀、扫描解码器泄漏）与四张候选的逐项指标 |
| `docs/test-runs/20261102-relight-decode-cache.md` | 视频重打光去重、缓存与运行计时验收：378 帧 8K 小样冷 66.6 秒/热 30.3 秒（原 128.1 秒）、换氛围图重新选帧、20 帧整段冷/热逐帧 maxdiff 0、各阶段耗时与门禁 |
| `docs/test-runs/20261104-relight-compose-threads.md` | 8K 重打光读帧传输与行带多线程验收：378 帧整段 1409.50→276.40 秒（4.6 分钟）、成片 SHA256 与改动前相同、10 张小样逐像素 maxdiff 0、峰值内存 1.71 GB、内存生命周期逐条对账 |
| `docs/test-runs/20261105-relight-tone-fidelity.md` | 重打光强度与色彩保真实测：两版原型成片（暗部权重、色度差低通）的区域指标、锯齿来源判定（光场平滑无效、台阶在 GT 里、编码只占 5 个百分点）、24 帧编码对照表、色彩标签往返与行带加速 1.06→0.23 秒 |
| `docs/plan/fullredraw-img-prompt-vars.md` | fullRedrawImg 提示词变量的按场景取值：静态场景只写光影、不写原图没有的物体，氛围参考图标成 `lighting_ref`，取值为 `vrgen_runs/<case>/prompt-vars.toml` 的模板（审查稿） |
| `docs/plan/img-flows-frontend-plan.md` | patchimg / fullRedrawImg 两条 360 图片流程前端接入：命名统一（flow 值不变，契约文件/产物/模板改 image/img）、CLI 已就绪的证据、web 与前端缺口清单（建案例图片源、op 透传 num/index/model/session、门控去 else 兜底、草稿段单一判定、素材挂载、候选网格、静图对比与差异视图）、WP0–WP7 与真实额度前置（WP0–WP5 已实施，WP6 进行中，WP1/WP7 待平台额度） |
| `docs/key-issues/frontend-decisions.md` | 前端关键问题与决策记录：逐条记录问题、决策、排除方案、验证与涉及文件（持续更新） |
| `docs/key-issues/20261027-windows-process-port-management.md` | Windows 下进程与端口占用的排查与治理：uv venv 跳板的 exe 陷阱、运行中 exe 锁 venv、serve 启动接管旧实例（portguard） |
| `docs/key-issues/20261023-frontend-stack-selection.md` | 前端技术栈选型：需求、方案对比、概念对齐与用户确认记录 |
| `docs/plan/frontend-refactor-plan.md` | 前端重构实施计划：Vue 3 + Element Plus、页面迁移、后端解耦与验收 |
| `docs/plan/patch-browser-acceptance-plan.md` | Patch 流程新前端浏览器验收计划：两条真实路径、首尾帧 4+4、逐按钮验收与自动化接口 |
| `docs/plan/frontend-workflow-and-skills.md` | 前端开发流程、验收步骤与 skill/工具留档（持续更新） |
| `docs/plan/frontend-review-fixes.md` | 前端审查修复计划：保存竞态、切 case、提示词显示、流程判断与共享工具，含实施状态与测试 |
| `docs/plan/frontend-agent-test-plan.md` | Agent 浏览器验收计划：MCP 工具、无额度用例、接口证据、付费边界与逐次提交确认 |
| `docs/lessons-learned.md` | 经验与教训记录：MCP 浏览器 profile 占用、整页导航与 SPA 切换、测试数据边界（持续更新） |
| `docs/web-stack.md` | web 控制台技术栈三路线对比（决策 11 的论证） |
| `docs/roadmap.md` | 实施里程碑与验收标准 |
