# 用 DSH 驱动浏览器验证前端交互

记录时间：2026-11-19。适用场景：让 DSH 会话打开本机前端页面，按人的操作路径点击、拖拽、填表、上传，并留下截图、控制台与网络证据；整个过程在一个可见的 Chrome 窗口里进行，人可以旁观。

## 1. 这套流程由哪些部件组成

DSH 本身不含浏览器工具，浏览器能力由三段拼起来：

- `@deepseek-ai/dsh-mcp-client`：DSH 自带的 MCP 客户端，负责按配置启动服务器进程并把工具注册进模型。本机版本 0.1.5-rc.3。
- `@playwright/mcp@0.0.86`：微软的 MCP 服务器，由 `npx` 拉起，提供 25 个 `browser_*` 工具。
- 一条写进 profile 的 `cordis.patch.yml` 配置：把上面两者接起来，模型侧看到的工具名是 `mcp__playwright__browser_navigate` 这种形状。

`dsh-mcp-bridge` 不是必需件。它只是社区做的一份「预置配置 + 校验脚本」合集，真正干活的是 dsh-mcp-client 和 @playwright/mcp 这两个包；直接写配置就够，少一个第三方依赖。

## 2. 开工前的四项检查

1. 页面能通：`Invoke-WebRequest http://<主机>:<端口>/next/` 返回 200。本机 `172.28.55.7` 是 WLAN 地址，等价于 `127.0.0.1`。
2. 认对 profile：桌面端跑的是 `desktop`，命令行另起的实例可能是 `web`；两者配置互不生效。查法：`Get-CimInstance Win32_Process` 找 `DeepSeek Harness.exe` 的命令行，末尾就是 profile 目录。
3. 工具在不在：会话里能否调用 `mcp__playwright__browser_navigate`。没有就先看第 3 节配置与第 5 节第 6 条。
4. case 锁：`POST /api/case/<name>/lock` 返回 409 说明别人持有锁。`/api/case/<name>` 能读不代表能安全写，写操作会覆盖对方。

## 3. 给 desktop profile 配 Playwright MCP

配置文件：`C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml`。改动前先备份，文件名带日期，便于回滚。

在文件末尾追加一条 `insert`。注意顶格写 `- insert:`，其下四空格缩进，`config` 下的 `args` 用列表逐项写，避免引号与逗号解析出错：

```yaml
- insert:
    - id: mcp-playwright
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: playwright
        transport: stdio
        command: npx
        args:
          - '-y'
          - '@playwright/mcp@0.0.86'
          - '--browser'
          - 'chrome'
          - '--isolated'
          - '--viewport-size'
          - '1600,1000'
        toolCallTimeoutMs: 120000
```

各参数的作用：

- `--browser chrome`：用系统 Chrome，不另下 Chromium；本机是 156.0.8078.80。
- 不写 `--headless`：默认就是有头窗口，人能看到操作过程。
- `--viewport-size 1600,1000`：固定视口，截图与断言的尺寸才稳定。
- `--isolated`：每次启动用内存 profile，状态干净、可重复；代价是每次都要过一遍首访弹窗、没有登录态。要保留状态就换 `--user-data-dir <固定目录>`。
- `toolCallTimeoutMs`：长流程（等视频解码、等接口）留足时间，默认 60 秒偏短。

改完不必重启桌面端。patch 是热加载的：保存后几秒内，桌面端进程下会长出 `cmd → node(npx) → node(@playwright/mcp)` 三段子进程，命令行里能对上你写的参数。查法：

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match '@playwright/mcp' } |
  Select-Object ProcessId, ParentProcessId, CommandLine
```

## 4. 一次验收的走法

1. 先 `browser_navigate` 打开目标页，再 `browser_snapshot`。快照是无障碍树，每个可交互节点带 `ref=eN`，比截图更适合定位；本页一次快照约 8,800 字符。
2. 处理首访弹窗。页面第一次进入会弹「设置显示名」，不关掉它后面所有点击都会被遮罩吃掉。用 `browser_click` 点「稍后」，或 `browser_type` 填名字再保存。
3. 按业务顺序操作：`browser_click` 切单选组，`browser_fill_form` 填数字输入，`browser_select_option` 选下拉，`browser_click` 触发保存/另存。
4. 画布上的操作单独处理。全景图上拖矩形不能用 `browser_drag`（它只接受两个元素引用），要用 `browser_run_code_unsafe` 写 `page.mouse.move/down/up`，或 `browser_evaluate` 在页面里派发 `pointerdown/move/up`。
5. 留证据四件套：
   - `browser_take_screenshot` 存到 `.playwright-mcp/<日期>/`（该目录已被 gitignore）。
   - `browser_console_messages` 读异常与警告。
   - `browser_network_requests` 看请求状态码与顺序，必要时用 `browser_network_request` 取单个请求的响应体。
   - `browser_evaluate` 直接读页面状态与接口 JSON，例如 `fetch('/api/case/1106-04')` 后比对 `pick.draft` 与页面显示。
6. 收尾：恢复被改的设置（显示名、临时上传），确认没有留下临时素材；有后台任务要 `job_kill`。

判定标准沿用 `docs/plan/frontend-agent-test-plan.md`：页面文字、接口返回、截图三者对得上才算通过，不能只看页面。

## 5. 踩坑记录

1. **profile 搞错，配置白写。** `web` profile 里已有的 `mcp-playwright` 不会作用到桌面端；桌面端读的是 `profiles\desktop`。先确认进程命令行里的 profile 目录，再改文件。
2. **把 dsh-mcp-bridge 当成 Playwright MCP 的上级。** 两者是并列的：桥只提供预置配置，Playwright MCP 是独立 npm 包；不装桥也能配通。
3. **DSH 版本门槛。** `dsh-chrome-use@0.15.0` 要求 DSH ≥ 0.2.1-rc.2，本机 0.1.5-rc.3 装不上；`dsh-inner-browser-use` 要求 ≥ 0.2.0。选插件前先看 `dsh.engines`。
4. **通用 YAML 校验器对 `!!js` 报警。** profile 文件里有 `disabled: !!js process.platform === 'win32'` 这类自定义标签，用 `yaml` 包解析会出 `Unresolved tag` warning，这是预期现象；改用 `node --no-warnings` 看退出码与顶层条目数即可。
5. **以为必须重启。** 实际 patch 热加载，子进程会自动起来。但本轮会话的工具清单在开轮时已固定，工具是否在下一轮出现还没验证过；如果一直没出现，只能等桌面端下次自然启动。
6. **无头与有头混淆。** 想看见窗口就不要传 `--headless`；`--help` 里写的是默认 headed。传了 `--headless` 照样能截图，但你只能看截图不能看过程。
7. **`--isolated` 的副作用。** 每次都是干净 profile，弹窗每次重现、登录态不保留；需要保留就换 `--user-data-dir`，并且不要和 `%LOCALAPPDATA%\ms-playwright-mcp` 下的历史 profile 混用，否则会撞「Browser is already in use」。
8. **拿 `browser_drag` 拖画布。** 它只做元素到元素的拖放；画布内任意矩形要合成指针事件，见第 4 节第 4 条。
9. **忽略 case 锁。** 本次目标 case 的锁被另一使用者持有，`POST /api/case/1106-04/lock` 返回 409，页面顶部提示「保存仍会写入，请先沟通」。写操作前先确认锁归属，或换一个空闲 case。
10. **误杀用户的 Chrome。** 自动化开的 Chrome 与用户自己开的窗口可能同名（本次两个窗口都叫 `vrstudio - Google Chrome`）。判断依据是命令行里的 `--remote-debugging-pipe`、`--user-data-dir` 与父进程，不是窗口标题；只清理带 Playwright 参数的进程。
11. **首次 `npx` 要联网。** `npx -y @playwright/mcp@0.0.86` 第一次会下载包，网络不通就起不来；本机已缓存到 `%LOCALAPPDATA%\npm-cache\_npx`，后续启动很快。研究阶段访问 `registry.npmjs.org` 可能超时，`registry.npmmirror.com` 可用。
12. **残留进程与截图没归档。** 脚本被中断时会留下 Chrome 与 npx 子进程；测试结束用 `Get-CimInstance Win32_Process` 对命令行确认后清理，截图统一放 `.playwright-mcp/<日期>/`，不要把临时文件留在仓库根目录。
13. **只看截图就下结论。** 无头渲染能出图不代表交互正常；本次靠 `browser_network_requests` 才看到 409 的锁冲突，光看截图是发现不了的。

## 6. 证据怎么留

- 截图：`.playwright-mcp/<日期>/`，文件名带用例编号，例如 `smoke-initial.png`。
- 接口：把关键 JSON 片段贴进 `docs/test-runs/<日期>-<主题>.md`，不要只写「接口正常」。
- 控制台：记录条数与首条错误的原文，例如本次是 3 条（1 错误 2 警告），错误为 `POST /api/case/1106-04/lock` 的 409。
- 视口：记录宽高与 `document.documentElement.scrollWidth` 对比，判断有没有横向溢出。

## 7. 回滚配置

把备份覆盖回 `cordis.patch.yml`，删掉追加的 `insert` 段，等热加载生效。备份文件名形如 `cordis.patch.yml.bak-20261119-mcp`。回滚后同样用子进程列表确认 `@playwright/mcp` 已经退出。

## 8. 已知边界

- 只验证了 0.1.5-rc.3 桌面端 + Chrome 156 + Playwright MCP 0.0.86 这一组组合；升级 DSH 或 MCP 版本后要重新核对参数与工具名。
- 本轮没有启用 `--caps vision/pdf/devtools`，视觉坐标点击、PDF 导出、DevTools 性能面板都还不可用。
- 长流程（视频解码、大文件上传）的超时与稳定性没有压测过，只通过 `toolCallTimeoutMs` 放宽了上限。

## 9. 参考

- 调研与选型对比：`docs/plan/agent-browser-testing-tools-research.md`。
- 验收标准与证据格式：`docs/plan/frontend-agent-test-plan.md`。
- 历史 Playwright MCP 踩坑：`docs/lessons-learned.md` 第 1 节。
- 本轮脚本与截图：`.playwright-mcp/research-20261119/`（`cdp-smoke.mjs`、`mcp-drive.mjs`、`mcp-headed-check.mjs`、`smoke-initial.png`）。
