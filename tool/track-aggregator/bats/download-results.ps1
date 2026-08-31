param(
    [string]$MasterDataFilePath,
    [string]$AutoHotkeyExePath,
    [string]$AutoHotkeyScriptPath,
    [string]$TargetGroupName,
    [string]$TestResultRootDir,
    [string]$SurveyResultRootDir,
    [int]$DownloadDetail,
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'download-results' })-$TargetGroupName"

function Download-File {
    param(
        [string]$Url,
        [string]$OutFileDir,
        [string]$AutoHotkeyExePath,
        [string]$AutoHotkeyScriptPath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    Use-Mutex "Download-File" {
        # 実行前のファイル数
        $beforeCount = @(Get-ChildItem -Path $OutFileDir -File -ErrorAction SilentlyContinue).Count

        $p = Start-Process -FilePath $AutoHotkeyExePath `
                           -ArgumentList @($AutoHotkeyScriptPath, $Url, $OutFileDir) `
                           -PassThru
        $p.WaitForExit()
        $exitCode = [int]$p.ExitCode
        Write-Message $exitCode -VarName "exitCode" -Type "Info"
        if ($exitCode -eq 0) {
            $timeoutSec = 30
            $sw = [Diagnostics.Stopwatch]::StartNew()
            do {
                Start-Sleep -Milliseconds 500
                $afterCount = @(Get-ChildItem -Path $OutFileDir -File -ErrorAction SilentlyContinue).Count
            } while ($afterCount -le $beforeCount -and $sw.Elapsed.TotalSeconds -lt $timeoutSec)

            if ($afterCount -gt $beforeCount) {
                Write-Message "success [$Url]" -VarName "message" -Type "Info" -ForegroundColor Blue
            }
            else {
                Write-Message "timeout waiting file [$Url]" -VarName "message" -Type "Error" -ForegroundColor Red
            }
        }
        else {
            Write-Message "fail [$Url]" -VarName "message" -Type "Error" -ForegroundColor Red
        }
        # Start-Sleep -Milliseconds 500
    }
}


function Download-TrackResults {
    param(
        [string]$AutoHotkeyExePath,
        [string]$AutoHotkeyScriptPath,
        [string]$TargetRootDir,
        [string]$TargetGroupName,
        [array]$Datas,
        [string]$NameProperty,
        [bool]$IsDetail = $false
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    $Datas = @($Datas | Where-Object { ToBool $_.DL })
    Use-Mutex "Make-Dir" {
        foreach($data in $Datas){
            $name = $data.$NameProperty
            $groupDir = Join-Path $TargetRootDir $TargetGroupName
            New-Item -Path $groupDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            $resultDir = Join-Path $groupDir $name
            Remove-Item $resultDir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -Path $resultDir -ItemType Directory | Out-Null
        }
    }

    foreach($data in $Datas){
        $name = $data.$NameProperty
        $groupDir = Join-Path $TargetRootDir $TargetGroupName
        $resultDir = Join-Path $groupDir $name
        $trackID = $data.TrackID
        $trackIds = ($trackID -split "\||\r?\n") | Where-Object { $_ -ne "" }

        foreach($trackId in $trackIds){
            $trackIdParts = $trackId -split "-"
            $classId = $trackIdParts[0]
            $materialId = $trackIdParts[1]
            Write-Message $classId -VarName "classId" -Type "Info"
            Write-Message $materialId -VarName "materialId" -Type "Info"

            if(-not $classId -or -not $materialId){
                Write-Message "Skipping. [$TargetGroupName] [$name]" -VarName "message" -Type "Info" -ForegroundColor Yellow
                continue
            }
            $Url = if( $IsDetail ){
                "https://nttdata-univ.train.tracks.run/api/classes/$ClassId/materials/$MaterialId/results.csv"
            } else {
                "https://nttdata-univ.train.tracks.run/api/classes/$ClassId/results.csv?cmid=$MaterialId"
            }
            Write-Message $Url -VarName "functionName" -Type "Url"

            Download-File `
                -Url $Url `
                -OutFileDir $resultDir `
                -AutoHotkeyExePath $AutoHotkeyExePath `
                -AutoHotkeyScriptPath $AutoHotkeyScriptPath
        }
    }
}


& {
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    $downloadDetail = if($DownloadDetail -eq 1){ $true } else { $false }

    $testDatas = Create-TestDatas -DataFilePath $MasterDataFilePath
    $testDatas = @($testDatas | Where-Object { -not (ToBool $_.停止中) })

    $surveyDatas = Create-SurveyDatas -DataFilePath $MasterDataFilePath
    $surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

    Download-TrackResults -AutoHotkeyExePath $AutoHotkeyExePath -AutoHotkeyScriptPath $AutoHotkeyScriptPath -TargetRootDir $TestResultRootDir -TargetGroupName $TargetGroupName -Datas $testDatas -NameProperty "testName" -IsDetail $downloadDetail

    Download-TrackResults -AutoHotkeyExePath $AutoHotkeyExePath -AutoHotkeyScriptPath $AutoHotkeyScriptPath -TargetRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -Datas $surveyDatas -NameProperty "surveyName"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
