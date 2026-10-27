# Windows 下进程与端口占用的排查与治理

日期：2026-10-27。背景：`vrstudio serve` 反复遇到端口占用（10048）、
`uv sync` 因 exe 被锁而失败两类问题，一轮排查与修复的经验记录。

## 现象与根因

1. **`serve` 报 10048（端口只允许使用一次）**：端口被旧实例占用。
   来源通常是两类——AI/开发者自己忘关的上一轮 serve，或 uvicorn 热重载
   之外的孤儿进程（父终端已关、子进程仍在）。
2. **`uv run` / `uv sync` 报 `拒绝访问 (os error 5)`，目标是
   `.venv\Scripts\vrstudio.exe`**：`pyproject.toml` 变更会让 `uv run`
   触发环境重建，重建要改写入口脚本 exe；Windows 锁住**正在运行**的 exe，
   任何从该 venv 启动且未退出的进程都会导致重建失败。
3. **exe 判定"是不是本项目进程"不能用 exe 路径**：`uv run` 的 venv 是
   跳板机制，进程的 exe 指向 uv 的基础解释器
   （`AppData\Roaming\uv\python\cpython-…\python.exe`），不在 `.venv` 下；
   但**命令行**里带着 `.venv\Scripts\vrstudio.exe` 的完整路径。

## 排查命令（Windows）

```powershell
# 谁在监听端口 → pid
netstat -ano | findstr ":8760" | findstr LISTENING
Get-NetTCPConnection -LocalPort 8760 -State Listen | Select-Object OwningProcess

# pid → 进程与命令行（exe 会骗人，cmdline 才见真身）
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'vrstudio' } |
  Select-Object ProcessId, CommandLine | Format-List

# 谁在用这个 venv（找锁源）
Get-Process | Where-Object { $_.Path -like 'E:\VRAIGC\vrstudio\.venv\*' } |
  Select-Object Id, ProcessName, Path, StartTime

# 端到端确认：端口空闲 + 进程存活
(Test-NetConnection 127.0.0.1 -Port 8760 -WarningAction SilentlyContinue).TcpTestSucceeded
```

## 已落地的治理（portguard）

`src/vrstudio/web/portguard.py`，`serve` 启动横幅打印后、`uvicorn.run` 前调用
`reclaim_port(port)`：

- 占用进程的 **exe 或命令行任一**落在当前 venv（`sys.prefix`）之下 → 判定
  为本项目残留实例，控制台打印 `端口 x 已被本项目的旧实例占用：PID …，
  自动结束它以便本次启动接管`（`flush=True`，先于 uvicorn 报错显示），
  同时写 `serve.port_reclaim` 到 JSONL 日志，然后 terminate、5s 不退再 kill。
- 与项目无关的占用者只跳过不碰，让 bind 自然失败。
- 不碰自己（`os.getpid()`）。
- 依赖：`psutil>=5.9`（web extra）。psutil 拿进程 exe/cmdline 是唯一可靠
  途径；`netstat` 文本解析在中文系统上不可靠，不要用。

## 经验与教训

1. **Windows 锁运行中的 exe**：升级/重建 venv 前先确认
   `Get-Process | Where Path -like '*.venv*'` 为空；AI 在后台任务里起的
   serve 会一直锁着 venv，任务结束前要记得停。
2. **AI 接管过的端口要还**：AI 为验证重启过用户的服务后，要么把服务交还
   （停掉自己的实例），要么明确告知端口由谁持有——否则用户在自己的终端
   启动就会撞 10048，还以为出了别的故障。
3. **stdout 重定向后 print 变块缓冲**：排查启动顺序问题时，日志文件里的
   行序不可信（logging 走 stderr 无缓冲、print 有缓冲）；要保证"先打印后
   动作"的可见顺序，print 必须带 `flush=True`。
4. **PowerShell 管道改文件会毁编码**：`Get-Content -Raw` + `-replace` +
   `Set-Content -Encoding UTF8` 在中文 Windows 上按 GBK 读 UTF-8 文件，
   中文注释全变乱码且可能产生非法字符——改测试/源码文件一律用编辑工具
   或 `Edit`，不走 shell 文本管道。
5. **多实例共存的习惯**：本机常用 8760（主）、8763（cases_qa）等端口并行
   起服务；闲置实例要么关掉，要么在 portguard 的接管日志里留意它们的存在。

## 涉及文件

- `vrstudio/src/vrstudio/web/portguard.py`（接管逻辑）
- `vrstudio/src/vrstudio/cli/serve.py`（接入点）
- `vrstudio/pyproject.toml`（web extra 加 psutil）
- `vrstudio/tests/test_portguard.py`（判定与只杀同源的用例）
