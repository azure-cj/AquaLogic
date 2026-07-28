@echo off
setlocal
set "PROJECT_ROOT=%~dp0"

echo Starting AquaLogic development servers...
echo API: http://127.0.0.1:8000/docs
echo Web: http://localhost:5173

start "AquaLogic API" powershell.exe -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%PROJECT_ROOT%backend'; $env:DATABASE_URL = 'sqlite:///./aqualogic.db'; $env:DEMO_SENSOR_ENABLED = 'true'; $env:DEMO_SENSOR_INSTANCE = 'true'; $env:DEMO_SENSOR_INTERVAL_SECONDS = '30'; alembic upgrade head; python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
start "AquaLogic Web" powershell.exe -NoExit -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%PROJECT_ROOT%web'; npm run dev"

endlocal
