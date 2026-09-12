@echo off
chcp 932 >nul
setlocal
set "SCRIPT_DIR=%~dp0"
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%import-macros.ps1" -XlsmPath "%SCRIPT_DIR%..\å¥âøä«óùÉVÅ[Ég.xlsm" -MacroDir "%SCRIPT_DIR%..\macros" -BackupDir "%SCRIPT_DIR%backup"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%import-macros.ps1" -XlsmPath "%~1" -MacroDir "%SCRIPT_DIR%..\macros" -BackupDir "%SCRIPT_DIR%backup"
)
endlocal
