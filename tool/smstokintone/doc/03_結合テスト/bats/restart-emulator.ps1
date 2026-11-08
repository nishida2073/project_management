param([string]$Avd = "Pixel_6", [string]$Device = "emulator-5554")
& adb -s $Device emu kill | Out-Null
Start-Sleep -Seconds 5
Get-Process -Name qemu-system-x86_64,emulator -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Start-Process "C:\Android\emulator\emulator.exe" -ArgumentList "-avd",$Avd,"-no-snapshot-load" -RedirectStandardOutput $env:TEMP\emu-out.log -RedirectStandardError $env:TEMP\emu-err.log
& adb kill-server | Out-Null
& adb start-server | Out-Null
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $state = (& adb -s $Device get-state 2>$null) -join ""
    if ($state.Trim() -eq "device") {
        $b = (& adb -s $Device shell getprop sys.boot_completed 2>$null) -join ""
        if ($b.Trim() -eq "1") { & (Join-Path $PSScriptRoot "center-emulator.ps1"); Write-Host "booted"; exit 0 }
    }
    Start-Sleep -Seconds 5
}
Write-Host "boot timeout"; exit 1
