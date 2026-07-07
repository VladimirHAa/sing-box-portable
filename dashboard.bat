@echo off
title sing-box portable dashboard
cd /d "%~dp0"

echo.
echo  ========================================
echo    SING-BOX PORTABLE DASHBOARD
echo  ========================================
echo.

:: Set required env vars
set ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true

:: Check if sing-box is running
tasklist /fi "imagename eq sing-box.exe" 2>nul | find /i "sing-box.exe" >nul
if %errorlevel%==0 (
    echo  [+] sing-box already running
) else (
    echo  [*] Starting sing-box...
    sing-box.exe run -c config-windows.json -D "%~dp0" >nul 2>&1 &
    timeout /t 5 /nobreak >nul
    tasklist /fi "imagename eq sing-box.exe" 2>nul | find /i "sing-box.exe" >nul
    if %errorlevel%==0 (
        echo  [+] sing-box started
    ) else (
        echo  [!] FAILED to start sing-box
        echo      Check sing-box.log
        echo.
        pause
        exit /b 1
    )
)

echo.
echo  [*] Starting dashboard...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0dashboard.ps1"

echo.
echo  [+] Dashboard closed.
