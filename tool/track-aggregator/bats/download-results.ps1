param(
    [string]$MasterDataFilePath,
    [string]$AutoHotkeyExePath,
    [string]$AutoHotkeyScriptPath,
    [string]$TargetGroupName,
    [string]$TestResultRootDir,
    [string]$SurveyResultRootDir,
    [int]$DownloadDetail
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

$downloadDetail = if($DownloadDetail -eq 1){ $true } else { $false }

$testDatas = Create-TestDatas -DataFilePath $MasterDataFilePath
$testDatas = @($testDatas | Where-Object { -not (ToBool $_.停止中) })

$surveyDatas = Create-SurveyDatas -DataFilePath $MasterDataFilePath
$surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

Download-TrackResults -AutoHotkeyExePath $AutoHotkeyExePath -AutoHotkeyScriptPath $AutoHotkeyScriptPath -TargetRootDir $TestResultRootDir -TargetGroupName $TargetGroupName -Datas $testDatas -NameProperty "testName" -IsDetail $downloadDetail

Download-TrackResults -AutoHotkeyExePath $AutoHotkeyExePath -AutoHotkeyScriptPath $AutoHotkeyScriptPath -TargetRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -Datas $surveyDatas -NameProperty "surveyName"
