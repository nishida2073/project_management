# =========================================
# 実行ログの組み立て・表示（ツリー表示含む）
# =========================================
# 各ワーカースクリプトが実行結果をログファイルへ書き出し、GUIログ欄にも表示するための共通処理。

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
    $logLines += "開始時刻: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $logLines += "終了時刻: $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
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

    Write-Message "" -Type "Info" -NoHeader
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $cp932)) {
        if ($line -match '^#') {
            Write-Message $line -Type "Info" -NoHeader
        } elseif ($line -match 'エラー|失敗|存在しません') {
            Write-Message $line -ForegroundColor Red -Type "Info" -NoHeader
        } else {
            Write-Message $line -Type "Info" -NoHeader
        }
    }
    Write-Message "" -Type "Info" -NoHeader
}
