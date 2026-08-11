# =========================================
# テンプレートと新スペースのダウンロード結果からconfigを自動生成する
# =========================================
# template\<TEMPLATE_CONFIG_NAME>.xlsx（共通のACL・メンバー設定などを持つテンプレート）と
# download\<DOWNLOAD_CONFIG_NAME>.xlsx（新しく作成したスペースを一度ダウンロードした結果、
# IDは正しいがACLなどはまだ反映されていない状態）を組み合わせて、
# 正しいIDを持つ完成済みconfig（config\<DOWNLOAD_CONFIG_NAME>.xlsx、ダウンロード結果と同じ名前）を生成する。
# テンプレート側は実際のスペースに紐づかないため、スペースID・アプリIDを持たない
# （space-app-list/space-app-acl/space-app-record-aclはアプリ名だけでテンプレート内の
# 行同士を結び付ける）。
# アプリの対応付けはアプリ名の一致（どちらかがどちらかを含むか）で自動判定するため、
# 対応できなかったアプリはコンソールに一覧で表示する。「対応なし」のアプリはACL等が
# 生成されないため、必要なら手動でconfigに追記する。
# ダウンロード結果のスペース名・アプリ名に"{PH}"が含まれる場合、生成先のconfig名に置き換える
# （kintone側でスペース・アプリを作成する時点では最終的な名前が決まらないため、
# 仮の名前として"{PH}"を埋め込んでおく運用を想定）。
# kintoneへの書き込みは行わない（apply-kintone-resources.bat で別途反映する）。

param(
    [string]$TemplateConfigName,
    [string]$DownloadConfigName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$templateRoot = $env:KINTONE_TEMPLATE_PATH
$configRoot = $env:KINTONE_CONFIG_PATH
$downloadRoot = $env:KINTONE_DOWNLOAD_PATH
$logRoot = $env:KINTONE_LOG_PATH

if (-not $templateRoot -or -not $configRoot -or -not $downloadRoot -or -not $logRoot) {
    Write-Host "KINTONE_TEMPLATE_PATH / KINTONE_CONFIG_PATH / KINTONE_DOWNLOAD_PATH / KINTONE_LOG_PATH を set-env.bat で設定してください"
    exit 1
}
if (-not $TemplateConfigName) {
    $TemplateConfigName = Read-Host "テンプレートのconfig"
}
if (-not $DownloadConfigName) {
    $DownloadConfigName = Read-Host "ダウンロードしたconfig"
}

$templatePath = Join-Path $templateRoot "$TemplateConfigName.xlsx"
$downloadPath = Join-Path $downloadRoot "$DownloadConfigName.xlsx"
$outputPath = Join-Path $configRoot "$DownloadConfigName.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "generate_$DownloadConfigName"

$script:exitCode = 0

& {
    $templateSpaceRow = Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-settings" | Select-Object -First 1
    $templateMemberRows = Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-member-list"
    $templateAppRows = @(Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-list" | Where-Object { $_.'アプリ名' })
    $templateAclRows = Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-acl"
    $templateRecordAclRows = Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-record-acl"

    $downloadSpaceRow = Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" | Select-Object -First 1
    $downloadAppRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-list" | Where-Object { $_.'アプリID' })

    if (-not $templateSpaceRow -or -not $downloadSpaceRow) {
        Write-Host "テンプレートまたはダウンロード結果のspace-settingsが空です" -ForegroundColor Red
        $script:exitCode = 1
        return
    }
    $newSpaceId = $downloadSpaceRow.'スペースID'
    $finalSpaceName = Expand-KintonePlaceholder -Value $downloadSpaceRow.'スペース名' -ConfigName $DownloadConfigName

    # --- アプリ名の一致でテンプレート側アプリと新スペース側アプリを対応付ける ---
    $mapping = Get-AppNameMapping -TemplateApps $templateAppRows -DownloadApps $downloadAppRows

    # ダウンロード結果のアプリ名に含まれる"{PH}"をconfig名に置き換えた最終的な名前を作る
    # （DownloadAppNameは対応付けに使った元の名前として残すため、別プロパティとして持たせる）。
    foreach ($m in $mapping) {
        $m | Add-Member -NotePropertyName "FinalAppName" -NotePropertyValue (Expand-KintonePlaceholder -Value $m.DownloadAppName -ConfigName $DownloadConfigName)
    }

    $unmatched = @($mapping | Where-Object { $_.Status -ne "対応" })
    if ($unmatched.Count -gt 0) {
        Write-Host ""
        Write-Host "=== アプリの対応付けで確認が必要な項目 ===" -ForegroundColor Yellow
        foreach ($m in $unmatched) {
            if (-not $m.DownloadAppId) {
                Write-Host "  テンプレートのアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow
            } else {
                Write-Host "  新スペースのアプリ[$($m.DownloadAppName)](appId=$($m.DownloadAppId))に対応するテンプレートのアプリが見つかりません" -ForegroundColor Yellow
            }
        }
    }

    # --- space-settings（スペース名は新スペース側、それ以外はテンプレート側の値を使う） ---
    $outSpaceRow = [PSCustomObject]@{
        "スペースID"                                                     = $newSpaceId
        "スペース名"                                                     = $finalSpaceName
        "参加メンバーだけにこのスペースを公開する"                       = $templateSpaceRow.'参加メンバーだけにこのスペースを公開する'
        "スペースのポータルと複数のスレッドを使用する"                   = $templateSpaceRow.'スペースのポータルと複数のスレッドを使用する'
        "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $templateSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
        "アプリ作成できるユーザーをスペースの管理者に限定する"           = $templateSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する'
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-settings" -Rows @($outSpaceRow) -Headers @("スペースID", "スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する")
    Write-Host ""
    Write-Host "=== space-settings ===" -ForegroundColor Cyan
    Write-Host "  スペースID[$newSpaceId] のスペース名を[$finalSpaceName]に設定"
    Write-Host "  参加メンバーだけにこのスペースを公開する=$($outSpaceRow.'参加メンバーだけにこのスペースを公開する') スペースのポータルと複数のスレッドを使用する=$($outSpaceRow.'スペースのポータルと複数のスレッドを使用する') スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する=$($outSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する') アプリ作成できるユーザーをスペースの管理者に限定する=$($outSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')"

    # --- space-member-list（テンプレートのメンバー構成をそのまま新スペースIDに適用） ---
    $outMemberRows = @($templateMemberRows | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $newSpaceId
            "種別"                   = $_.'種別'
            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
            "管理者"                 = $_.'管理者'
            "下位組織も含める"       = $_.'下位組織も含める'
        }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-member-list" -Rows $outMemberRows -Headers @("スペースID", "種別", "ユーザー/組織/グループ", "管理者", "下位組織も含める")
    Write-Host ""
    Write-Host "=== space-member-list ===" -ForegroundColor Cyan
    Write-Host "  スペースID[$newSpaceId] にメンバーを設定 ($($outMemberRows.Count)件)"

    # --- space-app-list（新スペース側の実際のID・アプリ名（{PH}置き換え済み）を使う） ---
    $matchedApps = @($mapping | Where-Object { $_.TemplateAppName -and $_.DownloadAppId })
    $outAppRows = @($matchedApps | ForEach-Object {
        [PSCustomObject]@{ "アプリID" = $_.DownloadAppId; "アプリ名" = $_.FinalAppName }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-list" -Rows $outAppRows -Headers @("アプリID", "アプリ名")
    Write-Host ""
    Write-Host "=== space-app-list ===" -ForegroundColor Cyan
    foreach ($m in $matchedApps) {
        Write-Host "  アプリID[$($m.DownloadAppId)] の名前を[$($m.FinalAppName)]に設定"
    }

    # --- space-app-acl（テンプレートの権限内容を、対応付けた新スペース側のID・アプリ名に付け替える） ---
    $outAclRows = New-Object System.Collections.Generic.List[psobject]
    Write-Host ""
    Write-Host "=== space-app-acl ===" -ForegroundColor Cyan
    foreach ($m in $matchedApps) {
        $rows = @($templateAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.TemplateAppName)" })
        foreach ($r in $rows) {
            $outAclRows.Add([PSCustomObject]@{
                "アプリID"         = $m.DownloadAppId
                "アプリ名"         = $m.FinalAppName
                "種別"             = $r.'種別'
                "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                "レコード閲覧"     = $r.'レコード閲覧'
                "レコード追加"     = $r.'レコード追加'
                "レコード編集"     = $r.'レコード編集'
                "レコード削除"     = $r.'レコード削除'
                "アプリ管理"       = $r.'アプリ管理'
                "ファイル読み込み" = $r.'ファイル読み込み'
                "ファイル書き出し" = $r.'ファイル書き出し'
            })
        }
        Write-Host "  アプリID[$($m.DownloadAppId)]($($m.FinalAppName)) のACLを設定 ($($rows.Count)件)"
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-acl" -Rows $outAclRows.ToArray() -Headers @("アプリID", "アプリ名", "種別", "ユーザー／組織／グループ", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し")

    # --- space-app-record-acl（同様に付け替える） ---
    $outRecordAclRows = New-Object System.Collections.Generic.List[psobject]
    Write-Host ""
    Write-Host "=== space-app-record-acl ===" -ForegroundColor Cyan
    foreach ($m in $matchedApps) {
        $rows = @($templateRecordAclRows | Where-Object { "$($_.'アプリ名')" -eq "$($m.TemplateAppName)" })
        foreach ($r in $rows) {
            $outRecordAclRows.Add([PSCustomObject]@{
                "アプリID"                 = $m.DownloadAppId
                "アプリ名"                 = $m.FinalAppName
                "レコードの条件"           = $r.'レコードの条件'
                "種別"                     = $r.'種別'
                "ユーザー／組織／グループ" = $r.'ユーザー／組織／グループ'
                "閲覧"                     = $r.'閲覧'
                "編集"                     = $r.'編集'
                "削除"                     = $r.'削除'
                "アクセス権の継承"         = $r.'アクセス権の継承'
            })
        }
        Write-Host "  アプリID[$($m.DownloadAppId)]($($m.FinalAppName)) のレコードACLを設定 (条件$($rows.Count)件)"
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-record-acl" -Rows $outRecordAclRows.ToArray() -Headers @("アプリID", "アプリ名", "レコードの条件", "種別", "ユーザー／組織／グループ", "閲覧", "編集", "削除", "アクセス権の継承")

    Set-KintoneHeaderRowColor -Path $outputPath -WorksheetNames @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl") -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))

    # --- 差分を赤字にする ---
    # スペース名・アプリ名はダウンロード結果の値に対して{PH}を置き換えただけなので、
    # 置き換わった部分（config名）だけをリッチテキストで赤字にする（"クラススペース"のような
    # 共通部分は、ダウンロードとテンプレートのどちらから見ても変わっていないため色を付けない）。
    # 非公開などの設定値はダウンロード結果の実際の値とテンプレートの値を比較し、異なるセルだけ
    # 赤字にする。space-member-list/space-app-acl/space-app-record-aclはダウンロード側に対応
    # データが無い（テンプレートから丸ごと生成した）行なので、行全体を赤字にする。
    $diffColor = [System.Drawing.Color]::FromArgb(255, 0, 0)
    $pkg = Open-ExcelPackage -Path $outputPath

    function Set-KintoneCellDiffColor {
        param($Cell, [string]$DownloadValue, [string]$FinalValue)
        if ($DownloadValue -eq $FinalValue) { return }
        $Cell.Style.Font.Color.SetColor($diffColor)
        $Cell.Style.Font.Bold = $true
    }

    $wsSettings = $pkg.Workbook.Worksheets["space-settings"]
    Set-KintonePlaceholderRichText -Cell $wsSettings.Cells[2, 2] -OriginalValue $downloadSpaceRow.'スペース名' -ConfigName $DownloadConfigName -Color $diffColor
    Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 3] -DownloadValue "$($downloadSpaceRow.'参加メンバーだけにこのスペースを公開する')" -FinalValue "$($templateSpaceRow.'参加メンバーだけにこのスペースを公開する')"
    Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 4] -DownloadValue "$($downloadSpaceRow.'スペースのポータルと複数のスレッドを使用する')" -FinalValue "$($templateSpaceRow.'スペースのポータルと複数のスレッドを使用する')"
    Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 5] -DownloadValue "$($downloadSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')" -FinalValue "$($templateSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する')"
    Set-KintoneCellDiffColor -Cell $wsSettings.Cells[2, 6] -DownloadValue "$($downloadSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')" -FinalValue "$($templateSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')"

    $wsAppList = $pkg.Workbook.Worksheets["space-app-list"]
    for ($i = 0; $i -lt $matchedApps.Count; $i++) {
        Set-KintonePlaceholderRichText -Cell $wsAppList.Cells[($i + 2), 2] -OriginalValue $matchedApps[$i].DownloadAppName -ConfigName $DownloadConfigName -Color $diffColor
    }

    foreach ($sheetName in @("space-member-list", "space-app-acl", "space-app-record-acl")) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws -or -not $ws.Dimension) { continue }
        for ($row = 2; $row -le $ws.Dimension.End.Row; $row++) {
            for ($col = 1; $col -le $ws.Dimension.End.Column; $col++) {
                $ws.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                $ws.Cells[$row, $col].Style.Font.Bold = $true
            }
        }
    }

    foreach ($sheetName in @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl")) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws) { continue }
        Set-KintoneColumnWidth -Worksheet $ws
    }

    Close-ExcelPackage $pkg

    Write-Host ""
    Write-Host "設定内容を出力しました: $outputPath" -ForegroundColor Green
    if ($unmatched.Count -gt 0) {
        $script:exitCode = 1
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Host ""
Write-Host "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
