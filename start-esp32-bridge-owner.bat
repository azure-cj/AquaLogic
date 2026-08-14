@echo off
setlocal
set "ROOT=%~dp0"

if not exist "%ROOT%backend\.venv\Scripts\activate.bat" (
  echo First run: creating the backend virtual environment and installing packages...
  py -3 -m venv "%ROOT%backend\.venv"
  if errorlevel 1 (
    echo Could not create the virtual environment. Install Python 3 and try again.
    pause
    exit /b 1
  )
  call "%ROOT%backend\.venv\Scripts\activate.bat"
  python -m pip install --upgrade pip
  python -m pip install -r "%ROOT%backend\requirements-dev.txt"
  if errorlevel 1 (
    echo Package installation failed. Check your internet connection and try again.
    pause
    exit /b 1
  )
)

call "%ROOT%backend\.venv\Scripts\activate.bat"
python -c "import swagger_ui_bundle" >nul 2>nul
if errorlevel 1 (
  echo Installing newly required backend packages...
  python -m pip install -r "%ROOT%backend\requirements-dev.txt"
  if errorlevel 1 (
    echo Package installation failed. Check your internet connection and try again.
    pause
    exit /b 1
  )
)

echo Starting AquaLogic backend and dashboard in separate windows...
start "AquaLogic backend" cmd /k "cd /d ""%ROOT%backend"" && call .venv\Scripts\activate.bat && alembic upgrade head && python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000"
start "AquaLogic dashboard" cmd /k "cd /d ""%ROOT%web"" && npm run dev -- --host 127.0.0.1 --port 5173"

echo.
echo Backend:   http://127.0.0.1:8000/docs
echo Dashboard: http://127.0.0.1:5173
echo Next: run start-esp32-bridge-tunnels.bat in another terminal.
pause
