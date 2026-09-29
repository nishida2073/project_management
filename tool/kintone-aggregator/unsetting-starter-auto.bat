@echo off

set "SHORTCUT_NAME=starter-auto.bat.lnk"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

if exist "%STARTUP%\%SHORTCUT_NAME%" (
    del "%STARTUP%\%SHORTCUT_NAME%"
    echo スタートアップの設定を解除しました
) else (
    echo スタートアップの設定はありません
)

pause