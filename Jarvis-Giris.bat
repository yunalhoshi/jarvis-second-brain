@echo off
title Jarvis - Claude sign in
setlocal
set "CLAUDE="
for /f "delims=" %%F in ('where claude 2^>nul') do if not defined CLAUDE set "CLAUDE=%%F"
if not defined CLAUDE (
    for /f "delims=" %%F in ('dir /b /s /o:d "%APPDATA%\Claude\claude-code\claude.exe" 2^>nul') do set "CLAUDE=%%F"
)
if not defined CLAUDE (
    echo Claude was not found on this computer.
    pause
    exit /b 1
)
"%CLAUDE%" auth login
echo.
"%CLAUDE%" auth status
echo.
pause
