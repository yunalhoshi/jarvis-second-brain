@echo off
title Jarvis
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-graph.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
where python >nul 2>nul
if errorlevel 1 (
    echo Python not found: opening the page without voice answers from Claude.
    start "" "%~dp0index.html"
    exit /b 0
)
python "%~dp0jarvis-server.py"
