VRAIGC 安装说明
================

安装完成后请按顺序做三件事。

1. 安装 mglc（生成功能需要，安装包不附带）
   - 向管理员索取 mglc 的 Windows 版本（mglc-windows-amd64.zip）。
   - 解压到 %LOCALAPPDATA%\Programs\mglc\bin\，确认目录里有 mglc.exe。
   - 把该目录加进当前用户 PATH，或让 vrstudio 通过 VRGEN_MGLC_BIN 找到它：
     安装器已经在 %APPDATA%\vrstudio\default.toml 里写好数据目录与 vrgen 路径，
     mglc 请用其中一种方式提供。
   - 新开一个终端执行：
       mglc login --access-key <AK> --secret-key <SK>
     AK/SK 向平台管理员申请；登录态写在 %USERPROFILE%\.mglc\config.yaml。
   - 验证：
       mglc virtual-ip list
     能返回列表说明登录成功（只读，不消耗额度）。

2. 准备数据目录
   - 安装时已经选过数据目录（例如 D:\VRAIGC-data），里面应该有
     cases\ sources\ vrgen_runs\ logs\ 四个子目录。
   - 如果是迁移过来的旧数据，把迁移包解压出的 vrstudio 目录内容直接指过去即可，
     两者布局一致。
   - 数据目录不要放在系统盘，也不要放在 OneDrive 等同步目录。

3. 启动（两种模式）
   - 开始菜单里有两条：
       VRAIGC（本机）    只监听 127.0.0.1:8760，双击后自动打开浏览器
       VRAIGC（局域网）  监听 0.0.0.0:8760，控制台会打印本机的局域网地址
   - 桌面图标与「本机」等价；控制台窗口关掉，服务就停。
   - 局域网模式下，其它机器用控制台打印的地址访问；首次需要在本机放行端口：
       New-NetFirewallRule -DisplayName 'VRAIGC 8760' -Direction Inbound -Protocol TCP -LocalPort 8760 -Action Allow
   - 命令行等价写法：vrstudio.exe（本机）、vrstudio.exe --lan（局域网）、
     vrstudio.exe --lan --port 8860（换端口）。--help 列出全部子命令。
   - 控制台没有登录认证，只在可信网络里对外开放。
   - mglc、ffmpeg、rife 都不需要你配 PATH：程序按固定位置查找；
     mglc 依次找 <程序目录>\tools\mglc.exe、%LOCALAPPDATA%\Programs\mglc\bin、
     环境变量 VRGEN_MGLC_BIN、PATH。

常见问题
--------
- 首次运行被 SmartScreen 拦下：点“更多信息 → 仍要运行”。安装包没有数字签名。
- 提示找不到 mglc 或其版本过旧：重新按第 1 步安装最新版。
- 补帧报 Vulkan 错误：机器缺少可用的 Vulkan 驱动，补帧功能不可用，其它流程正常。
- 数据目录放错：删除 %APPDATA%\vrstudio\default.toml 中的 [paths] 段后重新启动，
  或在命令行用 --set paths.data_root=<新目录> 覆盖。
