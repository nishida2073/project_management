param(
    [string]$BaseUrl,
    [string]$MasterDataFilePath,
    [string]$TargetGroupName,
    [string]$KintoneID,
    [string]$KintonePW,
    [string]$Authorization,
    [string]$OutputRootDir,
    [string]$OutputSheetNameSuffix,
    [int]$CreateExcelFile,
    [int]$CreateClassSheet,
    [int]$CreateReminderLink,
    [string]$SummarySheetNamePrefix,
    [string]$TemplateFilePath,
    [string]$ClassTemplateSheetName,
    [string]$SummaryTemplateSheetName,
    [string]$TargetAppIds,
    [string]$TargetDate,
    [string]$TargetDateCodeField,
    [string]$TargetUserCodeField,
    [string]$TargetFixedCodeFields,
    [string]$TargetAppCodeFields,
    [string]$TargetSummaryCodeFields
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$appDefinedCodeFields = [PSCustomObject]@{
    DateCodeField                = $TargetDateCodeField
    UserCodeField                = $TargetUserCodeField
}


function Get-AppDatas {
    param(
        [array]$TargetAppIds,
        [string]$TargetDate,
        [string]$BaseUrl,
        [string]$Authorization
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $resultAllDatas = @()
    $fieldDatas = $null
    foreach ($targetAppId in $TargetAppIds) {
        # フィールドコード取得
        if(-not $fieldDatas) {
            $fieldDatas = Get-CurrentAppFieldData -TargetAppId $targetAppId -BaseUrl $BaseUrl -Authorization $Authorization
            # Write-Message $fieldDatas -VarName "fieldDatas" -Type "Info" -ForegroundColor Green
        }
        # 結果取得
        $resultDatas = Get-CurrentAppData -TargetAppId $targetAppId -BaseUrl $BaseUrl -Authorization $Authorization -TargetDateCodeField $appDefinedCodeFields.DateCodeField -TargetDate $TargetDate
        $labelDatas = @()
        foreach ($resultData in $resultDatas) {
            # フィールドをラベルに変換
            $labelData = [PSCustomObject]@{}
            foreach ($fieldCode in $resultData.PSObject.Properties.Name) {
                if ($null -ne $fieldDatas.PSObject.Properties[$fieldCode]) {
                    $label = $fieldDatas.$fieldCode.label
                    Add-Member -InputObject $labelData -MemberType NoteProperty -Name $label -Value $resultData.$fieldCode.value -Force
                } 
                Add-Member -InputObject $labelData -MemberType NoteProperty -Name $fieldCode -Value $resultData.$fieldCode.value -Force
            }
            $userCode = Get-NestedPropertyValue -Object $labelData -PropertyPath $appDefinedCodeFields.UserCodeField
            Add-Member -InputObject $labelData -MemberType NoteProperty -Name userCode -Value $userCode -Force
            $labelDatas += $labelData
        }
        $resultAllDatas += $labelDatas
    }
    Write-Message $resultAllDatas -VarName "resultAllDatas"

    # 最新版を取得
    $resultAllDatas = @($resultAllDatas | Group-Object userCode |
                          ForEach-Object {
                              $_.Group | Sort-Object { $_.更新日時 } -Descending |
                              Select-Object -First 1
                          })
    
    return $resultAllDatas
}


function Check-Result {
    param(
        [array]$AppDatas,
        [array]$UserDatas,
        [string]$TargetDate,
        [object]$CourseScheduleData
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $checkResults = @()
    foreach ($userData in $UserDatas) {
        $appData = $AppDatas | Where-Object { $_.userCode -eq $userData.userCode } | Select-Object -First 1
        if ($appData) {
            $existStatus = $true
        } else {
            $existStatus = $false
        }
        $userData | Add-Member -MemberType NoteProperty -Name "scheduledDate" -Value $TargetDate -Force
        $userData | Add-Member -MemberType NoteProperty -Name "日付" -Value $TargetDate -Force
        if( $CourseScheduleData ){
            $courseName = $CourseScheduleData.courseName
        } else {
            $courseName = ""
        }
        $userData | Add-Member -MemberType NoteProperty -Name "isHoliday" -Value $CourseScheduleData.isHoliday -Force
        $userData | Add-Member -MemberType NoteProperty -Name "scheduledCourseName" -Value $courseName -Force
        $userData | Add-Member -MemberType NoteProperty -Name "科目名" -Value $courseName -Force
        if( $CreateReminderLink -eq 1){
            $userUrl = "$BaseUrl/k/#/people/user/$($userData.userCode)"
            $reminderLink = '=HYPERLINK("' + $userUrl + '","督促")'
        }else {
            $reminderLink = ""
        }
        $checkResults += [PSCustomObject]@{
            userData    = $userData
            appData     = $appData
            existStatus = $existStatus
            reminderLink = $reminderLink
        }
    }
    return $checkResults
}


function Export-ClassData {
    param(
        $Workbook,
        [PSObject[]]$CheckResults,
        [string]$TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $classGroupedResults = $CheckResults | Group-Object -Property { $_.userData.クラス名 } | Sort-Object -Property Name
    foreach ($class in $classGroupedResults) {
        $checkResults = $class.Group
        $sheetName = "$($class.Name)$OutputSheetNameSuffix"
        
        Remove-Sheet $Workbook $sheetName
        
        $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
        $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
        $sheet = $Workbook.Worksheets.Item($Workbook.Sheets.Count)
        $sheet.Name = $sheetName
        
        # --- クラス部 ---
        $classDatas = @(
            @(
                $class.Name,
                $class.Count,
                @($checkResults | Where-Object { $_.existStatus -eq $true }).Count,
                @($checkResults | Where-Object { $_.existStatus -eq $false }).Count
            )
        )
        $dataStartCell = Get-CellByKey $sheet "{クラスデータ}" -ErrorOnMissing
        Write-BodyDatas -StartCell $dataStartCell -Datas $classDatas
        
        # --- 提出状況 ---
        $statusDatas = @()
        $checkResults | ForEach-Object {
            $rowData = @($_.existStatus)
            
            foreach ($field in $fixedCodeFields) {
                # Write-Message "field = $field"
                $rowData += $_.userData.$field
            }
            foreach ($field in $appCodeFields) {
                $rowData += $_.appData.$field
            }
            if(-not $_.existStatus){
                $rowData += $_.reminderLink
            } else {
                $rowData += ""
            }
            $statusDatas += ,$rowData
        }
        $dataStartCell = Get-CellByKey $sheet "{提出状況データ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row
        $columsStartIndex = $dataStartCell.Column
        Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $statusDatas.Count
        Write-BodyDatas -StartCell $dataStartCell -Datas $statusDatas
        
        $maxRowCount = $rowStartIndex + $statusDatas.Count -1
        $resultRange = $sheet.Range($sheet.Cells.Item($rowStartIndex, 1), $sheet.Cells.Item($maxRowCount, 1))
        Set-ResultCellColor $resultRange
        
        # 初期セル設定
        Set-SheetFirstCell -Sheet $sheet
        
        # ウィンドウ枠の固定
        # Set-FreezePane $sheet 4 ($rowStartIndex - 1)
        
        # オートフィット
        Set-AutoFit $sheet
        
        # オートフィルター
        $headerRange = $sheet.Range(
            $sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
            $sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $statusDatas[0].Count)
        )
        Set-AutoFilter $headerRange 1 "FALSE"
        
        # エラー判定
        $hasError = @($checkResults | Where-Object { $_.existStatus -eq $false }).Count -gt 0
        # Write-Message $hasError -VarName "hasError" -Type "Info"
        Set-SheetTabColor $sheet $hasError
    }

}


function Export-SummaryData {
    param(
        $Workbook,
        [PSObject[]]$CheckResults,
        [string]$TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $sheetName = "$SummarySheetNamePrefix$OutputSheetNameSuffix"
    
    Remove-Sheet $Workbook $sheetName
    
    $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
    $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
    $sheet = $Workbook.Worksheets.Item($Workbook.Sheets.Count)
    $sheet.Name = $sheetName
    
    # --- 全体部 ---
    $totalDatas = @(
        @(
            $CheckResults.Count,
            @($CheckResults | Where-Object { $_.existStatus -eq $true }).Count,
            @($CheckResults | Where-Object { $_.existStatus -eq $false }).Count
        )
    )
    $dataStartCell = Get-CellByKey $sheet "{全体データ}" -ErrorOnMissing
    Write-BodyDatas -StartCell $dataStartCell -Datas $totalDatas
    
    # --- 提出状況 ---
    $statusDatas = @()
    $CheckResults | ForEach-Object {
        $rowData = @($_.existStatus)
        
        foreach ($field in $summaryCodeFields) {
            # Write-Message "field = $field"
            $rowData += $_.userData.$field
        }        
        foreach ($field in $fixedCodeFields) {
            # Write-Message "field = $field"
            $rowData += $_.userData.$field
        }
        foreach ($field in $appCodeFields) {
            $rowData += $_.appData.$field
        }
        if(-not $_.existStatus){
            $rowData += $_.reminderLink
        } else {
            $rowData += ""
        }
        $statusDatas += ,$rowData
    }
    $dataStartCell = Get-CellByKey $sheet "{提出状況データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    Expand-RowsFromTemplate -Sheet $sheet -TemplateStartRow $rowStartIndex -TotalSets $statusDatas.Count
    Write-BodyDatas -StartCell $dataStartCell -Datas $statusDatas
    
    $maxRowCount = $rowStartIndex + $statusDatas.Count -1
    $resultRange = $sheet.Range($sheet.Cells.Item($rowStartIndex, 1), $sheet.Cells.Item($maxRowCount, 1))
    Set-ResultCellColor $resultRange
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $sheet
    
    # ウィンドウ枠の固定
    # Set-FreezePane $sheet 4 ($rowStartIndex - 1)
    
    # オートフィット
    Set-AutoFit $sheet
    
    # オートフィルター
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
        $sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $statusDatas[0].Count)
    )
    Set-AutoFilter $headerRange 1 "FALSE"
    
    # 個別のエラー判定
    $hasError = @($CheckResults | Where-Object { $_.existStatus -eq $false }).Count -gt 0
    # Write-Message $hasError -VarName "hasError" -Type "Info"
    Set-SheetTabColor $sheet $hasError
}


function Export-Excel {
    param(
        [PSObject[]]$CheckResults,
        [string]$OutputFilePath,
        [string]$TemplateFilePath,
        [string]$ClassTemplateSheetName,
        [string]$SummaryTemplateSheetName
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
        $excel.Calculation = -4135
        
        # テンプレートを表示
        Set-SheetVisibleModeByKeyword -Workbook $workbook -Keyword "テンプレート" -Visible $true
        
        # データ作成
        Export-SummaryData -Workbook $workbook -CheckResults $CheckResults -TemplateSheetName $SummaryTemplateSheetName
        if($CreateClassSheet -eq 1){
            Export-ClassData -Workbook $workbook -CheckResults $CheckResults -TemplateSheetName $ClassTemplateSheetName
        }
        # サマリーシートの移動
        Move-SheetsToFront -Workbook $workbook -Keyword $SummarySheetNamePrefix
        
        # 最初のシートをアクティブに
        Set-FirstVisibleSheet -Workbook $workbook
        
        # テンプレートを非表示
        Set-SheetVisibleModeByKeyword -Workbook $workbook -Keyword "テンプレート" -Visible $false
        
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



function Export-File {
    param(
        [array]$CheckResults,
        [string]$OutputFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $allDatas = @() 
    $rowData = @("提出状況")
    foreach ($field in $summaryCodeFields) {
        $rowData += $field
    }
    foreach ($field in $fixedCodeFields) {
        $rowData += $field
    }
    foreach ($field in $appCodeFields) {
        $rowData += $field
    }
    $allDatas +=,$rowData
    
    $CheckResults | ForEach-Object {
        $rowData = @($_.existStatus)
        
        foreach ($field in $summaryCodeFields) {
            # Write-Message "field = $field"
            $rowData += $_.userData.$field
        }        
        foreach ($field in $fixedCodeFields) {
            # Write-Message "field = $field"
            $rowData += $_.userData.$field
        }
        foreach ($field in $appCodeFields) {
            $rowData += $_.appData.$field
        }
        $allDatas += ,$rowData
    }
    Export-ArrayToFile $allDatas $OutputFilePath
}



$newTargetAppIds = if ([string]::IsNullOrWhiteSpace($TargetAppIds)) {
    @()
} else {
    $TargetAppIds -split '[,\s]+' | Where-Object { $_ }
}

$fixedCodeFields = $TargetFixedCodeFields -split '[,\s]+'
if ([string]::IsNullOrWhiteSpace($fixedCodeFields)) {
    $fixedCodeFields = @()
}

$appCodeFields = $TargetAppCodeFields -split '[,\s]+'
if ([string]::IsNullOrWhiteSpace($appCodeFields)) {
    $appCodeFields = @()
}

$summaryCodeFields = $TargetSummaryCodeFields -split '[,\s]+'
if ([string]::IsNullOrWhiteSpace($summaryCodeFields)) {
    $summaryCodeFields = @()
}

New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if ([string]::IsNullOrWhiteSpace($Authorization)) {
    $pair = "${KintoneID}:${KintonePW}"
    $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
}


$courseScheduleDatas = Create-CourseScheduleDatas -DataFilePath $MasterDataFilePath -CurrentDate $TargetDate
Write-Message $courseScheduleDatas -VarName "courseScheduleDatas"

$courseScheduleData = $CourseScheduleDatas | Where-Object { $_.date -eq $TargetDate } | Select-Object -First 1
Write-Message $courseScheduleData -VarName "courseScheduleData"

if(-not $courseScheduleData){
    Write-Message "対象の科目がありません。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
    return
}
if($courseScheduleData.isHoliday){
    Write-Message "休日です。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
    return
}

$userDatas = Create-UserDatas -DataFilePath $MasterDataFilePath
Write-Message $userDatas -VarName "userDatas"

$appDatas = Get-AppDatas -TargetAppIds $newTargetAppIds -TargetDate $TargetDate -BaseUrl $BaseUrl -Authorization $Authorization
Write-Message $appDatas -VarName "appDatas"

$checkResults = Check-Result -AppDatas $appDatas -UserDatas $userDatas -TargetDate $TargetDate -CourseScheduleData $courseScheduleData
Write-Message $checkResults -VarName "checkResults"

if( $CreateExcelFile -eq 1 ){
    $outputFilePath = Join-Path $OutputRootDir "$TargetGroupName.xlsx"
    if (-not (Test-Path $outputFilePath)) {
        Copy-Item -Path $TemplateFilePath -Destination $outputFilePath
    }
    Export-Excel -CheckResults $checkResults -TemplateFilePath $TemplateFilePath -OutputFilePath $outputFilePath -ClassTemplateSheetName $ClassTemplateSheetName -SummaryTemplateSheetName $SummaryTemplateSheetName
}

$outputFileName = "$TargetGroupName-$SummarySheetNamePrefix$OutputSheetNameSuffix.txt"
$outputFilePath = Join-Path $OutputRootDir $outputFileName
Export-File -CheckResults $checkResults -OutputFilePath $outputFilePath
