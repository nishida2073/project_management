param(
    [string]$MasterDataRootDir,
    [string]$TestResultRootDir,
    [string]$SurveyResultRootDir
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

$PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

function Test-HasResultFiles {
    param(
        [string]$ResultRootDir,
        [string]$TargetGroupName,
        [string]$Name
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $dir = Join-Path (Join-Path $ResultRootDir $TargetGroupName) $Name
    return @(Get-ChildItem -Path $dir -Filter *.csv -ErrorAction SilentlyContinue).Count -gt 0
}

$masterFiles = Get-ChildItem -Path $MasterDataRootDir -Filter *.xlsx

foreach ($masterFile in $masterFiles) {
    Use-Mutex "Test-File" {      
        $targetGroupName = $masterFile.BaseName

        $testDatas = Create-TestDatas -DataFilePath $masterFile.FullName
        $surveyDatas = Create-SurveyDatas -DataFilePath $masterFile.FullName

        foreach ($testData in $testDatas) {
            $isDownloaded = Test-HasResultFiles -ResultRootDir $TestResultRootDir -TargetGroupName $targetGroupName -Name $testData.testName
            $status = if ($isDownloaded) { "済" } else { "未" }
            $color = if ($isDownloaded) { "Green" } else { "Red" }
            Write-Message "$targetGroupName / テスト / $($testData.testName) : $status" -VarName "downloadStatus" -Type "Info" -ForegroundColor $color
        }
        
        foreach ($surveyData in $surveyDatas) {
            $isDownloaded = Test-HasResultFiles -ResultRootDir $SurveyResultRootDir -TargetGroupName $targetGroupName -Name $surveyData.surveyName
            $status = if ($isDownloaded) { "済" } else { "未" }
            $color = if ($isDownloaded) { "Green" } else { "Red" }
            Write-Message "$targetGroupName / アンケート / $($surveyData.surveyName) : $status" -VarName "downloadStatus" -Type "Info" -ForegroundColor $color
        }
    }
}
