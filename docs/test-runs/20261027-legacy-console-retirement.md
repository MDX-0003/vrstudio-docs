# 旧版控制台退役验收（2026-10-27）

关联决策：`docs/decisions.md` 第 42 条。背景与排除方案见 `docs/key-issues/frontend-decisions.md` 条目 19。

## 范围

- 删除设置页「旧版入口 / 打开旧版控制台」。
- 删除旧版后端：Jinja2 模板（8 个文件）、`static/` 下 10 个旧脚本、`GET /case/{name}` 的页面渲染、`web.default_frontend` 配置键、`/static` 挂载与 Jinja2 依赖。
- `GET /` 固定 307 到 `/next/`；`GET /case/{name}` 改为 307 到 `/next/case/{name}`，旧书签与局域网直链不 404。
- 删除旧版 API 兼容层：`keyframe.sheet` / `sheet_candidates` 派生字段、`GET/PUT /api/case/{name}/keyframe/sheet`、`set_asset_role` 对 `[submit.roles]` 的同步。
- 保留：全部 `/api/*`、`/img/{name}/vp.png`（新前端 `PickStep` 使用）、`/img/asset/*`、`/file`、`/video/*`。

## 改动的文件

- 后端：`src/vrstudio/web/app.py`、`case.py`、`config.py`、`config/default.toml`、`pyproject.toml`、`uv.lock`。
- 前端：`views/SettingsView.vue`、`api/keyframe.ts`、`types/case-info.ts`、`views/wizard/KeyframeStep.vue`（删掉无引用的 `.kf-sheet-*` 样式）。
- 测试：`tests/test_web_console.py`、`tests/test_casemodel.py`、`tests/test_web_media_cache.py`。

## 自动化门禁

- `pytest`：332 条全绿。仓库根直接跑会有 9 条 `test_web_proxy.py` 失败，原因是本机 `vrstudio.toml` 设了 `web.proxy_max_w = 2048`，而这些用例按内置默认 4096 断言；在无本地配置的目录执行 `E:\VRAIGC\vrstudio\.venv\Scripts\python.exe -m pytest E:\VRAIGC\vrstudio\tests -q` 可复现全绿。该差异在本次改动前就存在，与退役无关。
- `ruff check .`：All checks passed。
- 前端 `npm run build`（含 `vue-tsc -b`）：通过；`npm test`：22 个文件、95 条全绿；`npm run lint`：通过。
- `npm run format:check`：12 个文件报格式问题，均为改动前既有状态（对 `HEAD` 的 `KeyframeStep.vue` 单独跑 prettier 同样报错），本次未做全仓格式化。

## 运行时验证

用新代码在 8799 起临时服务，并重启 8760 / 8763 / 8766 三个常驻服务后逐项请求：

| 请求 | 结果 |
|---|---|
| `GET /` | 307 → `/next/`（8760、8763、8766 一致） |
| `GET /case/walk_01` | 307 → `/next/case/walk_01` |
| `GET /next/` | 200 |
| `GET /api/cases` | 200 |
| `GET /api/case/walk_01` | 200 |
| `GET /api/case/walk_01/keyframe/sheet` | 404（路由已删） |
| `GET /img/dacne/vp.png` | 200 `image/png` |
| `GET /file?root=cases&p=walk_01/case.toml` | 200 |

字段抽查：`dacne`（patch）`keyframe.refs` 1 条、`walk_4k`（patch）2 条且 `first`/`last` 都在、`CYQF_01`（fullredraw）0 条；三者的 `keyframe` 都不再有 `sheet` 字段。构建产物 `assets/index-RCQg0kVM.js` 中已检索不到「旧版控制台」。

## 环境处理

常驻服务是改动前启动的旧进程：editable 安装下代码不热更新，而 `default.toml` 已删除 `default_frontend`，旧 `config._validate` 读新文件会在每次请求时抛 `KeyError`，表现为 500。已终止三个旧进程树，`uv sync --extra web --extra dev` 重建 venv（jinja2 卸载），再用原参数重启：

- `uv run vrstudio serve --host 0.0.0.0 --port 8760`
- `uv run vrstudio serve --host 127.0.0.1 --port 8763 --cases-dir E:\VRAIGC\vrstudio\cases_qa`
- `uv run vrstudio serve --port 8766`

三个服务均以隐藏窗口的后台进程运行，日志仍在 `logs/serve/`。临时验证服务 8799 已停止。

这类「旧进程读新配置」的错位已由决策 43 从结构上消除（配置改为启动时定格），修复与验收见 `20261028-config-snapshot-and-log-dedup.md`。

## 未做

- 未用真实浏览器逐页点验新前端；只验证了构建产物、HTTP 跳转与接口字段。
- 未涉及任何付费生成。
