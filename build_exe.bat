@echo off
setlocal
cd /d "%~dp0"

python -c "import PyInstaller" 2>nul
if errorlevel 1 (
    echo Installing pyinstaller ...
    python -m pip install pyinstaller
)

echo Building VivadoLabReg.exe ...
python -m PyInstaller --noconfirm --clean --onefile --windowed --name VivadoLabReg ^
  --add-data "gui.tcl;." ^
  --add-data "tool.tcl;." ^
  gui.py
if errorlevel 1 (
    echo BUILD FAILED
    pause
    exit /b 1
)

copy /Y "dist\VivadoLabReg.exe" "VivadoLabReg.exe" >nul
echo.
echo OK: %~dp0VivadoLabReg.exe
echo Runtime still needs Vivado Lab xsdb.bat on this PC.
echo Double-click VivadoLabReg.exe  (Python not required)
echo.
pause
