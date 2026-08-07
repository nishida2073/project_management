@echo off

cd /d %~dp0

set "BATCH_NAME=%~nx0"
echo ==================================================
echo %BATCH_NAME% 開始：%date% %time%
echo ==================================================

call set-env.bat

rem 引数で対象/除外シートを指定する場合（順不同、片方だけの指定も可）:
rem   generate-package.bat "include=対象シート1,対象シート2"
rem   generate-package.bat "exclude=除外シート1,除外シート2"
rem   generate-package.bat "include=対象シート1" "exclude=除外シート1"
:parse_args
if "%~1"=="" goto args_done
set "arg=%~1"
if /i "%arg:~0,8%"=="include=" set "GENERATE_SHEETS_INCLUDE=%arg:~8%"
if /i "%arg:~0,8%"=="exclude=" set "GENERATE_SHEETS_EXCLUDE=%arg:~8%"
shift
goto parse_args
:args_done

powershell.exe ^
 -ExecutionPolicy Bypass ^
 -File .\scripts\generate-package.ps1
set "EXITCODE=%ERRORLEVEL%"

echo 5秒後に自動的に閉じます...
timeout /t 5 >nul

exit /b %EXITCODE%
