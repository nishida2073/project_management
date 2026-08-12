# =========================================
# 共通処理（Azure CLI / Microsoft Graph 関連）
# =========================================
# generate-package.ps1 / download-folder.ps1 / upload-folder.ps1 で共通して使う関数をまとめたもの。
# 各スクリプトの先頭でドットソース（. "パス\common.ps1"）して読み込む。

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$cp932 = [System.Text.Encoding]::GetEncoding(932)
$defaultClientLabel = "デフォルト"

function Write-LogFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    [System.IO.File]::WriteAllLines($Path, $Lines, $cp932)
}

function Get-ClientLogSegment {
    if ($env:CLIENT_NAME) {
        return "$($env:CLIENT_NAME)_"
    }
    return "${defaultClientLabel}_"
}

function Get-ClientLogHeaderLines {
    if ($env:CLIENT_NAME) {
        return @("クライアント: $($env:CLIENT_NAME)")
    }
    return @("クライアント: $defaultClientLabel")
}

function Write-TreeNode {
    param(
        [System.Collections.Specialized.OrderedDictionary]$Node,
        [string]$Prefix = ""
    )

    $keys = @($Node.Keys | Sort-Object { $null -eq $Node[$_] }, { $_ })
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $key = $keys[$i]
        $isLast = ($i -eq $keys.Count - 1)
        $connector = if ($isLast) { "└─ " } else { "├─ " }
        Write-Output "$Prefix$connector$key"

        if ($null -ne $Node[$key]) {
            $childPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix│   " }
            Write-TreeNode -Node $Node[$key] -Prefix $childPrefix
        }
    }
}

function Get-FolderTree {
    param([string]$Path)

    $tree = [ordered]@{}
    foreach ($item in (Get-ChildItem -LiteralPath $Path)) {
        if ($item.PSIsContainer) {
            $tree[$item.Name] = Get-FolderTree -Path $item.FullName
        } else {
            $tree[$item.Name] = $null
        }
    }
    return $tree
}

function Get-ZipTree {
    param([string]$Path)

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $tree = [ordered]@{}
        foreach ($entry in $zip.Entries) {
            $segments = @($entry.FullName -split '[\\/]' | Where-Object { $_ })
            $node = $tree
            for ($i = 0; $i -lt $segments.Count; $i++) {
                $segment = $segments[$i]
                if ($i -eq $segments.Count - 1) {
                    $node[$segment] = $null
                } else {
                    if (!$node.Contains($segment) -or $null -eq $node[$segment]) {
                        $node[$segment] = [ordered]@{}
                    }
                    $node = $node[$segment]
                }
            }
        }
        return $tree
    } finally {
        $zip.Dispose()
    }
}

function Get-TreeNodeForPath {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ($Path.ToLower().EndsWith(".zip")) {
            return Get-ZipTree -Path $Path
        }
        return $null
    }
    return Get-FolderTree -Path $Path
}

function Get-TreeLines {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $tree = Get-TreeNodeForPath -Path $Path
    if ($null -eq $tree) { $tree = [ordered]@{} }
    Write-TreeNode -Node $tree -Prefix $Prefix
}

function Get-ItemListLines {
    param(
        [string[]]$Paths,
        [string]$Prefix = ""
    )

    $tree = [ordered]@{}
    foreach ($itemPath in $Paths) {
        $tree[(Split-Path $itemPath -Leaf)] = $null
    }
    Write-TreeNode -Node $tree -Prefix $Prefix
}

function Write-RunLogFile {
    param(
        [string]$LogPath,
        [string]$LogFileName,
        [string[]]$ExtraHeaderLines = @(),
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$ResultSectionTitle,
        [string[]]$ResultLines,
        [string]$TreeRootPath = "",
        [string]$ItemListRootPath = "",
        [string[]]$ItemListPaths = @()
    )

    if ($TreeRootPath -and $ItemListPaths.Count -gt 0) {
        throw "TreeRootPath と ItemListPaths は同時に指定できません"
    }

    $timestamp = $StartTime.ToString('yyyyMMdd_HHmmss')
    $logFileExt = [System.IO.Path]::GetExtension($LogFileName)
    $logFileBase = [System.IO.Path]::GetFileNameWithoutExtension($LogFileName)
    $logFilePath = Join-Path $LogPath "${logFileBase}_${timestamp}${logFileExt}"
    $logLines = @()
    $logLines += "# 実行情報"
    $logLines += (Get-ClientLogHeaderLines)
    $logLines += "バッチ名: $($env:BATCH_NAME)"
    $logLines += $ExtraHeaderLines
    $logLines += "開始時刻: $($StartTime.ToString('yyyy/MM/dd HH:mm:ss'))"
    $logLines += "終了時刻: $($EndTime.ToString('yyyy/MM/dd HH:mm:ss'))"
    $logLines += ""
    $logLines += "# $ResultSectionTitle"
    $logLines += $ResultLines
    if ($TreeRootPath) {
        $logLines += ""
        $logLines += "# 構成"
        $logLines += $TreeRootPath
        $logLines += (Get-TreeLines -Path $TreeRootPath)
    } elseif ($ItemListPaths.Count -gt 0) {
        $logLines += ""
        $logLines += "# 構成"
        if ($ItemListRootPath) {
            $logLines += $ItemListRootPath
        }
        $logLines += (Get-ItemListLines -Paths $ItemListPaths)
    }
    Write-LogFile -Path $logFilePath -Lines $logLines

    return $logFilePath
}

function Show-LogFileContent {
    param([string]$Path)

    Write-Host ""
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $cp932)) {
        Write-Host $line
    }
    Write-Host ""
}

function Get-AzureCliPath {
    $az = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
    if (!$az) {
        $az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
    }
    if (!(Test-Path $az)) {
        Write-Host "Azure CLIが見つかりません。以下でインストールしてください："
        Write-Host "  winget install --id Microsoft.AzureCLI"
        exit 1
    }
    return $az
}

function Get-GraphToken {
    param(
        [string]$Az,
        [string]$TenantId
    )

    $out = & $Az account get-access-token --resource "https://graph.microsoft.com" --tenant $TenantId 2>$null
    if ($LASTEXITCODE -ne 0 -or !$out) {
        Write-Host "サインインが必要です。表示されるURLとコードでログインしてください。"
        Write-Host ""

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c ""`"$Az`" login --tenant $TenantId --scope https://graph.microsoft.com/.default --use-device-code --allow-no-subscriptions 2>&1"""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true

        $loginProc = New-Object System.Diagnostics.Process
        $loginProc.StartInfo = $psi
        $loginProc.Start() | Out-Null

        $shown = $false
        while (!$loginProc.StandardOutput.EndOfStream) {
            $line = $loginProc.StandardOutput.ReadLine()
            if (!$shown -and $line -match "open the page (?<url>\S+)\s+and enter the code (?<code>[A-Z0-9\-]+)") {
                Write-Host "URL: $($Matches.url)"
                Write-Host "コード：$($Matches.code)"
                Write-Host ""
                $shown = $true
            }
        }
        $loginProc.WaitForExit()

        $out = & $Az account get-access-token --resource "https://graph.microsoft.com" --tenant $TenantId 2>$null
    }
    if (!$out) {
        Write-Host "トークンの取得に失敗しました"
        exit 1
    }
    return ($out | Out-String | ConvertFrom-Json).accessToken
}

function Invoke-GraphGet {
    param(
        [hashtable]$Headers,
        [string]$Uri
    )
    $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Invoke-GraphPost {
    param(
        [hashtable]$Headers,
        [string]$Uri,
        [string]$Body
    )
    $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Post -Body $Body -ContentType "application/json" -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Resolve-GraphSiteId {
    param(
        [hashtable]$Headers,
        [string]$SiteUrl
    )
    $siteUri = [Uri]$SiteUrl
    $sitePath = $siteUri.AbsolutePath.TrimStart('/')
    $site = Invoke-GraphGet -Headers $Headers -Uri "https://graph.microsoft.com/v1.0/sites/$($siteUri.Host):/$sitePath"
    return $site.id
}

function Test-NameMatchesPatterns {
    param([string]$Name, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }
    return $false
}

function Get-EncodedSitePath {
    param([string]$Path)
    return ($Path -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
}