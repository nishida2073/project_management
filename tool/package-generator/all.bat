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
echo ˆ—‚ª¸”s‚µ‚½‚½‚ß’†’f‚µ‚Ü‚µ‚½B
exit /b 1

