@echo off
chcp 932 >nul
setlocal

schtasks /Delete /TN "run-import-task" /F
if errorlevel 1 (
    echo タスクの削除に失敗しました。
    pause
    exit /b 1
)

echo タスク「run-import-task」を削除しました。
pause
endlocal
