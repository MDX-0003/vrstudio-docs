# vrstudio 操作手册

本目录存放「从打开网页到拿到 AIGC 重绘视频」这份操作手册，以及制作它所需要的全部中间材料。手册面向不懂 AIGC 与 360 视频的普通用户，三条流程各自成章。

当前状态：第 1 版已完成，42 张截图与 1 张对照图已就位，正文每个小节都配有图片。

## 目录结构

- `output/aigc-redraw-guide.md` 是当前正式文档。图号只出现在图注里，图片文件名不带图号，正文用相对路径 `../images/<文件名>` 引用。
- `output/aigc-redraw-guide-<序号>.md` 是历史版本。每次更新前，先把当前文件改名为 `-1`，下一次改名用 `-2`，依次递增；新内容始终写回 `output/aigc-redraw-guide.md`。这样当前版本路径固定，外部引用不会失效，历史版本又能逐个查到。
- `images/` 存放最终选用的截图与对照图。文件名与正文引用一致，不带日期。
- `draft/` 存放历史草稿，文件名带日期。改结构之前先复制一份当前文档进来，改坏了可以退回。
- `shots/raw/` 存放未经标注的原始截图。
- `shots/annotated/` 存放带编号与红框的截图。`images/` 里的同名文件从这里复制而来。
- `shots/archive/<日期>/` 存放被替换下来的旧图，用来对比新旧界面。
- `tools/shots.json` 是每张图的拍摄与标注清单，也是判断「哪张图对应哪一节」的唯一依据。
- `tools/specs/<图片id>.spec.json` 记录该图的裁剪矩形与每个编号的屏幕坐标，配合 `annotate.py` 可以离线重新生成标注图。
- `tools/annotate.py` 读取截图与 spec，用 FFmpeg 裁剪并画出红框与编号。
- `tools/capture-lib.mjs` 在浏览器里计算目标元素的坐标，生成 spec 所需的 `clip` 与 `marks`。
- 第六章的对照图是手写的 SVG，文件本身就是源：`images/flow-compare.svg`。

临时目录 `E:\VRAIGC\.manual-draft\` 只放可以再生的东西，例如 case 副本、浏览器用户数据、失败重拍的中间文件；它随时可以整个删除，不影响本目录。

## 三条保留规则

1. 正文、历史版本、草稿、原始截图、标注截图、最终图片全部长期保留，制作结束后不删除。
2. 图片文件名是唯一标识，正文与清单都引用它。重命名一张图要同时改正文、`shots.json` 与三处图片目录。
3. 被替换的旧图不删除，移动到 `shots/archive/<日期>/`，保留新旧对照。

## 只更新必要部分的操作

**只有文字要改。** 先把 `output/aigc-redraw-guide.md` 改名为 `output/aigc-redraw-guide-1.md`（已经存在 `-1` 时改用下一个未占用的序号），再把新版写回 `output/aigc-redraw-guide.md`。图片与清单不动。

**只有一张或几张图要换。** 在正文里找到图片文件名，到 `tools/shots.json` 里找同名 `id`，按下面的制作流程重拍这一张。重拍会同时覆盖 `shots/raw`、`shots/annotated` 与 `images` 三处的同名文件。新旧界面对照完成后，把旧图移到 `shots/archive/<日期>/`。

**页面结构大改、多数图要换。** 先按新界面修改 `shots.json` 里的 `target`、`clip` 与 `annotations`，再整体重拍。重拍前把整个 `images/` 与 `shots/annotated/` 复制到 `shots/archive/<日期>/`。

**界面没变、只是代码提交变了。** 用 `shots.json` 顶部的 `vrstudio_commit` 与 `captured_at` 判断录制时间，按改动涉及的页面挑出可能过期的图，只重拍这些。

## 截图制作流程

1. 把演示 case（`walk_4k`、`ship_01`、`simple_gen_allMediaRef`）硬链接到 `E:\VRAIGC\.manual-draft\cases\`，用 `uv run vrstudio serve --cases-dir ... --port 8761` 起一个专用实例。不要直接对 8760 操作，那会在真实 case 上写占用标记。
2. 用浏览器打开 `http://localhost:8761`（注意用 localhost，不要用 127.0.0.1，昵称 Cookie 只对写入时的域名有效），按 `shots.json` 逐项定位目标元素。
3. 用 `tools/capture-lib.mjs` 的 `computeSpec` 计算 `clip` 与 `marks`，把当前页面整屏截图与 spec 一起保存。坐标使用浏览器视口坐标，单位是 CSS 像素。
4. 执行 `python tools/annotate.py <截图> <spec> <raw输出> <annotated输出>`。脚本用 FFmpeg 按 `clip` 裁剪，再画 2 像素红框与白底红边的编号方块。
5. 逐张读图验收：编号不压文字、红框不框到无关区域、画面里没有占用警告或错误提示。不合格改 spec 重跑，不直接编辑图片。

`shots.json` 顶部的 `captured_at` 与 `vrstudio_commit` 在每次整体重拍后更新。单项重拍不更新这两个字段，只在对应条目里记录 `recaptured_at`。

## 截图约定

- 所有截图按控件簇裁剪，只有每个步骤的布局图保留较大画面。
- 裁图至少保留一个定位参照：步骤条、面板标题或页面标题。
- **裁剪与标注互相独立。** 裁过的图仍然可以同时加编号与红框；裁剪去掉无关内容，编号说明操作顺序，红框强调需要细看的位置，三者可以叠加使用。
- 红框用于强调，圆圈数字表示操作顺序，两者可以出现在同一张图里，也可以按需要只用其中一种。
- 一张图最多四个编号。
- 编号与红框只出现在交互区域，不框标题栏，不框浏览器标签页。

## 已知例外

- 第一章的「浏览器地址栏」不是真实截图，而是用 FFmpeg 画出的示意图。本环境无法截取浏览器外框，示意图只承担「地址写在哪里」这一个信息。更新时同样用 FFmpeg 重画，没有原始截图。
- 「任务中心」一节没有可拍的真实任务，按「要么有图、要么不写」的规则整节删除了。
- 简单生成实际提供四个模式（VideoEdit、AllMediaRef、VideoExtend、FirstLastFrame），没有 FirstFrame。第 1 版按四个模式编写。
- 简单生成的结果区没有视频播放器，第 1 版的「选用成片」图改为展示可用轮次、选用按钮与最近可用轮次编号。
- 「常见问题与报错处理」与「成片文件在哪里」两章按审查意见删除；成片路径改成写在合并、裁回与简单生成三节里。
