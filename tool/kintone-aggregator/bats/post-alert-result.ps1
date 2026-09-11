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
    [string]$LogNamePrefix
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'post-alert-result' })-$TargetGroupName-$TargetDate"

& {
    if ([string]::IsNullOrWhiteSpace($SpaceId) -or [string]::IsNullOrWhiteSpace($ThreadId)) {
        Write-Message "SpaceIdまたはThreadIdが未設定のため、スレッド投稿をスキップします。" -VarName "message" -Type "Info"
        return
    }

    if ([string]::IsNullOrWhiteSpace($Authorization)) {
        $pair = "${KintoneLoginName}:${KintonePassword}"
        $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
    }

    # 日付なしファイル（$TargetGroupName.xlsx）は直近に実行した日の内容で上書きされるため、
    # 過去の特定日を指定して単独で投稿し直しても内容が食い違わないよう、backupの日付付きファイルを使う
    $backupFilePath = Join-Path $BackupRootDir "$TargetGroupName-$TargetDate.xlsx"
    if (-not (Test-Path -LiteralPath $backupFilePath)) {
        Write-Message "アラート結果ファイルが見つかりません: $backupFilePath" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }

    $mentions = @(($MentionUserCodes -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        $pair = $_ -split ':', 2
        $code = $pair[0].Trim()
        $type = if ($pair.Count -ge 2 -and $pair[1].Trim()) { $pair[1].Trim().ToUpper() } else { "USER" }
        @{ code = $code; type = $type }
    })

    # client.batは1行1変数のため、複数行の文言は"\n"リテラルで1行に収めて渡ってくる。ここで実改行に戻す
    $commentTextTemplate = if ([string]::IsNullOrWhiteSpace($CommentTextTemplate)) { "アラート結果を更新しました。（{TargetGroupName} / {TargetDate}）" } else { $CommentTextTemplate -replace '\\n', "`n" }
    $commentText = $commentTextTemplate -replace '\{TargetGroupName\}', $TargetGroupName -replace '\{TargetDate\}', $TargetDate

    $commentResponse = Add-KintoneThreadComment -SpaceId $SpaceId -ThreadId $ThreadId -Text $commentText -FilePaths @($backupFilePath) -Mentions $mentions -BaseUrl $BaseUrl -Authorization $Authorization
    Write-Message $commentResponse -VarName "スレッド投稿" -Type "Info"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
