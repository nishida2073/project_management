@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\..\ui-test\spec-to-excel.ps1" -SpecPath "%~dp0..\*.md" -Zoom 80 -ColumnWidths "通番=8,入力値=50,操作=50,期待値=50,参照=30" -LineBreakColumns "入力値,期待値,参照"
