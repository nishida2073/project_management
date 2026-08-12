@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "SCRIPT_PATH=%~dp0collect-test-result.ps1"

set "MasterDataRootDir=%MasterDataRootDir%"
set "ResultRootDir=%ResultRootDir%\01_テスト"
set "OutputTargetDir=%OutputTestCollectDir%"
set "TemplateFilePath=%TemplateRootDir%\テスト結果.xlsx"
set "PassScore=80"
set "ShowDetail=0"

for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF]"
    
    set "envFile=%MasterDataRootDir%\%%~nF.bat"
    if exist "!envFile!" (
        call "!envFile!"
        
        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
        
        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "& '%SCRIPT_PATH%'" ^
          "   -BaseUrl '!BaseUrl!'" ^
          "   -MasterDataFilePath '%%F'" ^
          "   -AutoHotkeyExePath '%AutoHotkeyExePath%'" ^
          "   -AutoHotkeyScriptPath '%AutoHotkeyScriptPath%'" ^
          "   -TargetGroupName '%%~nF'" ^
          "   -OutputRootDir '%OutputTargetDir%'" ^
          "   -ResultRootDir '!ResultRootDir!'" ^
          "   -TemplateFilePath '!TemplateFilePath!'" ^
          "   -PassScore '%PassScore%'" ^
          "   -ShowDetail '%ShowDetail%';" ^
          "Remove-Item -Path '!JOB_FLAG!' -Force;"
        
    ) else (
        call "%~dp0message.bat" "環境設定ファイルが見つかりません: !envFile!" "Red"
    )
    call "%~dp0message.bat" "Finished %MyName% [%%~nF]"
)

call "%~dp0message.bat" "Start Jobs %MyName% ALL"

:WAIT_LOOP
set "ALL_DONE=1"
for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    set "JOB_FLAG=%TEMP%\%MyName%%%~nF_%TargetDate%.running"
    if exist "!JOB_FLAG!" set "ALL_DONE=0"
)
if !ALL_DONE! EQU 0 (
    timeout /t 1 >nul
    goto WAIT_LOOP
)

call "%~dp0message.bat" "Finished Jobs %MyName% ALL"