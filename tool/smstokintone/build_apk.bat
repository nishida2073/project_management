@echo off
chcp 932 >nul
setlocal

cd /d "%~dp0"

rem 出力先ディレクトリの決定 (優先順位: 第1引数 > 環境変数 OUTPUT_DIR > 既定はバッチ自身のフォルダ)
set "OUT_DIR=%~1"
if not defined OUT_DIR set "OUT_DIR=%OUTPUT_DIR%"
if not defined OUT_DIR set "OUT_DIR=%~dp0"
if "%OUT_DIR:~-1%"=="\" set "OUT_DIR=%OUT_DIR:~0,-1%"

echo ============================================
echo  APKファイルを作成します (assembleDebug)
echo ============================================

where gradle >nul 2>nul
if errorlevel 1 (
    echo [エラー] gradle コマンドが見つかりません。Gradle をインストールし、PATH に追加してください。
    pause
    exit /b 1
)

call gradle assembleDebug
if errorlevel 1 (
    echo.
    echo [エラー] ビルドに失敗しました。
    pause
    exit /b 1
)

set "APK_SRC=app\build\outputs\apk\debug\s2k.apk"

if not exist "%OUT_DIR%" (
    mkdir "%OUT_DIR%"
)
copy /y "%APK_SRC%" "%OUT_DIR%\" >nul
if errorlevel 1 (
    echo.
    echo [エラー] APKのコピーに失敗しました。出力先: %OUT_DIR%
    pause
    exit /b 1
)
set "APK_SRC=%OUT_DIR%\s2k.apk"

echo.
echo ============================================
echo  ビルドに成功しました。
echo  APK: %APK_SRC%
echo ============================================

timeout /t 5 /nobreak >nul
endlocal
