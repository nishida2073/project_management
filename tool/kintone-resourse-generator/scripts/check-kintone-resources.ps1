# =========================================
# kintoneの現在の状態と編集済みExcelを比較する（読み取り専用）
# =========================================
# config\<CONFIG_NAME>.xlsx（期待値）とkintoneの現在の状態を比較し、差分をExcelに出力する。
# 出力はダウンロードファイルと同じ5シート構成（space-settings / space-member-list /
# space-app-list / space-app-acl / space-app-record-acl）。各シートは同じキー列に加えて
# 項目ごとの「_現状」「_期待値」列と、行全体の「結果」列（一致/不一致/kintoneに未定義/設定ファイルに未定義/Everyoneの影響）を持つ。
# kintoneへの書き込みは行わない。

param(
    [string]$ConfigName,
    [string]$Sheets
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$baseUrl = $env:KINTONE_BASE_URL
$configRoot = $env:COMMON_CONFIG_PATH
$outputRoot = $env:COMMON_CHECK_OUTPUT_PATH
$logRoot = $env:COMMON_LOG_PATH

if (-not $baseUrl -or -not $configRoot -or -not $outputRoot -or -not $logRoot) {
    Write-Message "KINTONE_BASE_URL / COMMON_CONFIG_PATH / COMMON_CHECK_OUTPUT_PATH / COMMON_LOG_PATH を設定してください（clients\set-kintone.bat・set-env.bat）"
    exit 1
}
if (-not $ConfigName) {
    $ConfigName = Read-Host "設定ファイル名（config\<CONFIG_NAME>_config.xlsx の<CONFIG_NAME>）"
}

$configPath = Join-Path $configRoot "${ConfigName}_config.xlsx"
$outputPath = Join-Path $outputRoot "${ConfigName}_check.xlsx"
$logFilePath = New-KintoneLogPath -LogRoot $logRoot -Prefix "check_$ConfigName"

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
        Write-Message "対象シートを絞り込みます: $($selectedSheets -join ', ')" -ForegroundColor Cyan
    }
    $checkSpaceSettings = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-settings"
    $checkSpaceMembers  = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-member-list"
    $checkAppList       = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-list"
    $checkAppAcl        = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-acl"
    $checkAppRecordAcl  = Test-SheetSelected -SelectedSheets $selectedSheets -Name "space-app-record-acl"

    # $Pairs: @({Label; Current; Expected}, ...) を "<Label>_現状"/"<Label>_期待値" 列に展開する。
    # 全項目が一致すれば"一致"、1つでも違えば"不一致"を返す（存在有無はこの関数の外で判定する）。
    function Add-FieldColumns {
        param([System.Collections.Specialized.OrderedDictionary]$Row, [array]$Pairs)
        $allMatch = $true
        foreach ($p in $Pairs) {
            $Row["$($p.Label)_現状"] = $p.Current
            $Row["$($p.Label)_期待値"] = $p.Expected
            if ("$($p.Current)" -ne "$($p.Expected)") { $allMatch = $false }
        }
        return $allMatch
    }

    # Everyoneが持つ権限がそのまま個別ユーザーの現状としてkintone側に残ることがあるため、
    # 「設定ファイルに未定義」の現状値がEveryoneの期待値と完全一致する場合だけ"Everyoneの影響"として区別する。
    function Test-PairsMatch {
        param([array]$Pairs)
        foreach ($p in $Pairs) {
            if ("$($p.Current)" -ne "$($p.Expected)") { return $false }
        }
        return $true
    }

    # List[object]（型引数がobject）を@()で囲むとWindows PowerShell 5.1で
    # "Argument types do not match" エラーになり中身が消える。List[psobject]なら問題ない。
    $spaceSettingsDiff = New-Object System.Collections.Generic.List[psobject]
    $memberDiff = New-Object System.Collections.Generic.List[psobject]
    $appListDiff = New-Object System.Collections.Generic.List[psobject]
    $appAclDiff = New-Object System.Collections.Generic.List[psobject]
    $appRecordAclDiff = New-Object System.Collections.Generic.List[psobject]

    if ($checkSpaceSettings -or $checkSpaceMembers) {
        foreach ($spaceGroup in (Group-RowsBySpaceId -Rows $spaceRows)) {
            $spaceId = $spaceGroup.Name
            $expectedSpaceRow = $spaceGroup.Group | Select-Object -First 1
            Write-Message ""
            Write-Message "=== スペースID: $spaceId ($($expectedSpaceRow.'スペース名')) ===" -ForegroundColor Cyan

            $current = $null
            try {
                $current = Get-CurrentSpace -SpaceId $spaceId -BaseUrl $baseUrl -Authorization $authorization -HasAppAcl:$false -HasRecordAcl:$false
            } catch {
                if ($checkSpaceSettings) {
                    $row = [ordered]@{ "スペースID" = $spaceId }
                    $row["結果"] = "kintoneに未定義"
                    $spaceSettingsDiff.Add([PSCustomObject]$row)
                }
                continue
            }

            if ($checkSpaceSettings) {
                $row = [ordered]@{ "スペースID" = $spaceId; "結果" = $null }
                $allMatch = Add-FieldColumns -Row $row -Pairs @(
                    @{ Label = "スペース名";                                                       Current = $current.spaceName;      Expected = $expectedSpaceRow.'スペース名' },
                    @{ Label = "参加メンバーだけにこのスペースを公開する";                           Current = $current.isPrivate;      Expected = (ToBool $expectedSpaceRow.'参加メンバーだけにこのスペースを公開する') },
                    @{ Label = "スペースのポータルと複数のスレッドを使用する";                       Current = $current.useMultiThread; Expected = (ToBool $expectedSpaceRow.'スペースのポータルと複数のスレッドを使用する') },
                    @{ Label = "スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する"; Current = $current.fixedMember;    Expected = (ToBool $expectedSpaceRow.'スペースの参加/退会、スレッドのフォロー/フォロー解除を禁止する') },
                    @{ Label = "アプリ作成できるユーザーをスペースの管理者に限定する";               Current = ($current.createApp -eq "ADMIN"); Expected = (ToBool $expectedSpaceRow.'アプリ作成できるユーザーをスペースの管理者に限定する') }
                )
                $row["結果"] = if ($allMatch) { "一致" } else { "不一致" }
                $spaceSettingsDiff.Add([PSCustomObject]$row)
            }

            if ($checkSpaceMembers) {
                $currentMembersByCode = @{}
                foreach ($m in $current.members) {
                    $currentMembersByCode[$m.entity.code] = $m
                }
                $expectedMemberRows = @($memberRows | Where-Object { $_.'スペースID' -eq $spaceId })
                $expectedMembersByCode = @{}
                foreach ($r in $expectedMemberRows) { $expectedMembersByCode[$r.'ユーザー/組織/グループ'] = $r }

                $allOrgCodes = @($currentMembersByCode.Keys) + @($expectedMembersByCode.Keys) | Select-Object -Unique
                foreach ($code in $allOrgCodes) {
                    $cur = $currentMembersByCode[$code]
                    $exp = $expectedMembersByCode[$code]
                    # 種別は比較対象ではなく表示用の参考情報。現状があればそれを正とし、
                    # 現状が無い（存在しない）場合はシートの種別、無ければ自動判定を試す。
                    $typeLabel = if ($cur) {
                        Get-KintoneMemberTypeLabel $cur.entity.type
                    } elseif ($exp.'種別') {
                        $exp.'種別'
                    } else {
                        try { Get-KintoneMemberTypeLabel (Get-KintoneMemberEntityType -BaseUrl $baseUrl -Authorization $authorization -Code $code) } catch { "不明" }
                    }
                    $row = [ordered]@{ "スペースID" = $spaceId; "種別" = $typeLabel; "ユーザー/組織/グループ" = $code; "結果" = $null }
                    if ($cur -and -not $exp) {
                        $row["管理者_現状"] = $cur.isAdmin; $row["管理者_期待値"] = $null
                        $row["下位組織も含める_現状"] = $cur.includeSubs; $row["下位組織も含める_期待値"] = $null
                        $everyoneExp = $expectedMembersByCode["everyone"]
                        $matchesEveryone = $cur.entity.type -eq "USER" -and $everyoneExp -and (Test-PairsMatch @(
                            @{ Current = $cur.isAdmin;     Expected = (ToBool $everyoneExp.'管理者') },
                            @{ Current = $cur.includeSubs; Expected = (ToBool $everyoneExp.'下位組織も含める') }
                        ))
                        $row["結果"] = if ($matchesEveryone) { "Everyoneの影響" } else { "設定ファイルに未定義" }
                    } elseif (-not $cur -and $exp) {
                        $row["管理者_現状"] = $null; $row["管理者_期待値"] = (ToBool $exp.'管理者')
                        $row["下位組織も含める_現状"] = $null; $row["下位組織も含める_期待値"] = (ToBool $exp.'下位組織も含める')
                        $row["結果"] = "kintoneに未定義"
                    } else {
                        $allMatch = Add-FieldColumns -Row $row -Pairs @(
                            @{ Label = "管理者";           Current = $cur.isAdmin;     Expected = (ToBool $exp.'管理者') },
                            @{ Label = "下位組織も含める"; Current = $cur.includeSubs; Expected = (ToBool $exp.'下位組織も含める') }
                        )
                        $row["結果"] = if ($allMatch) { "一致" } else { "不一致" }
                    }
                    $memberDiff.Add([PSCustomObject]$row)
                }
            }
        }
    }

    if ($checkAppList -or $checkAppAcl -or $checkAppRecordAcl) {
        Write-Message ""
        Write-Message "=== アプリの確認 ===" -ForegroundColor Cyan

        $allAppIds = @(
            @($(if ($checkAppList) { $appRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } })) +
            @($(if ($checkAppAcl) { $appAclRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } })) +
            @($(if ($checkAppRecordAcl) { $recordAclRows | Where-Object { $_.'アプリID' } | ForEach-Object { "$($_.'アプリID')" } }))
        ) | Select-Object -Unique

        $skippedAppRows = @($appRows | Where-Object { -not $_.'アプリID' })
        if ($checkAppList -and $skippedAppRows.Count -gt 0) {
            Write-Message "(アプリIDが空の行($($skippedAppRows.Count)件)は確認対象外です)" -ForegroundColor Yellow
        }

        foreach ($appId in $allAppIds) {
            Write-Message "アプリID: $appId を確認中..."
            $current = Get-AppCurrentInfo -BaseUrl $baseUrl -Authorization $authorization -AppId $appId
            $appLabel = $current.name

            if ($checkAppList) {
                $expectedAppRow = $appRows | Where-Object { "$($_.'アプリID')" -eq $appId } | Select-Object -First 1
                if ($expectedAppRow) {
                    if (-not $appLabel) {
                        $row = [ordered]@{ "アプリID" = $appId; "結果" = "kintoneに未定義"; "アプリ名_現状" = $null; "アプリ名_期待値" = $expectedAppRow.'アプリ名' }
                    } else {
                        $row = [ordered]@{ "アプリID" = $appId; "結果" = $null }
                        $allMatch = Add-FieldColumns -Row $row -Pairs @(
                            @{ Label = "アプリ名"; Current = $appLabel; Expected = $expectedAppRow.'アプリ名' }
                        )
                        $row["結果"] = if ($allMatch) { "一致" } else { "不一致" }
                    }
                    $appListDiff.Add([PSCustomObject]$row)
                    if (-not $appLabel) { $appLabel = $expectedAppRow.'アプリ名' }
                }
            }

            # 組織名で突き合わせ
            if ($checkAppAcl) {
                $expectedAclRowsForApp = @($appAclRows | Where-Object { "$($_.'アプリID')" -eq $appId })
                $expectedAclByOrg = @{}
                foreach ($r in $expectedAclRowsForApp) {
                    $expectedAclByOrg[$r.'ユーザー／組織／グループ'] = $r
                    if (-not $appLabel) { $appLabel = $r.'アプリ名' }
                }

                $currentAclByOrg = @{}
                foreach ($r in ($current.rights | Where-Object { $_.entity.type -ne "CREATOR" })) {
                    $currentAclByOrg[$r.entity.code] = $r
                }

                $allOrgCodes = @($currentAclByOrg.Keys) + @($expectedAclByOrg.Keys) | Select-Object -Unique
                foreach ($orgName in $allOrgCodes) {
                    $cur = $currentAclByOrg[$orgName]
                    $exp = $expectedAclByOrg[$orgName]
                    $typeLabel = if ($cur) {
                        Get-KintoneMemberTypeLabel $cur.entity.type
                    } elseif ($exp.'種別') {
                        $exp.'種別'
                    } else {
                        try { Get-KintoneMemberTypeLabel (Get-KintoneMemberEntityType -BaseUrl $baseUrl -Authorization $authorization -Code $orgName) } catch { "不明" }
                    }
                    $row = [ordered]@{ "アプリID" = $appId; "アプリ名" = $appLabel; "種別" = $typeLabel; "ユーザー／組織／グループ" = $orgName; "結果" = $null }
                    if ($cur -and -not $exp) {
                        foreach ($label in @("レコード閲覧", "レコード追加", "レコード編集", "レコード削除", "アプリ管理", "ファイル読み込み", "ファイル書き出し")) {
                            $row["${label}_現状"] = $null; $row["${label}_期待値"] = $null
                        }
                        $row["レコード閲覧_現状"] = $cur.recordViewable; $row["レコード追加_現状"] = $cur.recordAddable
                        $row["レコード編集_現状"] = $cur.recordEditable; $row["レコード削除_現状"] = $cur.recordDeletable
                        $row["アプリ管理_現状"] = $cur.appEditable; $row["ファイル読み込み_現状"] = $cur.recordImportable
                        $row["ファイル書き出し_現状"] = $cur.recordExportable
                        $everyoneExp = $expectedAclByOrg["everyone"]
                        $matchesEveryone = $cur.entity.type -eq "USER" -and $everyoneExp -and (Test-PairsMatch @(
                            @{ Current = $cur.recordViewable;   Expected = (ToBool $everyoneExp.'レコード閲覧') },
                            @{ Current = $cur.recordAddable;    Expected = (ToBool $everyoneExp.'レコード追加') },
                            @{ Current = $cur.recordEditable;   Expected = (ToBool $everyoneExp.'レコード編集') },
                            @{ Current = $cur.recordDeletable;  Expected = (ToBool $everyoneExp.'レコード削除') },
                            @{ Current = $cur.appEditable;      Expected = (ToBool $everyoneExp.'アプリ管理') },
                            @{ Current = $cur.recordImportable; Expected = (ToBool $everyoneExp.'ファイル読み込み') },
                            @{ Current = $cur.recordExportable; Expected = (ToBool $everyoneExp.'ファイル書き出し') }
                        ))
                        $row["結果"] = if ($matchesEveryone) { "Everyoneの影響" } else { "設定ファイルに未定義" }
                    } elseif (-not $cur -and $exp) {
                        $row["レコード閲覧_現状"] = $null; $row["レコード閲覧_期待値"] = (ToBool $exp.'レコード閲覧')
                        $row["レコード追加_現状"] = $null; $row["レコード追加_期待値"] = (ToBool $exp.'レコード追加')
                        $row["レコード編集_現状"] = $null; $row["レコード編集_期待値"] = (ToBool $exp.'レコード編集')
                        $row["レコード削除_現状"] = $null; $row["レコード削除_期待値"] = (ToBool $exp.'レコード削除')
                        $row["アプリ管理_現状"] = $null; $row["アプリ管理_期待値"] = (ToBool $exp.'アプリ管理')
                        $row["ファイル読み込み_現状"] = $null; $row["ファイル読み込み_期待値"] = (ToBool $exp.'ファイル読み込み')
                        $row["ファイル書き出し_現状"] = $null; $row["ファイル書き出し_期待値"] = (ToBool $exp.'ファイル書き出し')
                        $row["結果"] = "kintoneに未定義"
                    } else {
                        $allMatch = Add-FieldColumns -Row $row -Pairs @(
                            @{ Label = "レコード閲覧";     Current = $cur.recordViewable;   Expected = (ToBool $exp.'レコード閲覧') },
                            @{ Label = "レコード追加";     Current = $cur.recordAddable;    Expected = (ToBool $exp.'レコード追加') },
                            @{ Label = "レコード編集";     Current = $cur.recordEditable;   Expected = (ToBool $exp.'レコード編集') },
                            @{ Label = "レコード削除";     Current = $cur.recordDeletable;  Expected = (ToBool $exp.'レコード削除') },
                            @{ Label = "アプリ管理";       Current = $cur.appEditable;      Expected = (ToBool $exp.'アプリ管理') },
                            @{ Label = "ファイル読み込み"; Current = $cur.recordImportable; Expected = (ToBool $exp.'ファイル読み込み') },
                            @{ Label = "ファイル書き出し"; Current = $cur.recordExportable;  Expected = (ToBool $exp.'ファイル書き出し') }
                        )
                        $row["結果"] = if ($allMatch) { "一致" } else { "不一致" }
                    }
                    $appAclDiff.Add([PSCustomObject]$row)
                }
            }

            # 条件＋組織名で突き合わせ
            if ($checkAppRecordAcl) {
                $expectedRecordAclRowsForApp = @($recordAclRows | Where-Object { "$($_.'アプリID')" -eq $appId })
                $expectedRecordAclByKey = @{}
                foreach ($r in $expectedRecordAclRowsForApp) {
                    $expectedRecordAclByKey["$($r.'レコードの条件')|$($r.'ユーザー／組織／グループ')"] = $r
                    if (-not $appLabel) { $appLabel = $r.'アプリ名' }
                }

                $currentRecordAclByKey = @{}
                foreach ($r in $current.recordRights) {
                    foreach ($entity in $r.entities) {
                        $orgName = if ($entity.entity.type -eq "CREATOR") { "作成者" } else { $entity.entity.code }
                        $currentRecordAclByKey["$($r.filterCond)|$orgName"] = @{ FilterCond = $r.filterCond; Entity = $entity }
                    }
                }

                $allRecordAclKeys = @($currentRecordAclByKey.Keys) + @($expectedRecordAclByKey.Keys) | Select-Object -Unique
                foreach ($key in $allRecordAclKeys) {
                    $parts = $key -split '\|', 2
                    $cond = $parts[0]; $orgName = $parts[1]
                    $cur = $currentRecordAclByKey[$key]
                    $exp = $expectedRecordAclByKey[$key]
                    $typeLabel = if ($cur) {
                        if ($cur.Entity.entity.type -eq "CREATOR") { "作成者" } else { Get-KintoneMemberTypeLabel $cur.Entity.entity.type }
                    } elseif ($exp.'種別') {
                        $exp.'種別'
                    } elseif ($orgName -eq "作成者") {
                        "作成者"
                    } else {
                        try { Get-KintoneMemberTypeLabel (Get-KintoneMemberEntityType -BaseUrl $baseUrl -Authorization $authorization -Code $orgName) } catch { "不明" }
                    }
                    $row = [ordered]@{ "アプリID" = $appId; "アプリ名" = $appLabel; "レコードの条件" = $cond; "種別" = $typeLabel; "ユーザー／組織／グループ" = $orgName; "結果" = $null }
                    if ($cur -and -not $exp) {
                        $row["閲覧_現状"] = $cur.Entity.viewable; $row["閲覧_期待値"] = $null
                        $row["編集_現状"] = $cur.Entity.editable; $row["編集_期待値"] = $null
                        $row["削除_現状"] = $cur.Entity.deletable; $row["削除_期待値"] = $null
                        $everyoneExp = $expectedRecordAclByKey["$cond|everyone"]
                        $matchesEveryone = $cur.Entity.entity.type -eq "USER" -and $everyoneExp -and (Test-PairsMatch @(
                            @{ Current = $cur.Entity.viewable;  Expected = (ToBool $everyoneExp.'閲覧') },
                            @{ Current = $cur.Entity.editable;  Expected = (ToBool $everyoneExp.'編集') },
                            @{ Current = $cur.Entity.deletable; Expected = (ToBool $everyoneExp.'削除') }
                        ))
                        $row["結果"] = if ($matchesEveryone) { "Everyoneの影響" } else { "設定ファイルに未定義" }
                    } elseif (-not $cur -and $exp) {
                        $row["閲覧_現状"] = $null; $row["閲覧_期待値"] = (ToBool $exp.'閲覧')
                        $row["編集_現状"] = $null; $row["編集_期待値"] = (ToBool $exp.'編集')
                        $row["削除_現状"] = $null; $row["削除_期待値"] = (ToBool $exp.'削除')
                        $row["結果"] = "kintoneに未定義"
                    } else {
                        $allMatch = Add-FieldColumns -Row $row -Pairs @(
                            @{ Label = "閲覧"; Current = $cur.Entity.viewable;  Expected = (ToBool $exp.'閲覧') },
                            @{ Label = "編集"; Current = $cur.Entity.editable;  Expected = (ToBool $exp.'編集') },
                            @{ Label = "削除"; Current = $cur.Entity.deletable; Expected = (ToBool $exp.'削除') }
                        )
                        $row["結果"] = if ($allMatch) { "一致" } else { "不一致" }
                    }
                    $appRecordAclDiff.Add([PSCustomObject]$row)
                }
            }
        }
    }

    New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue

    $sheetData = [ordered]@{
        "space-settings"       = $spaceSettingsDiff
        "space-member-list"    = $memberDiff
        "space-app-list"       = $appListDiff
        "space-app-acl"        = $appAclDiff
        "space-app-record-acl" = $appRecordAclDiff
    }
    foreach ($sheetName in $sheetData.Keys) {
        $rows = @($sheetData[$sheetName])
        if ($rows.Count -eq 0) { continue }
        $rows | Export-Excel -Path $outputPath -WorksheetName $sheetName -AutoSize
    }

    # 各シートの「結果」列（ヘッダー名で検索、シートごとに位置が異なる）に色を付ける。
    $colorMap = @{
        "一致"                 = [System.Drawing.Color]::FromArgb(0, 128, 0)
        "不一致"               = [System.Drawing.Color]::FromArgb(255, 0, 0)
        "kintoneに未定義"        = [System.Drawing.Color]::FromArgb(255, 0, 255)
        "設定ファイルに未定義"   = [System.Drawing.Color]::FromArgb(128, 128, 0)
        "Everyoneの影響" = [System.Drawing.Color]::FromArgb(128, 128, 128)
    }
    # 「_現状」列は緑系、「_期待値」列は青系、「結果」列は黄系、それ以外（キー列）は灰色系にする。
    $genjoColor = [System.Drawing.Color]::FromArgb(226, 239, 218)
    $kitaichiColor = [System.Drawing.Color]::FromArgb(198, 224, 241)
    $resultHeaderColor = [System.Drawing.Color]::FromArgb(255, 230, 153)
    $otherColor = [System.Drawing.Color]::FromArgb(217, 217, 217)
    $pkg = Open-ExcelPackage -Path $outputPath
    foreach ($sheetName in $sheetData.Keys) {
        $ws = $pkg.Workbook.Worksheets[$sheetName]
        if (-not $ws) { continue }
        $lastRow = $ws.Dimension.End.Row
        $lastCol = $ws.Dimension.End.Column
        $resultCol = 0
        # "<項目名>_現状"/"<項目名>_期待値" の列ペアを項目名ごとに集める（行ごとの値比較に使う）。
        $fieldPairCols = @{}
        for ($c = 1; $c -le $lastCol; $c++) {
            $header = $ws.Cells[1, $c].Text
            if ($header -eq "結果") { $resultCol = $c }
            $headerCell = $ws.Cells[1, $c]
            $headerCell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            if ($header.EndsWith("_現状")) {
                $headerCell.Style.Fill.BackgroundColor.SetColor($genjoColor)
                $label = $header.Substring(0, $header.Length - "_現状".Length)
                if (-not $fieldPairCols.ContainsKey($label)) { $fieldPairCols[$label] = @{} }
                $fieldPairCols[$label]["現状"] = $c
            } elseif ($header.EndsWith("_期待値")) {
                $headerCell.Style.Fill.BackgroundColor.SetColor($kitaichiColor)
                $label = $header.Substring(0, $header.Length - "_期待値".Length)
                if (-not $fieldPairCols.ContainsKey($label)) { $fieldPairCols[$label] = @{} }
                $fieldPairCols[$label]["期待値"] = $c
            } elseif ($header -eq "結果") {
                $headerCell.Style.Fill.BackgroundColor.SetColor($resultHeaderColor)
            } else {
                $headerCell.Style.Fill.BackgroundColor.SetColor($otherColor)
            }
        }
        $diffColor = $colorMap["不一致"]
        for ($row = 2; $row -le $lastRow; $row++) {
            # 項目ごとに現状/期待値を比較し、値が違う項目だけそのセルを赤字にする（どの項目が違うか一目でわかるように）。
            foreach ($label in $fieldPairCols.Keys) {
                $pair = $fieldPairCols[$label]
                if (-not ($pair.ContainsKey("現状") -and $pair.ContainsKey("期待値"))) { continue }
                $curCell = $ws.Cells[$row, $pair["現状"]]
                $expCell = $ws.Cells[$row, $pair["期待値"]]
                if ($curCell.Text -ne $expCell.Text) {
                    $curCell.Style.Font.Color.SetColor($diffColor)
                    $expCell.Style.Font.Color.SetColor($diffColor)
                    $curCell.Style.Font.Bold = $true
                    $expCell.Style.Font.Bold = $true
                }
            }
            if ($resultCol -eq 0) { continue }
            $value = $ws.Cells[$row, $resultCol].Text
            if ($colorMap.ContainsKey($value)) {
                $ws.Cells[$row, $resultCol].Style.Font.Color.SetColor($colorMap[$value])
                $ws.Cells[$row, $resultCol].Style.Font.Bold = $true
            }
        }
        Set-KintoneColumnWidth -Worksheet $ws
    }
    Close-ExcelPackage $pkg

    $allDiffRows = @($spaceSettingsDiff) + @($memberDiff) + @($appListDiff) + @($appAclDiff) + @($appRecordAclDiff)
    $errorCount = @($allDiffRows | Where-Object { $_.'結果' -ne "一致" -and $_.'結果' -ne "Everyoneの影響" }).Count
    Write-Message ""
    Write-Message "チェック結果を出力しました: $outputPath" -ForegroundColor Green
    Write-Message "差分件数: $errorCount / $($allDiffRows.Count)"
    # 差分ありは確認が必要な警告であり、チェック結果自体は正常に出力済みのため致命的エラー(exit 1)とは区別する
    if ($errorCount -gt 0) { $script:exitCode = 2 }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-Message ""
Write-Message "ログを出力しました: $logFilePath" -ForegroundColor Green
exit $script:exitCode
