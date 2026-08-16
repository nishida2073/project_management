@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "SCRIPT_PATH=%~dp0check-download-status.ps1"

call "%~dp0message.bat" "Start %MyName%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "& '%SCRIPT_PATH%'" ^
  "   -MasterDataRootDir '%MasterDataRootDir%'" ^
  "   -TestResultRootDir '%TestResultRootDir%'" ^
  "   -SurveyResultRootDir '%SurveyResultRootDir%'"

call "%~dp0message.bat" "Finished %MyName%"