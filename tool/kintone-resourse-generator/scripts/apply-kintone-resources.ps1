# =========================================
# 編集済みExcelの内容をkintoneに反映する
# =========================================
# config\<CONFIG_NAME>.xlsx の内容をkintoneに反映する。
# スペース単位で、スペース設定（space-settings）・スペースのメンバー（space-member-list）を更新。
# アプリ単位で、アプリ名（space-app-list）・アプリのACL（space-app-acl）・レコードACL
# （space-app-record-acl）を更新。

param(
    [string]$ConfigName,
    [string]$Sheets,
    [switch]$WhatIf
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$configRoot = $env:KINTONE_CONFIG_PATH
$logRoot = $env:KINTONE_LOG_PATH

if (-not $baseUrl -or -not $configRoot -or -not $logRoot) {
    Write-Host "KINTONE_BASE_URL / KINTONE_CONFIG_PATH / KINTONE_LOG_PATH を set-env.bat で設定してください"
    exit 1
}
if (-not $ConfigName) {
    $ConfigName = Read-Host "config名（config\<CONFIG_NAME>.xlsx の<CONFIG_NAME>）"
}

$configPath = Join-Path $configRoot "$ConfigName.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "apply_$ConfigName"

$script:exitCode = 0

& {
    $spaceRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-settings"
    $memberRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-member-list"
    $appRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-list"
    $appAclRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-acl"
    $recordAclRows = Read-KintoneExcelRows -Path $configPath -WorksheetName "space-app-record-acl"

    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

    $selectedSheets = ConvertTo-SheetNameArray -Sheets $Sheets
    if ($selectedSheets.Count -gt 0) {
        Write-Host "対象シートを絞り込みます: $($selectedSheets -join ', ')" -ForegroundColor Cyan
    }

    $hasError = $false

    # =========================================
    # スペース単位の処理
    # =========================================
    foreach ($spaceGroup in (Group-RowsBySpaceId -Rows $spaceRows)) {
        $spaceId = $spaceGroup.Name
        $spaceRow = $spaceGroup.Group | Select-Object -First 1

        Write-Host ""
        Write-Host "=== スペースID: $spaceId ($($spaceRow.'スペース名')) ===" -ForegroundColor Cyan

        # --- 1. スペース設定 ---
        if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-settings") {
            try {
                if ($WhatIf) {
                    Write-Host "[WhatIf] スペース設定を更新: name=$($spaceRow.'スペース名') isPrivate=$($spaceRow.'非公開') useMultiThread=$($spaceRow.'複数スレッドを使用する') fixedMember=$($spaceRow.'参加退会・フォロー解除を禁止する') createAppAdminOnly=$($spaceRow.'アプリ作成を管理者に限定する')"
                } else {
                    Set-Space -BaseUrl $baseUrl -Authorization $authorization -SpaceId $spaceId `
                        -Name $spaceRow.'スペース名' -IsPrivate (ToBool $spaceRow.'非公開') `
                        -UseMultiThread (ToBool $spaceRow.'複数スレッドを使用する') `
                        -FixedMember (ToBool $spaceRow.'参加退会・フォロー解除を禁止する') `
                        -CreateAppAdminOnly (ToBool $spaceRow.'アプリ作成を管理者に限定する')
                    Write-Host "スペース設定を更新しました: name=$($spaceRow.'スペース名') isPrivate=$($spaceRow.'非公開') useMultiThread=$($spaceRow.'複数スレッドを使用する') fixedMember=$($spaceRow.'参加退会・フォロー解除を禁止する') createAppAdminOnly=$($spaceRow.'アプリ作成を管理者に限定する')"
                }
            } catch {
                Write-Host "スペースID $spaceId のスペース設定更新でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
                $hasError = $true
            }
        }

        # --- 2. スペースメンバー ---
        if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-member-list") {
            try {
                $targetMemberRows = @($memberRows | Where-Object { $_.'スペースID' -eq $spaceId })
                if ($WhatIf) {
                    Write-Host "[WhatIf] スペースメンバーを更新: $($targetMemberRows.Count)件"
                } else {
                    Set-SpaceMembers -BaseUrl $baseUrl -Authorization $authorization -SpaceId $spaceId -MemberRows $targetMemberRows
                    Write-Host "スペースメンバーを更新しました ($($targetMemberRows.Count)件)"
                }
            } catch {
                Write-Host "スペースID $spaceId のメンバー更新でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
                $hasError = $true
            }
        }
    }

    # =========================================
    # アプリ単位の処理（スペースとは無関係にアプリIDだけで処理する）
    # =========================================
    Write-Host ""
    Write-Host "=== アプリの設定 ===" -ForegroundColor Cyan

    $touchedAppIds = New-Object System.Collections.Generic.List[string]

    # --- 3. アプリ名 ---
    if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-list") {
        foreach ($row in @($appRows | Where-Object { $_.'アプリID' })) {
            $appId = $row.'アプリID'
            $finalName = $row.'アプリ名'

            try {
                if ($WhatIf) {
                    Write-Host "[WhatIf] アプリID[$appId]の名前を[$finalName]に設定"
                } else {
                    Set-AppName -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Name $finalName
                    Write-Host "  アプリID[$appId] の名前を[$finalName]に設定しました"
                    $touchedAppIds.Add([string]$appId)
                }
            } catch {
                Write-Host "  アプリID[$appId]の名前設定でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
                $hasError = $true
            }
        }
        $skippedAppRows = @($appRows | Where-Object { -not $_.'アプリID' })
        if ($skippedAppRows.Count -gt 0) {
            Write-Host "  (アプリIDが空の行($($skippedAppRows.Count)件)はスキップしました。このツールはアプリの新規作成は行いません)" -ForegroundColor Yellow
        }
    }

    # --- 4. アプリのACL ---
    if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-acl") {
        foreach ($aclGroup in (@($appAclRows | Where-Object { $_.'アプリID' }) | Group-Object -Property 'アプリID')) {
            $appId = $aclGroup.Name
            $label = $aclGroup.Group[0].'アプリ名'
            try {
                $rights = @($aclGroup.Group | ForEach-Object { New-AppAclRightFromRow -Row $_ })

                if ($WhatIf) {
                    Write-Host "[WhatIf] アプリ[$label](appId=$appId)のACLを更新: $($rights.Count)件"
                } else {
                    Set-AppAcl -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Rights $rights
                    Write-Host "  アプリ[$label](appId=$appId)のACLを更新しました ($($rights.Count)件)"
                    $touchedAppIds.Add([string]$appId)
                }
            } catch {
                Write-Host "  アプリ[$label](appId=$appId)のACL更新でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
                $hasError = $true
            }
        }
    }

    # --- 5. アプリのレコードACL ---
    if (Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-record-acl") {
        foreach ($recordAclGroup in (@($recordAclRows | Where-Object { $_.'アプリID' }) | Group-Object -Property 'アプリID')) {
            $appId = $recordAclGroup.Name
            $label = $recordAclGroup.Group[0].'アプリ名'
            try {
                $recordRights = New-RecordAclRightsFromRows -Rows $recordAclGroup.Group

                if ($WhatIf) {
                    Write-Host "[WhatIf] アプリ[$label](appId=$appId)のレコードACLを更新: 条件$($recordRights.Count)件"
                } else {
                    Set-AppRecordAcl -BaseUrl $baseUrl -Authorization $authorization -AppId $appId -Rights $recordRights
                    Write-Host "  アプリ[$label](appId=$appId)のレコードACLを更新しました (条件$($recordRights.Count)件)"
                    $touchedAppIds.Add([string]$appId)
                }
            } catch {
                Write-Host "  アプリ[$label](appId=$appId)のレコードACL更新でエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
                $hasError = $true
            }
        }
    }

    # --- 6. デプロイ ---
    if (-not $WhatIf -and $touchedAppIds.Count -gt 0) {
        try {
            Deploy-KintoneApps -BaseUrl $baseUrl -Authorization $authorization -AppIds $touchedAppIds
        } catch {
            Write-Host "デプロイでエラーが発生しました: $($_.Exception.Message)" -ForegroundColor Red
            $hasError = $true
        }
    }

    Write-Host ""
    if ($hasError) {
        Write-Host "一部の処理でエラーが発生しました。上のログを確認してください。" -ForegroundColor Red
        $script:exitCode = 1
    } else {
        Write-Host "すべての反映が完了しました。" -ForegroundColor Green
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Host ""
Write-Host "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
