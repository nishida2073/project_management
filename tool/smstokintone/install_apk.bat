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

adb install -r "%APK_SRC%"
if errorlevel 1 (
    echo.
    echo [エラー] インストールに失敗しました（端末が未接続の可能性があります）。
    pause
    exit /b 1
)

echo.
echo ============================================
echo  インストールが完了しました。
echo ============================================

timeout /t 5 /nobreak >nul
endlocal