@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "SCRIPT_PATH=%~dp0collect-test-result.ps1"

set "OutputTargetDir=%OutputTestCollectDir%"
set "TemplateFilePath=%TemplateRootDir%\テスト結果.xlsx"
set "ShowDetail=1"

for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF]"
    
    call "%~dp0resolve-env-file.bat" "%%~nF"
    if exist "!envFile!" (
        call "!envFile!"
        
        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
        set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_.failed"
        if exist "!ERROR_FLAG!" del /f /q "!ERROR_FLAG!"
        
        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "try {" ^
          "  & '%SCRIPT_PATH%'" ^
          "     -BaseUrl '!BaseUrl!'" ^
          "     -MasterDataFilePath '%%F'" ^
          "     -TargetGroupName '%%~nF'" ^
          "     -OutputRootDir '!OutputTargetDir!'" ^
          "     -ResultRootDir '!TestResultRootDir!'" ^
          "     -TemplateFilePath '!TemplateFilePath!'" ^
          "     -PassScore '!PassScore!'" ^
          "     -ShowDetail '!ShowDetail!'" ^
          "} catch {" ^
          "  New-Item -Path '!ERROR_FLAG!' -ItemType File -Force | Out-Null;" ^
          "  throw" ^
          "} finally {" ^
          "  Remove-Item -Path '!JOB_FLAG!' -Force" ^
          "}"
        
    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%~nF]"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"

set "HAS_ERROR=0"
for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_.failed"
    if exist "!ERROR_FLAG!" (
        set "HAS_ERROR=1"
        call "%~dp0message.bat" "Failed %MyName% [%%~nF]" "Red"
        del /f /q "!ERROR_FLAG!"
    )
)
if !HAS_ERROR! EQU 1 exit /b 1