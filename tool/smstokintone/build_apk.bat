@echo off
chcp 932 >nul
setlocal

cd /d "%~dp0"

rem 出力先ディレクトリの決定 (優先順位: 第1引数 > 環境変数 OUTPUT_DIR > 既定のバッチルートのフォルダ)
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

rem Google DriveのマルウェアスキャンでAPKがブロックされ配布できない事象への対応として、
rem パスワード付きZIPも合わせて作成する (7-Zipが見つからない場合はこの手順のみスキップする)
set "SEVEN_ZIP="
set "PF86=%ProgramFiles(x86)%"
where 7z >nul 2>nul
if not errorlevel 1 set "SEVEN_ZIP=7z"
if not defined SEVEN_ZIP if exist "C:\kenshu\software\7-Zip\7z.exe" set "SEVEN_ZIP=C:\kenshu\software\7-Zip\7z.exe"
if not defined SEVEN_ZIP if exist "%ProgramFiles%\7-Zip\7z.exe" set "SEVEN_ZIP=%ProgramFiles%\7-Zip\7z.exe"
if not defined SEVEN_ZIP if exist "%PF86%\7-Zip\7z.exe" set "SEVEN_ZIP=%PF86%\7-Zip\7z.exe"
if not defined SEVEN_ZIP goto skip_zip

if not defined ZIP_PASSWORD set "ZIP_PASSWORD=abc"
set "ZIP_DEST=%OUT_DIR%\s2k.zip"
"%SEVEN_ZIP%" a -tzip -p%ZIP_PASSWORD% -mem=AES256 -y "%ZIP_DEST%" "%APK_SRC%" >nul
if errorlevel 1 goto zip_failed

echo.
echo ============================================
echo  配布用ZIPを作成しました (パスワード付き)
echo  ZIP: %ZIP_DEST%
echo  パスワード: %ZIP_PASSWORD%
echo  ※Google Driveのマルウェアスキャン回避のため、配布はこちらのZIPを使ってください
echo ============================================
goto after_zip

:zip_failed
echo.
echo [警告] 配布用ZIPの作成に失敗しました。
goto after_zip

:skip_zip
echo.
echo [警告] 7-Zipが見つからないため、配布用ZIPの作成をスキップしました。

:after_zip

timeout /t 5 /nobreak >nul
endlocal
