function Get-PrimeSurveyItems {
    return @("S27","S1","S2","S7","S10","S13","S16","S19","S22","S25")
}


function Create-SurveyDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '通番'   = 'surveyNo'
        'アンケート名'     = 'surveyName'
    }
    return Create-MasterDatas -DataFilePath $DataFilePath -SheetIndex 3 -HeaderMap $headerMap
}


function Create-SurveyResultDatas {
    param(
        [string]$SurveyResultRootDir,
        [string]$TargetGroupName,
        [array]$SurveyDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allResultDatas = @()
    foreach($surveyData in $SurveyDatas){
        $surveyName = $surveyData.surveyName
        $surveyGroupDir = Join-Path $SurveyResultRootDir $TargetGroupName
        $surveyResultDir = Join-Path $surveyGroupDir $surveyName
        $resultFiles = @(Get-ChildItem $surveyResultDir -Filter *.csv)
        foreach($resultFile in $resultFiles){
            $csv = Import-Csv $resultFile.FullName
            foreach ($row in $csv) {
                $obj = $row | Select-Object *
                $obj | Add-Member -NotePropertyName surveyName -NotePropertyValue $surveyName
                $obj | Add-Member -NotePropertyName userCode -NotePropertyValue $row.account
                $obj | Add-Member -NotePropertyName isExecute -NotePropertyValue ($row.status -ne "NotStarted")
                $surveyCount = ($obj.PSObject.Properties.Name -like 'surveyAnswerValue*').Count
                $obj | Add-Member -NotePropertyName surveyCount -NotePropertyValue $surveyCount
                for ($i = 0; $i -lt $obj.surveyCount; $i++) {
                    $propName = "surveyAnswerValue/$i"
                    $propValue = if ($obj.PSObject.Properties.Name -contains $propName){
                        $obj.$propName
                    }else {
                        ""
                    }
                    $obj | Add-Member -NotePropertyName "S$i" -NotePropertyValue $propValue
                }
                $allResultDatas += $obj
            }
        }
    }
    # Write-Message $allResultDatas -VarName "allResultDatas" -Type "Info"
    return $allResultDatas
}


function Create-SurveySummaryDataByGroup {
    param(
        [array]$ValidResultDatas,
        [array]$UserDatas,
        [array]$SurveyDatas,
        [array]$GroupValues,
        [string]$GroupKey
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $results = foreach ($group in (Get-GroupedResults -UserDatas $UserDatas -ValidResultDatas $ValidResultDatas -GroupValues $GroupValues -GroupKey $GroupKey)) {
        $groupUsers = $group.GroupUsers
        $groupResults = $group.GroupResults
        foreach ($surveyData in $SurveyDatas) {
            $filtered = @(
                $groupResults |
                Where-Object { $_.surveyName -eq $surveyData.surveyName }
            )
            $planCount   = $groupUsers.Count
            $actualCount = $filtered.Count
            $isExecute = ($filtered.Count -ne 0)
            $obj = [ordered]@{}
            # total 以外のみグループキー追加
            if ($GroupKey) {
                $obj[$GroupKey] = $group.GroupValue
            }
            $obj += @{
                surveyName  = $surveyData.surveyName
                isExecute = $isExecute
                planCount    = $planCount
                actualCount  = $actualCount
            }

            # 平均
            if ($isExecute) {
                $surveyCount = [int]$filtered[0].surveyCount
                $obj["surveyCount"] = $surveyCount
                foreach ($primeSurveyItem in (Get-PrimeSurveyItems)) {
                    $propValues = $filtered | Where-Object { $_.isExecute -and $_.PSObject.Properties.Name -contains $primeSurveyItem } | ForEach-Object { $_.$primeSurveyItem }
                    $avgValue = ($propValues | Measure-Object -Average).Average
                    if ($null -eq $avgValue) {
                        $avgValue = ""
                    }
                    $obj[$primeSurveyItem] = $avgValue
                }
            }
            [pscustomobject]$obj
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}
