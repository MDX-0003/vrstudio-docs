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
- 报告新增 `regions`：`count 1`、`enabled 1`、`coverage 0.00804`、`clip false`。

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

## 5. 未做与已知限制

- 只验证到单帧小样；整段 378 帧 8K 的完整渲染未在本轮跑（预计约 5 分钟量级，
  见决策 82 的实测），留待下一次真实素材验收。
- 时间轴只有「整段」占位；`ranges` 在首版必须为 null，时间区间是第二阶段。
- 视野外的区域只画可见段、不填充；全局校对的 equirect 缩略图未做。
- 区域外与无区域路径最多 1–3 级差异（逐像素白平衡与羽化边界），不是逐位一致；
  「删除全部区域后逐位一致」作为回归基线已由单测与 CLI 用例覆盖。
- 近似预览、套索、撤销栈未做（按方案留到后续）。
