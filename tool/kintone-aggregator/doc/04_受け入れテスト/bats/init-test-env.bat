@echo off
chcp 932 >nul
set "TEST=%~dp0.."
set "KA=%~dp0..\..\.."
if not exist "%KA%\bats\common.bat" (
    echo NG: kintone-aggregator の場所が違います
    exit /b 1
)
if not exist "%TEST%\test-data\bats\common.bat" (
    echo NG: test-data\bats\common.bat がありません
    exit /b 1
)
if not exist "%TEST%\test-data\clients" (
    echo NG: test-data\clients がありません
    exit /b 1
)
copy /y "%TEST%\test-data\bats\common.bat" "%KA%\bats\common.bat" >nul
if errorlevel 1 (
    echo NG: common.bat をコピーできません
    exit /b 1
)
xcopy "%TEST%\test-data\clients" "%KA%\clients" /e /y /i >nul
if errorlevel 1 (
    echo NG: clients をコピーできません
    exit /b 1
)
if exist "%KA%\output" rmdir /s /q "%KA%\output"
if exist "%KA%\logs" rmdir /s /q "%KA%\logs"
echo OK: テスト環境を初期化しました
exit /b 0
