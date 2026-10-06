param(
    [string]$SourceRootDir,
    [string]$TargetGroupName,
    [string]$TargetDate,
    [string]$CollectDataDefsPath,
    [string]$CollectRootDir,
    [string]$SourceTypeFileNameMap,
    [string]$LogNamePrefix
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "${LogNamePrefix}-$TargetGroupName-$TargetDate"

function Combine-ArrayHorizontal {
    param(
        [Parameter(Mandatory)]
        [array[]]$Arrays
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $maxRows = ($Arrays | ForEach-Object {
            if ($_ -is [array] -and $_.Count -gt 0 -and $_[0] -is [array]) {
                $_.Count
            }
            else {
                1
            }
        } | Measure-Object -Maximum).Maximum
    $result = [System.Collections.Generic.List[object]]::new($maxRows)
    for ($r = 0; $r -lt $maxRows; $r++) {
        $row = @()
        foreach ($arr in $Arrays) {
            if ($arr -isnot [array]) {
                $row += $arr
                continue
            }
            if ($arr.Count -gt 0 -and $arr[0] -is [array]) {
                if ($r -lt $arr.Count) {
                    $row += $arr[$r]
                }
            }
            else {
                if ($r -eq 0) {
                    $row += $arr
                }
            }
        }
        $result.Add($row)
    }
    return , $result.ToArray()
}

function Read-SourseDataDefsFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$SourceRootDir,
        [Parameter(Mandatory)]
        [string]$TargetGroupName,
        [Parameter(Mandatory)]
        [hashtable]$FileKeyMap
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $json = Get-Content -Path $FilePath -Encoding UTF8 | ConvertFrom-Json
    $json = @($json)

    $sourseDataProps = @()
    $lastSourceType = $null

    foreach ($item in $json) {
        $sourceType = $item.type
        $sourceTypeKey = "SourceType_$sourceType"
        $sourceTypeValue = if ($FileKeyMap.ContainsKey($sourceTypeKey)) { $FileKeyMap[$sourceTypeKey] } else { $sourceType }

        if ($sourceType -ne $lastSourceType) {
            $sourseDataProps += [PSCustomObject]@{
                filePath   = Join-Path $SourceRootDir "$TargetGroupName-$sourceTypeValue.txt"
                columnDefs = @()
            }
            $lastSourceType = $sourceType
        }

        $sourseDataProps[-1].columnDefs += [PSCustomObject]@{
            OrgName = $item.orgName
            NewName = $item.newName
        }
    }

    return $sourseDataProps
}

function Export-Datas {
    param(
        [string]$SourceRootDir,
        [string]$TargetGroupName,
        [string]$TargetDate,
        [array]$SourseDataProps,
        [string]$CollectDirPath,
        [string]$CollectFileName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allHeaderDatas = @()
    $allBodyDatas = @()

    foreach ($sourceDataProp in $SourseDataProps) {
        $sourceFilePath = $sourceDataProp.filePath
        $columnDefs = $sourceDataProp.columnDefs
        $range = Read-FileToArray $sourceFilePath
        $headerRow = $range[0]

        $columnIndexes = @($columnDefs | ForEach-Object {
                $index = [array]::IndexOf($headerRow, $_.OrgName)
                if ($index -lt 0) {
                    throw "列が見つかりません: $($_.OrgName) (ファイル: $sourceFilePath)"
                }
                $index
            })

        $headerDatas = @()
        foreach ($def in $columnDefs) {
            $headerName = if (-not [string]::IsNullOrWhiteSpace($def.NewName)) {
                $def.NewName
            }
            else {
                $def.OrgName
            }
            $headerDatas += , $headerName
        }
        $allHeaderDatas += , $headerDatas
        $bodyDatas = [System.Collections.Generic.List[object]]::new($range.Count)
        for ($r = 1; $r -lt $range.Count; $r++) {
            $rowData = @()
            foreach ($columnIndex in $columnIndexes) {
                $val = if ($columnIndex -lt 0) { $null } else { $range[$r][$columnIndex] }
                $rowData += $val
            }
            $bodyDatas.Add($rowData)
        }
        $allBodyDatas += , $bodyDatas.ToArray()
    }
    
    $allHeaderDatas = Combine-ArrayHorizontal $allHeaderDatas
    $allBodyDatas = Combine-ArrayHorizontal $allBodyDatas
    
    $allDatas = @()
    $allDatas += $allHeaderDatas
    $allDatas += $allBodyDatas
    
    $collectFilePath = Join-Path -Path $CollectDirPath -ChildPath $CollectFileName
    Export-ArrayToFile $allDatas $collectFilePath
}

$psParams = $PSBoundParameters

try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            New-Item -Path $CollectRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

            $hasFiles = @(Get-ChildItem -Path (Join-Path $SourceRootDir "$TargetGroupName-*txt") -ErrorAction SilentlyContinue).Count -gt 0
            if (-not $hasFiles) {
                throw "集計対象がありません。日付=$($TargetDate)"
            }

            $fileKeyMap = @{}
            foreach ($pair in ($SourceTypeFileNameMap -split ',' | Where-Object { $_ })) {
                $kv = $pair -split '=', 2
                if ($kv.Count -eq 2) { $fileKeyMap[$kv[0]] = $kv[1] }
            }
            $sourseDataProps = Read-SourseDataDefsFile -FilePath $CollectDataDefsPath -SourceRootDir $SourceRootDir -TargetGroupName $TargetGroupName -FileKeyMap $fileKeyMap

            Write-Message $sourseDataProps -VarName "sourseDataProps" -Type "Info" -ForegroundColor Green

            $collectFileName = "$($TargetGroupName)-$($TargetDate).txt"

            Export-Datas -SourseDataProps $sourseDataProps -CollectDirPath $CollectRootDir -CollectFileName $collectFileName

            Write-MessageComplete "集計結果を出力しました: $(Join-Path $CollectRootDir $collectFileName)"
        }
        catch {
            Write-MessageError "実行エラー: $($error[0])"
        }
    } *>&1 | Tee-Object -FilePath $logFilePath
}
finally {
    ConvertTo-Utf8LogFile -Path $logFilePath
    Write-MessageComplete "ログを出力しました: $logFilePath"
}
if ($error) {
    throw $error
}
