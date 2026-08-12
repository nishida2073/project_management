@echo off

set "TARGET_BAT=%~dp0starter-auto.bat"
set "SHORTCUT_NAME=starter-auto.bat.lnk"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

powershell -NoProfile -ExecutionPolicy Bypass ^
 "Unblock-File -Path '%TARGET_BAT%'"

powershell -NoProfile -ExecutionPolicy Bypass ^
 "$s=(New-Object -COM WScript.Shell).CreateShortcut('%STARTUP%\%SHORTCUT_NAME%');" ^
 "$s.TargetPath='%TARGET_BAT%';" ^
 "$s.WorkingDirectory='%~dp0';" ^
 "$s.Save()"

powershell -NoProfile -ExecutionPolicy Bypass ^
 "Unblock-File -Path '%STARTUP%\%SHORTCUT_NAME%'"
 

echo スタートアップに%TARGET_BAT%のショートカットを作成しました
pause