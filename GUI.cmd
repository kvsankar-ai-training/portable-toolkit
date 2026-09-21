@echo off
setlocal

rem Same unblock step as SETUP.cmd, harmless to repeat if already done.
powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul

rem Hidden so only the window this opens is visible, not a console behind it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0toolkit\gui.ps1"
