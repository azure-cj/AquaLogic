@echo off
setlocal

set "PROJECT_ROOT=%~dp0"

echo Starting AquaLogic development servers...
call "%PROJECT_ROOT%start-dev.bat"

echo Waiting for the web app to start on port 5173...
timeout /t 8 /nobreak >nul

where ngrok >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: ngrok was not found in PATH.
    echo Install ngrok and make sure the ^"ngrok^" command works in PowerShell.
    pause
    exit /b 1
)

echo.
echo Starting the public classroom tunnel...
echo Keep this window open while presenting.
echo.
ngrok http 5173 --host-header=rewrite

endlocal
