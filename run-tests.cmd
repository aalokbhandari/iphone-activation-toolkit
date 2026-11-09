@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-project.ps1"
set "test_exit=%ERRORLEVEL%"
echo.
pause
exit /b %test_exit%
