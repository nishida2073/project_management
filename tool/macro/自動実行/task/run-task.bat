@echo off
chcp 932 >nul
setlocal

schtasks /Run /TN "run-import-task"
if errorlevel 1 (
    echo タスクの実行開始に失敗しました。
    pause
    exit /b 1
)

echo タスク「run-import-task」の実行を開始しました。
echo バックグラウンドで実行されるため、完了はlogsフォルダのログで確認してください。
pause
endlocal
