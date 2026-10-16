@echo off
setlocal
cd /d "%~dp0"
REM Source GUI when Python is installed. build_exe.bat writes
REM dist\VivadoLabReg.exe for a lab PC; that exe does not include Vivado Lab.
where pythonw >nul 2>nul && (
    start "XSDB Register GUI" pythonw "%~dp0gui.py"
    exit /b 0
)
where python >nul 2>nul && (
    python "%~dp0gui.py"
    exit /b %ERRORLEVEL%
)
if exist "%~dp0dist\VivadoLabReg.exe" (
    start "" "%~dp0dist\VivadoLabReg.exe"
    exit /b 0
)
if exist "%~dp0VivadoLabReg.exe" (
    start "" "%~dp0VivadoLabReg.exe"
    exit /b 0
)
echo ERROR: Python not found, and dist\VivadoLabReg.exe is missing.
echo Install Python 3.10+ or run build_exe.bat on a Windows build PC.
pause
exit /b 1
