@echo off

cd /d %~dp0

call SetEnv.bat

if "%DOWNLOAD_ENABLED%"=="1" (
    call DownloadFolder.bat
    if errorlevel 1 goto :error
)

if "%GENERATE_ENABLED%"=="1" (
    call GeneratePackage.bat
    if errorlevel 1 goto :error
)

if "%UPLOAD_ENABLED%"=="1" (
    call UploadFolder.bat
    if errorlevel 1 goto :error
)

goto :eof

:error
echo.
echo 処理が失敗したため中断しました。
exit /b 1

