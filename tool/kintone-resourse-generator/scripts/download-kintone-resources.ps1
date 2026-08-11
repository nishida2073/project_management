# =========================================
# 現在のスペースの状態をExcelへ書き出す
# =========================================
# 指定したスペースIDの現在の状態を download\<CONFIG_NAME>.xlsx のシート
# （space-settings / space-member-list / space-app-list / space-app-acl / space-app-record-acl）に書き出す。
# 対象の5シートは毎回完全に上書きする。

param(
    [string]$SpaceId,
    [string]$ConfigName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$downloadRoot = $env:KINTONE_DOWNLOAD_PATH
$logRoot = $env:KINTONE_LOG_PATH

if (-not $baseUrl -or -not $downloadRoot -or -not $logRoot) {
    Write-Host "KINTONE_BASE_URL / KINTONE_DOWNLOAD_PATH / KINTONE_LOG_PATH を set-env.bat で設定してください"
    exit 1
}
if (-not $SpaceId) {
    $SpaceId = Read-Host "ダウンロード対象のスペースID"
}
if (-not $ConfigName) {
    $ConfigName = Read-Host "config名（download\<CONFIG_NAME>.xlsx の<CONFIG_NAME>）"
}

$downloadPath = Join-Path $downloadRoot "$ConfigName.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "download_$ConfigName"

$script:exitCode = 0

& {
    $authorization = Get-KintoneAuthorizationHeader -BaseUrl $baseUrl

    $space = $null
    try {
        $space = Get-CurrentSpace -SpaceId $SpaceId -BaseUrl $baseUrl -Authorization $authorization
    } catch {
        Write-Host "スペース取得に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
        $script:exitCode = 1
        return
    }

    Write-Host "スペース名: $($space.spaceName)　アプリ数: $($space.apps.Count)　メンバー数: $($space.members.Count)"

    # --- space-settings ---
    $spaceListRows = @([PSCustomObject]@{
        "スペースID"                       = $space.spaceId
        "スペース名"                       = $space.spaceName
        "非公開"                           = $space.isPrivate
        "複数スレッドを使用する"           = $space.useMultiThread
        "参加退会・フォロー解除を禁止する" = $space.fixedMember
        "アプリ作成を管理者に限定する"     = ($space.createApp -eq "ADMIN")
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" -Rows $spaceListRows -Headers @("スペースID", "スペース名", "非公開", "複数スレッドを使用する", "参加退会・フォロー解除を禁止する", "アプリ作成を管理者に限定する")

    # --- space-member-list ---
    $memberRows = @($space.members | Where-Object { $_.entity.type -eq "ORGANIZATION" } | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"       = $space.spaceId
            "組織名"           = $_.entity.code
            "管理者"           = $_.isAdmin
            "下位組織も含める" = $_.includeSubs
        }
    })
    if ($memberRows.Count -lt $space.members.Count) {
        Write-Host "  (ORGANIZATION以外のメンバー($($space.members.Count - $memberRows.Count)件)はspace-member-listシートの対象外のため書き出していません)" -ForegroundColor Yellow
    }
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-member-list" -Rows $memberRows -Headers @("スペースID", "組織名", "管理者", "下位組織も含める")

    # --- space-app-list ---
    $appListRows = @($space.apps | ForEach-Object {
        [PSCustomObject]@{
            "アプリID" = $_.appId
            "アプリ名" = $_.name
        }
    })
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-list" -Rows $appListRows -Headers @("アプリID", "アプリ名")

    # --- space-app-acl ---
    $appAclRows = @()
    foreach ($app in $space.apps) {
        foreach ($right in $app.rights) {
            if ($right.entity.type -eq "CREATOR") { continue }
            $appAclRows += [PSCustomObject]@{
                "アプリID"         = $app.appId
                "アプリ名"         = $app.name
                "組織名"           = $right.entity.code
                "レコード閲覧"     = $right.recordViewable
                "レコード追加"     = $right.recordAddable
                "レコード編集"     = $right.recordEditable
                "レコード削除"     = $right.recordDeletable
                "アプリ管理"       = $right.appEditable
                "ファイル読み込み" = $right.recordImportable
            }
        }
    }
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-acl" -Rows $appAclRows -Headers @("アプリID", "アプリ名", "組織名", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み")

    # --- space-app-record-acl ---
    $recordAclRows = @()
    foreach ($app in $space.apps) {
        foreach ($right in $app.recordRights) {
            foreach ($entity in $right.entities) {
                $orgName = if ($entity.entity.type -eq "CREATOR") { "作成者" } else { $entity.entity.code }
                $recordAclRows += [PSCustomObject]@{
                    "アプリID"         = $app.appId
                    "アプリ名"         = $app.name
                    "レコードの条件"   = $right.filterCond
                    "組織名"           = $orgName
                    "閲覧"             = $entity.viewable
                    "編集"             = $entity.editable
                    "削除"             = $entity.deletable
                    "アクセス権の継承" = $entity.includeSubs
                }
            }
        }
    }
    Write-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-record-acl" -Rows $recordAclRows -Headers @("アプリID", "アプリ名", "レコードの条件", "組織名", "閲覧", "編集", "削除", "アクセス権の継承")

    # ヘッダー行を灰色で塗る
    Set-KintoneHeaderRowColor -Path $downloadPath -WorksheetNames @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl") -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))

    Write-Host ""
    Write-Host "書き出し完了: $downloadPath" -ForegroundColor Green
    Write-Host "  シート: space-settings / space-member-list / space-app-list / space-app-acl / space-app-record-acl"
    Write-Host "アプリ名やACLを編集した後、apply-kintone-resources.bat で反映してください。"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Host ""
Write-Host "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
