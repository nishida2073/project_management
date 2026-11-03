param([string]$Device = "emulator-5554")
$root = Join-Path $PSScriptRoot "..\test-data"
$files = Get-ChildItem -LiteralPath (Join-Path $root "setup"), (Join-Path $root "import") -Filter *.json
foreach ($f in $files) { & adb -s $Device push $f.FullName ("/sdcard/Download/" + $f.Name) | Out-Host }
& adb -s $Device shell ls /sdcard/Download/ | Out-Host
