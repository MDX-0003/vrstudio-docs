@echo off
rem 修改控制台的监听端口：写入 %APPDATA%\vrstudio\default.toml，下次启动生效。
chcp 65001 >nul
echo Current settings:
"%~dp0vrstudio.exe" config show
echo.
set /p P=New port (press Enter to cancel):
if "%P%"=="" goto :done
"%~dp0vrstudio.exe" config set web.port %P%
:done
pause
