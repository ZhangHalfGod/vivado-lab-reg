@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

call :find_xsdb
if not defined XSDB (
    echo ERROR: xsdb not found. Add Vivado Lab bin to PATH, or set XSDB.
    echo Example: D:\vivdao_down\Vivado_Lab\2022.2\bin\xsdb.bat
    pause
    exit /b 1
)

set "HERE=%~dp0"
set "HERE=%HERE:\=/%"
if "%HERE:~-1%"=="/" set "HERE=%HERE:~0,-1%"

if "%~1"=="" goto INTERACTIVE
if /i "%~1"=="help" goto USAGE
if /i "%~1"=="-h" goto USAGE
if /i "%~1"=="/?" goto USAGE
if /i "%~1"=="verify" goto VERIFY
if /i "%~1"=="targets" goto TARGETS
if /i "%~1"=="rd" goto RD
if /i "%~1"=="wr" goto WR
if /i "%~1"=="wrd" goto WRD
if /i "%~1"=="jrd" goto JRD
if /i "%~1"=="jrd2" goto JRD2
if /i "%~1"=="jwr" goto JWR
if /i "%~1"=="jwr2" goto JWR2
if /i "%~1"=="jwrd" goto JWRD
if /i "%~1"=="jwrd2" goto JWRD2
if /i "%~1"=="interactive" goto INTERACTIVE

echo Unknown command: %~1
goto USAGE

:USAGE
echo.
echo  Vivado Lab XSDB tool
echo  xsdb : %XSDB%
echo.
echo  Two paths:
echo    MB   : JTAG -^> XSDB -^> MicroBlaze
echo    JTAG : JTAG -^> XSDB -^> Jtag Master (JTAG2AXI / hw_axi)
echo.
echo  Usage:
echo    xsdb.cmd                 interactive
echo    xsdb.cmd verify          both paths then exit
echo    xsdb.cmd targets         list JTAG targets
echo    xsdb.cmd rd   ^<addr^> [len]
echo    xsdb.cmd wr   ^<addr^> ^<data^>
echo    xsdb.cmd wrd  ^<addr^> ^<data^>
echo    xsdb.cmd jrd  ^<addr^> [len]     JTAG2AXI #1
echo    xsdb.cmd jrd2 ^<addr^> [len]     JTAG2AXI #2
echo    xsdb.cmd jwr  ^<addr^> ^<data^>
echo    xsdb.cmd jwr2 ^<addr^> ^<data^>
echo    xsdb.cmd jwrd ^<addr^> ^<data^>
echo.
echo  Examples:
echo    xsdb.cmd rd   11080000 10
echo    xsdb.cmd jrd  116BCC00 4
echo    xsdb.cmd jwr  116BCC08 1
echo.
if "%~1"=="" exit /b 0
if /i "%~1"=="help" exit /b 0
pause
exit /b 1

:INTERACTIVE
echo.
echo  XSDB: JTAG -^> MicroBlaze  and  JTAG -^> Jtag Master
echo  script: %~dp0tool.tcl
echo  xsdb : %XSDB%
echo.
"%XSDB%" -interactive -eval "source {%HERE%/tool.tcl}"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:VERIFY
echo verify both paths: %~dp0reg.tcl
"%XSDB%" "%~dp0reg.tcl"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:TARGETS
"%XSDB%" -eval "connect; targets; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:RD
if "%~2"=="" (
    echo Missing addr. Example: xsdb.cmd rd 11080000 10
    exit /b 1
)
set "LEN=%~3"
if "%LEN%"=="" set "LEN=1"
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {rd %~2 %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:WR
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd wr 11080000 12345678
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {wr %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:WRD
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd wrd 11080000 1
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {wrd %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JRD
if "%~2"=="" (
    echo Missing addr. Example: xsdb.cmd jrd 116BCC00 4
    exit /b 1
)
set "LEN=%~3"
if "%LEN%"=="" set "LEN=1"
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {rd %~2 %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JRD2
if "%~2"=="" (
    echo Missing addr. Example: xsdb.cmd jrd2 116BCC00 4
    exit /b 1
)
set "LEN=%~3"
if "%LEN%"=="" set "LEN=1"
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {rd %~2 %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWR
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd jwr 116BCC08 1
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {wr %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWR2
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd jwr2 116BCC08 1
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {wr %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWRD
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd jwrd 116BCC08 1
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {wrd %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWRD2
if "%~3"=="" (
    echo Missing args. Example: xsdb.cmd jwrd2 116BCC08 1
    exit /b 1
)
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {wrd %~2 %~3}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:find_xsdb
if defined XSDB if exist "%XSDB%" goto :eof
if defined XSDB_PATH if exist "%XSDB_PATH%" (
    set "XSDB=%XSDB_PATH%"
    goto :eof
)
where xsdb.bat >nul 2>nul && (
    for /f "delims=" %%I in ('where xsdb.bat') do (
        echo %%I | findstr /i "vivado" >nul && (
            set "XSDB=%%I"
            goto :eof
        )
    )
)
if defined XILINX_VIVADO if exist "%XILINX_VIVADO%\bin\xsdb.bat" (
    set "XSDB=%XILINX_VIVADO%\bin\xsdb.bat"
    goto :eof
)
for %%R in (D:\vivdao_down C:\Xilinx D:\Xilinx E:\Xilinx) do (
    for %%V in (2024.2 2024.1 2023.2 2023.1 2022.2 2022.1 2021.2 2021.1) do (
        if exist "%%R\Vivado_Lab\%%V\bin\xsdb.bat" (
            set "XSDB=%%R\Vivado_Lab\%%V\bin\xsdb.bat"
            goto :eof
        )
        if exist "%%R\Vivado\%%V\bin\xsdb.bat" (
            set "XSDB=%%R\Vivado\%%V\bin\xsdb.bat"
            goto :eof
        )
    )
)
goto :eof
