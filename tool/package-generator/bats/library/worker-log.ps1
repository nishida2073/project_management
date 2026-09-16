function Write-Message {
    param(
        [object]$Datas,
        [string]$VarName = "Debug Message",
        [string]$Type = "Debug",
        [ConsoleColor]$ForegroundColor = "White",
        [switch]$NoHeader,
        [switch]$Hidden
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.ff"
    if ($Type -eq "Debug") {
        return
    }
    if ($VarName -eq "functionName") {
        return
    }

    $isGuiMode = $env:GUI_LOG_MODE -eq "1"
    function Write-ColoredLine {
        param([string]$Text)
        if ($isGuiMode) {
            if ($Hidden) {
                Write-Host "[[HIDE]]$Text"
            } else {
                Write-Host "[[COLOR:$ForegroundColor]]$Text"
            }
        } else {
            Write-Host $Text -ForegroundColor $ForegroundColor
        }
    }

    if (-not $NoHeader) {
        Write-ColoredLine "=============== [$timestamp] $VarName ==============="
    }

    if( -not $Datas ){
        Write-ColoredLine "$Datas"
        return
    }

    if ($Datas -is [PSCustomObject] -or $Datas -is [Hashtable] -or $Datas -is [array]) {
        $Datas | ConvertTo-Json -Depth 10 | ForEach-Object { Write-ColoredLine $_ }
    }
    else {
        Write-ColoredLine "$Datas"
    }
}

function Write-MessageComplete {
    param([Parameter(Mandatory)][string]$Message)
    Write-Message "" -Type "Info" -NoHeader
    Write-Message $Message -ForegroundColor Green -Type "Info" -NoHeader
}

function Write-MessageError {
    param([Parameter(Mandatory)][string]$Message)
    Write-Message "" -Type "Info" -NoHeader
    Write-Message $Message -ForegroundColor Red -Type "Info" -NoHeader
}

function Write-MessageWarn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Message "" -Type "Info" -NoHeader
    Write-Message $Message -VarName "message" -Type "Warn" -ForegroundColor Yellow -NoHeader
}
