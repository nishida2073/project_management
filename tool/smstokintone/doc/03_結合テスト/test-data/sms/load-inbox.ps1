param([string]$Device, [string]$Json, [int]$DelaySeconds = 90)
& (Join-Path $PSScriptRoot "clear-inbox.ps1") -Device $Device
$items = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json
$sql = New-Object System.Collections.Generic.List[string]
foreach ($m in $items) {
    if (-not $m.receive) {
        $body = [string]$m.body
        if ($m.date -eq "now") { $ms = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() } else { $ms = [DateTimeOffset]::Parse($m.date).ToUnixTimeMilliseconds() }
        $esc = $body.Replace("'", "''")
        $sql.Add("INSERT INTO sms (address, date, date_sent, read, seen, type, body) VALUES ('" + $m.address + "', " + $ms + ", " + $ms + ", 1, 1, 1, '" + $esc + "');")
    }
}
if ($sql.Count -gt 0) {
    $tmp = Join-Path $env:TEMP "load-inbox.sql"
    [IO.File]::WriteAllText($tmp, ($sql -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
    & adb -s $Device push $tmp /data/local/tmp/load-inbox.sql | Out-Host
    & adb -s $Device shell "sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db '.read /data/local/tmp/load-inbox.sql'" | Out-Host
    Remove-Item -LiteralPath $tmp
}
foreach ($m in $items) {
    if ($m.receive -and -not $m.delayed) {
        $arg = ([string]$m.body) -replace "`r?`n", '\n'
        & adb -s $Device emu sms send $m.address $arg | Out-Host
    }
}
$triggered = @($items | Where-Object { $_.receive -and $_.delayed -and $_.triggerActivity })
$seenOther = $false
foreach ($m in $triggered) {
    $deadline = (Get-Date).AddSeconds(300)
    while ((Get-Date) -lt $deadline) {
        $dump = (& adb -s $Device shell "dumpsys activity activities" 2>$null) -join "`n"
        if ($dump -match ("topResumedActivity[^`n]*" + [regex]::Escape($m.triggerActivity))) {
            if ($seenOther) { break }
        } else {
            $seenOther = $true
        }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds ([int]$m.delaySeconds)
    $arg = ([string]$m.body) -replace "`r?`n", '\n'
    & adb -s $Device emu sms send $m.address $arg | Out-Host
}
$delayed = @($items | Where-Object { $_.receive -and $_.delayed -and -not $_.triggerActivity })
if ($delayed.Count -gt 0) {
    $elapsed = 0
    $schedule = foreach ($m in $delayed) { [pscustomobject]@{ At = $(if ($m.delaySeconds) { [int]$m.delaySeconds } else { $DelaySeconds }); Item = $m } }
    foreach ($s in ($schedule | Sort-Object At)) {
        if ($s.At -gt $elapsed) { Start-Sleep -Seconds ($s.At - $elapsed); $elapsed = $s.At }
        $arg = ([string]$s.Item.body) -replace "`r?`n", '\n'
        & adb -s $Device emu sms send $s.Item.address $arg | Out-Host
    }
}
