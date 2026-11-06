# patch 选区范围剪贴板导入导出验收（2026-11-06）

状态：接口、单测与前端构建通过；浏览器端到端未执行（本会话没有浏览器自动化工具），
人工步骤见文末。

## 实施落点

- 后端：`src/vrstudio/web/render.py` 新增 `_scale_inner()` 与
  `PreviewStore.import_region()`；`set_viewport_size()` 改用同一份缩放规则。
- 后端：`src/vrstudio/web/app.py` 新增 `REGION_KIND` / `REGION_VERSION`、
  `_region_payload()`、`_region_fields()`，两个端点与路由，导入纳入
  `_REVISION_WRITES`。
- 前端：`src/views/wizard/PickStep.vue` 新增「导出范围/导入范围」按钮、手动复制与
  手动粘贴对话框、导入后的页面同步；`views/WizardView.vue` 在几何事件里同步
  `frames`。
- 前端：`src/api/workflow.ts`、`types/case-info.ts` 增加选区负载与几何应答字段；
  `src/utils/clipboard.ts` 提供读写剪贴板与 `execCommand` 兜底。
- 测试：`tests/test_web_console.py` 新增 11 条 region 测试；
  `frontend/tests/unit/pick-step.spec.ts` 新增 4 条、`clipboard.spec.ts` 新增 6 条。

## 契约

```
GET  /api/case/{name}/region/export   → 200 {"kind":"vrstudio.patch.region","version":1,...}
POST /api/case/{name}/region/import   body 同上 → 200 轻量几何应答
```

- 负载含 `viewport`（yaw/pitch/fov/width/height）、`inner`、`frames`、来源 `fps` 与
  `frame_count`，以及仅供溯源的 `case` 与 `exported_at`。
- 导入只改 yaw/pitch/fov，不改目标视口尺寸；尺寸不同时 `inner` 按宽高各自比例缩放，
  四舍五入后钳进目标视口。
- `frames` 是来源 fps 下的绝对帧号，导入时按 `start / source_fps` 与
  `(end + 1) / source_fps` 换成秒、再乘目标 fps 还原；fps 相同则保持原帧号。
- 换算后结束帧超出目标最后一帧时截断并返回 `frames_clamped=true`；起点已超过目标
  时长时返回 400，不写盘。
- 导入前一次性校验 fov、pitch、yaw、inner 边界、来源帧范围与 fps/帧数；任一失败
  返回 400 且 `case.toml` 不变。
- 导入成功返回 `viewport`、`inner`、`previews.vp`、`viewport_footprint`、`coverage`、
  `fov_range`、`frames`、`scaled`、`frames_clamped`，并推进 revision。

## 门禁

- `uv run pytest`：775 passed（exit 0），含新增 11 条 region 测试。
- `uv run ruff check .`：All checks passed。
- `npm run test`：31 个测试文件、206 条测试全部通过（新增 10 条）。
- `npm run typecheck`：通过。
- `npm run lint`：通过。
- `npm run build`：通过；构建产物包含「导出范围」「导入范围」「region/export」
  「region/import」。
- `npm run format:check`：本次改动的文件已格式化；仍有 10 个与本功能无关的历史文件
  不符合 Prettier（relight 相关），未一并修改，避免把无关格式变更混进本笔。

## 接口行为验证（pytest）

1. 导出返回 `case.toml` 的 viewport/inner/frames、来源 `fps` 与 `frame_count`、
   `kind` 与 `version`，不返回完整 case info。
2. fullredraw 走「没有选区草稿」400，patchimg 走「只有视频 patch」400，未知 case 404。
3. 同尺寸导入逐字段落盘，应答 `scaled=false`、`frames` 与预览 key，revision 从 0 变 1；
   yaw 45.55 保留两位小数。
4. 来源 1920×1080、目标 320×180 时，目标视口尺寸保持 320×180，inner 480/270/960/540
   缩成 80/45/160/90，应答 `scaled=true`。
5. 来源 30 fps 的 15–44 帧（0.5–1.5 秒）导到 24 fps、48 帧的目标，落成 12–35 帧，
   `frames_clamped=false`。
6. 来源 0–299 帧（10 秒）导到 8 帧、30 fps 的目标，截成 0–7，`frames_clamped=true`。
7. 来源 150–179 帧（5–6 秒）导到 8 帧目标时 400，提示起点超过最后一帧，case 不变。
8. 导出再导入，同尺寸下 inner 逐字段相同。
9. 15 种非法负载（kind/version 不符、缺字段、fov/pitch/yaw 越界、inner 越界、
   帧范围超出来源总帧数或为空、缺 fps/frame_count、fps 为 0、布尔/字符串数值）全部
   400，且 viewport/inner/frames 不变。
10. 请求体不是 JSON 时 400。
11. 带过期 `X-Case-Revision` 导入返回 409，不写盘；不带头的旧客户端照旧写入并把
    revision 推进到 2。

## 前端行为验证（vitest）

1. patch 显示两个按钮，patchimg 不显示。
2. 导出把格式化 JSON 写入剪贴板，提示带尺寸与帧范围；写失败时打开手动复制框
   （readonly 文本域）。
3. 导入把解析后的对象交给 `importRegion`，页面 yaw/pitch、inner 文案、fov、
   帧范围都更新，`geometry` 事件带 `frames` 与新的 `previews.vp`。
4. 应答带 `frames_clamped` 时提示「帧范围已按目标时长截到 …」。
5. 剪贴板不是 JSON 时不调用导入端点，提示错误。
6. 剪贴板读取不可用时打开手动粘贴框，提交后走同一导入路径并关闭对话框。
7. `clipboard.ts`：`writeText` 成功、拒绝后走 `execCommand`、两条路都不可用返回
   false；`readText` 成功、API 缺失与权限拒绝都抛 `ClipboardUnavailableError`。

## 浏览器人工验收（未执行）

前置：Python 改动需要重启 `uv run vrstudio serve`；前端已重新 build，刷新页面即可。

1. 打开 case A 的选区页，确认「重置选区」下方一行有「导出范围」「导入范围」，两者
   并列且与下方「视口尺寸」有间距。
2. 在 A 上改动 yaw/pitch/fov/inner 与帧范围并确认已保存，点「导出范围」，看到
   `已复制选区范围（…×…，帧 …–…）`；把剪贴板内容粘到文本编辑器，确认是格式化 JSON。
3. 打开 case B（同源或同场景）的选区页，点「导入范围」，确认预览图、inner 框、
   yaw/pitch 文案、fov 数值与帧输入框立即更新（同 fps 时帧号与 A 相同，不同 fps 时
   是按时间换算后的帧号），刷新后仍在。
4. 把 B 的视口尺寸切到另一个档位再导入 A 的范围，确认 B 的尺寸不变、inner 按比例
   缩放，提示带「已缩放」。
5. 用一段比 A 短的 case 导入 A 的范围：确认结束帧截到目标最后一帧，提示带
   「帧范围已按目标时长截到」；再用一段 fps 不同的 case，确认帧号按秒换算。
6. 在剪贴板里放一段普通文本再点导入，确认提示「剪贴板内容不是选区范围」，且 B 的
   case.toml 未被修改。
7. 用局域网 http 打开页面（非安全上下文）时，确认导出退到手动复制框、导入退到手动
   粘贴框，粘贴后仍能成功导入。

## 未做与限制

- 没有跑浏览器端到端：本会话没有 Playwright/MCP 浏览器工具，无法点击真实页面。
- 帧范围按时间换算后，结束帧超出目标时长会截到最后一帧并提示；起点已超过目标时长
  时直接 400，不做比例回退，需要用户回页面调或换 case。
- `patchimg` 不显示按钮，后端也拒绝；如果以后要支持图片局部，先补 fov 与 frames 的
  缺省语义，不要复用同一份必填契约。
- 剪贴板读取在 http 局域网不可用是浏览器限制，页面用手动粘贴兜底；不引入服务端剪贴板。
