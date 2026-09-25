@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "TargetGroupNameFilter="

for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" set "arg=!arg:~1!"
    for /f "tokens=1,* delims=:" %%K in ("!arg!") do (
        set "%%K=%%~L"
    )
)

set "SCRIPT_PATH=%~dp0sync-kintone-to-sheet.ps1"
set "ConfigFile=%~dp0sync-kintone-to-sheet.json"

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

for %%F in ("%ClientDataRootDir%\%TargetGroupNameFilter%*.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF]"

    call "%~dp0resolve-env-file.bat" "%%~nF"
    if exist "!envFile!" (
        call "!envFile!"

        for %%A in (%*) do (
            set "arg=%%~A"
            if "!arg:~0,1!"=="-" set "arg=!arg:~1!"
            for /f "tokens=1,* delims=:" %%K in ("!arg!") do (
                set "%%K=%%~L"
            )
        )

        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
        set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_.failed"
        if exist "!ERROR_FLAG!" del /f /q "!ERROR_FLAG!"

        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "try {" ^
          "  & '%SCRIPT_PATH%'" ^
          "     -BaseUrl '!BaseUrl!'" ^
          "     -TargetGroupName '%%~nF'" ^
          "     -KintoneLoginName '!KintoneLoginName!'" ^
          "     -KintonePassword '!KintonePassword!'" ^
          "     -Authorization '!Authorization!'" ^
          "     -AppId '!SyncUserMasterAppId!'" ^
          "     -ExcelFilePath '%%F'" ^
          "     -SheetName '!SyncUserMasterSheetName!'" ^
          "     -ConfigPath '%ConfigFile%'" ^
          "     -LogNamePrefix '%~n0'" ^
          "} catch {" ^
          "  New-Item -Path '!ERROR_FLAG!' -ItemType File -Force | Out-Null;" ^
          "  throw" ^
          "} finally {" ^
          "  Remove-Item -Path '!JOB_FLAG!' -Force" ^
          "}"

    ) else (
        call "%~dp0message.bat" "設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%~nF]"
)

call "%~dp0message.bat" "Waiting Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%ClientDataRootDir%\%TargetGroupNameFilter%*.xlsx") do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"

set "HAS_ERROR=0"
for %%F in ("%ClientDataRootDir%\%TargetGroupNameFilter%*.xlsx") do (
    set "ERROR_FLAG=%TEMP%\%MyName%%%~nF_.failed"
    if exist "!ERROR_FLAG!" (
        set "HAS_ERROR=1"
        call "%~dp0message.bat" "Failed %MyName% [%%~nF]" "Red"
        del /f /q "!ERROR_FLAG!"
    )
)
if !HAS_ERROR! EQU 1 exit /b 1