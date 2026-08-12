@echo off
setlocal enabledelayedexpansion

set "MESSAGE=%~1"
set "COLOR=%~2"

if "%COLOR%"=="" (
    set "COLOR=White"
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$color = '%COLOR%'; $msg = '%MESSAGE%'; Write-Host ('============== [' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.ff') + '] ' + $msg + ' ==============') -ForegroundColor $color"