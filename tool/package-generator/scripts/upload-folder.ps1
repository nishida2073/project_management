# =========================================
# ローカルフォルダ→SharePointアップロードツール（Azure CLI + Microsoft Graph版）
# =========================================
# download-folder.ps1と同じ仕組み（Azure CLIで取得したトークンでMicrosoft Graph APIを直接呼ぶ）の逆方向版。

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")
$startTime = Get-Date

$siteUrl = $env:UPLOAD_SITE_URL
$sitePath = $env:UPLOAD_SITE_PATH
$tenantId = $env:UPLOAD_SITE_TENANT_ID
$localPath = $env:UPLOAD_LOCAL_PATH

if (!$siteUrl -or !$sitePath -or !$tenantId -or !$localPath) {
    Write-Host "UPLOAD_SITE_URL と UPLOAD_SITE_PATH と UPLOAD_SITE_TENANT_ID と UPLOAD_LOCAL_PATH を set-env.bat で設定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $localPath)) {
    Write-Host "アップロード元が存在しません：$localPath"
    exit 1
}

$logPath = $env:COMMON_LOG_PATH
New-Item -ItemType Directory -Path $logPath -Force | Out-Null

$uploadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

$folderParts = $sitePath -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'

function Send-EmptyFileToSharePoint {
    param(
        [string]$SiteRelativePath
    )

    $encodedPath = Get-EncodedSitePath $SiteRelativePath
    $contentUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedPath}:/content"

    $maxRetry = 8
    for ($retry = 1; $retry -le $maxRetry; $retry++) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($contentUri)
            $req.Method = "PUT"
            $req.KeepAlive = $false
            $req.Headers.Add("Authorization", $headers.Authorization)
            $req.ContentLength = 0
            $webResp = $req.GetResponse()
            $webResp.Close()
            break
        } catch {
            if ($retry -eq $maxRetry) { throw }
            Start-Sleep -Milliseconds (1000 * $retry)
        }
    }
}

function Send-FileToSharePoint {
    param(
        [string]$LocalFile,
        [string]$SiteRelativePath
    )

    $fileSize = (Get-Item -LiteralPath $LocalFile).Length

    if ($fileSize -eq 0) {
        Send-EmptyFileToSharePoint -SiteRelativePath $SiteRelativePath
        return
    }

    $encodedPath = Get-EncodedSitePath $SiteRelativePath
    $sessionUri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedPath}:/createUploadSession"
    $sessionBody = '{"item":{"@microsoft.graph.conflictBehavior":"replace"}}'
    $session = Invoke-GraphPost -Headers $headers -Uri $sessionUri -Body $sessionBody
    $uploadUrl = $session.uploadUrl

    $fileStream = [System.IO.File]::OpenRead($LocalFile)
    try {
        $chunkSize = 10485760
        $buffer = New-Object byte[] $chunkSize
        $offset = 0
        $totalSize = [Math]::Max($fileSize, 0)

        do {
            $readSize = [Math]::Min($chunkSize, $fileSize - $offset)
            $fileStream.Position = $offset
            $bytesRead = if ($fileSize -eq 0) { 0 } else { $fileStream.Read($buffer, 0, $readSize) }
            $rangeEnd = [Math]::Max($offset + $bytesRead - 1, 0)
            $rangeHeader = "bytes $offset-$rangeEnd/$totalSize"

            $maxRetry = 8
            for ($retry = 1; $retry -le $maxRetry; $retry++) {
                try {
                    $req = [System.Net.HttpWebRequest]::Create($uploadUrl)
                    $req.Method = "PUT"
                    $req.KeepAlive = $false
                    $req.Headers.Add("Content-Range", $rangeHeader)
                    $req.ContentLength = $bytesRead
                    if ($bytesRead -gt 0) {
                        $reqStream = $req.GetRequestStream()
                        $reqStream.Write($buffer, 0, $bytesRead)
                        $reqStream.Close()
                    }
                    $webResp = $req.GetResponse()
                    $webResp.Close()
                    break
                } catch {
                    if ($retry -eq $maxRetry) { throw }
                    Start-Sleep -Milliseconds (1000 * $retry)
                }
            }

            $offset += $bytesRead
        } while ($offset -lt $fileSize)
    } finally {
        $fileStream.Close()
    }
}

function Send-FolderRecursive {
    param(
        [string]$LocalFolder,
        [string]$SubPath
    )

    Get-ChildItem -LiteralPath $LocalFolder | ForEach-Object {
        $childSubPath = if ($SubPath) { "$SubPath/$($_.Name)" } else { $_.Name }

        if ($_.PSIsContainer) {
            Send-FolderRecursive -LocalFolder $_.FullName -SubPath $childSubPath
        } else {
            $fileSitePath = if ($relativeFolder) { "$relativeFolder/$childSubPath" } else { $childSubPath }
            Send-FileToSharePoint -LocalFile $_.FullName -SiteRelativePath $fileSitePath
            Write-Host "$($_.Name)"
            $script:uploadLog += "$($_.FullName) -> $sitePath/$childSubPath"
        }
    }
}

Write-Host "# アップロード開始"
Write-Host "$localPath -> $sitePath"
Send-FolderRecursive -LocalFolder $localPath -SubPath ""

$endTime = Get-Date
$logFilePath = Join-Path $logPath "$($env:UPLOAD_LOG_PREFIX)$(Get-ClientLogSegment)$(Split-Path $relativeFolder -Leaf).log"
$logLines = @()
$logLines += "# 実行情報"
$logLines += (Get-ClientLogHeaderLines)
$logLines += "バッチ名: $($env:BATCH_NAME)"
$logLines += "開始時刻: $($startTime.ToString('yyyy/MM/dd HH:mm:ss'))"
$logLines += "終了時刻: $($endTime.ToString('yyyy/MM/dd HH:mm:ss'))"
$logLines += ""
$logLines += "# アップロード結果"
$logLines += $uploadLog
$logLines += ""
$logLines += "# フォルダ構成"
$logLines += (Split-Path $localPath -Leaf)
$logLines += (Get-TreeLines -Path $localPath)
Write-LogFile -Path $logFilePath -Lines $logLines

Write-Host ""
Write-Host "# アップロード完了"