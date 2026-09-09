@echo off
chcp 932 >nul
setlocal enabledelayedexpansion

cd /d "%~dp0"

rem 使い方: mirror_device.bat [IPアドレス:ポート | 端末のシリアル番号]
rem 第1引数が「IPアドレス:ポート」の形式なら adb connect で接続してから、
rem 端末のシリアル番号の決定 (優先順位: 第1引数（シリアル指定時） > 環境変数 ADB_DEVICE_SERIAL > 接続端末が1台のみの場合は自動選択) に進む。
rem 初回のペア設定（ペア設定コードの入力）はワイヤレスデバッグの画面を見ながら別途 adb pair で行う必要がある。

where adb >nul 2>nul
if errorlevel 1 (
    echo [エラー] adb コマンドが見つかりません。Android SDK Platform Tools を PATH に追加してください。
    pause
    exit /b 1
)

set "SCRCPY_EXE="
where scrcpy >nul 2>nul
if not errorlevel 1 set "SCRCPY_EXE=scrcpy"

if not defined SCRCPY_EXE (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Genymobile.scrcpy_*") do (
        for /d %%V in ("%%D\scrcpy-win64-v*") do (
            if exist "%%V\scrcpy.exe" set "SCRCPY_EXE=%%V\scrcpy.exe"
        )
    )
)

if not defined SCRCPY_EXE (
    echo [エラー] scrcpy が見つかりません。次のコマンドでインストールしてください。
    echo   winget install --id Genymobile.scrcpy -e
    pause
    exit /b 1
)

set "CONNECT_TARGET=%~1"
set "DEVICE_SERIAL="
if defined CONNECT_TARGET (
    echo %CONNECT_TARGET% | findstr /c:":" >nul
    if not errorlevel 1 (
        echo ============================================
        echo  端末に接続します: %CONNECT_TARGET%
        echo ============================================
        set "CONNECT_OK=0"
        for /f "delims=" %%R in ('adb connect "%CONNECT_TARGET%" 2^>^&1') do (
            echo %%R
            echo %%R | findstr /I /c:"connected to" >nul
            if not errorlevel 1 set "CONNECT_OK=1"
        )
        rem adb connectは接続に失敗してもerrorlevelが0のままになることがあるため、
        rem 出力メッセージ自体（成功時は必ず"connected to"を含む）で成否を判定する
        if "!CONNECT_OK!"=="0" (
            echo [エラー] 接続に失敗しました。ワイヤレスデバッグの画面のIPアドレスとポートを確認してください。
            echo.
            echo 初回のペア設定がまだの場合は、次の手順が必要です:
            echo   1. スマホの「ワイヤレスデバッグ」画面で「ペア設定コードによるデバイスのペア設定」を開く
            echo      （この画面には接続用とは別のIPアドレス:ポートと、6桁のペア設定コードが表示される）
            echo   2. 次のコマンドを実行する（アドレスは画面の値に置き換える）
            echo        adb pair ペア設定画面のIPアドレス:ポート
            echo   3. 表示された6桁のコードを入力してEnter
            echo      「Successfully paired to ...」と出れば成功
            echo   4. ワイヤレスデバッグのメイン画面（ペア設定画面ではない方）に表示される
            echo      接続用のIPアドレス:ポートで、このバッチを再実行する
            echo.
            echo   ※ペア設定コードは数秒で切り替わるため、表示されている最新の値を使うこと
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
            echo ワイヤレス接続がまだの場合は、このバッチにIPアドレス:ポートを引数で指定して実行してください
            echo （初回のペア設定手順は、その場合に表示されるエラーメッセージを参照）。
            pause
            exit /b 1
        )
        if not "!DEVICE_COUNT!"=="1" (
            echo [エラー] 複数の端末が接続されています。第1引数に端末のシリアル番号を指定してください。
            adb devices
            pause
            exit /b 1
        )
    )
)

echo ============================================
echo  端末の画面をミラーリングします
echo  端末: !DEVICE_SERIAL!
echo ============================================

start "" "!SCRCPY_EXE!" -s "!DEVICE_SERIAL!"

timeout /t 3 /nobreak >nul
endlocal
