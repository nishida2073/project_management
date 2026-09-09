@echo off

set "BATCH=all.bat"

echo ===================================================================================================
echo.
echo - 実行バッチ名
echo   %BATCH%
echo.
echo - 事前準備
echo   * 実行前に、starter-chrome.batでブラウザ（Chrome）を起動し、Trackにログインしてください。
echo.
echo - 注意事項
echo   * PCを自動操作するため、PCには触れないでください。
echo   * 実行前に対象のExcelファイルが閉じられていることを確認してください。
echo   * 出力フォルダ内の既存ファイルは上書きされます。
echo.
echo ===================================================================================================


echo.
echo Enterキーを押してください。

set /p ARGS=

if /i "%ARGS%"=="q" exit /b

echo.
echo 開始: %BATCH%
echo.

call "%~dp0%BATCH%"


echo 終了
