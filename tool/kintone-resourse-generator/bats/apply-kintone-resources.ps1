# =========================================
# 編集済みExcelの内容をkintoneに反映する
# =========================================

param(
    [string]$ConfigName,
    [string]$Sheets,
    [string]$BaseUrl,
    [string]$ConfigRoot,
    [string]$LogRoot,
    [string]$KintoneLogin,
    [string]$KintonePassword
)

$libraryDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

if (-not $ConfigName) {
    Write-MessageError "ConfigName を指定してください（config\<CONFIG_NAME>_config.xlsx の<CONFIG_NAME>）"
    exit 1
}

$configPath = Join-Path $ConfigRoot "${ConfigName}_config.xlsx"
$logFilePath = New-WorkerLogPath -LogRoot $LogRoot -Prefix "apply_$ConfigName"

$script:exitCode = 0

& {
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-MessageError "設定ファイルが見つかりません: $configPath"
        $script:exitCode = 1
        return
    }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $excel.ScreenUpdating = $false
    $excel.EnableEvents = $false
    try {
        $workbook = $excel.Workbooks.Open($configPath)
        $spaceRows = Get-RowObjects -Sheet $workbook.Sheets.Item("space-settings")
        $memberRows = Get-RowObjects -Sheet $workbook.Sheets.Item("space-member-list")
        $appRows = Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-list")
        $appAclRows = Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-acl")
        $recordAclRows = Get-RowObjects -Sheet $workbook.Sheets.Item("space-app-record-acl")
    }
    finally {
        if ($workbook) { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel)    { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${KintoneLogin}:${KintonePassword}"))

    $selectedSheets = ConvertTo-SheetNameArray -Sheets $Sheets
    if ($selectedSheets.Count -gt 0) {
        Write-Message "対象シートを絞り込みます: $($selectedSheets -join ', ')" -ForegroundColor Cyan -Type "Info" -NoHeader
    }

    $hasError = $false

    foreach ($spaceGroup in (Group-RowsBySpaceId -Rows $spaceRows)) {
        $spaceId = $spaceGroup.Name
        $spaceRow = $spaceGroup.Group | Select-Object -First 1

        Write-Message "" -Type "Info" -NoHeader
        Write-Message "# スペースID: $spaceId ($($spaceRow.'スペース名'))" -Type "Info" -NoHeader

        if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-settings") {
            try {
                $spaceRightLines = @('参加メンバーだけにこのスペースを公開する', 'スペースのポータルと複数のスレッドを使用する', 'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する', 'アプリ作成できるユーザーをスペースの管理者に限定する') | ForEach-Object {
                    "　${_}: $($spaceRow.$_)"
                }
                Set-Space -BaseUrl $BaseUrl -Authorization $authorization -SpaceId $spaceId `
                    -Name $spaceRow.'スペース名' -IsPrivate (ToBool $spaceRow.'参加メンバーだけにこのスペースを公開する') `
                    -UseMultiThread (ToBool $spaceRow.'スペースのポータルと複数のスレッドを使用する') `
                    -FixedMember (ToBool $spaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する') `
                    -CreateAppAdminOnly (ToBool $spaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')
                Write-ApplyStepResult -ActionLabel "スペース名を設定しました" -DetailLines @("　$($spaceRow.'スペース名')")
                Write-ApplyStepResult -ActionLabel "スペース権限を設定しました" -DetailLines $spaceRightLines
            } catch {
                Write-MessageError "スペースID $spaceId のスペース設定でエラーが発生しました: $($_.Exception.Message)"
                $hasError = $true
            }
        }

        if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-member-list") {
            try {
                $targetMemberRows = @($memberRows | Where-Object { $_.'スペースID' -eq $spaceId })
                $targetMemberLines = @($targetMemberRows | ForEach-Object {
                    $row = $_
                    $flags = @('管理者', '下位組織も含める') | Where-Object { ToBool $row.$_ }
                    "　　$($row.'種別'):$($row.'ユーザー/組織/グループ') - $($flags -join ',')"
                })
                $memberResult = Set-SpaceMembers -BaseUrl $BaseUrl -Authorization $authorization -SpaceId $spaceId -MemberRows $targetMemberRows
                $memberDetailLines = @()
                if ($targetMemberRows.Count -gt 0) {
                    $memberDetailLines += "　テンプレート内のメンバー ($($targetMemberRows.Count)件)"
                    $memberDetailLines += $targetMemberLines
                }
                if ($memberResult.KeptMembers.Count -gt 0) {
                    $memberDetailLines += "  テンプレート外のメンバー ($($memberResult.KeptMembers.Count)件)"
                    $memberDetailLines += @($memberResult.KeptMembers | ForEach-Object {
                        $flags = @()
                        if ($_.IsAdmin) { $flags += '管理者' }
                        if ($_.IncludeSubs) { $flags += '下位組織も含める' }
                        "　　$($_.Type):$($_.Code) - $($flags -join ',')"
                    })
                }
                Write-ApplyStepResult -ActionLabel "スペースメンバーを設定しました" -CountPhrase "$($memberResult.TotalCount)件" -DetailLines $memberDetailLines
            } catch {
                Write-MessageError "スペースID $spaceId のメンバー設定でエラーが発生しました: $($_.Exception.Message)"
                $hasError = $true
            }
        }
    }

    $applyAppList = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-list"
    $applyAppAcl = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-acl"
    $applyAppRecordAcl = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-record-acl"

    if ($applyAppList -or $applyAppAcl -or $applyAppRecordAcl) {
        $allAppIds = @(
            @($(if ($applyAppList) { $appRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } })) +
            @($(if ($applyAppAcl) { $appAclRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } })) +
            @($(if ($applyAppRecordAcl) { $recordAclRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } }))
        ) | Select-Object -Unique

        foreach ($appId in $allAppIds) {
            $appNameRow = $appRows | Where-Object { "$($_.'アプリID')" -eq $appId } | Select-Object -First 1
            $aclRowsForApp = @($appAclRows | Where-Object { "$($_.'アプリID')" -eq $appId })
            $recordAclRowsForApp = @($recordAclRows | Where-Object { "$($_.'アプリID')" -eq $appId })

            $label = $appNameRow.'アプリ名'
            if (-not $label -and $aclRowsForApp.Count -gt 0) { $label = $aclRowsForApp[0].'アプリ名' }
            if (-not $label -and $recordAclRowsForApp.Count -gt 0) { $label = $recordAclRowsForApp[0].'アプリ名' }

            Write-Message "" -Type "Info" -NoHeader
            Write-Message "## アプリID: $appId ($label) ===" -Type "Info" -NoHeader

            $appHasError = $false
            $appChanged = $false

            if ($applyAppList -and $appNameRow) {
                $finalName = $appNameRow.'アプリ名'
                try {
                    Set-AppName -BaseUrl $BaseUrl -Authorization $authorization -AppId $appId -Name $finalName
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリ名を設定しました" -DetailLines @("　$finalName")
                } catch {
                    Write-MessageError "アプリID[$appId]の名前設定でエラーが発生しました: $($_.Exception.Message)"
                    $hasError = $true
                    $appHasError = $true
                }
            }

            if ($applyAppAcl -and $aclRowsForApp.Count -gt 0) {
                try {
                    $rights = @($aclRowsForApp | ForEach-Object { New-AppAclRightFromRow -BaseUrl $BaseUrl -Authorization $authorization -Row $_ })

                    $aclTargetLines = @($aclRowsForApp | ForEach-Object {
                        $row = $_
                        $grantedRights = @('レコード閲覧', 'レコード追加', 'レコード編集', 'レコード削除', 'アプリ管理', 'ファイル読み込み', 'ファイル書き出し') | Where-Object { ToBool $row.$_ }
                        "　$($row.'種別'):$($row.'ユーザー／組織／グループ') - $($grantedRights -join ',')"
                    })
                    $hasCreatorManage = [bool]($rights | Where-Object { $_.entity.type -eq "CREATOR" -and $_.appEditable })
                    $aclTotalCount = $rights.Count + $(if ($hasCreatorManage) { 0 } else { 1 })
                    if (-not $hasCreatorManage) {
                        $aclTargetLines += "　アプリ作成者(自動追加) - レコード閲覧,レコード追加,レコード編集,レコード削除,アプリ管理,ファイル読み込み,ファイル書き出し"
                    }

                    Set-AppAcl -BaseUrl $BaseUrl -Authorization $authorization -AppId $appId -Rights $rights
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリの権限を設定しました" -CountPhrase "$($aclTotalCount)件" -DetailLines $aclTargetLines
                } catch {
                    Write-MessageError "アプリ[$label](appId=$appId)のACL設定でエラーが発生しました: $($_.Exception.Message)"
                    $hasError = $true
                    $appHasError = $true
                }
            }

            if ($applyAppRecordAcl -and $recordAclRowsForApp.Count -gt 0) {
                try {
                    $recordRights = New-RecordAclRightsFromRows -BaseUrl $BaseUrl -Authorization $authorization -Rows $recordAclRowsForApp

                    $recordAclTargetLines = @($recordAclRowsForApp | Group-Object -Property 'レコードの条件' | ForEach-Object {
                        $condGroup = $_
                        $condLabel = if ($condGroup.Name) { $condGroup.Name } else { "すべてのレコード" }
                        "　条件: $condLabel"
                        "　　対象"
                        foreach ($row in $condGroup.Group) {
                            $grantedRights = @('閲覧', '編集', '削除') | Where-Object { ToBool $row.$_ }
                            $rightsLabel = if ($grantedRights.Count -gt 0) { $grantedRights -join ',' } else { "権限なし" }
                            "　　　- $($row.'種別'):$($row.'ユーザー／組織／グループ') ($rightsLabel)"
                        }
                    })

                    Set-AppRecordAcl -BaseUrl $BaseUrl -Authorization $authorization -AppId $appId -Rights $recordRights
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリのレコード権限を設定しました" -CountPhrase "条件$($recordRights.Count)件、対象$($recordAclRowsForApp.Count)件" -DetailLines $recordAclTargetLines
                } catch {
                    Write-MessageError "アプリ[$label](appId=$appId)のレコードACL設定でエラーが発生しました: $($_.Exception.Message)"
                    $hasError = $true
                    $appHasError = $true
                }
            }

            if ($appChanged) {
                if ($appHasError) {
                    Write-Message "アプリID[$appId]は一部の設定が失敗したため、更新（デプロイ）をスキップします" -ForegroundColor Yellow -Type "Info" -NoHeader
                } else {
                    try {
                        Update-KintoneApps -BaseUrl $BaseUrl -Authorization $authorization -AppIds @($appId)
                    } catch {
                        Write-MessageError "アプリ[$label](appId=$appId)の更新でエラーが発生しました: $($_.Exception.Message)"
                        $hasError = $true
                    }
                }
            }
        }

        $skippedAppRows = @($appRows | Where-Object { -not $_.'アプリID' })
        if ($applyAppList -and $skippedAppRows.Count -gt 0) {
            Write-Message "" -Type "Info" -NoHeader
            Write-Message "(アプリIDが空の行($($skippedAppRows.Count)件)はスキップしました。このツールはアプリの新規作成は行いません)" -ForegroundColor Yellow -Type "Info" -NoHeader
        }
    }

    if ($hasError) {
        Write-MessageError "一部の処理でエラーが発生しました。"
        $script:exitCode = 1
    } else {
        Write-MessageComplete "すべての反映が完了しました。"
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
exit $script:exitCode
