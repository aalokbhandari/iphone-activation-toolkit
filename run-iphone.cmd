@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-iphone.ps1" %*
set "workflow_exit=%ERRORLEVEL%"
echo.
pause
exit /b %workflow_exit%
