@echo off
setlocal enabledelayedexpansion

set "MESSAGE=%~1"
set "COLOR=%~2"

if "%COLOR%"=="" (
    set "COLOR=White"
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Import-Module '%~dp0library\common.psm1' -DisableNameChecking; $color = '%COLOR%'; $msg = '%MESSAGE%'; Write-Message ('================ [' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.ff') + '] ' + $msg + ' ================') -Type Info -ForegroundColor $color -NoHeader"