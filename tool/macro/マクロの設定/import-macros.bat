@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%import-macros.ps1" -MacroDir "%SCRIPT_DIR%..\macros" -XlsmDir "%SCRIPT_DIR%.." %*
endlocal
