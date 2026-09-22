@echo off
setlocal

rem Installs everything: the tools, Python, and the libraries that read
rem documents. There is nothing to choose - GUI.cmd does the same with a button.
rem
rem Earlier versions took the word "extras" for a second, larger install. It is
rem accepted and ignored, so older instructions still work.

echo.
echo Windows marks files that came from the internet, and a marked script will
echo not run. Clearing that mark for this folder only.
echo.
rem An inline -Command is not subject to PowerShell execution policy, unlike
rem loading a .ps1 file, so this still works on a machine where the installer
rem itself would be blocked.
powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul

rem Batch files are not affected by execution policy either. The switch below
rem applies to this one process and changes no machine setting.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolkit\install.ps1"
if errorlevel 1 goto failed
goto done

:failed
echo.
echo ---------------------------------------------------------------------
echo Setup did not finish.
echo.
echo If the message above says a script "is not digitally signed", then your
echo organisation enforces a PowerShell execution policy through Group Policy,
echo which overrides the setting this file uses. Nothing here can get around
echo that, and nothing should try.
echo.
echo If files went missing instead, your antivirus may have quarantined them.
echo See toolkit\troubleshooting.md. Report it rather than working around it.
echo ---------------------------------------------------------------------

:done
echo.
pause
