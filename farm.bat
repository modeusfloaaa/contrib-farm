@echo off
rem Double-click this to run the guided setup on Windows.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0farm.ps1" %*
echo.
pause
