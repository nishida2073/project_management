@echo off
chcp 932 >nul
setlocal
set "SCRIPT_DIR=%~dp0"

schtasks /Create /XML "%SCRIPT_DIR%run-import-task.xml" /TN "run-import-task" /F
if errorlevel 1 (
    echo タスクの登録に失敗しました。
    pause
    exit /b 1
)

echo タスク「run-import-task」を登録しました。
echo タスクスケジューラで「トリガー」タブから実行時刻・頻度を確認・編集してください（既定では毎日12:00）。
pause
endlocal
