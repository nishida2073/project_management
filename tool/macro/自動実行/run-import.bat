@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-import.ps1" -DataDir "%SCRIPT_DIR%実績データ" -LogDir "%SCRIPT_DIR%logs" -BackupDir "%SCRIPT_DIR%backup" -XlsmPath "%SCRIPT_DIR%..\原価管理シート.xlsm" %*
endlocal
