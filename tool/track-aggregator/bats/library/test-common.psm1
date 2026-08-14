function Create-TestDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '通番'   = 'testNo'
        'テスト名'     = 'testName'
    }
    return Create-MasterDatas -DataFilePath $DataFilePath -SheetIndex 2 -HeaderMap $headerMap
}


function Create-TestResultDatas {
    param(
        [string]$TestResultRootDir,
        [string]$TargetGroupName,
        [array]$TestDatas,
        [int]$PassScore
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allResultDatas = @()
    foreach($testData in $TestDatas){
        $testName = $testData.testName
        $testGroupDir = Join-Path $TestResultRootDir $TargetGroupName
        $testResultDir = Join-Path $testGroupDir $testName
        $resultFiles = @(Get-ChildItem $testResultDir -Filter *.csv -ErrorAction SilentlyContinue)
        foreach($resultFile in $resultFiles){
            $csv = Import-Csv $resultFile.FullName
            foreach ($row in $csv) {
                $obj = $row | Select-Object *
                $obj | Add-Member -NotePropertyName testName -NotePropertyValue $testName
                $obj | Add-Member -NotePropertyName userCode -NotePropertyValue $row.account
                $obj | Add-Member -NotePropertyName isExecute -NotePropertyValue ($row.status -ne "NotStarted")
                if (-not ($obj.PSObject.Properties.Name -contains 'score')) {
                    $challengeSuccessfulTestcases = [int]$row.challengeSuccessfulTestcases
                    $challengeTotalTestcases = [int]$row.challengeTotalTestcases
                    $score = if ($challengeTotalTestcases -ne 0) {
                        ($challengeSuccessfulTestcases / $challengeTotalTestcases) * 100
                    } else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName score -NotePropertyValue $score
                }
                if (-not ($obj.PSObject.Properties.Name -contains 'questionCount')) {
                    $challengeTotalTestcases = [int]$row.challengeTotalTestcases
                    $obj | Add-Member -NotePropertyName questionCount -NotePropertyValue $challengeTotalTestcases
                }
                for ($i = 1; $i -le $obj.questionCount; $i++) {
                    $propName = "q$i/score"
                    $propValue = if ($obj.PSObject.Properties.Name -contains $propName){
                        $obj.$propName
                    }else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName "Q$i" -NotePropertyValue $propValue
                }
                $obj | Add-Member -NotePropertyName isPass -NotePropertyValue ([int]$obj.score -ge $PassScore)
                $allResultDatas += $obj
            }
        }
    }
    # Write-Message $allResultDatas -VarName "allResultDatas" -Type "Info" -ForegroundColor Green
    return $allResultDatas
}


function Get-TestMedian {
    param(
        [array]$values
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green

    $sorted = $values |
        Where-Object { $_ -ne $null -and $_ -ne "" } |
        ForEach-Object { [double]$_ } |
        Sort-Object
    $count = $sorted.Count
    if ($count -eq 0) { return $null }
    $mid = [math]::Floor($count / 2)

    $median = if ($count % 2 -eq 1) {
        $sorted[$mid]
    }
    else {
        ($sorted[$mid - 1] + $sorted[$mid]) / 2
    }

    return $median
}


function Create-TestSummaryDataByGroup {
    param(
        [array]$ValidResultDatas,
        [array]$UserDatas,
        [array]$TestDatas,
        [array]$GroupValues,
        [string]$GroupKey
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $results = foreach ($group in (Get-GroupedResults -UserDatas $UserDatas -ValidResultDatas $ValidResultDatas -GroupValues $GroupValues -GroupKey $GroupKey)) {
        $groupUsers = $group.GroupUsers
        $groupResults = $group.GroupResults
        foreach ($testData in $TestDatas) {
            $filtered = @(
                $groupResults |
                Where-Object { $_.testName -eq $testData.testName }
            )
            $planCount   = $groupUsers.Count
            $actualCount = $filtered.Count
            $passedCount = @($filtered | Where-Object isPass).Count
            if ($actualCount -eq 0) {
                $passedPercentage = 0
            } else {
                $passedPercentage = ($passedCount / $actualCount) * 100
            }
            $scores = $filtered.score | ForEach-Object { [int]$_ }
            $stats  = $scores | Measure-Object -Average -Maximum -Minimum
            $isExecute = ($filtered.Count -ne 0)

            $obj = [ordered]@{}
            if ($GroupKey) {
                $obj[$GroupKey] = $group.GroupValue
            }
            $obj += @{
                テスト名  = $testData.testName
                testName  = $testData.testName
                isExecute = $isExecute
                scores    = if ($isExecute) { $scores } else { "" }
                予定数    = $planCount
                実施数    = $actualCount
                合格数    = if ($isExecute) { $passedCount } else { "" }
                不合格数  = if ($isExecute) { $actualCount - $passedCount } else { "" }
                修了率    = if ($isExecute) { $passedPercentage } else { "" }
                平均点    = if ($isExecute) { $stats.Average } else { "" }
                中央値    = if ($isExecute) { Get-TestMedian $scores } else { "" }
                最高点    = if ($isExecute) { $stats.Maximum } else { "" }
                最低点    = if ($isExecute) { $stats.Minimum } else { "" }
            }

            # 設問正答率
            if ($isExecute) {
                $questionCount = [int]$filtered[0].questionCount
                $obj["questionCount"] = $questionCount
                for ($i = 1; $i -le $questionCount; $i++) {
                    $propName = "Q$i"
                    $propValues = $filtered | Where-Object { $_.isExecute -and $_.PSObject.Properties.Name -contains $propName } | ForEach-Object { $_.$propName }
                    $avgValue = ($propValues | Measure-Object -Average).Average
                    if ($null -eq $avgValue) {
                        $avgValue = 0
                    } else {
                        $avgValue = [int]($avgValue * 100)
                    }
                    $obj["Q$i"] = $avgValue
                }
            }
            [pscustomobject]$obj
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}
