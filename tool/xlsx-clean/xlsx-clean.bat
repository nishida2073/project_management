@echo off
setlocal

if "%~1"=="" (
    echo 使い方: xlsx-clean.bat "ブック.xlsx"
    echo   .xlsx ファイルをこのバッチにドラッグ＆ドロップしても実行できます。
    echo   結果は元のファイルと同じフォルダに 名前_clean.xlsx として保存されます。
    pause
    exit /b 1
)


powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0xlsx-clean.ps1" -Path "%~1"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
