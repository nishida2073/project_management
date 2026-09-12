@echo off
chcp 932 >nul
setlocal
set "SCRIPT_DIR=%~dp0"

if "%~1"=="" (
    call "%SCRIPT_DIR%マクロの設定\import-macros.bat"
) else (
    call "%SCRIPT_DIR%マクロの設定\import-macros.bat" "%~1"
)

endlocal
