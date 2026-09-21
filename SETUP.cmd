@echo off
REM Entry point. Batch files are not affected by PowerShell execution policy,
REM so this runs on a machine where a .ps1 would be blocked. The -ExecutionPolicy
REM switch below applies to this one process only and changes no machine setting.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolkit\install.ps1"
pause
