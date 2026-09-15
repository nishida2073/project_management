[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$cp932 = [System.Text.Encoding]::GetEncoding(932)
$defaultClientLabel = "デフォルト"

function Use-Mutex {
    param(
        [string]$Name = "Global",
        [scriptblock]$Action
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Cyan
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $mutex = [System.Threading.Mutex]::new($false, "Global\$Name")
    try {
        $mutex.WaitOne() | Out-Null
        & $Action
    }
    finally {
        $mutex.ReleaseMutex()
    }
}

function ToBool($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [bool]) { return $value }
    if ($value -is [string]) {
        if ($value -eq "") { return $null }
        switch ($value.ToLower()) {
            "true"  { return $true }
            "false" { return $false }
        }
    }
    return $false
}

$breakLineKeyword = "BRBR"
function Convert-BreakLine {
    param(
        [Parameter(Mandatory)]
        [array]$Datas
    )
    for ($r = 0; $r -lt $Datas.Count; $r++) {
        if ($Datas[$r] -is [array]) {
            for ($c = 0; $c -lt $Datas[$r].Count; $c++) {
                $val = $Datas[$r][$c]
                if ($val -is [string]) {
                    $Datas[$r][$c] = $val -replace "`n", $breakLineKeyword
                }
            }
        }
        else {
            $val = $Datas[$r]
            if ($val -is [string]) {
                $Datas[$r] = $val -replace "`n", $breakLineKeyword
            }
        }
    }
    return $Datas
}


function Restore-BreakLine {
    param(
        [Parameter(Mandatory)]
        [array]$Datas
    )
    for ($r = 0; $r -lt $Datas.Count; $r++) {
        if ($Datas[$r] -is [array]) {
            for ($c = 0; $c -lt $Datas[$r].Count; $c++) {
                $val = $Datas[$r][$c]
                if ($val -is [string]) {
                    $Datas[$r][$c] = $val -replace $breakLineKeyword, "`n"
                }
            }
        }
        else {
            $val = $Datas[$r]
            if ($val -is [string]) {
                $Datas[$r] = $val -replace $breakLineKeyword, "`n"
            }
        }
    }
    return $Datas
}
