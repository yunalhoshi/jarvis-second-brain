@echo off
rem Opens the microphone setting of the Jarvis app window, so you can pick which microphone it listens to.
setlocal
set "PROFILE=%LOCALAPPDATA%\Jarvis\browser-profile"
set "BROWSER="
set "PAGE=chrome://settings/content/microphone"
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "BROWSER=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
    set "PAGE=edge://settings/content/microphone"
)
if not defined BROWSER (
    echo Chrome or Edge was not found.
    pause
    exit /b 1
)
start "" "%BROWSER%" --user-data-dir="%PROFILE%" --no-first-run "%PAGE%"
