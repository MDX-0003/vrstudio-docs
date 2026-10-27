# 新建 case 支持上传源视频（复用分片上传管线）

状态：待实施（方案已与用户对齐，2026-10-27）。
涉及：`vrstudio/src/vrstudio/web/app.py`（仅 `api_cases` POST 分支）、
`vrstudio/frontend/src/components/upload/AssetUploadDialog.vue`（解耦终点）、
`vrstudio/frontend/src/views/CaseListView.vue`（入口）、`api/uploads.ts`（不动）。

## 背景与决策

外部用户的源视频目前必须人工拷到主机 `sources/` 才能在新建 case 时选择。
已对齐的方案：把素材上传的分片管线接到 case 创建上；入口放在新建 case
弹窗里源视频下拉框旁边，上传完成后自动选中新文件。已拍板的点：

- 上传管线（`/api/uploads` 三件套 + `_uploaded_paths`）**原样复用，零改动**；
  它本身 case 无关，"终点"由消费方决定。
- **单文件**：源视频一次一个（素材库的多选语义不适用于此处）。
- **同名冲突报错**：sources/ 是共享池不记归属、不做覆盖，已存在同名文件时
  返回明确错误让用户改名；上传者昵称等信息不带。

## 改动一：后端 `api_cases` POST 接受 `upload_id`

body 里 `upload_id` 与 `video` 二选一（都传时报错）：

1. `_uploaded_paths([upload_id])` 解析出文件（未 complete 报 400）。
2. 目标 `sources_dir()/<原名>`：已存在 → 409 `sources/ 里已有同名视频：<名>`。
3. `shutil.move` 进 sources/，然后**完全走现有路径**：cv2 探测
   （打不开 400）、`case_mod.create`、patch 默认草稿。case 名缺省仍取
   视频名 stem（用上传文件的原始文件名）。
4. 上传会话目录在 move 成功后清理（与 `api_assets op=add` 同款）。
5. 校验上传文件扩展名属于 `_VIDEO_EXTS`，否则 400——防呆，创建接口的
   cv2 探测是第二道网。

## 改动二：`AssetUploadDialog` 解耦上传终点

现状：对话框完成上传后自己调 `addAssetsByUploads`，终点写死为素材库。
改法：新增可选属性 `destination`（默认 `'assets'` 保持现行为；`'source'`
时单文件、完成回调把 `{upload_id, name}` 交给调用方而非自行落库）。
上传、进度、取消、sha256 逻辑全部不动。

## 改动三：`CaseListView` 新建弹窗加入口

- 源视频下拉框（非 gen 流程可见）旁加「上传视频」按钮，点击打开
  `AssetUploadDialog destination="source"`。
- 上传成功回调：把新文件名追加进 sources 下拉列表并自动选中；弹窗关闭，
  用户点「创建」走原有 POST `/api/cases`（带 `upload_id`）。
- `sources/` 为空时的空态文案补一句"可点击上传视频"。
- 创建请求体在选择了上传文件时用 `upload_id`，用现有下拉项时仍传 `video`
  （两条路径后端都通）。

## 测试

- 后端：`upload_id` 建链主路径（fake 上传会话 → 建 case → case.toml 的
  帧数/宽高来自该视频）；未 complete 的 upload_id 400；同名 409；
  非视频扩展名 400；`upload_id` 与 `video` 同传 400；gen 流程带
  `upload_id` 的行为（与现规则一致：可无视频）。
- 前端：`AssetUploadDialog` destination='source' 时完成回调收到
  upload_id 且不调 addAssetsByUploads；CaseListView 上传成功后下拉列表
  出现新文件并选中。

## 验收

1. 在新建 case 弹窗（patch/fullredraw）点「上传视频」，选本机大视频文件，
   分片上传完成后下拉框自动选中它，填写名字创建成功。
2. 创建出的 case 选区步骤正常，帧数与源视频一致。
3. 再次上传同名文件：409 且提示明确；换名后成功。
4. gen 流程不受影响（仍可不传视频、只选模式）。
5. `uv run pytest`、`ruff check .`、`npm run typecheck`、`vitest run` 全绿。
