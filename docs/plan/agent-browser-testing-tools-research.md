# Agent 浏览器交互测试工具调研

记录时间：2026-11-19。状态：调研完成，接入方案待选。本文回答一个问题：用哪个工具或插件，能让当前的 DSH 会话对 `http://172.28.55.7:8760/next/case/1106-04/pick` 这类本地网页做完整的交互测试（点击、拖拽、填表、上传、截图、读控制台与网络）。

## 1. 结论

- 当前会话没有浏览器工具。桌面端运行的 profile 是 `desktop`，它的 `package.json` 只装了视频预览、QQ 机器人、插件市场等包，既没有浏览器插件，也没有 MCP 服务器；`web` profile 里配好的 Playwright MCP 不会作用到这个会话。
- 首推方案是 **Playwright MCP 经 `dsh-mcp-bridge` 接进 `desktop` profile**。理由是它今天就能用、跨平台、工具面完整，而且本机已经验证过同一条链路：`web` profile 的 `cordis.patch.yml` 里就有一条 `mcp-playwright` 配置，本轮我又用 `@playwright/mcp@0.0.86` 直接驱动目标页面跑通了导航、无障碍快照、控制台日志与网络请求。
- 次选是 DSH 原生插件：**`dsh-browser-cdp@1.14.0`**（2026-11-18，35 个工具，工具懒注入）和 **`dsh-ego-browser@0.14.1`**（2026-11-16，35 个工具，Windows 修复记录多）。两者都在 DSH 0.1.5 上可尝试，但前者把 0.1.5-rc.3 标为 experimental，且自述 Windows 复杂流程稳定性弱于 macOS。
- 更新最勤的 **`dsh-chrome-use@0.15.0`**（2026-11-19 发布）当前装不上：它要求 DSH ≥ 0.2.1-rc.2，本机 DSH 是 0.1.5-rc.3。要用它得先升级 DSH 桌面端。
- 零安装的兜底方案是直接用 Chrome DevTools Protocol 脚本。本仓库已有先例（`vrstudio/.tmp_prototype/keyframe-refs/e2e.mjs` 跑过 21 条断言），本轮我也用它读到了页面的完整状态。

## 2. 环境与版本事实

- DSH 版本：profile 共享的 `@deepseek-ai/dsh-base`、`dsh-agent`、`dsh-tools`、`dsh-mcp-client` 都是 **0.1.5-rc.3**，桌面端与命令行 `@deepseek-ai/dsh@0.1.5-rc.3` 同线。
- Node：22.20.0，满足浏览器插件普遍要求的 ≥ 22。
- Chrome：**156.0.8078.80**，位于 `C:\Program Files\Google\Chrome\Application\chrome.exe`。
- 网络：`172.28.55.7` 是本机 WLAN 地址，`http://172.28.55.7:8760/next/` 与 `http://127.0.0.1:8760/next/` 都返回 200。
- 现有浏览器痕迹：`~/.dsh/profiles/web/cordis.patch.yml` 里配置过 `mcp-playwright`（`npx -y @playwright/mcp`），`~/.dsh/profiles/web/node_modules` 里有 `dsh-mcp-bridge@0.1.3`；`C:\Users\Administrator\AppData\Local\ms-playwright-mcp\` 下有 7 个历史 profile，最新一个更新于 2026-11-08。
- 目标 case 的当前状态：`/api/case/1106-04` 返回 200，但页面发起 `POST /api/case/1106-04/lock` 得到 **409**，页面顶部提示「case 正被 访客 使用；保存仍会写入，请先沟通」。做写操作测试前要先确认锁的归属。

## 3. 候选一：DSH 原生浏览器插件

DSH 插件市场的 11,979 条记录里有 233 条归在 `browser` 分类。下表只列与「网页交互测试」直接相关、且在 2026-11-13 之后还有提交或发版的条目；更新日期取自插件的 GitHub 提交与 release，下载量取自市场统计的 2026-10-20 至 2026-11-18 区间。

- **`dsh-browser-cdp@1.14.0`**：2026-11-18 发版，npm 上共 92 个版本（10 月以来 85 个），月下载 52,680，GitHub 39 星，仓库 2026-09-22 建立。
  - 工具面：35 个 `bcdp_*`，含 `bcdp_snapshot`（语义树，带稳定 `loc=` 定位）、`bcdp_click`、`bcdp_fill`、`bcdp_drag`、`bcdp_upload`、`bcdp_screenshot`、`bcdp_js`、`bcdp_cdp`（原始 CDP）、`bcdp_wait_for_response`、`bcdp_dialog`、`bcdp_tab`。
  - 接入方式：自己管一个 Chromium 用 CDP 启动，不需要装浏览器扩展；观察窗可以在页面上直接点选元素并把引用塞进输入框。
  - 兼容：`dsh >=0.1.0-rc.2 <0.3.0-0`，兼容表把 `0.1.5-rc.3` 标成 **experimental**。
  - 已知限制（README 原文）：Windows 只做了 v0.4.0 适配，「复杂多步流程稳定性可能弱于 macOS」；Linux 的非 macOS 快照是 CDP `DOMSnapshot` 重建，复杂 iframe 与画布场景可能降级。
  - 优点：常驻只注册 1 个工具，其余按需解锁，对不碰浏览器的会话几乎不占上下文。
- **`dsh-ego-browser@0.14.1`**：2026-11-16 更新，24 个版本，月下载 42,728，GitHub **549 星**，10 个未关 issue。
  - 工具面：35 个 `ego_*`，与上一款同源（内置 ego-compatible 运行时），同样有快照、点击、表单、JS/CDP、截图、下载、标签页，以及 `ego_doctor`、`ego_login_import`、`ego_http`。
  - 兼容：`dsh >=0.1.2-rc.1`，**不限制上界**，是本批里对 0.1.5 最友好的一款。
  - Windows：更新日志里有多条 Windows 专项修复（有头模式不再抬窗 #99、焦点修复 #96、冷启动回归）。
- **`dsh-chrome-use@0.15.0`**：2026-11-19 发版，30 个版本，月下载 6,066，GitHub 11 星。
  - 工具面：38 个 `chrome_*`，覆盖点击、填写、拖拽、滚动、截图、上传文件、导出 PDF、读控制台与网络日志、按任务分组标签页。
  - 接入方式：要另外装一个 Chrome 扩展，用 8 位配对码连接，操作的是你日常用的那个已登录 Chrome。
  - 兼容：`dsh >=0.2.1-rc.2`，**当前 0.1.5-rc.3 装不上**。
- **`dsh-agent-team-ui-testing@0.1.4`**：npm 2026-11-12 发版，仓库 2026-11-18 有提交，5 个版本，月下载 1,289，3 星。
  - 工具面：36 个 `browser_*`，主打结构化 GUI 操作、视觉比对、动态帧分析与网络调试，是这批里唯一明确以「前端 GUI 测试」为定位的。
  - 风险：版本号 0.1.4、星数 3、单作者，打包体积大（`index.js` 1.1 MB），成熟度明显低于前三款。
- **`@wxg-prc-cpg/browser-skill-dsh-plugin@0.5.0`**（腾讯 BrowserSkill 的 DSH 桥）：2026-11-18 更新，GitHub **10,569 星**，月下载 59,540。
  - 工具面：原生浏览器工具驱动可见的 Chrome / Edge Agent Window，支持可访问性与 VOM 观察、截图、隔离多会话。
  - 定位偏「通用浏览器自动化」，没有专门面向测试断言的网络/控制台工具描述。
- 其他同向但优先级更低的：`dsh-inner-browser-use@0.47.101`（要求 DSH ≥0.2.0，当前装不上）、`dsh-browser-control@1.7.14`（11-15，72 星，需设置里开启）、`@dougen/dsh-cdp@0.5.1`（11-17，不注册工具、靠 shell 发本机 HTTP 命令）、`dsh-browser-playwright-codex@0.9.0`（11-14，23 个 Playwright 工具）、`dsh-frontend-replay@0.2.0`（11-17，录制回放并导出 Playwright 测试）。

桌面级 computer use（控制整个桌面而不只是浏览器）在这批里更薄：`dsh-computer-browser@0.3.0`（11-15，1 星，后台 CDP 加前台真实键鼠）、`opencu`（Linux/Hyprland 向）。本需求只针对一个网页，浏览器级工具已经够用，桌面级反而引入窗口焦点和坐标漂移。

## 4. 候选二：MCP 服务器

DSH 通过内置的 `@deepseek-ai/dsh-mcp-client` 接 MCP 服务器，`dsh-mcp-bridge` 是把常用服务器打包成开箱配置的插件（npm 最新 0.3.0，2026-10-20；本机 `web` profile 装的是 0.1.3）。工具在模型侧呈现为 `mcp__<serverName>__<toolName>`。

- **`@playwright/mcp`**：npm 0.0.86，2026-11-18 发布，累计 439 个版本；GitHub `microsoft/playwright-mcp` **39,874 星**，2026-11-18 还有提交。
  - 我本轮实测到的工具面是 25 个：`browser_navigate`、`browser_snapshot`（无障碍树，带 `ref=eN`）、`browser_click`、`browser_type`、`browser_fill_form`、`browser_select_option`、`browser_drag`、`browser_drop`、`browser_file_upload`、`browser_press_key`、`browser_hover`、`browser_tabs`、`browser_network_requests`、`browser_network_request`、`browser_console_messages`、`browser_evaluate`、`browser_take_screenshot`、`browser_handle_dialog`、`browser_wait_for`、`browser_resize`、`browser_find`、`browser_emulate_media`、`browser_navigate_back`、`browser_close`、`browser_run_code_unsafe`。
  - 服务端版本串是 `Playwright 1.66.0-alpha-2026-11-18`。
  - 支持 `--browser chrome` 直接用系统 Chrome，不必另下 Chromium；`--isolated` 每次开干净 profile；`--cdp-endpoint` 可接管已有浏览器。
- **`chrome-devtools-mcp`**：npm 1.13.0，2026-11-11 发布；GitHub `ChromeDevTools/chrome-devtools-mcp` **58,257 星**，2026-11-19 有提交，139 个未关 issue。强项是性能追踪、网络与 DOM 调试，交互工具不如 Playwright MCP 完整，更适合「查为什么慢」而不是「点完整个流程」。
- **`browser-use`**：GitHub 121,459 星，Python 实现，本身是一个会用浏览器的 agent，不是给宿主 agent 用的工具集；嵌进 DSH 等于再套一层 agent，重复且不可控。
- **`@midscene/web`**：1.18.1，2026-11-17 发布，GitHub 15,643 星。视觉模型驱动的 UI 自动化，适合「看得懂就能点」，但需要额外的视觉模型额度，断言不如 DOM 断言确定。
- **`@browserbasehq/stagehand`**：4.4.0，2026-11-04 发布，GitHub 26,095 星，441 个未关 issue。混合自然语言与 Playwright，偏应用内集成而非 MCP 工具面。
- **`@browserbasehq/mcp`**：3.0.0 发布于 2026-03-31，已停更，且是云端浏览器服务，不适合本机页面。

## 5. 候选三：零安装的 CDP 脚本

`vrstudio/.tmp_prototype/keyframe-refs/e2e.mjs` 已经证明这条路可行：Node 自带 `WebSocket`，脚本用 `--remote-debugging-port` 拉起 Chrome，直接发 `Page.navigate`、`Runtime.evaluate`、`Page.captureScreenshot`，跑过 21 条断言。它的代价是每换一个场景就要写一段脚本，断言逻辑不可复用；收益是不依赖任何插件、不占模型上下文、结果完全确定。

本轮我按同样思路写了 `cdp-smoke.mjs`（放在 `.playwright-mcp/research-20261119/`），结论见下一节。

## 6. 本轮已做的验证

### 6.1 目标页面能被无头 Chrome 完整渲染

- 打开 `http://172.28.55.7:8760/next/case/1106-04/pick`，标题是 `vrstudio`，正文 841 字，`document.readyState=complete`。
- 页面里有 1 个 `<video>`，源是 `/video/source/1106-04`，分辨率 **8192×4096**；有 8 个输入控件；WebGL 可用（全景查看器要靠它）。
- 1600×1000 视口下 `scrollWidth=1600`、`innerWidth=1600`，没有横向溢出。
- 9 个网络请求、0 个失败；控制台只有 2 条消息。
- 截图：`.playwright-mcp/research-20261119/smoke-initial.png`。截图里能看到左侧导航、场景条、全景图与绿色视口框、右侧「预设比例 / 自由框选」、视口 5064×1624、fov 滑杆 75.8°、抽取范围 0–85，以及首次进入弹出的「设置显示名」对话框。

### 6.2 Playwright MCP 能驱动同一个页面

- `npx -y @playwright/mcp@0.0.86 --headless --isolated --browser chrome` 启动成功，`tools/list` 返回 25 个工具。
- `browser_navigate` 打开目标页后，`browser_snapshot` 返回 8,798 字符的无障碍树，节点带 `ref`，例如 `button "归属到我的名下" [ref=e121]`、`radiogroup "radio-group" [ref=e60]`。
- `browser_console_messages` 读到 3 条：1 条错误是 `POST /api/case/1106-04/lock` 的 409，2 条是 Element Plus 的 `el-radio` 弃用警告。
- `browser_network_requests` 列出了 `/api/me` 200、`/api/case/1106-04` 200、`/api/case/1106-04/lock` 409。

这两条验证说明：页面本身、浏览器、Node 与网络链路都没有障碍，缺的只是把工具接进 `desktop` profile。

## 7. 目标页面的交互测试需要覆盖什么

按 `docs/plan/frontend-agent-test-plan.md` 的证据标准（页面状态 + 接口证据 + 截图），这个选区页要测的动作与可用工具对应如下：

- 进入页面与首访弹窗：`browser_navigate` 后 `browser_snapshot`，用 `browser_click` 关掉「设置显示名」对话框，或用 `browser_type` 填显示名后保存。
- 切换「预设比例 / 自由框选」：`browser_click` 点单选组，`browser_snapshot` 确认选中态。
- 在全景图上拖矩形：`browser_drag` 只做元素到元素的拖放，画布内的任意矩形要二选一——用 `browser_run_code_unsafe` 写 `page.mouse.move/down/up`，或用 `browser_evaluate` 在页面里发 `pointerdown/move/up` 合成事件。
- 调 fov 滑杆与上下左右微调：`browser_evaluate` 设定 `input[type=range]` 的值并派发 `input` 事件，或 `browser_fill_form`。
- 改抽取范围（0–85）：`browser_fill_form` 填两个数字输入，再读 `/api/case/1106-04` 的 `pick.draft` 对齐。
- 另存 / 保存 / 导出范围 / 导入范围：`browser_click` 触发，`browser_handle_dialog` 处理确认框，`browser_file_upload` 给导入选文件，下载走 `/api` 断言。
- 断言：`browser_network_requests` 看请求体与状态码，`browser_console_messages` 看异常，`browser_take_screenshot` 留证，`browser_evaluate` 读 `scrollWidth` 与接口 JSON。

## 8. 接入方案与命令

### 8.1 方案 A：Playwright MCP 接进 desktop profile（首推）

1. 在 `desktop` profile 装桥：`dsh plugin --profile desktop add dsh-mcp-bridge`。
2. 在 `C:\Users\Administrator\.dsh\profiles\desktop\cordis.patch.yml` 末尾追加一条 insert：

   ```yaml
   - insert:
       - id: mcp-playwright
         name: '@deepseek-ai/dsh-mcp-client'
         config:
           serverName: playwright
           transport: stdio
           command: npx
           args: ['-y', '@playwright/mcp@0.0.86', '--browser', 'chrome', '--isolated']
           toolCallTimeoutMs: 120000
   ```

3. 重启桌面端，或等 HMR 热替换生效；新会话里应当出现 `mcp__playwright__browser_*` 工具。
4. `--isolated` 每次测试开干净浏览器；要保留登录态就换成固定 `--user-data-dir`，别和 `ms-playwright-mcp` 的历史 profile 混用。

### 8.2 方案 B：DSH 原生插件

- `dsh plugin --profile desktop add dsh-browser-cdp`，装完在设置页确认工具注入模式为 lazy，首次调用 `bcdp_status` 解锁其余工具。
- 或 `dsh plugin --profile desktop add dsh-ego-browser`，首次调用 `ego_doctor` 体检，再 `ego_navigate`。

### 8.3 方案 C：不装任何东西

把 `.playwright-mcp/research-20261119/cdp-smoke.mjs` 当作模板，按测试场景改 `Runtime.evaluate` 里的表达式；输出截图到 `.playwright-mcp/<日期>/`。适合回归脚本与 CI，不适合临场探索。

## 9. 风险与边界

- 写操作会碰到 case 锁：当前 `POST /api/case/1106-04/lock` 返回 409，说明有另一个使用者持有锁；直接保存会覆盖对方，测试前要先确认锁的归属或换一个空闲 case。
- 桌面端 profile 是全局的：装插件或加 MCP 会影响这台机器上的所有会话，装之前要确认。
- 工具数量与上下文：Playwright MCP 25 个工具、`dsh-browser-cdp` 常驻 1 个、ego 35 个；工具越多，每轮请求的 schema 占用越大。
- Windows 稳定性：`dsh-browser-cdp` 自述 Windows 复杂流程弱于 macOS；ego 有较多 Windows 修复；Playwright 跨平台一致性最好。
- 首访弹窗与语言：页面首次进入会弹「设置显示名」，自动化脚本要显式处理，否则后续点击会被遮罩挡住。
- 360 画布：WebGL 在无头 Chrome 下可用，但拖拽矩形必须合成 pointer 事件，不能用 `elementFromPoint` 之外的可视化点击代替。

## 10. 来源

- DSH 插件市场快照：`https://awesome-dsh-plugin.com/plugins.json`（2026-11-18 更新）与 `https://awesome-dsh-plugin.com/updates.json`。
- npm 元数据：`https://registry.npmmirror.com/<包名>`，取 `dist-tags.latest` 与 `time`。
- GitHub 仓库数据：`https://api.github.com/repos/<owner>/<repo>`，取 stars、pushed_at、open_issues。
- `https://github.com/drscrewdriver/dsh-browser-cdp`（README 的兼容矩阵与已知限制）。
- `https://github.com/Fisfzy/dsh-ego-browser`（README 的平台支持与更新日志）。
- `https://github.com/tao1020/dsh-chrome-use`（README 的安装与 DSH 版本要求）。
- `https://github.com/microsoft/playwright-mcp`、`https://github.com/ChromeDevTools/chrome-devtools-mcp`。
- 本仓库先例：`vrstudio/.tmp_prototype/keyframe-refs/e2e.mjs`、`docs/plan/frontend-agent-test-plan.md`、`docs/lessons-learned.md` §1。
