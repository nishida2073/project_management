@echo off
chcp 932 >nul
setlocal

cd /d "%~dp0"

echo ============================================
echo  端末へインストールします (adb install)
echo ============================================

where adb >nul 2>nul
if errorlevel 1 (
    echo [エラー] adb コマンドが見つかりません。Android SDK Platform-Tools をインストールし、PATH に追加してください。
    pause
    exit /b 1
)

set "APK_SRC=s2k.apk"
if not exist "%APK_SRC%" (
    echo [エラー] APKが見つかりません: %APK_SRC%
    echo 先に build_apk.bat を実行してビルドしてください。
    pause
    exit /b 1
)

rem 引数が指定されていれば、その端末を使用
if not "%~1"=="" (
    set "DEVICE_ID=%~1"
) else (
    rem 引数がなければ、接続されている最初の端末を使用
    for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
        if "%%B"=="device" (
            set "DEVICE_ID=%%A"
            goto :FOUND_DEVICE
        )
    )
)

:FOUND_DEVICE

if not defined DEVICE_ID (
    echo [エラー] 接続されている端末が見つかりません。
    echo.
    adb devices
    echo.
    pause
    exit /b 1
)

echo.
echo 端末ID: %DEVICE_ID%
echo.

adb -s "%DEVICE_ID%" install -r "%APK_SRC%"
if errorlevel 1 (
    echo.
    echo [エラー] インストールに失敗しました。
    echo 端末ID: %DEVICE_ID%
    pause
    exit /b 1
)

echo.
echo ============================================
echo  インストールが完了しました。
echo ============================================

timeout /t 5 /nobreak >nul
endlocal