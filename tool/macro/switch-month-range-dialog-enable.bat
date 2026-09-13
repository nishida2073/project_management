@echo off
chcp 932 >nul
if /I "%USE_MONTH_RANGE_DIALOG%"=="TRUE" (
    setx USE_MONTH_RANGE_DIALOG FALSE >nul
    echo 反映月ダイアログを無効にしました。
) else (
    setx USE_MONTH_RANGE_DIALOG TRUE >nul
    echo 反映月ダイアログを有効にしました。
)
echo 開いているExcelがあれば、一度閉じてから開き直してください。
pause
