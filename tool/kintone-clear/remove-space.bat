@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo égópñ@: remove-space.bat <MinSpaceId> [MaxSpaceId]
    echo MaxSpaceId Çè»ó™ÇµÇΩèÍçáÇÕ MinSpaceId + 100 Ç…Ç»ÇËÇ‹Ç∑
    exit /b 1
)

set "MIN=%~1"

if "%~2"=="" (
    for /f %%A in ('powershell -Command "%~1+100"') do set "MAX=%%A"
) else (
    set "MAX=%~2"
)

set "SCRIPT_DIR=%~dp0"
set "PS_FILE=%SCRIPT_DIR%remove-space.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "!PS_FILE!" !MIN! !MAX!
exit /b %ERRORLEVEL%