@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\..\ui-test\spec-to-excel.ps1" -SpecPath "%~dp0..\*.md" -Zoom 70 -ColumnWidths "通番=8,区分=10,入力値=70,操作=70,期待値=70,参照=20,実施結果=12" -LineBreakColumns "入力値,期待値,参照"
