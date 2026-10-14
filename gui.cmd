@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0VivadoLabReg.exe" (
    start "" "%~dp0VivadoLabReg.exe"
    exit /b 0
)
where pythonw >nul 2>nul && (
    start "XSDB Register GUI" pythonw "%~dp0gui.py"
    exit /b 0
)
where python >nul 2>nul && (
    python "%~dp0gui.py"
    exit /b %ERRORLEVEL%
)
echo ERROR: VivadoLabReg.exe / Python not found.
pause
exit /b 1
