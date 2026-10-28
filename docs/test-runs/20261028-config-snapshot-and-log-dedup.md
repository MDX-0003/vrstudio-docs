# 配置启动定格与异常日志去重（2026-10-28）

关联决策：`docs/decisions.md` 第 43 条。事故现场见 `docs/test-runs/20261027-legacy-console-retirement.md` 的「环境处理」。

## 起因

2026-10-27 18:14:04，正在运行的 serve 在 `/`、`/case/walk_01`、`/api/case/walk_01` 上连续报错，最后一次的末尾是 `KeyError: 'default_frontend'`，栈里指向 `config.py` 的 `_validate`。

同一条 traceback 里还有几句不可能在执行的行：`def _media_meta(path: Path, kind: str) -> dict:`、`return None`、`return JSONResponse({"error": "no such case"}, status_code=404)`。这些行本身不会抛异常。

## 诊断

1. 那条 traceback 的行号来自旧代码对象，行文本来自磁盘上的当前文件，两者错位。旧 `_open_roots` 在第 398 行，当前第 398 行是 `_file_target` 里的 `return None`，于是显示成「`_open_roots` 执行了 `return None`」。
2. `netstat` 与 `Get-CimInstance` 查到监听 8760 的进程创建于 18:15:00，报错的请求发生在 18:14:04，也就是报错时跑的是更早启动的旧进程。
3. `logs/serve/service-20261027.jsonl` 里 18:14:04 同一秒有两条 `/` 与 `/api/case/walk_01` 的 `request.error`，异常都是 `KeyError: 'default_frontend'`；同一秒还有一条 `/case/walk_01` 的 `TemplateNotFound: 'wizard.html'`，模板已在退役改动中删除。三条错误同一个原因：进程早于退役改动启动。
4. 代码里已经没有任何 `default_frontend`（`git grep` 为空），`config/default.toml` 的 `[web]` 只剩 `proxy_max_w`。

根因是配置与代码的热度不对称：`Config.load()` 每次调用都重新读 `config/default.toml`，而 `_validate` 是进程启动时导入的函数对象。退役改动把 `default.toml` 与 `config.py` 一起改了，旧进程读到了新文件、仍跑旧校验，于是每个走到配置的请求都拿到一套与自身代码不匹配的配置。

顺带确认了两件事：

- 每个 500 在服务日志里写两遍：`RequestLogMiddleware` 记一条 `request.error`，`uvicorn.error` 又记一条同内容的 `Exception in ASGI application`。
- `api_me` 把用户输入直接写进 cookie，17:32:47 一条 `/api/me` 报 `UnicodeEncodeError: 'latin-1' codec can't encode characters`。HTTP 头只允许 latin-1，任何中文昵称都会失败。

## 改动

1. 配置在启动时定格：`config.py` 新增 `activate()`（加载并校验一次）与 `active()`（只读，未装配时按需装配）；`build_app()` 装配一次；`serve` 在启动时装配，失败时把原因写到 stderr 并以退出码 2 退出；`web/app.py` 与 `web/proxy.py` 的取配置全部改读 `active()`。进程级配置是不可变 `Config`，属于应用状态，不是硬规则 5 禁止的模块级可变缓存。
2. `_validate` 缺键报 `ConfigError`：新增 `_table()`/`_value()`，段表与标量都经它们读取，`_number()` 的缺失分支同样改成 `ConfigError`。缺键不再是裸 `KeyError`。
3. `api_me` 昵称编码：写入时 `quote(name, safe="")`，`identity.NicknameProvider` 读取时 `unquote()`。
4. 异常日志去重：新增 `AsgiExceptionDuplicateFilter`，只丢弃 `uvicorn.error` 上文案为 `Exception in ASGI application` 的记录，其他 uvicorn 异常照常保留；`request.error` 的消息改成带方法与路径（如 `request.error GET /api/case/walk_01`），控制台上那条记录因此保留原有信息量。

## 行为变化

- 改 `config/default.toml` 或本机 `vrstudio.toml` 后要重启 serve 才生效；原来「改 `proxy_max_w` 即时生效」的承诺取消。侧车 `max_w` 判定不变，重启后旧代理仍按新宽度自动重建，结果与原来一致，只多一步重启。
- 配置写错时 serve 不再带着半套配置接请求，而是启动即退出：`配置有问题（web.proxy_max_w must be an int in [256, 8192], got 100），serve 没有启动。`
- 每条未捕获异常在服务日志与控制台各只记一次，控制台那行带请求方法与路径。

## 验证

- `pytest`：418 条通过、0 失败、0 跳过。在 `E:\VRAIGC` 目录执行，避开本机 `vrstudio.toml` 对代理默认值断言的影响；在仓库根执行仍有 `test_web_proxy` 的 9 条既有失败（`docs/lessons-learned.md` §4），与本次无关。
- `ruff check .`：All checks passed。
- 启动门禁：临时目录写 `[web] proxy_max_w = 100`，`vrstudio.exe serve --port 8798` 返回码 2，stderr 是上面的中文提示。
- 运行态：用临时服务（端口 8798，日志写临时目录，验证后已停止）请求 `POST /api/me {"display_name":"张三"}` 返回 200，随后 `GET /api/me` 返回 `张三`；`GET /api/cases` 返回 200。
- 日志去重（真实 uvicorn，不是 TestClient）：临时起一个只含 `RequestLogMiddleware`、路由必抛 `RuntimeError` 的应用，请求一次得到 500，服务日志里只有一条 `request.error`（带 `path=/boom` 与 `traceback`），`Exception in ASGI application` 出现 0 次，uvicorn 的启动与关闭 INFO 记录照常保留；控制台只有一个 traceback。
- 新增 6 条测试：`test_missing_config_key_is_a_config_error`、`test_active_config_is_loaded_once`、`test_identity_accepts_non_ascii_name`、`test_request_path_does_not_reload_config`、`test_setup_logging_drops_duplicate_asgi_exception`、`test_request_error_record_carries_path_and_traceback`。其中 `test_request_path_does_not_reload_config` 把 `config.load` 换成直接失败，请求 `/api/case/<名>` 仍返回 200，直接钉住「请求路径不重读配置」。

## 一次被验证纠正的实现

`AsgiExceptionDuplicateFilter` 第一版按 `record.getMessage() != "Exception in ASGI application"` 判断，单元测试用不带换行的文案构造记录，全部通过；但用真实 uvicorn 跑同一个必抛异常的应用时，重复记录依然出现。原因是 uvicorn 在 `h11_impl` 里写的是 `"Exception in ASGI application\n"`，消息带尾随换行。改成 `record.getMessage().strip()` 之后，真实路径上的重复记录降到 0，单元测试也补上了带换行的文案。

这条记进 `docs/lessons-learned.md` §5 的预防：按消息文本过滤日志时，对照真实日志里的文案，不要只信自己构造的字符串。

## 未做

- 没有重启 8760、8763、8766 三个常驻服务：它们仍是旧代码进程，新行为要重启才生效。配置数据没有变化，所以它们不会重复 18:14 的事故。
- 没有用浏览器逐页点验新前端，只做了接口级验证。
- `web.upload_max_bytes` 在 `default.toml` 里不存在，`_deep_merge` 又拒绝未知键，这个键实际上设不了值，`_upload_max_bytes()` 永远返回内置默认。属既有问题，本次未动。

## 涉及文件

- 后端：`src/vrstudio/config.py`、`src/vrstudio/web/app.py`、`src/vrstudio/web/proxy.py`、`src/vrstudio/web/identity.py`、`src/vrstudio/web/logging.py`、`src/vrstudio/cli/serve.py`、`config/default.toml`。
- 测试：`tests/test_infra.py`、`tests/test_web_console.py`、`tests/test_web_logging.py`。
- 文档：`docs/decisions.md` 第 43 条、`docs/lessons-learned.md` §5、`docs/key-issues/frontend-decisions.md` 条目 17 的修正块、本文件。
