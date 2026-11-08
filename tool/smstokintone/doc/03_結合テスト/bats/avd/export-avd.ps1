param(
    [string]$Avd = "Pixel_6",
    [string]$Device = "emulator-5554",
    [string]$OutFile
)
$avdHome = Join-Path $env:USERPROFILE ".android\avd"
$avdDir = Join-Path $avdHome "$Avd.avd"
$avdIni = Join-Path $avdHome "$Avd.ini"
if (!(Test-Path -LiteralPath $avdDir) -or !(Test-Path -LiteralPath $avdIni)) {
    Write-Host "AVD が見つかりません: $Avd"
    exit 1
}
if (!$OutFile) {
    $OutFile = Join-Path $PSScriptRoot "..\..\avd-export\$Avd.zip"
}
New-Item -ItemType Directory -Path (Split-Path $OutFile -Parent) -Force | Out-Null

& adb -s $Device emu kill 2>$null | Out-Null
Start-Sleep -Seconds 5
Get-Process -Name qemu-system-x86_64,emulator -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
Compress-Archive -LiteralPath @($avdDir, $avdIni) -DestinationPath $OutFile -Force
Write-Host "エクスポートしました: $OutFile"
exit 0
