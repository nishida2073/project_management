# =========================================
# ローカルフォルダ→SharePointアップロードツール（Azure CLI + Microsoft Graph版）
# =========================================
# download-folder.ps1と同じ仕組み（Azure CLIで取得したトークンでMicrosoft Graph APIを直接呼ぶ）の逆方向版。

$basePath = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $basePath "common.ps1")

$siteUrl = $env:UPLOAD_SITE_URL
$folder = $env:UPLOAD_FOLDER
$tenantId = $env:UPLOAD_TENANT_ID
$localSource = $env:UPLOAD_LOCAL_SOURCE

if (!$siteUrl -or !$folder -or !$tenantId -or !$localSource) {
    Write-Host "UPLOAD_SITE_URL と UPLOAD_FOLDER と UPLOAD_TENANT_ID と UPLOAD_LOCAL_SOURCE を set-env.bat で設定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $localSource)) {
    Write-Host "アップロード元が存在しません：$localSource"
    exit 1
}

$logBasePath = if ($env:COMMON_LOG_PATH) { $env:COMMON_LOG_PATH } else { Join-Path $basePath "log" }
New-Item -ItemType Directory -Path $logBasePath -Force | Out-Null

$uploadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

# --- サイトIDの解決 ---
$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

# --- アップロード先パスの解決（先頭のドキュメントライブラリ名を除いた残りが既定のdriveのroot以下のパスになる） ---
$folderParts = $folder -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'

# --- 空ファイル（0バイト）は範囲指定が不正になるため、アップロードセッションを使わず直接PUTする ---
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

# --- チャンクアップロード（サイズ上限を避けるため常にアップロードセッション経由） ---
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

# --- 再帰アップロード ---
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
            $sitePath = if ($relativeFolder) { "$relativeFolder/$childSubPath" } else { $childSubPath }
            Send-FileToSharePoint -LocalFile $_.FullName -SiteRelativePath $sitePath
            Write-Host "アップロード：$($_.Name)"
            $script:uploadLog += "$($_.FullName) -> $folder/$childSubPath"
        }
    }
}

Write-Host ""
Write-Host "アップロード開始：$localSource -> $folder"
Send-FolderRecursive -LocalFolder $localSource -SubPath ""

$logPath = Join-Path $logBasePath "$($env:UPLOAD_LOG_PREFIX)$(Split-Path $localSource -Leaf).log"
$logLines = @()
$logLines += "# アップロード結果"
$logLines += $uploadLog
$logLines += ""
$logLines += "# フォルダ構成"
$logLines += (Split-Path $localSource -Leaf)
$logLines += (Get-TreeLines -Path $localSource)
$logLines | Out-File -FilePath $logPath -Encoding Default

Write-Host ""
Write-Host "アップロード完了：$folder"
Write-Host "$logPath 作成完了"