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
29 files / 185 tests passed
```

本轮新增的前端用例：

- 339° 盖帽的 `regionShapeIssue(verts, 'north')` 为空；`regionBoundary` 末尾补到
  `[190, 60]`，`regionErpPolygon` 末尾两条是 `[190, 90]` 与 `[-170, 90]`。
- `pointInRegion` 在极点、接缝缺口（经度 175° 与 -175°）、边界内外、南北两侧的判定。
- 普通多边形带 `pole`、绕两圈的边界带 `pole` 都被判为 `winding`；普通区域自交被判为
  `self-intersect`。
- `erpPixel` 的接缝补画按像素平移：`erpPixel(0, 0, 2048, 1024, -2048) = [-1024, 512]`，
  而不是把 2048 当经度加到 2048°。

## 2.1 浏览器验收时修掉的高亮缺口

真实页面（`/next/case/RL_video_02/relight` 的区域 3）上，盖帽的高亮在接缝一侧少了
约 30% 的一块。原因是 `paintEquirect` 把整周平移量加在了经度上：

```ts
const x = ((lon + shift + 180) / 360) * width   // shift 是像素，却被当成度
```

掩码宽 2048 时 `shift = ±2048` 被当成 ±2048°（约 ±248°），补画的副本落到画布外；
普通小区域只靠 0 位移的副本就能覆盖，这个错误一直没显形。盖帽跨满一整周，接缝一侧
（经度 -180° 到边界起点 -65.7°）只能由 -W 副本覆盖，于是整块缺失。

修法是把经纬度到 ERP 像素的换算收进 `erpMath.erpPixel`，像素平移直接加在 x 上：

```ts
export function erpPixel(lon, lat, width, height, shiftPx = 0) {
  return [((lon + 180) / 360) * width + shiftPx, ((90 - lat) / 180) * height]
}
```

重建前端后重新加载页面，区域 3 的绿色高亮覆盖完整的一整圈盖帽，全周缩略图左侧
也不再缺块。这条修复同时消掉了普通区域跨接缝时可能出现的错位副本。

## 3. 未做

- **浏览器端到端**：已在 `RL_video_02` 的区域 3 上确认列表标签「包含上方」、3D 高亮与
  全周缩略图在修复后完整覆盖盖帽；还没有走「画满一圈 → 确认框 → 建成盖帽」的创建路径，
  也没有验证拖顶点破坏扭转量后按钮禁用与刷新持久化。下次用真实图片 case 补这两段。
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
