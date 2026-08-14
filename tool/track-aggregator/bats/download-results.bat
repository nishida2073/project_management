@echo off
setlocal enabledelayedexpansion

set "MyName=%~nx0"

call "%~dp0common-env.bat"

set "SCRIPT_PATH=%~dp0download-results.ps1"

set "DownloadDetail=1"

for %%F in ("%MasterDataRootDir%\*.xlsx") do (
    call "%~dp0message.bat" "Start %MyName% [%%~nF]"
    
    call "%~dp0resolve-env-file.bat" "%%~nF"
    if exist "!envFile!" (
        call "!envFile!"
        
        set "JOB_FLAG=%TEMP%\%MyName%%%~nF_.running"
        
        start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "New-Item -Path '!JOB_FLAG!' -ItemType File -Force | Out-Null;" ^
          "& '%SCRIPT_PATH%'" ^
          "   -MasterDataFilePath '%%F'" ^
          "   -AutoHotkeyExePath '%AutoHotkeyExePath%'" ^
          "   -AutoHotkeyScriptPath '%AutoHotkeyScriptPath%'" ^
          "   -TargetGroupName '%%~nF'" ^
          "   -TestResultRootDir '%TestResultRootDir%'" ^
          "   -SurveyResultRootDir '%SurveyResultRootDir%'" ^
          "   -DownloadDetail '%DownloadDetail%';" ^
          "Remove-Item -Path '!JOB_FLAG!' -Force;"
        
    ) else (
        call "%~dp0message.bat" "ŠÂ‹«Ý’èƒtƒ@ƒCƒ‹‚ªŒ©‚Â‚©‚è‚Ü‚¹‚ñ: !envFile!" "Red"
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