# 重打光区域覆盖的实施与验收（阶段一）

状态：第一阶段（空间选取 + 逐参数覆盖）已实施；第二阶段（时间区间）待做。
对应决策 88，方案见 `docs/plan/relight-regions-plan.md`。

## 1. 落点

- 引擎：`vrstudio/relight/regions.py`（新增）、`relight/compose.py`、`relight/report.py`。
- CLI：`cli/relight.py` 的 `--regions`、`--sample-at`，图片、视频、视频氛围三条路径。
- case 模型：`[relight] regions` 指针，`relight/regions.json`（`version = 1`）。
- Web：`GET/POST /api/case/{name}/relight/regions`，`/api/case` 的 relight 负载新增
  `regions` 与 `regions_error`。
- 前端：`constants/relightParams.ts`、`utils/erpMath.ts`、`components/relight/ParamRow.vue`、
  `ErpRegionViewer.vue`、`RegionWorkbench.vue`，并接进 `RelightStep.vue`。

## 2. 测试

新增 `tests/test_relight_regions.py`（19 个）：

- 解析与校验：未知键、version、ranges、顶点数、纬度上限、区域数上限、坏 JSON。
- 光栅化：矩形覆盖、跨 ±180° 接缝、羽化从 0 到 1、全部停用时返回 None。
- 叠加：只覆盖声明过的通道、后建区域盖住先建的。
- 合成：区域强度 0 时与 GT 逐像素一致、区域外与无区域路径最多差 1 级；
  区域软裁切只影响自己的像素；逐像素 knee/max 在均匀时与标量结果逐位一致。
- CLI：坏区域文件退出 2、图片 GT 上 `--sample-at` 退出 2、`--sample` 与
  `--sample-at` 互斥、带区域出图与报告、无区域时报告 `regions: null`。
- 视频：`--sample-at 0,3` 在真实文件上出两帧、报告帧号与区域数正确、
  区域中心与解码帧逐像素一致（需要 ffmpeg，缺了跳过）。

新增 `tests/test_web_relight.py` 两条：读写往返（落盘与指针）与坏文档 400 且不落盘。

前端新增 10 条单测：`erp-math.spec.ts`（投影互逆、相机背后、跨接缝、点内判定）与
`relight-params.spec.ts`（默认卡与区域卡的控件集合逐项相等；软裁切在默认卡上可开启并改值）。

门禁结果：`uv run pytest` 全量通过、`uv run ruff check .` 干净、`vue-tsc -b` 与
`eslint .` 干净、`vitest run` 29 个文件 177 个测试通过。

## 3. 真实素材（8K）CLI 验收

素材：`cases/relight_space_video_01`（8192×4096、378 帧、30fps）的 GT 与氛围图，
区域由浏览器画出后直接用于 CLI。

```text
vrstudio relight --gt …space.mp4 --atmo …cand2.png --out <dir> \
  --sample-at 24 --ref-frame 24 --regions cases/…/relight/regions.json
```

- 退出码 0，单帧小样 3.40 秒（scan 0.04、read 0.59、align 0.24、fields 0.34、
  decode 0.57、compose 0.46、write 0.53）。
- 报告新增 `regions`：`file` 与 `sha256`（这次用的是哪一份区域文件）、`count`、`enabled`、
  `clip`，以及逐区域的完整定义（`verts`、`params`、`feather_deg`）与 `coverage`。
  完整定义写进报告，事后验收不依赖 `regions.json` 是否被改过；CLI 另外打一行
  `regions: N defined, M enabled, from <path>` 进任务日志。

与不带区域的一次运行逐像素比较（同一帧、同一参考帧）：

- 区域框内：288,796 个像素变化，最大差 72、均值 4.27——覆盖确实生效。
- 区域框外：1,976 个像素变化（占全帧 0.006%），最大差 3、均值 0.00007。这部分来自
  逐像素白平衡的浮点混合与羽化边界，不是区域扩散；没有区域时仍走原标量路径，
  逐位一致。

## 4. 浏览器验收

在 1440×900 的浏览器里对同一 case 完成：

- 点「多边形」逐点围出四边形，回车闭合：列表出现「区域 1」，视图显示填充、轮廓与顶点。
- 自动保存后 `cases/<case>/relight/regions.json` 有四个 `[lon, lat]` 顶点，
  `case.toml` 出现 `regions = "relight/regions.json"`。
- 选中区域把「整体施加量」切到覆盖并改成 0.40，刷新页面后仍为 0.40、开关仍打开。
- 拖动一个顶点改形，刷新后顶点位置与文件一致。
- 默认参数卡与区域参数卡都由同一份描述表渲染：软裁切两处都能开关并改拐点与上限。
- 播放：视图原先只在 `timeupdate`（约 4 次/秒）时上传纹理，8K 素材实测画布约 4fps、
  3 秒内 90 帧丢 77 帧；改用 `requestVideoFrameCallback` 按视频帧驱动后，上传 29.6 次/秒、
  解码 30.2fps、丢帧 0。

## 5. 后续修复（同轮）

- **环绕区域画不对**：`cases/RL_video_02` 的区域 3 在 unwrap 后经度跨度 383°，超过一整圈，
  多边形自重叠，引擎掩码覆盖率 7.08% 但不是一条横带。第一版在闭合时校验经度跨度与自交，
  超限拒绝并提示拆块；已存在的非法区域在列表里标 ⚠。
- **跨度小于 360° 的绕极盖帽仍被接受**：同一类形状里还有「从 -170° 走到 169°、纬度 60°」
  这种只差 21° 没走到接缝的盖帽，跨度 339° 低于旧阈值，旧版会保存成功，而引擎掩码覆盖率
  只有 0.092%，等于区域静默失效。现在闭合校验改为 `polygonWinding` 非零（绕极点）或跨度
  超过 360°（绕出去再折返的带）两条并列：前者的反例是 339° 盖帽（扭转量 1），后者的反例
  是一条从 0° 走到 680° 再折返的简单多边形（扭转量 0，但引擎会画成整幅宽、172 像素高的
  横带，覆盖率 14.17%）。旧文案里的「让边界经过极点」同步删除：整圈顶边会被最短路径折叠，
  只加一个极点顶点会画出锥形。引擎在 `load_regions` 用同一套规则按参数错退出 2，
  Web 读接口保持宽松以便页面标出旧数据。
- **高亮消失**：填充改为等距柱状掩码（2048×1024，S 方向 REPEAT）+ 片元着色器采样，
  不再要求所有顶点在相机前方；环绕观察者的区域也能显示填充。
- **全周缩略图**：只在选中区域时出现在右下角，且只画当前选中的那一个，跨视角与绕极点
  的形状可以在展开图上直接核对。

## 6. 未做与已知限制

- 只验证到单帧小样；整段 378 帧 8K 的完整渲染未在本轮跑（预计约 5 分钟量级，
  见决策 82 的实测），留待下一次真实素材验收。
- 时间轴只有「整段」占位；`ranges` 在首版必须为 null，时间区间是第二阶段。
- 视野外的区域只画可见段、不填充；全局校对的 equirect 缩略图未做。
- 区域外与无区域路径最多 1–3 级差异（逐像素白平衡与羽化边界），不是逐位一致；
  「删除全部区域后逐位一致」作为回归基线已由单测与 CLI 用例覆盖。
- 近似预览、套索、撤销栈未做（按方案留到后续）。
