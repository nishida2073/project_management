@echo off
chcp 932 >nul

pushd "%~dp0"

set "BATCH=all-multiple.bat"

echo ===================================================================================================
echo.
echo - 実行バッチ名
echo   %BATCH%
echo.
echo - 引数の種類 - 
echo   [未入力]          : 前日分を集計
echo   [YYYY-MM-DD]      : 指定日付を集計
echo   [YYYY-MM-DD N]    : 指定日付から複数日を集計（第一引数を含めたN日前まで）
echo   q                 : 終了
echo.
echo - 引数の例
echo   未入力
echo   2026-04-05
echo   2026-04-05 10
echo   q
echo.
echo - 注意事項
echo   * 実行前に対象のExcelファイルが閉じられていることを確認してください。
echo   * 出力フォルダ内の既存ファイルは上書きされます。
echo   * 指定日付は YYYY-MM-DD 形式で入力してください。
echo   * PCのクリップボードを使用しているため、実行中はコピー操作を行わないでください。
echo.
echo ===================================================================================================


echo.
echo 引数を入力し、Enterキーを押してください。（未入力可）

set /p ARGS=

if /i "%ARGS%"=="q" exit /b

echo.
echo 開始: %BATCH% %ARGS%
echo.

call %BATCH% %ARGS%


echo 終了

popd
