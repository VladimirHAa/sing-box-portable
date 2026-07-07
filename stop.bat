@echo off
echo [*] Stopping sing-box...
taskkill /f /im sing-box.exe 2>nul
if %errorlevel%==0 (
    echo [+] sing-box stopped
) else (
    echo [i] sing-box was not running
)
timeout /t 2 /nobreak >nul
echo [+] Done
pause
