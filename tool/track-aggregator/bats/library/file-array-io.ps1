function Export-ArrayToFile {
    param(
        [Parameter(Mandatory)]
        [array]$Datas,
        [Parameter(Mandatory)]
        [string]$OutputFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    $Datas = Convert-BreakLine $Datas
    $lines = foreach ($row in $Datas) {
        if ($row -isnot [array]) {
            $row = @($row)
        }
        ($row | ForEach-Object {
            if ($null -eq $_) { "" } else { $_ }
        }) -join "`t"
    }
    $content = $lines -join "`r`n"
    $dir = Split-Path $OutputFilePath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    Set-Content -Path $OutputFilePath -Value $content
    Write-Message $OutputFilePath -VarName "OutputFilePath" -Type "Info"
}

function Read-FileToArray {
    param(
        [Parameter(Mandatory)]
        [string]$ReadFilePath
    )
    $lines = Get-Content -Path $ReadFilePath
    if ($lines.Count -lt 2) { return @() }
    $result = @()
    for ($r = 0; $r -lt $lines.Count; $r++) {
        $values = $lines[$r] -split "`t"
        $values = Restore-BreakLine $values
        $result += ,$values
    }
    return ,$result
}

function Transpose-Array {
    param(
        [object[][]]$data
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $rowCount = $data.Count
    $colCount = $data[0].Count
    $result = @()
    for ($c = 0; $c -lt $colCount; $c++) {
        $newRow = @()
        for ($r = 0; $r -lt $rowCount; $r++) {
            $newRow += $data[$r][$c]
        }
        $result += ,$newRow
    }
    return $result
}

function Convert-TsvPsObject {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    return Import-Csv -Path $Path -Delimiter "`t" -Encoding Default
}
