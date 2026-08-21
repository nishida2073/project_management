@echo off
chcp 932 >nul
setlocal enabledelayedexpansion

cd /d "%~dp0"

rem 使い方: take_screenshot.bat [出力先ディレクトリ] [IPアドレス:ポート | 端末のシリアル番号]
rem 第2引数が「IPアドレス:ポート」の形式なら adb connect で接続してから端末を自動選択する。
rem 初回のペア設定（ペア設定コードの入力）はワイヤレスデバッグの画面を見ながら別途 adb pair で行う必要がある。
rem 出力先ディレクトリの決定 (優先順位: 第1引数 > 環境変数 SCREENSHOT_OUTPUT_DIR > docs\screenshots)
set "OUT_DIR=%~1"
if not defined OUT_DIR set "OUT_DIR=%SCREENSHOT_OUTPUT_DIR%"
if not defined OUT_DIR set "OUT_DIR=%~dp0screenshots"
if "%OUT_DIR:~-1%"=="\" set "OUT_DIR=%OUT_DIR:~0,-1%"

echo ============================================
echo  実機のスクリーンショットを取得します
echo ============================================

where adb >nul 2>nul
if errorlevel 1 (
    echo [エラー] adb コマンドが見つかりません。Android SDK Platform Tools を PATH に追加してください。
    pause
    exit /b 1
)

rem 端末のシリアル番号の決定 (優先順位: 第2引数（シリアル指定時） > 環境変数 ADB_DEVICE_SERIAL > 接続端末が1台のみの場合は自動選択)
set "CONNECT_TARGET=%~2"
set "DEVICE_SERIAL="
if defined CONNECT_TARGET (
    echo %CONNECT_TARGET% | findstr /c:":" >nul
    if not errorlevel 1 (
        echo 端末に接続します: %CONNECT_TARGET%
        adb connect "%CONNECT_TARGET%"
        if errorlevel 1 (
            echo [エラー] 接続に失敗しました。ワイヤレスデバッグの画面のIPアドレスとポートを確認してください。
            echo 初回のペア設定が済んでいない場合は、先に adb pair での実行が必要です。
            pause
            exit /b 1
        )
    ) else (
        set "DEVICE_SERIAL=%CONNECT_TARGET%"
    )
)
if not defined DEVICE_SERIAL set "DEVICE_SERIAL=%ADB_DEVICE_SERIAL%"

if not defined DEVICE_SERIAL (
    rem ワイヤレスデバッグはmDNS用のシリアル（末尾が_tcp）とIP:PORTの両方で
    rem 同じ端末が二重に列挙されることがあるため、mDNS側の安定した識別子を優先する
    set "TCP_SERIAL="
    set "DEVICE_COUNT=0"
    for /f "skip=1 tokens=1,2" %%A in ('adb devices') do (
        if "%%B"=="device" (
            echo %%A | findstr /c:"_tcp" >nul
            if not errorlevel 1 (
                if not defined TCP_SERIAL set "TCP_SERIAL=%%A"
            ) else (
                set /a DEVICE_COUNT+=1
                set "DEVICE_SERIAL=%%A"
            )
        )
    )
    if defined TCP_SERIAL (
        set "DEVICE_SERIAL=!TCP_SERIAL!"
    ) else (
        if "!DEVICE_COUNT!"=="0" (
            echo [エラー] 接続されている端末が見つかりません。adb devices で接続状態を確認してください。
            pause
            exit /b 1
        )
        if not "!DEVICE_COUNT!"=="1" (
            echo [エラー] 複数の端末が接続されています。第2引数に端末のシリアル番号を指定してください。
            adb devices
            pause
            exit /b 1
        )
    )
)

for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%T"

if not exist "%OUT_DIR%" (
    mkdir "%OUT_DIR%"
)
set "SCREENSHOT_FILE=%OUT_DIR%\screenshot_!TS!.png"

adb -s "!DEVICE_SERIAL!" exec-out screencap -p > "!SCREENSHOT_FILE!"
if errorlevel 1 (
    echo.
    echo [エラー] スクリーンショットの取得に失敗しました。
    pause
    exit /b 1
)

echo.
echo ============================================
echo  取得に成功しました。
echo  端末: !DEVICE_SERIAL!
echo  保存先: !SCREENSHOT_FILE!
echo ============================================

timeout /t 5 /nobreak >nul
endlocal
