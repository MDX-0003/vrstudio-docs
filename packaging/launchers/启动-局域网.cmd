@echo off
rem 局域网 host 模式：监听 0.0.0.0，控制台会打印本机的局域网地址。
chcp 65001 >nul
"%~dp0vrstudio.exe" --lan
