Dim shell, scriptDir, cmd
Set shell = CreateObject("WScript.Shell")
scriptDir = Left(WScript.ScriptFullName, Len(WScript.ScriptFullName) - Len(WScript.ScriptName))

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "run-import.ps1"" -DataDir """ & scriptDir & "実績データ"" -LogDir """ & scriptDir & "logs"" -BackupDir """ & scriptDir & "backup"" -XlsmPath """ & scriptDir & "..\原価管理シート.xlsm"""

shell.Run cmd, 0, True
