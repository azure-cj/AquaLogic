@echo off
setlocal
set "ROOT=%~dp0"
set "CONFIG=%ROOT%bridge\bridge-config.json"

if not exist "%ROOT%bridge\esp32_bridge.py" (
  echo Bridge files were not found.
  echo Put this BAT file in the AquaLogic folder beside the bridge folder:
  echo   AquaLogic\start-esp32-bridge-tester.bat
  echo   AquaLogic\bridge\esp32_bridge.py
  echo   AquaLogic\bridge\bridge-config.example.json
  echo Do not run a copied BAT file by itself from Downloads.
  pause
  exit /b 1
)

if not exist "%CONFIG%" (
  copy "%ROOT%bridge\bridge-config.example.json" "%CONFIG%" >nul
  if errorlevel 1 (
    echo Could not create bridge\bridge-config.json.
    pause
    exit /b 1
  )
  echo Created bridge\bridge-config.json from the example.
  echo Edit it with the ESP32 local /data URL, backend HTTPS tunnel URL, and device key.
  echo The bridge has NOT started yet.
  notepad "%CONFIG%"
  pause
  exit /b 0
)

echo Starting local-only ESP32 sensor and actuator bridge...
echo The ESP32 is never exposed publicly; actuator calls are allowlisted and one-shot.
python "%ROOT%bridge\esp32_bridge.py" --config "%CONFIG%"
echo.
echo The bridge stopped. Review the messages above before closing this window.
pause
