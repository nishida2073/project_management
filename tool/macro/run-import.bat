@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-import.ps1" -DataDir "%SCRIPT_DIR%é¿ê—ÉfÅ[É^" -LogDir "%SCRIPT_DIR%logs" %*
endlocal
