param([string]$Device, [string]$Json, [int]$DelaySeconds = 90)
& (Join-Path $PSScriptRoot "clear-inbox.ps1") -Device $Device
$items = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json
$sql = New-Object System.Collections.Generic.List[string]
foreach ($m in $items) {
    if (-not $m.receive) {
        $body = [string]$m.body
        $ms = [DateTimeOffset]::Parse($m.date).ToUnixTimeMilliseconds()
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
if (@($items | Where-Object { $_.receive -and $_.delayed }).Count -gt 0) {
    Start-Sleep -Seconds $DelaySeconds
    foreach ($m in $items) {
        if ($m.receive -and $m.delayed) {
            $arg = ([string]$m.body) -replace "`r?`n", '\n'
            & adb -s $Device emu sms send $m.address $arg | Out-Host
        }
    }
}
