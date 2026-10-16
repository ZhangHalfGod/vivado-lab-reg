@echo off
setlocal
cd /d "%~dp0"

REM Lab Windows build. Writes dist\VivadoLabReg.exe only.
REM Vivado Lab is not bundled. Profiles and config stay outside the exe.
REM Pass --nopause to skip the final pause (double-click still pauses).

where python >nul 2>nul
if errorlevel 1 (
    echo ERROR: Python 3.10+ with tkinter is required to build.
    echo The lab PC that only runs dist\VivadoLabReg.exe does not need Python.
    pause
    exit /b 1
)

python -c "import tkinter" 2>nul
if errorlevel 1 (
    echo ERROR: tkinter is missing. Reinstall Python with Tcl/Tk, then rebuild.
    pause
    exit /b 1
)

python -c "import PyInstaller" 2>nul
if errorlevel 1 (
    echo Installing pyinstaller ...
    python -m pip install pyinstaller
    if errorlevel 1 (
        echo ERROR: pip install pyinstaller failed.
        pause
        exit /b 1
    )
)

python -c "import openpyxl" 2>nul
if errorlevel 1 (
    echo NOTE: openpyxl is not installed. The exe will not read .xlsx.
    echo       pip install openpyxl and rebuild if you need workbooks.
    echo       A CSV with the same columns still works.
)

echo Building dist\VivadoLabReg.exe from VivadoLabReg.spec ...
python -m PyInstaller --noconfirm --clean VivadoLabReg.spec
if errorlevel 1 (
    echo BUILD FAILED
    pause
    exit /b 1
)

echo.
echo OK: %~dp0dist\VivadoLabReg.exe
echo This file is gitignored. Do not commit dist\ or the exe.
echo Vivado Lab is not inside the exe. Install it on the lab PC and pick xsdb.bat.
echo Board profiles stay in profiles\private\ . Config stays in %%APPDATA%%\VivadoLabReg\config.json .
echo Development: gui.cmd or pythonw gui.py . After Tcl or gui.py changes, rebuild.
echo.
if /I "%~1"=="--nopause" exit /b 0
pause
