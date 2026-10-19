# 项目、剧集与生成会话（mglc 的计费上下文）

本文记录 mglc 的层级结构、生成会话 ID 的取得方式、它如何影响额度扣减，以及 vrgen 当前把会话 ID 接到生成请求上的位置。文中“已验证”指 2026-10-19 在本机实际执行命令或提交任务得到的结果；“未验证”表示尚未实测，后续使用前应保持怀疑。

## 1. 层级与术语

mglc 的平台资源从大到小分为四层，生成任务挂在最底层的会话下面：

1. 企业（enterprise）：账号所属的组织。`mglc user info` 返回 `enterpriseId` 与 `enterpriseName`。
2. 项目（project）：企业下的制作项目。`mglc project list` 返回项目 ID、名称与类型；`mglc project show <project_id>` 返回成员、项目角色与项目余额。
3. 剧集（episode）：项目下的剧集，用剧集序号区分。`mglc episode list --project-id <id>` 返回每集的 `episodeNo`、`episodeId`、名称与镜头数。
4. 生成会话（session）：某一剧集下的生成上下文，用户界面里表现为一次项目内的生成工作区。`mglc session list --project-id <id> --episode <n>` 返回该集的 `sessionId`、`sessionName` 与 `episodeId`。

`mglc episode list` 返回的是剧集，不是子项目。项目与剧集之间没有额外的“子项目”层；如果看到多条记录，应当理解为同一项目下的多集。生成会话必须挂在某一集下面，因此查询会话时必须同时给出项目 ID 和剧集序号。

## 2. 生成会话 ID 的取得

2026-10-19 在本机执行的完整查询链路如下，输出经过摘录，保留了 id 字段：

```text
mglc project list
→ projectId 2060150527854528，name「2026大秦寻仙VR」

mglc episode list --project-id 2060150527854528
→ episodeNo 1..5，其中第 1 集 episodeId 为 2040714108516707

mglc session list --project-id 2060150527854528 --episode 1
→ sessionId 2060150528006080，sessionName「未命名」，episodeId 2040714108516707
```

这三条命令都是只读命令，不消耗额度。第 1 集当时只返回一个会话，因此 `2060150528006080` 是该集唯一的生成会话 ID。如果项目下有多集、每集有多个会话，应当先确定要计费的项目与剧集，再在对应剧集的返回结果里选择会话。

## 3. 会话 ID 与额度扣减

mglc 的额度分为个人额度与项目额度。个人额度为 0 时，不带项目会话的生成请求会被平台拒绝，错误信息为：

```text
ERROR mglc code 400403: 生产栗额度不足，请联系项目管理员进行分配
```

把项目生成会话 ID 传给 `mglc video generate --session-id <sessionId>` 之后，生成请求落在该项目下，扣减的是项目余额。2026-10-19 的实测对照如下：

- 不带 `--session-id` 的命令连续两次返回 `400403`，没有产生任务。
- 带 `--session-id 2060150528006080` 的同一提示词、同一素材、同一 1080p 参数提交成功，平台任务号为 `2062561366728128`，约 3 分半完成下载，通用闸门判定为 `ok`。

`mglc project show <project_id>` 返回的 `totalBalance` 与 `usedBalance` 是项目余额与已用额度。当前项目在生成后仍可继续使用，说明会话提交确实走项目额度。这个结论只在本机当前账号与项目上验证过；换账号、换项目或平台改接口后应重新验证。

## 4. vrgen 的会话参数

vrgen 把会话 ID 作为生成参数的一部分，而不是把它写进 case 或前端代码。参数有三个来源，优先级从高到低：

1. 命令行 `vrgen submit --session-id <id>` 或 `vrstudio generate submit --session-id <id>`。
2. job 级草稿 `runs/<job>/generation.toml` 的 `session_id`，由 `vrgen params save --session-id <id>` 写入。
3. 配置文件 `config/default.toml` 的 `[mglc] session_id`，默认值为 0。

取值规则与文件位置：

- `0` 表示不使用项目会话，按个人额度提交；不写该字段也按 0 处理。
- `vrgen params save --session-id` 不传时保留草稿里已有的会话；传 `0` 会显式清空。
- submit 解析出的会话 ID 写进该轮 `run.json` 的 `params.session_id`，与提示词、分辨率、上传尺寸一起留档。
- 只有 `session_id > 0` 时，`build_generate_argv` 才向 mglc 追加 `--session-id`；为 0 时命令行不出现该参数。

当前任务的草稿位置示例：

```toml
# E:\VRAIGC\vrstudio\vrgen_runs\simple_gen_01\generation.toml
resolution = "1080p"
scale = "auto"
session_id = 2060150528006080
```

`runs/` 是数据目录，按工作区规则不进 git；会话 ID 不是密钥，但它绑定具体项目与账号，不应写死到源码、配置模板或测试里。

## 5. 为什么前端代码里没有这个 ID

vrgen 与 vrstudio 的边界只走 CLI 契约。vrstudio 的 web 生成页提交时调用 `vrstudio generate submit`，不读取也不传递会话 ID；vrgen 在自己的 `generation.toml` 草稿里取到会话 ID，再拼进 mglc 命令。因此：

- web 前端代码里没有任何硬编码的会话 ID。
- 每个 job 的会话是独立配置的。新建另一个 case 不会继承 `simple_gen_01` 的会话。
- 当前 web 页面没有项目、剧集、会话选择器；修改分辨率或输入缩放时，`params save` 保留已有会话，不会把它清掉。

## 6. 失败模式与边界

- 会话 ID 属于已删除的会话，或不属于当前账号可访问的项目：平台会拒绝提交；具体错误码尚未实测，遇到时应以平台返回为准。
- 会话 ID 有效但项目余额不足：平台返回额度类错误，与个人额度不足的表现类似，需要结合 `mglc project show` 的余额判断。
- 多个剧集、多个会话同时存在：会话名可能重复（当前会话名为「未命名」），选择器不能只显示名称，应同时显示项目名、剧集序号与会话 ID 的后几位。
- 平台会话列表变化：已保存的会话 ID 可能从列表中消失。此时应当提示用户重新选择，而不是静默改回个人额度，因为静默回退会让下一次提交在额度不足时才失败。

## 7. 相关实现与决策

- 决策 22 记录项目额度的接法与 2026-10-19 的实测结果，见 `docs/decisions.md`。
- vrgen 的参数读取与写回在 `vrgen/src/vrgen/cli.py`（submit、params show/save）与 `vrgen/src/vrgen/jobs.py`（`generation.toml`）。
- 会话参数拼进 mglc 命令行在 `vrgen/src/vrgen/round/task.py` 的 `build_generate_argv`。
- 该轮参数留档在 `vrgen/src/vrgen/round/pipeline.py` 的 `prepare_round`。
- `vrstudio/src/vrstudio/cli/generate.py`。
- 前端会话选择器的实现方案、JSON 契约与回退顺序见 `docs/session-ui-plan.md`。
