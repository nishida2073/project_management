@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Rebuild-ConditionalFormatting.ps1" -XlsmPath "%SCRIPT_DIR%..\å¥âøä«óùÉVÅ[Ég.xlsm" -Range "D5:AH5000" %*
endlocal
