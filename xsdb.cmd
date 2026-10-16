@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

REM --json anywhere selects one JSON document on stdout. Detect it before
REM the xsdb search so a missing toolchain still prints JSON.
set "JSON=0"
if "%~1"=="" goto FIND_XSDB
for %%A in (%*) do if /i "%%~A"=="--json" set "JSON=1"
:FIND_XSDB

call :find_xsdb
if not defined XSDB (
    if "%JSON%"=="1" (
        echo {"ok":false,"command":"xsdb","operation":"error","error":"xsdb not found. Add Vivado Lab bin to PATH, or set XSDB.","targets":[]}
        exit /b 1
    )
    echo ERROR: xsdb not found. Add Vivado Lab bin to PATH, or set XSDB.
    echo Example: C:\Xilinx\Vivado_Lab\2022.2\bin\xsdb.bat
    pause
    exit /b 1
)

set "HERE=%~dp0"
set "HERE=%HERE:\=/%"
if "%HERE:~-1%"=="/" set "HERE=%HERE:~0,-1%"

REM --profile and --json may appear before the command or after it.
set "PN=0"
set "P1="
set "P2="
set "P3="
set "P4="

:PARSE_ARGS
if "%~1"=="" goto PARSE_DONE
if /i "%~1"=="--json" (
    set "JSON=1"
    shift
    goto PARSE_ARGS
)
if /i "%~1"=="--profile" (
    if "%~2"=="" goto PROFILE_NEEDS_ARG
    set "VIVADO_LAB_REG_PROFILE=%~2"
    shift
    shift
    goto PARSE_ARGS
)
set /a PN+=1
if !PN! EQU 1 set "P1=%~1"
if !PN! EQU 2 set "P2=%~1"
if !PN! EQU 3 set "P3=%~1"
if !PN! EQU 4 set "P4=%~1"
shift
goto PARSE_ARGS

:PARSE_DONE
if "%P1%"=="" goto INTERACTIVE
if /i "%P1%"=="help" goto USAGE
if /i "%P1%"=="-h" goto USAGE
if /i "%P1%"=="/?" goto USAGE
if /i "%P1%"=="verify" goto VERIFY
if /i "%P1%"=="targets" goto TARGETS
if /i "%P1%"=="rd" goto RD
if /i "%P1%"=="wr" goto WR
if /i "%P1%"=="wrd" goto WRD
if /i "%P1%"=="jrd" goto JRD
if /i "%P1%"=="jrd2" goto JRD2
if /i "%P1%"=="jwr" goto JWR
if /i "%P1%"=="jwr2" goto JWR2
if /i "%P1%"=="jwrd" goto JWRD
if /i "%P1%"=="jwrd2" goto JWRD2
if /i "%P1%"=="interactive" goto INTERACTIVE

if "%JSON%"=="1" (
    call :JSON_EARLY %P1% %P1% "Unknown command: %P1%" targets
    exit /b 1
)
echo Unknown command: %P1%
goto USAGE

:PROFILE_NEEDS_ARG
if "%JSON%"=="1" (
    call :JSON_EARLY xsdb error "--profile needs a .tcl board profile." targets
    exit /b 1
)
echo ERROR: --profile needs a .tcl board profile.
echo Example: xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
exit /b 1

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
echo    xsdb.cmd verify --profile ^<file.tcl^>
echo    xsdb.cmd --profile ^<file.tcl^> [command]
echo    xsdb.cmd targets         list JTAG targets
echo    xsdb.cmd rd   ^<addr^> [len]
echo    xsdb.cmd wr   ^<addr^> ^<data^>
echo    xsdb.cmd wrd  ^<addr^> ^<data^>
echo    xsdb.cmd jrd  ^<addr^> [len]     JTAG2AXI #1
echo    xsdb.cmd jrd2 ^<addr^> [len]     JTAG2AXI #2
echo    xsdb.cmd jwr  ^<addr^> ^<data^>
echo    xsdb.cmd jwr2 ^<addr^> ^<data^>
echo    xsdb.cmd jwrd ^<addr^> ^<data^>
echo    --json                   one JSON object on stdout
echo.
echo  Board profile ^(Master Base Address^), optional:
echo    --profile ^<file.tcl^>   source before tool.tcl
echo    or set VIVADO_LAB_REG_PROFILE ^(XSDB_PROFILE also works^)
echo    0x0 or no profile skips that smoke read.
echo.
echo  Examples:
echo    xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
echo    xsdb.cmd rd   00001000 10
echo    xsdb.cmd jrd  00002000 4
echo    xsdb.cmd jwr  00002008 1
echo    xsdb.cmd --json targets
echo    xsdb.cmd --json rd 00001000 4
echo    xsdb.cmd --json wr 00001000 1
echo    xsdb.cmd --json verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
echo.
if "%P1%"=="" exit /b 0
if /i "%P1%"=="help" exit /b 0
if /i "%P1%"=="-h" exit /b 0
if /i "%P1%"=="/?" exit /b 0
pause
exit /b 1

:INTERACTIVE
if "%JSON%"=="1" (
    call :JSON_EARLY interactive error "interactive has no JSON result. Use targets, rd, wr, wrd, jrd, jwr, jwrd, or verify." mem
    exit /b 1
)
if not "%P2%"=="" (
    echo Unknown argument: %P2%
    echo Usage: xsdb.cmd [--profile file.tcl]
    exit /b 1
)
echo.
echo  XSDB: JTAG -^> MicroBlaze  and  JTAG -^> Jtag Master
echo  script: %~dp0tool.tcl
echo  xsdb : %XSDB%
if defined VIVADO_LAB_REG_PROFILE echo  profile: "%VIVADO_LAB_REG_PROFILE%"
echo.
"%XSDB%" -interactive -eval "source {%HERE%/tool.tcl}"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:VERIFY
if "%JSON%"=="1" goto VERIFY_JSON
if not "%P2%"=="" (
    echo Unknown argument: %P2%
    echo Usage: xsdb.cmd verify [--profile file.tcl]
    echo Example: xsdb.cmd verify --profile D:\lab\vivado-lab-reg\profiles\private\board.tcl
    exit /b 1
)
echo verify both paths: %~dp0reg.tcl
if defined VIVADO_LAB_REG_PROFILE echo board profile: "%VIVADO_LAB_REG_PROFILE%"
"%XSDB%" "%~dp0reg.tcl"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:VERIFY_JSON
if not "%P2%"=="" (
    call :JSON_EARLY verify verify "Unknown argument: %P2%" verify
    exit /b 1
)
call :RUN_JSON "json_cli_main verify" verify verify verify
exit /b %ERRORLEVEL%

:TARGETS
if "%JSON%"=="1" goto TARGETS_JSON
"%XSDB%" -eval "connect; targets; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:TARGETS_JSON
if not "%P2%"=="" (
    call :JSON_EARLY targets targets "Unknown argument: %P2%" targets
    exit /b 1
)
call :RUN_JSON "json_cli_main targets" targets targets targets
exit /b %ERRORLEVEL%

:RD
if "%P2%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY rd read "Missing addr. Example: xsdb.cmd rd 00001000 10" mem
        exit /b 1
    )
    echo Missing addr. Example: xsdb.cmd rd 00001000 10
    exit /b 1
)
set "LEN=%P3%"
if "%LEN%"=="" set "LEN=1"
if "%JSON%"=="1" goto RD_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {rd %P2% %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:RD_JSON
if not "%P4%"=="" (
    call :JSON_EARLY rd read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY rd read "bad address: %P2%" mem
    exit /b 1
)
call :LEN_OK "%LEN%"
if errorlevel 1 (
    call :JSON_EARLY rd read "length must be a positive integer" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main read {%P2%} {%LEN%} mb 0 rd" rd read mem
exit /b %ERRORLEVEL%

:WR
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY wr write "Missing args. Example: xsdb.cmd wr 00001000 12345678" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd wr 00001000 12345678
    exit /b 1
)
if "%JSON%"=="1" goto WR_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {wr %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:WR_JSON
if not "%P4%"=="" (
    call :JSON_EARLY wr write "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY wr write "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY wr write "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write {%P2%} {%P3%} mb 0 wr" wr write mem
exit /b %ERRORLEVEL%

:WRD
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY wrd write_read "Missing args. Example: xsdb.cmd wrd 00001000 1" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd wrd 00001000 1
    exit /b 1
)
if "%JSON%"=="1" goto WRD_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; mb; catch {wrd %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:WRD_JSON
if not "%P4%"=="" (
    call :JSON_EARLY wrd write_read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY wrd write_read "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY wrd write_read "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write_read {%P2%} {%P3%} mb 0 wrd" wrd write_read mem
exit /b %ERRORLEVEL%

:JRD
if "%P2%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jrd read "Missing addr. Example: xsdb.cmd jrd 00002000 4" mem
        exit /b 1
    )
    echo Missing addr. Example: xsdb.cmd jrd 00002000 4
    exit /b 1
)
set "LEN=%P3%"
if "%LEN%"=="" set "LEN=1"
if "%JSON%"=="1" goto JRD_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {rd %P2% %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JRD_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jrd read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jrd read "bad address: %P2%" mem
    exit /b 1
)
call :LEN_OK "%LEN%"
if errorlevel 1 (
    call :JSON_EARLY jrd read "length must be a positive integer" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main read {%P2%} {%LEN%} jtag 1 jrd" jrd read mem
exit /b %ERRORLEVEL%

:JRD2
if "%P2%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jrd2 read "Missing addr. Example: xsdb.cmd jrd2 00002000 4" mem
        exit /b 1
    )
    echo Missing addr. Example: xsdb.cmd jrd2 00002000 4
    exit /b 1
)
set "LEN=%P3%"
if "%LEN%"=="" set "LEN=1"
if "%JSON%"=="1" goto JRD2_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {rd %P2% %LEN%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JRD2_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jrd2 read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jrd2 read "bad address: %P2%" mem
    exit /b 1
)
call :LEN_OK "%LEN%"
if errorlevel 1 (
    call :JSON_EARLY jrd2 read "length must be a positive integer" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main read {%P2%} {%LEN%} jtag 2 jrd2" jrd2 read mem
exit /b %ERRORLEVEL%

:JWR
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jwr write "Missing args. Example: xsdb.cmd jwr 00002008 1" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd jwr 00002008 1
    exit /b 1
)
if "%JSON%"=="1" goto JWR_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {wr %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWR_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jwr write "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jwr write "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY jwr write "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write {%P2%} {%P3%} jtag 1 jwr" jwr write mem
exit /b %ERRORLEVEL%

:JWR2
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jwr2 write "Missing args. Example: xsdb.cmd jwr2 00002008 1" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd jwr2 00002008 1
    exit /b 1
)
if "%JSON%"=="1" goto JWR2_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {wr %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWR2_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jwr2 write "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jwr2 write "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY jwr2 write "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write {%P2%} {%P3%} jtag 2 jwr2" jwr2 write mem
exit /b %ERRORLEVEL%

:JWRD
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jwrd write_read "Missing args. Example: xsdb.cmd jwrd 00002008 1" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd jwrd 00002008 1
    exit /b 1
)
if "%JSON%"=="1" goto JWRD_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 1; catch {wrd %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWRD_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jwrd write_read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jwrd write_read "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY jwrd write_read "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write_read {%P2%} {%P3%} jtag 1 jwrd" jwrd write_read mem
exit /b %ERRORLEVEL%

:JWRD2
if "%P3%"=="" (
    if "%JSON%"=="1" (
        call :JSON_EARLY jwrd2 write_read "Missing args. Example: xsdb.cmd jwrd2 00002008 1" mem
        exit /b 1
    )
    echo Missing args. Example: xsdb.cmd jwrd2 00002008 1
    exit /b 1
)
if "%JSON%"=="1" goto JWRD2_JSON
"%XSDB%" -eval "set ::XSDB_QUIET 1; source {%HERE%/tool.tcl}; xconnect; jtag 2; catch {wrd %P2% %P3%}; exit"
if errorlevel 1 pause
exit /b %ERRORLEVEL%

:JWRD2_JSON
if not "%P4%"=="" (
    call :JSON_EARLY jwrd2 write_read "Unknown argument: %P4%" mem
    exit /b 1
)
call :HEX_OK "%P2%"
if errorlevel 1 (
    call :JSON_EARLY jwrd2 write_read "bad address: %P2%" mem
    exit /b 1
)
call :HEX_OK "%P3%"
if errorlevel 1 (
    call :JSON_EARLY jwrd2 write_read "bad data: %P3%" mem
    exit /b 1
)
call :RUN_JSON "json_cli_main write_read {%P2%} {%P3%} jtag 2 jwrd2" jwrd2 write_read mem
exit /b %ERRORLEVEL%

:RUN_JSON
set "JSON_SCRIPT=%~1"
set "JSON_CMD=%~2"
set "JSON_OP=%~3"
set "JSON_KIND=%~4"
set "JSON_FILE=%TEMP%\vivado-lab-reg-%RANDOM%.json"
set "JSON_LOG=%TEMP%\vivado-lab-reg-%RANDOM%.log"
set "VIVADO_LAB_REG_JSON=1"
set "VIVADO_LAB_REG_JSON_FILE=%JSON_FILE%"
call "%XSDB%" -eval "set ::XSDB_QUIET 1; set ::XSDB_JSON 1; source {%HERE%/tool.tcl}; %JSON_SCRIPT%" > "%JSON_LOG%" 2>&1
set "JSON_RC=%ERRORLEVEL%"
if exist "%JSON_FILE%" goto JSON_HAS_FILE
call :JSON_EARLY %JSON_CMD% %JSON_OP% "xsdb produced no JSON result" %JSON_KIND%
del /q "%JSON_LOG%" >nul 2>&1
exit /b 1

:JSON_HAS_FILE
for /f "usebackq delims=" %%L in ("%JSON_LOG%") do call :JSON_LOG_LINE "%%L"
type "%JSON_FILE%"
del /q "%JSON_FILE%" "%JSON_LOG%" >nul 2>&1
exit /b %JSON_RC%

:JSON_LOG_LINE
echo %~1| findstr /b /c:"VIVADO_LAB_REG_JSON " >nul
if errorlevel 1 echo %~1 1>&2
exit /b 0

:JSON_EARLY
set "JC=%~1"
set "JO=%~2"
set "JE=%~3"
set "JK=%~4"
set JE=!JE:"=!
if /i "!JK!"=="targets" (
    echo {"ok":false,"command":"!JC!","operation":"!JO!","error":"!JE!","targets":[]}
    exit /b 0
)
if /i "!JK!"=="verify" (
    echo {"ok":false,"command":"!JC!","operation":"!JO!","error":"!JE!","results":[]}
    exit /b 0
)
echo {"ok":false,"command":"!JC!","operation":"!JO!","error":"!JE!","skipped":false,"reason":null,"target":null,"address":null,"length":null,"data":[],"written":[]}
exit /b 0

:HEX_OK
set "VAL=%~1"
if "!VAL!"=="" exit /b 1
set "TEST=!VAL!"
for %%C in (0 1 2 3 4 5 6 7 8 9 A B C D E F a b c d e f x X _) do set "TEST=!TEST:%%C=!"
if not "!TEST!"=="" exit /b 1
exit /b 0

:LEN_OK
set "VAL=%~1"
if "!VAL!"=="" exit /b 1
set "TEST=!VAL!"
for %%C in (0 1 2 3 4 5 6 7 8 9) do set "TEST=!TEST:%%C=!"
if not "!TEST!"=="" exit /b 1
set "NZ=!VAL!"
:LEN_STRIP
if "!NZ!"=="" exit /b 1
if "!NZ:~0,1!"=="0" (
    set "NZ=!NZ:~1!"
    goto LEN_STRIP
)
exit /b 0

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
REM Optional extra install roots. The documented example is C:\Xilinx\Vivado_Lab.
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
