@echo off

cd /d %~dp0

call SetEnv.bat

rem 引数で対象/除外シートを指定する場合（順不同、片方だけの指定も可）:
rem   GeneratePackage.bat "include=対象シート1,対象シート2"
rem   GeneratePackage.bat "exclude=除外シート1,除外シート2"
rem   GeneratePackage.bat "include=対象シート1" "exclude=除外シート1"
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
 -File .\GeneratePackage.ps1

echo 5秒後に自動的に閉じます...
timeout /t 5 >nul