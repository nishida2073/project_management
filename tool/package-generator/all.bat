@echo off

cd /d %~dp0

call set-env.bat

if "%DOWNLOAD_ENABLED%"=="1" (
    call download-folder.bat
    if errorlevel 1 goto :error
)

if "%GENERATE_ENABLED%"=="1" (
    call generate-package.bat
    if errorlevel 1 goto :error
)

if "%UPLOAD_ENABLED%"=="1" (
    call upload-folder.bat
    if errorlevel 1 goto :error
)

goto :eof

:error
echo.
echo ˆ—‚ª¸”s‚µ‚½‚½‚ß’†’f‚µ‚Ü‚µ‚½B
exit /b 1

