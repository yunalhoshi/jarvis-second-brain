@echo off
title Jarvis - telefon
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0jarvis-phone.ps1" -Stop
echo.
pause
