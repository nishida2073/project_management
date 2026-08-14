param(
    [string]$BaseUrl,
    [string]$MasterDataFilePath,
    [string]$AutoHotkeyExePath,
    [string]$AutoHotkeyScriptPath,
    [string]$TargetGroupName,
    [string]$OutputRootDir,
    [string]$TemplateFilePath,
    [string]$SurveyResultRootDir
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

function Create-CollectResultsDatas {
    param(
        $UserDatas,
        $SurveyDatas,
        $SurveyResultDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $userCodes = $UserDatas.userCode
    $validSurveyResultDatas = $SurveyResultDatas |
        Where-Object {
            $_.isExecute -and $_.userCode -in $userCodes
        } |
        Group-Object userCode, surveyName | ForEach-Object { $_.Group[0] }
    
    $plainSurveyResults = foreach ($userData in $UserDatas) {
        $userResults = @($validSurveyResultDatas | Where-Object { $_.userCode -eq $userData.userCode })
        foreach ($surveyData in $SurveyDatas) {
            $filtered = $userResults | Where-Object { $_.surveyName -eq $surveyData.surveyName }| Select-Object -First 1
            [pscustomobject]@{
                userCode    = $userData.userCode
                userData    = $userData
                surveyName  = $surveyData.surveyName
                surveyResult = $filtered
                isExecute   = $filtered -and $filtered.isExecute
            }
        }
    }
    
    $ClassNames = $UserDatas.className | Sort-Object -Unique
    $CompanyNames = $UserDatas.companyName | Select-Object -Unique
    $rankOrder = @("S","A","B","C","D","E")
    $RankNames = $UserDatas.rankName | Select-Object -Unique | Sort-Object { $rankOrder.IndexOf($_) }
    
    # totalSummary
    $totalSummarySurveyResults = Create-SurveySummaryDataByGroup `
        -UserDatas $UserDatas `
        -SurveyDatas $SurveyDatas `
        -ValidResultDatas $validSurveyResultDatas
    
    # companySummary
    $companySummarySurveyResults = Create-SurveySummaryDataByGroup `
        -GroupValues $CompanyNames `
        -GroupKey "companyName" `
        -UserDatas $UserDatas `
        -SurveyDatas $SurveyDatas `
        -ValidResultDatas $validSurveyResultDatas
    
    # classSummary
    $classSummaryResults = Create-SurveySummaryDataByGroup `
        -GroupValues $ClassNames `
        -GroupKey "className" `
        -UserDatas $UserDatas `
        -SurveyDatas $SurveyDatas `
        -ValidResultDatas $validSurveyResultDatas
    
    # rankSummary
    $rankSummaryResults = Create-SurveySummaryDataByGroup `
        -GroupValues $RankNames `
        -GroupKey "rankName" `
        -UserDatas $UserDatas `
        -SurveyDatas $SurveyDatas `
        -ValidResultDatas $validSurveyResultDatas
    
    # 全体
    $results = [PSCustomObject]@{
        plainSurveyResults = $plainSurveyResults
        
        totalSummarySurveyResults = $totalSummarySurveyResults
        companySummarySurveyResults = $companySummarySurveyResults
        classSummarySurveyResults = $classSummaryResults
        rankSummarySurveyResults = $rankSummaryResults
    }
    
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}


function Export-UserPlainData {
    param(
        $Workbook,
        $SurveyDatas,
        $TotalSummarySurveyResultDatas,
        $PlainSurveyResultDatas,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    $newSheetNameParts = $TemplateSheetName -split "-", 2
    $newSheetNameFormat = "$($newSheetNameParts[0])-{0}-$($newSheetNameParts[1])"

    $pickedSurveyItems = Get-PrimeSurveyItems

    foreach ($surveyData in $SurveyDatas) {
        $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
        $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
        $newSheet = $Workbook.ActiveSheet
        $newSheet.Name = $newSheetNameFormat -f $surveyData.surveyName

        $rowDatas = @()

        $targetPlainSurveyResultDatas = @($PlainSurveyResultDatas | Where-Object { $_.surveyName -eq $surveyData.surveyName })

        # 全体
        $targetTotalSummarySurveyResultData = @($TotalSummarySurveyResultDatas | Where-Object { $_.surveyName -eq $surveyData.surveyName })
        $surveyCount = if ($targetTotalSummarySurveyResultData) { [int]$targetTotalSummarySurveyResultData[0].surveyCount } else { 0 }

        $rowData = @()
        $rowData += "全体-平均"
        $rowData += ""
        $rowData += ""
        $rowData += ""
        $rowData += ""
        $rowData += ""
        foreach ($pickedSurveyItem in $pickedSurveyItems) {
            $exists = $targetTotalSummarySurveyResultData | Where-Object { $_.PSObject.Properties[$pickedSurveyItem] }
            if ($exists) {
                $rowData += $targetTotalSummarySurveyResultData.$pickedSurveyItem
            }else{
                $rowData +=""
            }
        }
        for ($i = 0; $i -lt $surveyCount; $i++) {
            $rowData += ""
        }
        $rowDatas += ,$rowData

        # ユーザ別
        foreach ($targetPlainSurveyResultData in $targetPlainSurveyResultDatas) {
            $targetUserData = $targetPlainSurveyResultData.userData
            $rowData = @()
            $rowData += $targetUserData.userCode
            $rowData += $targetUserData.userName
            $rowData += $targetUserData.companyName
            $rowData += $targetUserData.className
            $rowData += $targetUserData.rankName
            if ($targetPlainSurveyResultData.isExecute){
                $rowData += ""
            } else {
                $userUrl = "$BaseUrl/k/#/people/user/$($targetUserData.userCode)"
                $rowData += '=HYPERLINK("' + $userUrl + '","督促")'
            }
            $targetSurveyResult = $targetPlainSurveyResultData.surveyResult
            foreach ($pickedSurveyItem in $pickedSurveyItems) {
                $exists = $targetSurveyResult.PSObject.Properties[$pickedSurveyItem]
                if ($exists) {
                    $rowData += $targetSurveyResult.$pickedSurveyItem
                }else{
                    $rowData +=""
                }
            }
            for ($i = 0; $i -lt $surveyCount; $i++) {
                $propName = "S$i"
                $rowData += $targetSurveyResult.$propName
            }
            $rowDatas += ,$rowData
        }

        if($rowDatas.Count -eq 0){
            $rowDatas += ,@("")
        }
        $dataStartCell = Get-CellByKey $newSheet "{ユーザーデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row
        $columsStartIndex = $dataStartCell.Column

        # 行のコピー
        Expand-RowsFromTemplate -Sheet $newSheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count

        # データの書き込み
        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        # 初期セル設定
        Set-SheetFirstCell -Sheet $newSheet

        # オートフィルター
        $headerRange = $newSheet.Range(
            $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
            $newSheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $rowDatas[0].Count - 1)
        )
        Set-AutoFilter $headerRange

        # オートフィット
        Set-AutoFit $newSheet
    }
    Remove-Sheet $Workbook $TemplateSheetName
}


function Export-GroupSummaryData {
    param(
        $Workbook,
        $SurveyDatas,
        $TotalSummarySurveyResultDatas,
        $UseSummaryResults,
        $TemplateSheetName,
        $TargetUniquePropName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = @("planCount","actualCount") + (Get-PrimeSurveyItems)
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    Export-GroupSummaryDataCore `
        -Sheet $sheet `
        -DataItems $SurveyDatas `
        -ItemNameProperty "surveyName" `
        -ViewItems $pickedSurveyItems `
        -TotalResults $TotalSummarySurveyResultDatas `
        -UseSummaryResults $UseSummaryResults `
        -TargetUniquePropName $TargetUniquePropName `
        -DataMarkerKey "{アンケートデータ}" | Out-Null
}


function Export-UserSummaryData {
    param(
        $Workbook,
        $SurveyDatas,
        $TotalSummarySurveyResultDatas,
        $PlainSurveyResultDatas,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $columnsPerSet = $pickedSurveyItems.Count

    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)

    $dataStartCell = Get-CellByKey $sheet "{アンケートデータ}" -ErrorOnMissing
    $columsStartIndex = $dataStartCell.Column
    Expand-ColumnsFromTemplate -Sheet $sheet -TemplateStartColumn $columsStartIndex -TotalSets $SurveyDatas.Count -ColumnsPerSet $columnsPerSet

    $headData = @()
    foreach ($surveyData in $SurveyDatas) {
        $headData += $surveyData.surveyName
        $headData += [string[]]::new($columnsPerSet - 1)
    }
    $headDatas = ,$headData
    Write-BodyDatas -StartCell $dataStartCell -Datas $headDatas

    $rowDatas = @()

    # 全体
    $rowData = @()
    $rowData += "全体-平均"
    $rowData += ""
    $rowData += ""
    $rowData += ""
    $rowData += ""
    foreach ($surveyData in $SurveyDatas) {
        $targetTotalSummarySurveyResultData = $TotalSummarySurveyResultDatas | Where-Object { $_.surveyName -eq $surveyData.surveyName } | Select-Object -First 1
        foreach ($pickedSurveyItem in $pickedSurveyItems) {
            $exists = $targetTotalSummarySurveyResultData | Where-Object { $_.PSObject.Properties[$pickedSurveyItem] }
            if ($exists) {
                $rowData += $targetTotalSummarySurveyResultData.$pickedSurveyItem
            } else {
                $rowData += ""
            }
        }
    }
    $rowDatas += ,$rowData

    # ユーザ別
    $uniqueUsers = @($PlainSurveyResultDatas |
        Group-Object -Property { $_.userData.userCode } |
        ForEach-Object {
            $first = $_.Group[0].userData
            [PSCustomObject]@{
                userCode    = $first.userCode
                userName    = $first.userName
                companyName = $first.companyName
                className   = $first.className
                rankName    = $first.rankName
            }
        })
    foreach ($uniqueUser in $uniqueUsers) {
        $rowData = @()
        $rowData += $uniqueUser.userCode
        $rowData += $uniqueUser.userName
        $rowData += $uniqueUser.companyName
        $rowData += $uniqueUser.className
        $rowData += $uniqueUser.rankName

        $userSurveyResults = $PlainSurveyResultDatas | Where-Object { $_.userData.userCode -eq $uniqueUser.userCode }

        foreach ($surveyData in $SurveyDatas) {
            $targetPlainSurveyResultData = $userSurveyResults | Where-Object { $_.surveyName -eq $surveyData.surveyName } | Select-Object -First 1
            $targetSurveyResult = $targetPlainSurveyResultData.surveyResult
            foreach ($pickedSurveyItem in $pickedSurveyItems) {
                $exists = $targetSurveyResult.PSObject.Properties[$pickedSurveyItem]
                if ($exists) {
                    $rowData += $targetSurveyResult.$pickedSurveyItem
                } else {
                    $rowData += ""
                }
            }
        }
        $rowDatas += ,$rowData
    }

    $dataStartCell = Get-CellByKey $sheet "{ユーザーデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column

    # 行のコピー
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count

    # データの書き込み
    Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet

    # オートフィルター
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex),
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex + $rowDatas[0].Count - 1)
    )
    Set-AutoFilter $headerRange

    # オートフィット
    Set-AutoFit $sheet
}


function Export-Excel {
    param(
        [array]$SurveyDatas,
        [string]$TemplateFilePath,
        [object]$CollectResultDatas,
        [string]$OutputFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $excel = $null
    $workbook = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents = $false
        
        $workbook = $excel.Workbooks.Open($OutputFilePath)
        # サマリ(テスト結果との組み合わせ)は collect-combine-result.ps1 側で出力する

        Export-UserPlainData -Workbook $workbook -SurveyDatas $SurveyDatas -TotalSummarySurveyResultDatas $CollectResultDatas.totalSummarySurveyResults -PlainSurveyResultDatas $CollectResultDatas.plainSurveyResults -TemplateSheetName "詳細-ユーザ別"

        Export-UserSummaryData -Workbook $workbook -SurveyDatas $SurveyDatas -TotalSummarySurveyResultDatas $CollectResultDatas.totalSummarySurveyResults -PlainSurveyResultDatas $CollectResultDatas.plainSurveyResults -TemplateSheetName "サマリ-ユーザー別"

        Export-GroupSummaryData -Workbook $workbook -SurveyDatas $SurveyDatas -TotalSummarySurveyResultDatas $CollectResultDatas.totalSummarySurveyResults -UseSummaryResults $CollectResultDatas.companySummarySurveyResults -TemplateSheetName "サマリ-会社別" -TargetUniquePropName "companyName"
        
        Export-GroupSummaryData -Workbook $workbook -SurveyDatas $SurveyDatas -TotalSummarySurveyResultDatas $CollectResultDatas.totalSummarySurveyResults -UseSummaryResults $CollectResultDatas.classSummarySurveyResults -TemplateSheetName "サマリ-クラス別" -TargetUniquePropName "className"
        
        Export-GroupSummaryData -Workbook $workbook -SurveyDatas $SurveyDatas -TotalSummarySurveyResultDatas $CollectResultDatas.totalSummarySurveyResults -UseSummaryResults $CollectResultDatas.rankSummarySurveyResults -TemplateSheetName "サマリ-ランク別" -TargetUniquePropName "rankName"
        
        # 最初のシートをアクティブに
        Set-FirstVisibleSheet -Workbook $workbook
        
        # 保存
        $workbook.SaveAs($OutputFilePath, 51)
    }
    finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}


$userDatas = Create-UserDatas -DataFilePath $MasterDataFilePath
# Write-Message $userDatas -VarName "userDatas" -Type "Info"

New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$surveyDatas = Create-SurveyDatas -DataFilePath $MasterDataFilePath
$surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

# Write-Message $surveyDatas -VarName "surveyDatas" -Type "Info"

Download-TrackResults -AutoHotkeyExePath $AutoHotkeyExePath -AutoHotkeyScriptPath $AutoHotkeyScriptPath -TargetRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -Datas $surveyDatas  -NameProperty "surveyName"

$surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $TargetGroupName -SurveyDatas $surveyDatas
# Write-Message $surveyResultDatas -VarName "surveyResultDatas" -Type "Info" 

$collectResultDatas = Create-CollectResultsDatas -UserDatas $userDatas -SurveyDatas $surveyDatas -SurveyResultDatas $surveyResultDatas
# Write-Message $collectResultDatas -VarName "collectResultDatas" -Type "Info" 

$outputFilePath = Join-Path $OutputRootDir "$TargetGroupName-アンケート結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -SurveyDatas $surveyDatas -TemplateFilePath $TemplateFilePath -CollectResultDatas $collectResultDatas -OutputFilePath $outputFilePath
