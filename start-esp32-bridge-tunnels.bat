@echo off
setlocal

where ngrok >nul 2>nul
if errorlevel 1 (
  echo ngrok was not found on PATH.
  echo Install/sign in to ngrok, then run this file again.
  pause
  exit /b 1
)

echo Starting one temporary HTTPS dashboard tunnel...
echo The bridge uses the same URL with /api added, for example:
echo   https://YOUR-NGROK-URL.ngrok-free.dev/api
echo Never create a tunnel to the ESP32 or a second ngrok tunnel.
start "AquaLogic dashboard and API tunnel" cmd /k "ngrok http 5173"
pause
