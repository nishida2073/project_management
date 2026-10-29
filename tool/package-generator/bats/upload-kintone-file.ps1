# =========================================
# zipファイルをkintoneアプリのファイル欄へアップロード
# =========================================

param(
    [string]$TargetFilePath,
    [string]$Title,
    [string]$Description,
    [string]$AllowUpdate = "true",
    [string]$TargetAppId,
    [string]$KintoneBaseUrl,
    [string]$KintoneLoginName,
    [string]$KintonePassword,
    [string]$ClientName,
    [string]$BackupPath,
    [string]$LogPath,
    [string]$LogNamePrefix
)

$titleFieldCode = "Title"
$descriptionFieldCode = "Description"
$fileFieldCode = "File"

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
$logFilePath = New-WorkerLogPath -LogRoot $LogPath -Prefix "${LogNamePrefix}-${ClientName}-${TargetAppId}"

$script:exitCode = 0
$psParams = $PSBoundParameters
try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            if (-not $Title) {
                throw "タイトルを入力してください"
            }
            $files = @($TargetFilePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($files.Count -eq 0) {
                throw "zipファイルを指定してください"
            }
            foreach ($file in $files) {
                if (-not (Test-Path -LiteralPath $file)) {
                    throw "ファイルが存在しません：$file"
                }
                if ([System.IO.Path]::GetExtension($file) -ne ".zip") {
                    throw "zipファイルを指定してください：$file"
                }
            }

            $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${KintoneLoginName}:${KintonePassword}"))
            $headers = @{ "X-Cybozu-Authorization" = $authorization }
            $allowUpdate = $AllowUpdate -ne "false"

            $recordId = $null
            if ($Title) {
                $query = "$titleFieldCode = `"$($Title.Replace('\', '\\').Replace('"', '\"'))`""
                $search = Invoke-RestMethod -Method Get -Uri "$KintoneBaseUrl/k/v1/records.json?app=$TargetAppId&query=$([System.Uri]::EscapeDataString($query))" -Headers $headers
                if ($search.records.Count -gt 0) { $recordId = $search.records[0].'$id'.value }
            }
            if ($recordId -and -not $allowUpdate) {
                throw "同じタイトルのレコードが既にあります（更新しない設定です）：レコードID $recordId"
            }

            $fileKeys = @($files | ForEach-Object { Add-KintoneFile -FilePath $_ -BaseUrl $KintoneBaseUrl -Authorization $authorization })

            $record = @{
                $titleFieldCode = @{ value = $Title }
                $descriptionFieldCode = @{ value = ($Description -replace '\\n', "`n") }
                $fileFieldCode = @{ value = @($fileKeys | ForEach-Object { @{ fileKey = $_ } }) }
            }

            if ($recordId) {
                $body = @{ app = $TargetAppId; id = $recordId; record = $record }
                $resp = Invoke-RestMethod -Method Put -Uri "$KintoneBaseUrl/k/v1/record.json" -Headers $headers -ContentType "application/json; charset=utf-8" -Body ($body | ConvertTo-Json -Depth 10)
                Write-MessageComplete "同じタイトルのレコードを更新しました: レコードID $recordId"
                $backupDir = Join-Path (Join-Path $BackupPath $ClientName) (Get-Date -Format "yyyyMMdd-HHmmss")
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                foreach ($file in $files) {
                    Copy-Item -LiteralPath $file -Destination $backupDir
                    Write-MessageComplete "バックアップファイルを作成しました: $(Join-Path $backupDir (Split-Path -Leaf $file))"
                }
            } else {
                $body = @{ app = $TargetAppId; record = $record }
                $resp = Invoke-RestMethod -Method Post -Uri "$KintoneBaseUrl/k/v1/record.json" -Headers $headers -ContentType "application/json; charset=utf-8" -Body ($body | ConvertTo-Json -Depth 10)
                Write-MessageComplete "アップロードが完了しました: レコードID $($resp.id)"
            }
        } catch {
            Write-MessageError "実行エラー: $($error[0])"
            $script:exitCode = 1
        }
    } *>&1 | Tee-Object -FilePath $logFilePath
}
finally {
    ConvertTo-Utf8LogFile -Path $logFilePath
    Write-MessageComplete "ログを出力しました: $logFilePath"
}
exit $script:exitCode
