@echo off
chcp 932 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\..\..\ui-test\spec-to-excel.ps1" -SpecPath "%~dp0..\テスト仕様書.md" -Zoom 70 -ColumnWidths "通番=8,区分=10,入力値=70,操作=70,期待値=70,参照=20,実施結果=12,内容=70,意味=70,事前条件=70" -LineBreakColumns "事前条件,入力値,期待値,参照"
