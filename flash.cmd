@echo off
rem Double-click friendly wrapper: runs flash.ps1 without changing the PowerShell execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash.ps1" %*
if errorlevel 1 pause
