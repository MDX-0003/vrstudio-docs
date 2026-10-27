# 对比页 360 视频播放卡顿排查与修复

状态：已实施修复，Playwright 实测定位到主因（B 路从未播放），待最终验证（真实浏览器）。
日期：2026-10-27。
涉及文件：`vrstudio/frontend/src/views/wizard/CompareStep.vue`、
`vrstudio/frontend/src/legacy/Erp360Compare.ts`。

## Playwright 实测定位（2026-10-27，case walk_4k）

在页面加载前注入脚本：包一层 `WebGLRenderingContext.prototype.texImage2D`
计时、记录 rAF 帧间隔、50ms 采样 `video.seeking`，播放 8–10s 后读取
`video.getVideoPlaybackQuality()`。结果与结论：

- 修复前：B 路（右路成片）`paused` 全程为 `true`——它从未被 `play()` 过，
  只靠 `syncFromMaster` 的 seek 挪进度；10 秒里 B 路解码 2024 帧（A 路 298 帧，
  7 倍无谓解码），约 1.35 秒处于 seeking。这就是"明显卡顿"的主因：右路画面
  是一跳一跳的，seek 解码尖峰还会挤占渲染。
- 修复后：两路时间轴与解码帧数完全一致（t=8.02s / 246 帧 / 丢帧 1），全程
  `seekTicks=0`，`texImage2D` 474 次共 44ms（单次最大 0.7ms）——GPU 上传快路径
  工作正常。
- 注意无头环境的两个坑：页面被判为不可见时 rAF 节流到 1fps（测量前要
  `bringToFront()`，用 `document.hidden` 自检）；无头软件渲染下两路视频 +
  WebGL 只能稳 30fps（rAF p50≈33ms），这是环境限制，不代表真实 GPU 环境表现。

## 根因与修复

### 0. B 路从未播放（主因，Playwright 实锤，已修复）

`togglePlay` 只调用了 A 路的 `play()`，B 路从迁移起没有任何播放驱动。修复：
A 路的 `@play` / `@pause` 事件里同步 `videoB.play()` / `videoB.pause()`；
B 路 `loadedmetadata` 时把进度对齐到 A 路当前位置（`onFollowerLoaded`），
避免从 0 起播造成起步阶段的大幅追帧。

### 1. 视频元素被藏成 1px + opacity:0（已修复）

旧写法把两路 `<video>` 设为 `width:1px; height:1px; opacity:0`，只靠 canvas 显示。
WebGL 从 video 上传纹理（`texImage2D(..., video)`）有 GPU 直拷贝快路径，前提是
视频元素真实参与合成、处于被渲染状态。元素缩到 1px 且完全透明时，浏览器放弃
快路径，退回 CPU 读回整帧；6K ERP 帧每帧几十 MB，两路每帧各传一次，CPU 拷贝
直接拖垮 rAF 循环。旧版视频元素正常摆着（被 canvas 盖住也算参与合成），走的是
快路径，所以流畅。

修复：视频平铺到 canvas 正下方（`inset:0` 满尺寸、`object-fit: cover`），
`opacity: 0.01` 强制真实合成（不能是 0，opacity:0 会跳过绘制，同样失去快路径）；
canvas `position: relative; z-index: 1` 盖在上面，画面只看得到 canvas。

### 2. B 路追帧 seek 风暴（已修复）

`timeupdate`（约每 250ms）里只要 B 路漂移超过 0.05s 就对它 `seek`。seek 会让
解码器从最近关键帧重解；B 路解码压力大时（代理未 ready 时走 `open_url` 播原始
6K 成片，尤其如此）永远追不平，结果是每次 timeupdate 都触发一次 seek，B 路长期
处于 seeking 状态，右路一格格地卡，且 `upload()` 因 `video.seeking` 不停跳过上传。

修复：追帧阈值从 0.05s 放宽到 0.3s（常量 `SYNC_THRESHOLD`），并在
`follower.seeking` 期间不再发起新 seek。旧阈值下轻微漂移本就可接受，
新的阈值对双路时钟对齐的可见影响可忽略。

### 3. 每帧强制同步布局（已修复）

`Erp360Compare.resize()` 原来既挂在 `window.resize` 上，又在每帧 `frame()` 里调用，
每帧读 `clientWidth/clientHeight` 会强制同步布局。旧版独立页 DOM 极小无所谓，
现在页面上有 Element Plus 组件树，这个每帧布局更贵。

修复：改用 `ResizeObserver` 观察画布，尺寸真正变化时才重设 backbuffer；
`frame()` 里不再调 `resize()`，`window.resize` 监听移除（ResizeObserver 覆盖
窗口变化与全屏切换两种情况）。

### 未改动的次要项（记录备查）

- 上传去重以 `currentTime` 为 key，正常播放等于每帧两路各 `texImage2D` 一次。
  如后续仍不够流畅，可换 `requestVideoFrameCallback` 只在新帧到达时上传。
- `currentTime` ref 每次 timeupdate 更新并驱动 el-slider 重渲染（约 4Hz），
  量级小，暂不处理。
- 确认对比环境：Vue dev 模式（dev build）本身比构建产物慢，验证时两边用同一环境。

## 播放画质切换（已实施）

对比页顶部新增「播放画质」下拉框：`代理`（默认）/ `原始分辨率`，作用于左右两路；
某一路代理未就绪时该路自动回落到原始地址（`source_url` / `open_url`）。
切换即改 `src`，视频重载后由 `onFollowerLoaded` 把 B 路对齐到 A 路当前进度，
同步机制不变。

原始分辨率实测（walk_4k，8192×4096，无头环境）：两路同步播放（5.73s/5.75s、
解码 181/182 帧）、零丢帧、无 seek。真实 GPU 环境的流畅度待用户验证；
如 8K 原始分辨率下 `texImage2D` 变慢，预期的现象是 tex 单次耗时从毫秒级涨到
十几毫秒以上，那才是上传快路径失效的信号。

## 交互微调（已实施，Playwright 已验证）

- **分割线改回旧版交互**：去掉底部分割条，分割线自身成为拖拽把手直接在画面上
  拖动（视觉 2px，命中区放宽到 14px；`z-index: 2` 压在 canvas 之上，
  `stopPropagation` 防止拖线带动视角）。左右方向键微调保留。
- **删除侧栏「旧版入口」**（SideNav.vue）；设置页里的旧版入口链接未动。
- **两路自动循环**：`<video loop>`；实测播过 9.8s 回绕点后两路仍在 2.2s 处
  同步继续播放。
- **默认原始分辨率 + 空格播放/暂停**：`quality` 默认 `original`（打开对比页即
  加载原始分辨率，代理在「播放画质」里手动选）；空格切播放/暂停，焦点在
  按钮/输入类控件上时交给控件本身处理避免双触发。实测：打开页面两路直接加载
  8192 宽原始源，空格起播、再按暂停，两路状态一致。

## 验证步骤（真实浏览器，待执行）

1. 启动前端（`npm run dev`，后端 8760 需在跑），打开 case（如 walk_4k）对比页，
   播放全程观察流畅度——重点看右路是否还一跳一跳。
2. 播放/暂停各一次，确认左右两路同时起播、同时停。
3. 拖动视角/滚轮变焦流畅；拖动分割线不改变视角；全屏进出后画面比例正确。
4. 「播放画质」切到「原始分辨率」再切回：两路地址各自变化、重载后保持同步，
   原始档播放流畅度作为是否保留该档的依据。
5. 如需复测数据，可在控制台粘注入脚本（texImage2D 计时 + rAF 帧间隔 +
   `getVideoPlaybackQuality()`），判读标准：rAF p95 ≤ 20ms、tex 单次 ≤ 数毫秒、
   两路 totalVideoFrames 一致且 dropped 接近 0、seeking 采样为 0。
