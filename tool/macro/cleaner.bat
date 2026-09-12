@echo off
chcp 932 >nul
setlocal
set "SCRIPT_DIR=%~dp0"

if "%~1"=="" (
    call "%SCRIPT_DIR%ルールの再作成\rebuild-conditional-formatting.bat"
) else (
    call "%SCRIPT_DIR%ルールの再作成\rebuild-conditional-formatting.bat" "%~1"
)
if errorlevel 1 (
    echo ルールの再作成でエラーが発生しました。処理を中止します。
    exit /b 1
)

if "%~1"=="" (
    call "%SCRIPT_DIR%重複の除去\remove-duplicate-rows.bat"
) else (
    call "%SCRIPT_DIR%重複の除去\remove-duplicate-rows.bat" "%~1"
)
if errorlevel 1 (
    echo 重複の除去でエラーが発生しました。
    exit /b 1
)

endlocal
