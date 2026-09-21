@echo off
REM Runs one command with the toolkit's tools available, then exits.
REM
REM   run.cmd uv pip install requests
REM   run.cmd python myscript.py
REM
REM Useful before PATH takes effect, and for uv, which this keeps contained.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolkit\run.ps1" %*
