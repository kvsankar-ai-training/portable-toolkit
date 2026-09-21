@echo off
setlocal

echo.
echo Installing the toolkit AND the optional extras: ripgrep, jq, and the
echo Python document libraries for reading and writing Word, Excel, PowerPoint
echo and PDF files. This downloads a few hundred MB more than SETUP.cmd.
echo.

powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolkit\install.ps1" -IncludeOptional
if errorlevel 1 goto failed
goto done

:failed
echo.
echo ---------------------------------------------------------------------
echo Setup did not finish. See toolkit\troubleshooting.md, and if the message
echo above mentions a script not being digitally signed, report it rather than
echo looking for a way around it.
echo ---------------------------------------------------------------------

:done
echo.
pause
