# Patch 选区范围的剪贴板导出与导入方案

状态：已实施（2026-11-06）：接口、单测、前端测试与构建通过；浏览器待人工验收，
验收记录见 `docs/test-runs/20261106-patch-region-clipboard.md`。
涉及：`vrstudio/src/vrstudio/web/app.py`、`vrstudio/src/vrstudio/web/render.py`、
`vrstudio/frontend/src/views/wizard/PickStep.vue`、`views/WizardView.vue`、
`api/workflow.ts`、`utils/clipboard.ts`、`types/case-info.ts`、
`tests/test_web_console.py`、`frontend/tests/unit/pick-step.spec.ts`。

## 背景

patch 的选区由三部分组成：视口的 yaw/pitch/fov、视口像素里的 inner 矩形、抽取的帧范围。
同一场景的多个 case（不同机位、不同动作段、重跑）经常需要复用同一套取景，现在只能
在页面上重新点、拖、调 fov，或者手改 `case.toml`。前者的精度靠手感，后者容易写错键或
写出越界值。

本方案在选区页加两个按钮，用剪贴板在 case 之间搬运已保存的选区。

## 决策（2026-11-06 用户确认，决策 92）

1. 标题右侧的「重置选区」下面单独一行放「导出范围」与「导入范围」两个并列按钮；
   只对视频 patch 显示，patchimg 图片局部流程不显示（没有 fov 与抽取范围）。
2. 剪贴板里除 inner、yaw、pitch、fov 外还带视口尺寸 `width × height`。目标 case 的
   视口尺寸与来源不同时，inner 按宽高各自比例缩放，目标视口尺寸保持不变。
3. 抽取范围（帧起止）一起导出与导入。
4. 导出读 `case.toml` 里已保存的值，不读前端可能尚未落盘的状态；导入立即写入
   `case.toml`，并用轻量几何应答把预览、inner 框、fov 滑杆、帧输入框同步到页面。

## 剪贴板格式

前端把后端返回的对象用 `JSON.stringify(data, null, 2)` 格式化成文本写入剪贴板：

```json
{
  "kind": "vrstudio.patch.region",
  "version": 1,
  "case": "1106-30s",
  "exported_at": "2026-11-06T16:20:00+08:00",
  "viewport": {
    "yaw_deg": 12.5,
    "pitch_deg": -3.0,
    "fov_h_deg": 59.0,
    "width": 1920,
    "height": 1080
  },
  "inner": { "x": 480, "y": 270, "width": 960, "height": 540 },
  "frames": { "start": 0, "end": 299 },
  "fps": 30.0,
  "frame_count": 300
}
```

- `kind` 与 `version` 是识别标记，导入时缺省或不相符直接拒绝，避免把提示词、参数等
  任意 JSON 当成选区写进 case。
- `case` 与 `exported_at` 只用于人读和溯源，导入时忽略；不同 case 之间粘贴是正常用法。
- `viewport.width`/`viewport.height` 是来源视口的采样尺寸，只参与 inner 缩放，不写进
  目标 case。
- `frames` 是来源 fps 下的绝对帧号，闭区间；`fps` 与 `frame_count` 用来把它换成秒、
  再落到目标 case 的时间轴，帧号本身不直接搬进目标。
- 同一段 0.5–1.5 秒的选区，从 30 fps 的来源导到 24 fps 的目标会从 15–44 帧变成
  12–35 帧；目标更短时结束帧截到最后一帧。

## 后端

### 端点

```
GET  /api/case/{name}/region/export    → 200 剪贴板对象
POST /api/case/{name}/region/import    body: 剪贴板对象
                                       → 200 轻量几何应答
```

两个端点都要求 `flow = "patch"`；其他流程返回 400，文案说明只有视频 patch 有选区范围。
case 不存在返回 404。导出只读，不推进 revision；导入写入 `case.toml` 并纳入
`_REVISION_WRITES`，客户端带 `X-Case-Revision` 时由现有中间件做乐观并发校验，
冲突返回 409 `revision_conflict`。

### 导入校验

所有校验在读到的值上完成，任何一项失败都不写盘（不会出现「角度写进去了、帧范围没写」）：

- `kind` 必须是 `vrstudio.patch.region`，`version` 必须是 `1`。
- `viewport`、`inner`、`frames` 必须是对象；数值必须是有限数字，布尔值不算数字。
- `yaw_deg` 在 ±180° 内，`pitch_deg` 在 ±89° 内，`fov_h_deg` 在 20–120° 内。
- 角度按现有 setter 的精度落盘：yaw/pitch 保留两位小数，fov 保留一位。
- `viewport.width`、`height` 是正整数；`inner` 的 x/y 非负、width/height 为正，且
  `x + width <= 来源视口宽`、`y + height <= 来源视口高`。
- `fps` 为正数，`frame_count` 为正整数；`frames.start`、`end` 是整数，并且
  `0 <= start < end <= 来源 frame_count - 1`。
- 帧范围换算：来源与目标 fps 相同（相对误差 1e-3 内）时保留原帧号；不同时按
  `start / source_fps`、`(end + 1) / source_fps` 得到半开秒区间，再乘目标 fps 取整。
  换算后起点超过目标最后一帧时返回 400，提示目标时长与来源秒区间；结束帧超过目标
  最后一帧时截到最后一帧，应答带 `frames_clamped=true`。
- inner 按 `目标视口宽 / 来源视口宽`、`目标视口高 / 来源视口高` 缩放并四舍五入；
  取整可能越界 1 像素，写盘前把 x/y 钳到 `[0, 目标尺寸 - 1]`、width/height 钳到不越界。
- 当前 case 没有视口、或读不到来源/目标的 fps 与帧数时返回 400，提示无法换算。

### 写入与预览刷新

`PreviewStore.import_region()` 一次调用写入 viewport（只改 yaw/pitch/fov，尺寸保持）、
inner 和 frames，再刷新预览 key；端点用 `_remember_store()` 保住已解码的 ERP 帧缓存，
返回 `_geometry_payload(store, name, frames=..., scaled=..., frames_clamped=...)`。
`scaled` 表示 inner 是否因尺寸不同被缩放，`frames_clamped` 表示帧范围是否被目标时长
截断，前端用这两项决定提示文案。应答里的 `frames` 让前端不必再拉完整 case info。

### 缩放规则共用

`PreviewStore.set_viewport_size()` 原有的 inner 等比缩放抽成私有方法
`_scale_inner(inner, from_w, from_h, to_w, to_h)`，`set_viewport_size()` 与
`import_region()` 都调用它，避免同一套取整与钳制规则写两遍。

## 前端

### 按钮与状态

选区页右栏面板标题（`选区与抽帧范围` + 重置选区）下面新增一行：

```
[导出范围] [导入范围]
```

`display: flex`、`gap: var(--space-2)`、`margin-bottom: var(--space-3)`，与下方
「视口尺寸」行保持现有面板节奏。按钮带 `CopyDocument` / `Download` 图标，
请求期间各自显示 loading 并禁用重复点击。

### 导出

1. `GET .../region/export` 取已保存的选区对象。
2. `JSON.stringify(obj, null, 2)` 后写剪贴板。
3. 成功提示：`已复制选区范围（1920×1080，帧 0–299）`。
4. 浏览器拒绝写剪贴板时先走 `document.execCommand('copy')` 兜底；仍失败则弹
   「手动复制」对话框，展示同一段 JSON，提示按 Ctrl+C。

### 导入

1. 读剪贴板。读取被浏览器拒绝或环境没有 `navigator.clipboard.readText` 时，弹
   「手动粘贴」对话框，粘贴后点「导入」。
2. `JSON.parse` 失败提示「剪贴板内容不是 JSON」；解析成功但校验失败时显示后端返回的
   具体原因（哪个字段、什么范围）。
3. `POST .../region/import` 成功后：
   - 用应答调用页面现有的 `applyGeometry()`，刷新视口预览、footprint、coverage、
     fov 滑杆、yaw/pitch 文案；
   - 用应答的 `frames` 更新帧范围输入框；
   - 向父组件 `emit('geometry')`，使 `WizardView` 的 `caseInfo` 同步 viewport/inner/
     previews/frames，切走再回来不会看到旧帧范围。
4. 成功提示：尺寸一致且帧范围未截断时 `已导入选区范围`；尺寸不同时追加
   `inner 已按当前视口 1920×1080 缩放`；帧范围被截断时追加
   `帧范围已按目标时长截到 0–239`。两项都发生时用「；」连接。

剪贴板工具放 `frontend/src/utils/clipboard.ts`：`writeClipboard(text)` 返回是否成功，
`readClipboard()` 在不可用时抛 `ClipboardUnavailableError`，页面据此决定是否弹手动对话框。

## 测试

### 后端（`tests/test_web_console.py`）

1. 导出返回已保存的 viewport/inner/frames、来源 `fps`/`frame_count`、`kind` 与
   `version`，不返回完整 case info。
2. 导出对 fullredraw 与 patchimg 返回 400，未知 case 返回 404。
3. 同尺寸导入：yaw/pitch/fov/inner/frames 逐字段落盘，应答含 `frames`、`scaled=false`。
4. 不同尺寸导入：目标视口尺寸不变，inner 按比例缩放取整，应答 `scaled=true`。
5. 不同 fps：来源 30 fps 的 15–44 帧（0.5–1.5 秒）导到 24 fps 目标，落成 12–35 帧。
6. 目标更短：来源 0–299 帧导到 8 帧目标，截成 0–7 并返回 `frames_clamped=true`。
7. 起点已超过目标时长：400，提示目标最后一帧与来源秒区间，不写盘。
8. 非法 payload：kind/version 不符、fov/pitch/yaw 越界、inner 超出来源视口、
   帧范围超出来源总帧数、缺 frames/fps/frame_count、fps 非正，全部 400 且
   case.toml 不变。
9. 带过期 `X-Case-Revision` 的导入返回 409，不写盘。
10. 导入成功后 revision 加一，`case.toml` 的 `[frames]` 与 `[inner]` 同步更新。

### 前端（`frontend/tests/unit/pick-step.spec.ts`、`clipboard.spec.ts`）

1. patch 显示两个按钮，patchimg 不显示。
2. 点击导出调用 `exportRegion` 并把格式化 JSON 写入剪贴板，提示含尺寸与帧范围。
3. 点击导入把解析后的对象交给 `importRegion`，成功后 yaw/pitch、inner 文案、fov
   数值与帧范围全部更新，`geometry` 事件带 `frames`。
4. 应答带 `frames_clamped` 时提示「帧范围已按目标时长截到 …」。
5. 剪贴板内容不是 JSON 时不调用导入端点，提示错误。
6. `navigator.clipboard.readText` 不存在时打开手动粘贴对话框，提交后走同一导入路径。
7. `clipboard.ts`：正常读写、写失败时走 `execCommand` 兜底、读不可用时抛专用错误。

## 验收

1. `uv run pytest` 全绿，`uv run ruff check .` 干净。
2. `npm run test`、`npm run typecheck`、`npm run build` 全绿，`npm run lint` 干净。
3. 浏览器：case A 选区页点「导出范围」，切到 case B 的选区页点「导入范围」；
   B 的预览图、inner 框、yaw/pitch、fov 与帧输入框立即变成 A 的值；刷新后仍在。
4. 两个 case 视口尺寸不同时，B 的视口尺寸不变，inner 的相对位置与大小按比例保留，
   提示带「已缩放」。
5. 目标 case 比来源短时，导入后的结束帧落在目标最后一帧，提示带「已按目标时长截到」；
   目标 case 的 fps 与来源不同时，帧号按时间换算后落在同一段秒区间。
6. 剪贴板里塞一段普通文本再点导入，页面提示内容不是选区且 case 不被修改。

## 工作包

- WP1 文档：决策 92、本方案、前端决策条目与文档索引。
- WP2 后端：`_scale_inner()`、`import_region()`、导出/导入端点、路由与 revision。
- WP3 前端：类型与 API、剪贴板工具、按钮与手动对话框、`WizardView` 的 frames 同步。
- WP4 测试与验收：pytest、vitest、typecheck/build、浏览器端到端与验收记录。
