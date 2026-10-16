# Case 数据模型与 vrgen CLI 契约

两仓库的唯一接口权威。任何字段或命令面的变更先改本文，再改两侧代码与测试。

## 1. 原则

**case.toml 只放这个视频任务的静态事实。**
生成侧的一切（提示词、分辨率档、task_id、素材 id、调用日志）都不进 case；
它们住在 vrgen 的台账树里。case → vrgen 的唯一耦合是一行 `[adopt]` 指针。

## 2. case.toml 格式

### flow = "patch"（局部重绘：UE 出全景 + 白膜人物）

```toml
flow = "patch"

[source]
path = "../sources/ue_render_03.mp4"
sha256 = "…"            # merge 前校验；防"几何配错视频"

[viewport]              # 选区草稿：web pick 写入，extract 时冻结进 clip.json
yaw_deg = 0.0
pitch_deg = -10.0
fov_h_deg = 90.0
width = 1470
height = 943

[inner]                 # 白膜子区（视口内坐标）：真正送去重绘的部分
x = 400
y = 200
width = 600
height = 500

[frames]
start = 24
end = 168

[adopt]                 # vrgen 台账里被采用的轮次；采用时结果已拷入本 case
round = "dusk-c3a41f90"
```

### flow = "fullredraw"（全景重绘：AI 重绘整个 360°）

```toml
flow = "fullredraw"

[source]
path = "../sources/stock_pano.mp4"
sha256 = "…"            # 可选：pad 之后源不再被读，manifest 已含源身份

[adopt]
round = "dusk-a9fb11bc"
```

设计说明：

- `target_aspect` 不在 case 里——它是平台 bucket 参数，进 vrstudio 项目配置。
- `[viewport]/[inner]/[frames]` 是**草稿**（可变）；`clip.json` 是**契约**（冻结）。
  改范围 = 改草稿重新 extract = 新版本目录，两者分离避免 pick 迭代造成版本爆炸。
- 提示词草稿（theme/style）在 vrgen 侧按 job（=case 名）保存，case 不知道提示词的存在。

## 3. case 目录

```
cases/<名>/
  case.toml                      # 唯一真源（§2）
  # --- flow = patch ---
  extracts/<时间戳>/             # 版本化冻结契约（vrpatch 原样）
    clip.json                    #   字段集/version=1 冻结，单段守卫
    clip.mp4                     #   送生成的视口裁剪
    clip_mask.png                #   inner 掩膜
    result.mp4                   #   被采用的那轮结果（adopt 时从 vrgen 拷入）
  derived/                       # merge 产物 out_<版本>.mp4 + .merge.json + pick/ 预览缓存
  # --- flow = fullredraw ---
  seedance_input.mp4             # pad 画布（无损）
  seedance_input_mask.png
  seedance_input_pad.json        # recompose 唯一几何权威（契约原样）
  result.mp4                     # 被采用的那轮结果
  out/<轮次key>.mp4 + _recompose.json
```

## 4. vrgen CLI 契约

```
vrgen login [--check]                      # 登录态管理（透传 mglc）
vrgen models [--refresh]                   # 平台模型清单
vrgen submit --job <名> --input <视频> --mask <mask> \
           [--template <id>] [--set theme=…,style=…] \
           [--resolution 1080p] [--workdir <dir>]     # 断点续跑、task_id 防重发
vrgen status --job <名> [--watch]          # 轮询；--watch 阻塞到终态
vrgen register --job <名> --file <本地路径>            # 手动后端：写同格式台账
vrgen result --job <名> --round <key> --out <路径>     # 导出结果（adopt 时调用）
vrgen peek <task-id>                       # 零额度查平台侧状态
```

退出码：`0` 成功 / `2` 参数或配置错 / `1` 运行失败（台账里有完整现场）。

## 5. 台账格式（runs/<job>/<轮次key>/）

沿用 vrpad run.json 五件套，两条流程同构：

```
runs/<job>/<轮次key>/
  run.json            # 台账：stage/params/prompt/assets/task_id/result/gate/notes
  prompt.txt          # 实际发出的提示词
  command.txt         # 实际发出的 argv
  progress.log        # 过程叙事（含等待轮询），每次调用追加
  mglc.log            # 外部调用的 argv/返回码/错误消息
  upload_<w>x<h>.mp4  # 缩档后真正上传的（仅 mglc 后端）
  result.mp4          # 生成/注册的结果
```

关键机制（随 vrpad aigc/round 迁入）：task_id 防重发（断点续跑从台账断点继续）、
换账号后素材自愈、gate 数字留档、models.json 清单 24h 缓存。

手动注册后端（`register`）写同样的 run.json（backend = "manual"，无 upload 件与
task_id），保证下游 `result` / adopt 逻辑对两种后端无差别。
