param(
    [string]$BaseUrl,
    [string]$TargetGroupName,
    [string]$TestOutputDir,
    [string]$TestOutputFileSuffix,
    [string]$SurveyOutputDir,
    [string]$SurveyOutputFileSuffix,
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

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'post-collect-results' })-$TargetGroupName"

& {
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

    if ([string]::IsNullOrWhiteSpace($SpaceId) -or [string]::IsNullOrWhiteSpace($ThreadId)) {
        Write-Message "SpaceIdまたはThreadIdが未設定のため、スレッド投稿をスキップします。" -VarName "message" -Type "Info"
        return
    }

    if ([string]::IsNullOrWhiteSpace($Authorization)) {
        $pair = "${KintoneLoginName}:${KintonePassword}"
        $Authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
    }

    $testFilePath = Join-Path $TestOutputDir "$TargetGroupName-$TestOutputFileSuffix.xlsx"
    $surveyFilePath = Join-Path $SurveyOutputDir "$TargetGroupName-$SurveyOutputFileSuffix.xlsx"

    $filePaths = @()
    if (Test-Path -LiteralPath $testFilePath) {
        $filePaths += $testFilePath
    } else {
        Write-Message "テスト結果ファイルが見つかりません: $testFilePath" -VarName "message" -Type "Warn" -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath $surveyFilePath) {
        $filePaths += $surveyFilePath
    } else {
        Write-Message "アンケート結果ファイルが見つかりません: $surveyFilePath" -VarName "message" -Type "Warn" -ForegroundColor Yellow
    }

    if ($filePaths.Count -eq 0) {
        Write-Message "添付できるファイルがないため、投稿を中止します。" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }

    $mentions = @(($MentionUserCodes -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        $pair = $_ -split ':', 2
        $code = $pair[0].Trim()
        $type = if ($pair.Count -ge 2 -and $pair[1].Trim()) { $pair[1].Trim().ToUpper() } else { "USER" }
        @{ code = $code; type = $type }
    })

    $commentTextTemplate = if ([string]::IsNullOrWhiteSpace($CommentTextTemplate)) { "テスト・アンケート結果を更新しました。（{TargetGroupName}）" } else { $CommentTextTemplate -replace '\\n', "`n" }
    $commentText = $commentTextTemplate -replace '\{TargetGroupName\}', $TargetGroupName

    $commentResponse = Add-KintoneThreadComment -SpaceId $SpaceId -ThreadId $ThreadId -Text $commentText -FilePaths $filePaths -Mentions $mentions -BaseUrl $BaseUrl -Authorization $Authorization
    Write-Message $commentResponse -VarName "commentResponse" -Type "Info"
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
