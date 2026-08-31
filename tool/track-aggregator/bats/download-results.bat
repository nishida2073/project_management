@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "TargetGroupNameFilter="

rem コマンドラインから「環境変数名:値」の形式で、common-env.batの設定値を任意に上書きできる
rem （例: TargetGroupNameFilter など、名前は固定していない）
rem 区切りは = ではなく : を使うこと（cmd.exeは = とカンマを引数の区切り文字として扱うため）。
rem 1つだけ指定するならクォート不要。カンマを含む値を指定する場合は引数ごとに "" で囲むこと
for %%A in (%*) do (
    set "arg=%%~A"
    if "!arg:~0,1!"=="-" set "arg=!arg:~1!"
    for /f "tokens=1,* delims=:" %%K in ("!arg!") do (
        set "%%K=%%~L"
    )
)

set "SCRIPT_PATH=%~dp0download-results.ps1"

set "DownloadDetail=1"

for %%F in ("%ClientDataRootDir%\%TargetGroupNameFilter%*.xlsx") do (
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
          "     -ClientDataFilePath '%%F'" ^
          "     -AutoHotkeyExePath '!AutoHotkeyExePath!'" ^
          "     -AutoHotkeyScriptPath '!AutoHotkeyScriptPath!'" ^
          "     -TargetGroupName '%%~nF'" ^
          "     -TestResultRootDir '!TestResultRootDir!'" ^
          "     -SurveyResultRootDir '!SurveyResultRootDir!'" ^
          "     -DownloadDetail '!DownloadDetail!'" ^
          "     -LogNamePrefix '%~n0'" ^
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