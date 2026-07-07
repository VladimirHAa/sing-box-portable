@echo off
title sing-box portable dashboard
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0dashboard.ps1"
