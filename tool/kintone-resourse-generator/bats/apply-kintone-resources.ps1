# =========================================
# 編集済みExcelの内容をkintoneに反映する
# =========================================
# config\<CONFIG_NAME>.xlsx の内容をkintoneに反映する。
# スペース単位で、スペース設定（space-settings）・スペースのメンバー（space-member-list）を更新。
# アプリ単位で、アプリ名（space-app-list）・アプリのACL（space-app-acl）・レコードACL
# （space-app-record-acl）を更新。

param(
    [string]$ConfigName,
    [string]$Sheets
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "library\common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$configRoot = $env:COMMON_CONFIG_PATH
$logRoot = $env:COMMON_LOG_PATH

if (-not $baseUrl -or -not $configRoot -or -not $logRoot) {
    Write-Message "KINTONE_BASE_URL / COMMON_CONFIG_PATH / COMMON_LOG_PATH を設定してください（clients\set-kintone.bat・set-env.bat）" -Type "Info" -NoHeader
    exit 1
}
if (-not $ConfigName) {
    $ConfigName = Read-Host "設定ファイル名（config\<CONFIG_NAME>_config.xlsx の<CONFIG_NAME>）"
}

$configPath = Join-Path $configRoot "${ConfigName}_config.xlsx"
$logFilePath = New-WorkerLogPath -LogRoot $logRoot -Prefix "apply_$ConfigName"

$script:exitCode = 0

# 「■<ラベル>しました (<件数>)」のヘッダー行＋詳細行の出力を共通化する。CountPhraseは省略可（例: "2件"）。
function Write-ApplyStepResult {
    param(
        [Parameter(Mandatory)][string]$ActionLabel,
        [string]$CountPhrase = "",
        [string[]]$DetailLines = @()
    )
    $suffix = if ($CountPhrase) { " ($CountPhrase)" } else { "" }
    Write-Message "■${ActionLabel}しました${suffix}" -Type "Info" -NoHeader
    foreach ($line in $DetailLines) { Write-Message $line -Type "Info" -NoHeader }
}

& {
    $spaceRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-settings"
    $memberRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-member-list"
    $appRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-list"
    $appAclRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-acl"
    $recordAclRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-record-acl"

    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

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
                Set-Space -BaseUrl $baseUrl -Authorization $authorization -SpaceId $spaceId `
                    -Name $spaceRow.'スペース名' -IsPrivate (ToBool $spaceRow.'参加メンバーだけにこのスペースを公開する') `
                    -UseMultiThread (ToBool $spaceRow.'スペースのポータルと複数のスレッドを使用する') `
                    -FixedMember (ToBool $spaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する') `
                    -CreateAppAdminOnly (ToBool $spaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')
                Write-ApplyStepResult -ActionLabel "スペース名を設定" -DetailLines @("　$($spaceRow.'スペース名')")
                Write-ApplyStepResult -ActionLabel "スペース権限を設定" -DetailLines $spaceRightLines
            } catch {
                Write-Message "スペースID $spaceId のスペース設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
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
                $memberResult = Set-SpaceMembers -BaseUrl $baseUrl -Authorization $authorization -SpaceId $spaceId -MemberRows $targetMemberRows
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
                Write-ApplyStepResult -ActionLabel "スペースメンバーを設定" -CountPhrase "$($memberResult.TotalCount)件" -DetailLines $memberDetailLines
            } catch {
                Write-Message "スペースID $spaceId のメンバー設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
                $hasError = $true
            }
        }
    }

    # アプリ単位の処理（スペースとは無関係にアプリIDだけで処理する）
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
                    Set-AppName -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Name $finalName
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリ名を設定" -DetailLines @("　$finalName")
                } catch {
                    Write-Message "アプリID[$appId]の名前設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
                    $hasError = $true
                    $appHasError = $true
                }
            }

            if ($applyAppAcl -and $aclRowsForApp.Count -gt 0) {
                try {
                    $rights = @($aclRowsForApp | ForEach-Object { New-AppAclRightFromRow -BaseUrl $baseUrl -Authorization $authorization -Row $_ })

                    $aclTargetLines = @($aclRowsForApp | ForEach-Object {
                        $row = $_
                        $grantedRights = @('レコード閲覧', 'レコード追加', 'レコード編集', 'レコード削除', 'アプリ管理', 'ファイル読み込み', 'ファイル書き出し') | Where-Object { ToBool $row.$_ }
                        "　$($row.'種別'):$($row.'ユーザー／組織／グループ') - $($grantedRights -join ',')"
                    })
                    # kintoneはrightsにCREATOR(appEditable:true)相当が無いとエラーになるため、Set-AppAclが自動的に補う。
                    # ログ上の件数・対象一覧にもその自動追加分を反映しておく。
                    $hasCreatorManage = [bool]($rights | Where-Object { $_.entity.type -eq "CREATOR" -and $_.appEditable })
                    $aclTotalCount = $rights.Count + $(if ($hasCreatorManage) { 0 } else { 1 })
                    if (-not $hasCreatorManage) {
                        $aclTargetLines += "　アプリ作成者(自動追加) - レコード閲覧,レコード追加,レコード編集,レコード削除,アプリ管理,ファイル読み込み,ファイル書き出し"
                    }

                    Set-AppAcl -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Rights $rights
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリの権限を設定" -CountPhrase "$($aclTotalCount)件" -DetailLines $aclTargetLines
                } catch {
                    Write-Message "アプリ[$label](appId=$appId)のACL設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
                    $hasError = $true
                    $appHasError = $true
                }
            }

            if ($applyAppRecordAcl -and $recordAclRowsForApp.Count -gt 0) {
                try {
                    $recordRights = New-RecordAclRightsFromRows -BaseUrl $baseUrl -Authorization $authorization -Rows $recordAclRowsForApp

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

                    Set-AppRecordAcl -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Rights $recordRights
                    $appChanged = $true
                    Write-ApplyStepResult -ActionLabel "アプリのレコード権限を設定" -CountPhrase "条件$($recordRights.Count)件、対象$($recordAclRowsForApp.Count)件" -DetailLines $recordAclTargetLines
                } catch {
                    Write-Message "アプリ[$label](appId=$appId)のレコードACL設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
                    $hasError = $true
                    $appHasError = $true
                }
            }

            # 成功した項目だけが中途半端に反映されるのを避けるため、1つでも設定に失敗していればデプロイをスキップする
            if ($appChanged) {
                if ($appHasError) {
                    Write-Message "アプリID[$appId]は一部の設定が失敗したため、更新（デプロイ）をスキップします" -ForegroundColor Yellow -Type "Info" -NoHeader
                } else {
                    try {
                        Update-KintoneApps -BaseUrl $baseUrl -Authorization $authorization -AppIds @($appId)
                    } catch {
                        Write-Message "アプリ[$label](appId=$appId)の更新でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red -Type "Info" -NoHeader
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

    Write-Message "" -Type "Info" -NoHeader
    if ($hasError) {
        Write-Message "一部の処理でエラーが発生しました。" -ForegroundColor Red -Type "Info" -NoHeader
        $script:exitCode = 1
    } else {
        Write-Message "すべての反映が完了しました。" -ForegroundColor Green -Type "Info" -NoHeader
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message "" -Type "Info" -NoHeader
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green -Type "Info" -NoHeader
exit $script:exitCode
