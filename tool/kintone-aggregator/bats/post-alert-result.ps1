param(
    [string]$BaseUrl,
    [string]$TargetGroupName,
    [string]$TargetDate,
    [string]$BackupRootDir,
    [string]$KintoneLoginName,
    [string]$KintonePassword,
    [string]$Authorization,
    [string]$SpaceId,
    [string]$ThreadId,
    [string]$MentionUserCodes,
    [string]$CommentTextTemplate,
    [string]$CommentSummaryTemplate,
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "${LogNamePrefix}-$TargetGroupName-$TargetDate"

$psParams = $PSBoundParameters

try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            if ([string]::IsNullOrWhiteSpace($SpaceId) -or [string]::IsNullOrWhiteSpace($ThreadId)) {
                throw "SpaceIdまたはThreadIdが未設定のため、スレッド投稿をスキップします。"
            }

            if ([string]::IsNullOrWhiteSpace($Authorization)) {
                $pair = "${KintoneLoginName}:${KintonePassword}"
                $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
            }

            $backupFilePath = Join-Path $BackupRootDir "$TargetGroupName-$TargetDate.xlsx"
            if (-not (Test-Path -LiteralPath $backupFilePath)) {
                throw "アラート結果ファイルが見つかりません: $backupFilePath"
            }

            $mentions = @(($MentionUserCodes -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                    $pair = $_ -split ':', 2
                    $code = $pair[0].Trim()
                    $type = if ($pair.Count -ge 2 -and $pair[1].Trim()) { $pair[1].Trim().ToUpper() } else { "USER" }
                    @{ code = $code; type = $type }
                })
            
            $defaultCommentTextTemplate = "集計結果を更新しました。（{グループ名} / {対象日}）"
            $commentTextTemplate = if ([string]::IsNullOrWhiteSpace($CommentTextTemplate)) { $defaultCommentTextTemplate } else { $CommentTextTemplate -replace '\\n', "`n" }
            $commentText = $commentTextTemplate -replace '\{グループ名\}', $TargetGroupName -replace '\{対象日\}', $TargetDate
            
            $summaryJsonFilePath = Join-Path $BackupRootDir "$TargetGroupName-$TargetDate.json"
            if (-not (Test-Path -LiteralPath $summaryJsonFilePath)) {
                throw "集計テキストファイルが見つかりません: $summaryJsonFilePath"
            }
            $parsedSummaries = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $summaryJsonFilePath -Raw -Encoding UTF8)
            $summaries = @($parsedSummaries)
            $defaultCommentSummaryTemplate = @(
                "■ {クラス名}"
                "・業務日誌（未提出）: {業務日誌未提出人数}"
                "・パルスサーベイ（未提出）: {パルスサーベイ未提出人数}"
                "・アラート: {アラート人数}"
            )
            $summaryCommentTemplate = if ([string]::IsNullOrWhiteSpace($CommentSummaryTemplate)) { $defaultCommentSummaryTemplate } else { @(($CommentSummaryTemplate -replace '\\n', "`n") -split "`n") }
            $summaryLines = @()
            foreach ($summary in $summaries) {
                if ($summaryLines.Count -gt 0) { $summaryLines += "" }
                foreach ($templateLine in $summaryCommentTemplate) {
                    $line = $templateLine
                    foreach ($property in $summary.PSObject.Properties) {
                        $line = $line -replace "\{$($property.Name)\}", $property.Value
                    }
                    $summaryLines += $line
                }
            }
            
            $commentText = $commentText + "`n`n" + ($summaryLines -join "`n")
            Write-Message $commentText -VarName "投稿コメント" -Type "Info"

            $commentResponse = Add-KintoneThreadComment -SpaceId $SpaceId -ThreadId $ThreadId -Text $commentText -FilePaths @($backupFilePath) -Mentions $mentions -BaseUrl $BaseUrl -Authorization $Authorization
            Write-Message $commentResponse -VarName "スレッド投稿" -Type "Info"
            
            Write-MessageComplete "集計結果を投稿しました"
        }
        catch {
            Write-MessageError "実行エラー: $($error[0])"
        }
    } *>&1 | Tee-Object -FilePath $logFilePath
}
finally {
    ConvertTo-Utf8LogFile -Path $logFilePath
    Write-MessageComplete "ログを出力しました: $logFilePath"
}
if ($error) {
    throw $error[0]
}
