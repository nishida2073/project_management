param(
    [string]$MasterDataRootDir,
    [string]$TestResultRootDir,
    [string]$SurveyResultRootDir,
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'check-download-status' })"

function Test-HasResultFiles {
    param(
        [string]$ResultRootDir,
        [string]$TargetGroupName,
        [string]$Name
    )
    # Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    # $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $dir = Join-Path (Join-Path $ResultRootDir $TargetGroupName) $Name
    return @(Get-ChildItem -Path $dir -Filter *.csv -ErrorAction SilentlyContinue).Count -gt 0
}

function Write-DownloadStatusRows {
    param(
        [array]$Datas,
        [string]$NameProperty,
        [string]$ResultRootDir,
        [string]$TargetGroupName,
        [string]$TargetLabel
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    
    Write-Message "■$TargetGroupName - $TargetLabel" -VarName "downloadTarget" -Type "Info" -NoHeader
    foreach ($data in $Datas) {
        $name = $data.$NameProperty
        if (ToBool $data.停止中) {
            Write-Message "$name<$($data.DL)・$($data.停止中)> : 対象外" -VarName "downloadStatus" -Type "Info" -ForegroundColor Gray -NoHeader
            continue
        }
        $isDownloaded = Test-HasResultFiles -ResultRootDir $ResultRootDir -TargetGroupName $TargetGroupName -Name $name
        $status = if ($isDownloaded) { "取得済" } else { "未取得" }
        $color = if ($isDownloaded) { "Green" } else { "Red" }
        Write-Message "$name<$($data.DL)・$($data.停止中)> : $status" -VarName "downloadStatus" -Type "Info" -ForegroundColor $color -NoHeader
    }
}

& {
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    $masterFiles = Get-ChildItem -Path $MasterDataRootDir -Filter *.xlsx

    foreach ($masterFile in $masterFiles) {
        Use-Mutex "Test-File" {
            $targetGroupName = $masterFile.BaseName

            $testDatas = Create-TestDatas -DataFilePath $masterFile.FullName
            $surveyDatas = Create-SurveyDatas -DataFilePath $masterFile.FullName

            Write-DownloadStatusRows -Datas $testDatas -NameProperty "testName" -ResultRootDir $TestResultRootDir -TargetGroupName $targetGroupName -TargetLabel "テスト"
            Write-DownloadStatusRows -Datas $surveyDatas -NameProperty "surveyName" -ResultRootDir $SurveyResultRootDir -TargetGroupName $targetGroupName -TargetLabel "アンケート"
        }
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
