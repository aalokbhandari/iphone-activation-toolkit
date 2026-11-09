@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-windows.ps1"
set "task_exit_code=%errorlevel%"
echo.
pause
exit /b %task_exit_code%
