# =========================================
# テンプレートと新スペースのダウンロード結果からconfigを自動生成する
# =========================================
# テンプレート（スペースID・アプリIDを持たず、アプリ名だけで紐づく共通ACL・メンバー設定）と
# ダウンロード結果（新スペースの実ID入り）をアプリ名の一致で対応付けてconfigを生成する。
# 対応付けられなかったアプリはコンソールに一覧表示するので、必要なら手動でconfigに追記する。
# スペース名・アプリ名の"{PH}"は、kintone側で最終名が決まる前の仮名という運用を想定し、
# 設定ファイル名に置き換える。kintoneへの書き込みは行わない。

param(
    [string]$TemplateConfigName,
    [string]$DownloadConfigName
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$templateRoot = $env:COMMON_TEMPLATE_PATH
$configRoot = $env:COMMON_CONFIG_PATH
$downloadRoot = $env:COMMON_DOWNLOAD_PATH
$logRoot = $env:COMMON_LOG_PATH

if (-not $templateRoot -or -not $configRoot -or -not $downloadRoot -or -not $logRoot) {
    Write-Message "COMMON_TEMPLATE_PATH / COMMON_CONFIG_PATH / COMMON_DOWNLOAD_PATH / COMMON_LOG_PATH を set-env.bat で設定してください"
    exit 1
}
if (-not $TemplateConfigName) {
    $TemplateConfigName = Read-Host "テンプレート名"
}
if (-not $DownloadConfigName) {
    $DownloadConfigName = Read-Host "設定ファイル名"
}

$templatePath = Join-Path $templateRoot "$TemplateConfigName.xlsx"
$downloadPath = Join-Path $downloadRoot "${DownloadConfigName}_download.xlsx"
$outputPath = Join-Path $configRoot "${DownloadConfigName}_config.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "generate_$DownloadConfigName"

$script:exitCode = 0

& {
    $templateSpaceRow = Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-settings" | Select-Object -First 1
    $templateMemberRows = @(Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-member-list")
    $templateAppRows = @(Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-list" | Where-Object { $_.'アプリ名' })
    $templateAclRows = @(Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-acl")
    $templateRecordAclRows = @(Read-KintoneExcelRows -Path $templatePath -WorksheetName "space-app-record-acl")

    $downloadSpaceRow = Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-settings" | Select-Object -First 1
    $downloadAppRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-list" | Where-Object { $_.'アプリID' })
    $downloadAclRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-acl")
    $downloadRecordAclRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-app-record-acl")

    if (-not $templateSpaceRow -or -not $downloadSpaceRow) {
        Write-Message "テンプレートまたはダウンロード結果のspace-settingsが空です" -ForegroundColor Red
        $script:exitCode = 1
        return
    }
    $newSpaceId = $downloadSpaceRow.'スペースID'
    $finalSpaceName = Expand-KintonePlaceholder -Value $downloadSpaceRow.'スペース名' -ConfigName $DownloadConfigName

    $mapping = Get-AppNameMapping -TemplateApps $templateAppRows -DownloadApps $downloadAppRows

    # DownloadAppNameは対応付けに使った元の名前として残すため、{PH}置き換え後の名前は別プロパティに持たせる
    foreach ($m in $mapping) {
        $m | Add-Member -NotePropertyName "FinalAppName" -NotePropertyValue (Expand-KintonePlaceholder -Value $m.DownloadAppName -ConfigName $DownloadConfigName)
    }

    $unmatched = @($mapping | Where-Object { $_.Status -ne "対応" })
    if ($unmatched.Count -gt 0) {
        Write-Message ""
        Write-Message "=== アプリの対応付けで確認が必要な項目 ===" -ForegroundColor Yellow
        foreach ($m in $unmatched) {
            if (-not $m.DownloadAppId) {
                Write-Message "  テンプレートのアプリ[$($m.TemplateAppName)]に対応する新スペースのアプリが見つかりません" -ForegroundColor Yellow
            } else {
                Write-Message "  新スペースのアプリ[$($m.DownloadAppName)](appId=$($m.DownloadAppId))に対応するテンプレートのアプリが見つかりません" -ForegroundColor Yellow
            }
        }
    }

    # space-settings: スペース名は新スペース側、それ以外はテンプレート側の値を使う
    $outSpaceRow = [PSCustomObject]@{
        "スペースID"                                                     = $newSpaceId
        "スペース名"                                                     = $finalSpaceName
        "参加メンバーだけにこのスペースを公開する"                       = $templateSpaceRow.'参加メンバーだけにこのスペースを公開する'
        "スペースのポータルと複数のスレッドを使用する"                   = $templateSpaceRow.'スペースのポータルと複数のスレッドを使用する'
        "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する" = $templateSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する'
        "アプリ作成できるユーザーをスペースの管理者に限定する"           = $templateSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する'
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-settings" -Rows @($outSpaceRow) -Headers @("スペースID", "スペース名", "参加メンバーだけにこのスペースを公開する", "スペースのポータルと複数のスレッドを使用する", "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する", "アプリ作成できるユーザーをスペースの管理者に限定する")
    Write-Message ""
    Write-Message "=== space-settings ===" -ForegroundColor Cyan
    Write-Message "  スペースID[$newSpaceId] のスペース名を[$finalSpaceName]に設定"
    Write-Message "  参加メンバーだけにこのスペースを公開する=$($outSpaceRow.'参加メンバーだけにこのスペースを公開する') スペースのポータルと複数のスレッドを使用する=$($outSpaceRow.'スペースのポータルと複数のスレッドを使用する') スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する=$($outSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する') アプリ作成できるユーザーをスペースの管理者に限定する=$($outSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する')"

    # テンプレートに無い既存メンバー（スペース作成時にkintoneが自動追加する個人ユーザーなど）は
    # ダウンロード結果から引き継ぐ。apply側のSet-SpaceMembersはシートに無いコードのメンバーを
    # 消さずに残す設計のため、ここで引き継いでおかないとcheckで「想定外」と誤検知される
    $downloadMemberRows = @(Read-KintoneExcelRows -Path $downloadPath -WorksheetName "space-member-list")
    $templateMemberCodes = @($templateMemberRows | ForEach-Object { $_.'ユーザー/組織/グループ' })
    $keptMemberRows = @($downloadMemberRows | Where-Object { $templateMemberCodes -notcontains $_.'ユーザー/組織/グループ' })

    $outMemberRows = @($templateMemberRows | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $newSpaceId
            "種別"                   = $_.'種別'
            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
            "管理者"                 = $_.'管理者'
            "下位組織も含める"       = $_.'下位組織も含める'
        }
    }) + @($keptMemberRows | ForEach-Object {
        [PSCustomObject]@{
            "スペースID"             = $newSpaceId
            "種別"                   = $_.'種別'
            "ユーザー/組織/グループ" = $_.'ユーザー/組織/グループ'
            "管理者"                 = $_.'管理者'
            "下位組織も含める"       = $_.'下位組織も含める'
        }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-member-list" -Rows $outMemberRows -Headers @("スペースID", "種別", "ユーザー/組織/グループ", "管理者", "下位組織も含める")
    Write-Message ""
    Write-Message "=== space-member-list ===" -ForegroundColor Cyan
    Write-Message "  スペースID[$newSpaceId] にテンプレートのメンバーを設定 ($($templateMemberRows.Count)件)"
    if ($keptMemberRows.Count -gt 0) {
        Write-Message "  テンプレートに無い既存メンバーを引き継ぎ ($($keptMemberRows.Count)件): $(($keptMemberRows | ForEach-Object { $_.'ユーザー/組織/グループ' }) -join ', ')" -ForegroundColor Yellow
    }

    $matchedApps = @($mapping | Where-Object { $_.TemplateAppName -and $_.DownloadAppId })
    $outAppRows = @($matchedApps | ForEach-Object {
        [PSCustomObject]@{ "アプリID" = $_.DownloadAppId; "アプリ名" = $_.FinalAppName }
    })
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-list" -Rows $outAppRows -Headers @("アプリID", "アプリ名")
    Write-Message ""
    Write-Message "=== space-app-list ===" -ForegroundColor Cyan
    foreach ($m in $matchedApps) {
        Write-Message "  アプリID[$($m.DownloadAppId)] の名前を[$($m.FinalAppName)]に設定"
    }

    $outAclRows = New-Object System.Collections.Generic.List[psobject]
    $aclRowSources = New-Object System.Collections.Generic.List[psobject]
    Write-Message ""
    Write-Message "=== space-app-acl ===" -ForegroundColor Cyan
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
            $aclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
        }
        Write-Message "  アプリID[$($m.DownloadAppId)]($($m.FinalAppName)) のACLを設定 ($($rows.Count)件)"
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-acl" -Rows $outAclRows.ToArray() -Headers @("アプリID", "アプリ名", "種別", "ユーザー／組織／グループ", "レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し")

    $outRecordAclRows = New-Object System.Collections.Generic.List[psobject]
    $recordAclRowSources = New-Object System.Collections.Generic.List[psobject]
    Write-Message ""
    Write-Message "=== space-app-record-acl ===" -ForegroundColor Cyan
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
            })
            $recordAclRowSources.Add([PSCustomObject]@{ DownloadAppName = $m.DownloadAppName; TemplateRow = $r })
        }
        Write-Message "  アプリID[$($m.DownloadAppId)]($($m.FinalAppName)) のレコードACLを設定 (条件$($rows.Count)件)"
    }
    Write-KintoneExcelRows -Path $outputPath -WorksheetName "space-app-record-acl" -Rows $outRecordAclRows.ToArray() -Headers @("アプリID", "アプリ名", "レコードの条件", "種別", "ユーザー／組織／グループ", "閲覧", "編集", "削除")

    Set-KintoneHeaderRowColor -Path $outputPath -WorksheetNames @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl") -Color ([System.Drawing.Color]::FromArgb(217, 217, 217))

    $applyDiffColoring = $true # 赤字処理を一旦無効化

    # スペース名・アプリ名は{PH}置き換え部分だけを赤字にする。
    # それ以外は、ユニークキーでダウンロード結果に対応する行がある場合は値が異なるセルだけを赤字にし、
    # 対応する行が無い（新規追加）場合は行全体を赤字にする。ユニークキーは以下:
    #   space-settings: なし（1行のみ）
    #   space-member-list: 種別, ユーザー/組織/グループ
    #   space-app-list: アプリ名（マッチング済みのアプリのみ出力するため常に対応行あり）
    #   space-app-acl: アプリ名, 種別, ユーザー／組織／グループ
    #   space-app-record-acl: アプリ名, レコードの条件, 種別, ユーザー／組織／グループ
    $diffColor = [System.Drawing.Color]::FromArgb(255, 0, 0)
    $pkg = Open-ExcelPackage -Path $outputPath

    function Set-KintoneCellDiffColor {
        param($Cell, [string]$DownloadValue, [string]$FinalValue)
        if ($DownloadValue -eq $FinalValue) { return }
        $Cell.Style.Font.Color.SetColor($diffColor)
        $Cell.Style.Font.Bold = $true
    }

    if ($applyDiffColoring) {
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

        $wsMember = $pkg.Workbook.Worksheets["space-member-list"]
        if ($wsMember -and $wsMember.Dimension) {
            $templateRowEnd = [Math]::Min(1 + $templateMemberRows.Count, $wsMember.Dimension.End.Row)
            for ($row = 2; $row -le $templateRowEnd; $row++) {
                $tmplRow = $templateMemberRows[$row - 2]
                # ユニークキー: 種別 + ユーザー/組織/グループ
                $dlRow = $downloadMemberRows | Where-Object {
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー/組織/グループ')" -eq "$($tmplRow.'ユーザー/組織/グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsMember.Dimension.End.Column; $col++) {
                        $wsMember.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsMember.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsMember.Cells[$row, 4] -DownloadValue "$($dlRow.'管理者')" -FinalValue "$($tmplRow.'管理者')"
                Set-KintoneCellDiffColor -Cell $wsMember.Cells[$row, 5] -DownloadValue "$($dlRow.'下位組織も含める')" -FinalValue "$($tmplRow.'下位組織も含める')"
            }
        }

        $wsAcl = $pkg.Workbook.Worksheets["space-app-acl"]
        if ($wsAcl -and $wsAcl.Dimension) {
            for ($i = 0; $i -lt $aclRowSources.Count; $i++) {
                $row = $i + 2
                if ($row -gt $wsAcl.Dimension.End.Row) { break }
                $src = $aclRowSources[$i]
                $tmplRow = $src.TemplateRow
                # ユニークキー: アプリ名 + 種別 + ユーザー／組織／グループ
                $dlRow = $downloadAclRows | Where-Object {
                    "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsAcl.Dimension.End.Column; $col++) {
                        $wsAcl.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsAcl.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 5] -DownloadValue "$($dlRow.'レコード閲覧')" -FinalValue "$($tmplRow.'レコード閲覧')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 6] -DownloadValue "$($dlRow.'レコード追加')" -FinalValue "$($tmplRow.'レコード追加')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 7] -DownloadValue "$($dlRow.'レコード編集')" -FinalValue "$($tmplRow.'レコード編集')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 8] -DownloadValue "$($dlRow.'レコード削除')" -FinalValue "$($tmplRow.'レコード削除')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 9] -DownloadValue "$($dlRow.'アプリ管理')" -FinalValue "$($tmplRow.'アプリ管理')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 10] -DownloadValue "$($dlRow.'ファイル読み込み')" -FinalValue "$($tmplRow.'ファイル読み込み')"
                Set-KintoneCellDiffColor -Cell $wsAcl.Cells[$row, 11] -DownloadValue "$($dlRow.'ファイル書き出し')" -FinalValue "$($tmplRow.'ファイル書き出し')"
            }
        }

        $wsRecordAcl = $pkg.Workbook.Worksheets["space-app-record-acl"]
        if ($wsRecordAcl -and $wsRecordAcl.Dimension) {
            for ($i = 0; $i -lt $recordAclRowSources.Count; $i++) {
                $row = $i + 2
                if ($row -gt $wsRecordAcl.Dimension.End.Row) { break }
                $src = $recordAclRowSources[$i]
                $tmplRow = $src.TemplateRow
                # ユニークキー: アプリ名 + レコードの条件 + 種別 + ユーザー／組織／グループ
                $dlRow = $downloadRecordAclRows | Where-Object {
                    "$($_.'アプリ名')" -eq "$($src.DownloadAppName)" -and
                    "$($_.'レコードの条件')" -eq "$($tmplRow.'レコードの条件')" -and
                    "$($_.'種別')" -eq "$($tmplRow.'種別')" -and
                    "$($_.'ユーザー／組織／グループ')" -eq "$($tmplRow.'ユーザー／組織／グループ')"
                } | Select-Object -First 1
                if (-not $dlRow) {
                    for ($col = 1; $col -le $wsRecordAcl.Dimension.End.Column; $col++) {
                        $wsRecordAcl.Cells[$row, $col].Style.Font.Color.SetColor($diffColor)
                        $wsRecordAcl.Cells[$row, $col].Style.Font.Bold = $true
                    }
                    continue
                }
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 6] -DownloadValue "$($dlRow.'閲覧')" -FinalValue "$($tmplRow.'閲覧')"
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 7] -DownloadValue "$($dlRow.'編集')" -FinalValue "$($tmplRow.'編集')"
                Set-KintoneCellDiffColor -Cell $wsRecordAcl.Cells[$row, 8] -DownloadValue "$($dlRow.'削除')" -FinalValue "$($tmplRow.'削除')"
            }
        }
    }

    foreach ($sheetName in @("space-settings", "space-member-list", "space-app-list", "space-app-acl", "space-app-record-acl")) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws) { continue }
        Set-KintoneColumnWidth -Worksheet $ws
    }

    Close-ExcelPackage $pkg

    Write-Message ""
    Write-Message "設定内容を出力しました: $outputPath" -ForegroundColor Green
    if ($unmatched.Count -gt 0) {
        # 対応付け未了の警告のみで設定ファイル自体は生成済みのため、致命的エラー(exit 1)とは区別する
        $script:exitCode = 2
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message ""
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
