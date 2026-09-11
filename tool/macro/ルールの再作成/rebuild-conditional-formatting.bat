@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%rebuild-conditional-formatting.ps1" -XlsmPath "%SCRIPT_DIR%..\å¥âøä«óùÉVÅ[Ég.xlsm"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%rebuild-conditional-formatting.ps1" -XlsmPath "%~1"
)
endlocal
