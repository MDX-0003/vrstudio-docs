# 重打光区域盖帽（含极点扇形）实施与验收

对应决策 89，方案见 `docs/plan/relight-regions-plan.md` 第三阶段（WP10–WP13）。
本轮把「绕极点一圈的边界」从拒绝改成可保存的盖帽，契约、引擎、前端几何与界面一起改。

## 1. 落了什么

- **契约**：`regions.json` 的 `version` 保持 1，字段集直接增加可选 `pole`
  （`"north"` / `"south"` / 缺省或 `null`）。有 `pole` 时 `verts` 是绕该极点一圈的闭环，
  区域取极点所在的一侧；不存合成出来的接缝点与极点顶点。旧文件没有 `pole`，按普通
  多边形读取。
- **引擎**：`Region` 增加 `pole`；`_check_shape` 对盖帽要求 `abs(winding) == 1`、
  经度跨度不超过 360°、真实边界不自交；普通区域仍要求扭转量 0、跨度不超过 360°、
  不自交。`_rasterize` 把首个顶点按 ±360 复制成接缝短边，再从复制点与原点沿纬度 ±90
  补两条经线边与一条极点边，然后走原来的 `fillPoly` 与 ±W 平移。报告新增 `pole`。
- **前端几何**：`erpMath.ts` 新增 `regionBoundary` 与 `regionErpPolygon`，作为
  「区域 → ERP 平面多边形」的唯一实现；掩码、缩略图、轮廓、命中测试都走它。
  `pointInRegion` 在 x、x±360 三个代表位置上取并集，修掉宽区域按 `polygon[0]`
  归位会选错代表点的问题。`regionShapeIssue` 增加 `pole` 参数；`isPoleCapShape`
  供闭合时判断是否弹确认框。
- **交互**：闭合时若边界绕极点恰好一圈，弹「包含上方 / 包含下方」确认框，默认按
  边界平均纬度选一侧；确认后保存 `pole`，列表显示对应标签。拖顶点把扭转量改坏或
  造成自交时，该区域标 ⚠，运行按钮禁用并给出提示；引擎在 `load_regions` 同样按
  参数错退出 2。顶点的纬度在写入前夹到 ±89.5°，极点只由 `pole` 标记。
- **文档**：`docs/case-model.md` 的字段集与 JSON 例子补 `pole`；`docs/decisions.md`
  新增决策 89；计划补数据模型、闭合校验、光栅化、工作包与验收。

## 2. 已做的验证

引擎（`vrstudio`）：

```text
uv run pytest tests/test_relight_regions.py -q
26 passed
uv run pytest -q
全量通过（含既有区域基线、强度 0 与无区域逐位一致用例）
uv run ruff check .
All checks passed!
```

本轮新增的引擎用例：

- `test_parse_accepts_a_pole_cap_and_validates_the_field`：`pole` 取值校验；
  普通多边形与绕两圈的边界不能标成盖帽。
- `test_strict_geometry_rejects_self_intersection`：普通区域自交按参数错拒绝。
- `test_rasterize_pole_cap_covers_the_pole_side`：北极与南极盖帽逐行对照解析判定
  （北方为 `lat >= 60`、南方为 `lat <= -60`），所有经度都被覆盖，边界外不被覆盖；
  覆盖率落在 30/180 行。
- `test_rasterize_westward_cap_matches_eastward`：顺时针与逆时针绘制的盖帽掩码逐像素相同。
- `test_cli_applies_a_pole_cap_and_reports_it`：CLI 端到端，纬度 80° 的像素与 GT
  逐像素一致（`strength = 0`），报告带 `pole: "north"`。

前端（`vrstudio/frontend`）：

```text
npm run typecheck
npm run lint
npx vitest run
29 files / 184 tests passed
```

本轮新增的前端用例：

- 339° 盖帽的 `regionShapeIssue(verts, 'north')` 为空；`regionBoundary` 末尾补到
  `[190, 60]`，`regionErpPolygon` 末尾两条是 `[190, 90]` 与 `[-170, 90]`。
- `pointInRegion` 在极点、接缝缺口（经度 175° 与 -175°）、边界内外、南北两侧的判定。
- 普通多边形带 `pole`、绕两圈的边界带 `pole` 都被判为 `winding`；普通区域自交被判为
  `self-intersect`。

## 3. 未做

- **浏览器端到端**：确认框的点击、拖顶点破坏扭转量后按钮禁用、刷新后标签与形状保持，
  这三项还没有在真实浏览器里走一遍；本轮只覆盖了几何与 CLI。下次用真实图片 case
  沿极点外圈画一圈补验。
- **真实 8K 素材**：只跑了 256×128 合成图与 360×180 掩码对照，没有在 8K 视频上跑整段；
  区域场仍在 2K 构造，预期耗时与无盖帽路径相同，但还缺一次实测记录。
- 环带、洞、极点的补集与绕两圈以上的边界不在本轮范围，仍按参数错拒绝。

## 4. 涉及文件

- `docs/case-model.md`、`docs/decisions.md`、`docs/plan/relight-regions-plan.md`
- `vrstudio/src/vrstudio/relight/regions.py`
- `vrstudio/src/vrstudio/cli/relight.py`（报告透传 `pole`）
- `vrstudio/tests/test_relight_regions.py`
- `vrstudio/frontend/src/utils/erpMath.ts`
- `vrstudio/frontend/src/components/relight/ErpRegionViewer.vue`
- `vrstudio/frontend/src/components/relight/RegionWorkbench.vue`
- `vrstudio/frontend/src/views/wizard/RelightStep.vue`
- `vrstudio/frontend/src/types/case-info.ts`
- `vrstudio/frontend/tests/unit/erp-math.spec.ts`
