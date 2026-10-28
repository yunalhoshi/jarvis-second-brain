@echo off
title Jarvis - ElevenLabs key
setlocal
set "DIR=%USERPROFILE%\.jarvis"
set "FILE=%DIR%\elevenlabs-key.txt"
echo Paste your ElevenLabs API key below and press Enter.
echo (Right-click in this window to paste.)
echo.
set "KEY="
set /p "KEY=Key: "
if not defined KEY (
    echo No key entered. Nothing was saved.
    pause
    exit /b 1
)
if not exist "%DIR%" mkdir "%DIR%"
> "%FILE%" echo %KEY%
echo.
echo Saved to %FILE%
echo Close Jarvis and open Jarvis-Grafik.bat again.
echo.
pause
