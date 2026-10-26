# 经验与教训记录

状态：持续更新。本文记录可复用的排查步骤、测试经验与踩坑结论，作为项目内的
长期 memory；具体任务进度仍以 `docs/plan/` 和 `docs/test-runs/` 为准。

## 1. 2026-10-25 · Playwright MCP 浏览器 profile 被占用

### 现象

调用 Playwright MCP 的 `browser_navigate` 时返回：

```text
Error: Browser is already in use for
C:\Users\Administrator\AppData\Local\ms-playwright-mcp\mcp-chrome-2e8d960,
use --isolated to run multiple instances of the same browser
```

同时 `browser-use` 的守护进程启动失败，日志提示：

```text
DevToolsActivePort not found ... enable chrome://inspect/#remote-debugging,
or set BU_CDP_WS for a remote browser
```

### 诊断步骤

1. 先查占用 profile 的进程，而不是直接杀浏览器：

   ```powershell
   Get-CimInstance Win32_Process |
     Where-Object { $_.CommandLine -like '*ms-playwright-mcp*' -or $_.CommandLine -like '*mcp-chrome-2e8d960*' } |
     Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine |
     Format-List
   ```

2. 同时查 profile 目录与锁文件：

   ```powershell
   $p='C:\Users\Administrator\AppData\Local\ms-playwright-mcp\mcp-chrome-2e8d960'
   Get-ChildItem $p -Force | Select-Object Name,Length,LastWriteTime
   ```

3. 查父进程链。本次结果是：
   - Chrome `22772`，启动于 2026-10-23 19:19，`--user-data-dir=...\mcp-chrome-2e8d960`，`--remote-debugging-pipe`。
   - 父进程 Node `30052`，启动于 2026-10-23 18:51，命令是 `@playwright/mcp/cli.js`。
   - 祖父进程 `cmd.exe 16880`，命令是 `playwright-mcp`。
   - 当前会话另有一个 2026-10-25 8:50 启动的新 MCP server，但同一个 profile 被旧浏览器占用。

### 根因

不是端口冲突，也不是网络问题，而是 Playwright MCP 的浏览器 profile 被一个
**两天前启动、没有退出的旧 MCP 浏览器**占着。新的 MCP server 试图复用同一个
`--user-data-dir`，发现已有实例，于是拒绝启动。

### 处理

在确认旧实例是残留、没有当前会话在用它之后，关闭整棵旧进程树：

```powershell
taskkill /PID 16880 /T /F
```

本次关闭了旧 `cmd -> node -> chrome` 树，然后重新调用 `browser_navigate`，
当前 MCP server 成功启动了新浏览器。

### 判断旧实例是否可以关闭

至少同时看：

- 启动时间是否明显早于当前会话。
- 父进程是否还是旧的 `playwright-mcp` 或 `@playwright/mcp/cli.js`。
- 浏览器标题与页面是否停在旧任务（本次是 `vrstudio`）。
- 当前会话是否已有自己的 MCP server 进程。

不要因为错误信息里出现 `Browser is already in use` 就关闭用户正常使用的 Chrome；
只处理命令行里带 `--user-data-dir=...ms-playwright-mcp...` 的实例。

### 不要做的事

- 不要先 `npm install playwright` 或改项目依赖来“修” MCP；MCP 的浏览器由
  MCP server 自己管理。
- 不要把 `browser-use` 当成默认可用的备选；它需要 Chrome 远程调试端口或
  `BU_CDP_WS`，未配置时会直接报 `DevToolsActivePort not found`。
- 不要只删 profile 里的锁文件而不处理进程；浏览器仍在运行时，锁会再次出现。
- 不要在未确认旧实例归属时杀进程；先看父进程、启动时间与当前会话。

### 验证

- `browser_navigate` 成功，页面标题与 URL 正常。
- 当前 MCP server 进程启动时间是当前会话。
- profile 对应浏览器由一个当前会话的 MCP server 持有。

### 预防

- MCP 测试使用固定但独立的 profile；不要和用户日常浏览器混用。
- 测试结束尽量关闭 MCP 浏览器，避免跨天残留。
- 如果环境支持 `--isolated`，优先为一次性测试使用隔离实例。
- 记录 profile 路径、进程 ID、父进程与启动时间，方便下次判断。

## 2. 2026-10-25 · 整页导航与 SPA 路由切换不是一回事

### 现象

在测试“上传中切页是否取消上传”时，用 Playwright 的 `page.goto()` 切到
`/next/cases`，网络里只有 `POST /api/uploads` 和 `PUT /api/uploads/...`，
没有 `DELETE`，服务端残留不完整上传。

### 结论

- `page.goto()` 是整页导航，浏览器会销毁当前 JavaScript 上下文，Vue 的
  `onUnmounted` 不会执行；普通 `fetch` 的 DELETE 也会被中止。
- 点击 Vue Router 的侧栏链接是 SPA 路由切换，组件会正常 unmount，`onUnmounted`
  会执行。
- 上传弹窗是模态的，打开时侧栏链接被遮罩拦截；用户实际能触发的整页卸载路径
  更接近关闭标签页、刷新页面或浏览器前进/后退，而不是点侧栏。
- 因此，测试“切页取消上传”必须明确是 SPA 切换、整页导航还是关闭标签页，
  不能用一个 `page.goto()` 代表全部情况。

### 测试建议

- SPA 切换：点击 `router-link`，检查组件卸载后的 DELETE 是否到达。
- 整页卸载：关闭标签页/刷新，检查是否需要 `keepalive` 或 `sendBeacon`。
- 网络延迟：用 Playwright `page.route()` 延迟 PUT，确保上传在切页时仍在进行。
- 断言不能只看前端调用；要看服务端 `.uploads/<id>/` 是否消失，或网络里是否
  真的出现 DELETE。

## 3. 2026-10-25 · 测试前先确认“只读数据”与“可写数据”

浏览器验收经常需要修改提示词、设置或上传文件。执行前先分清：

- 哪些 case 是只读的，不能改提示词、提交集、素材。
- 哪些设置是全局的（显示名），测试后必须恢复。
- 哪些上传会产生服务端临时目录，测试后是否保留、何时清理。
- 哪些操作会扣费，必须单独批准。

本次没有修改 QA case 的提示词，因此长文本实际保存路径没有在浏览器里验证；
后续如果要测，应该使用可丢弃的临时 case，或先记录原值并在测试后恢复。

## 4. 2026-10-26 · 本机 vrstudio.toml 会让全量 pytest 变红

### 现象

`uv run pytest` 有 9 例失败，全部在 `tests/test_web_proxy.py`：断言默认 `web.proxy_max_w == 4096`，实际读到 2048；代理 sidecar 的 ready/disabled 判定与预期相反。

### 诊断步骤

1. 确认失败集中在一个模块，且断言的是配置默认值。
2. 查仓库根的 `vrstudio.toml`（gitignore）：本机按决策 17 设了 `proxy_max_w = 2048`。
3. 把该文件临时移开，只跑 `tests/test_web_proxy.py`，13 例全绿；再跑全量 386 例全绿；随后原样移回。

### 根因

`config_mod.load()` 不传 `cwd` 时按“用户目录 → 当前目录”的优先级读取 `vrstudio.toml`；代理测试直接断言内置默认值，没有隔离开发者机器的本地覆盖。与本次功能改动无关。

### 处理

临时移开本地配置验证后恢复；没有改代理逻辑，也没有改测试。

### 验证

默认配置下 `uv run pytest` 386 passed；`vrstudio.toml` 恢复后本机仍按 2048 运行服务。

### 预防

- 全量门禁变红且集中在 `test_web_proxy` 时，先看本机 `vrstudio.toml`，不要先动代理实现。
- 长期做法：这类断言默认值的测试显式传 `config_mod.load(cwd=tmp_path)` 或 monkeypatch `load`，不读开发者本地文件。本次未改，留作独立修复。

## 5. 记录模板

以后新增经验时按以下结构追加，不覆盖旧记录：

```text
## 日期 · 标题

### 现象
### 诊断步骤
### 根因
### 处理
### 验证
### 预防
### 相关文件/命令
```
