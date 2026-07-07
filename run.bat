@echo off
title sing-box portable
cd /d "%~dp0"

echo [*] Stopping old instance...
taskkill /f /im sing-box.exe 2>nul
timeout /t 2 /nobreak >nul

echo [*] Starting sing-box (config-windows.json)...
start /b "" sing-box.exe run -c config-windows.json -D "%~dp0"
timeout /t 5 /nobreak >nul

echo.
echo [*] Checking...
tasklist /fi "imagename eq sing-box.exe" 2>nul | find /i "sing-box.exe" >nul
if %errorlevel%==0 (
    echo [+] sing-box RUNNING
    echo.
    echo [+] SOCKS5:  127.0.0.1:1080
    echo [+] HTTP:    127.0.0.1:8080
    echo [+] Clash:   http://127.0.0.1:9090
    echo.
    echo [+] Exit IP:
    curl.exe -4 -sk --connect-timeout 8 --socks5 127.0.0.1:1080 https://ifconfig.me 2>nul
    echo.
    echo.
    echo [+] Configure your app to use SOCKS5 127.0.0.1:1080
    echo     Press Ctrl+C in this window to stop sing-box
    pause
) else (
    echo [!] FAILED to start. Check logs.
    type sing-box.log 2>nul | findstr /i "error" | more
    pause
)
