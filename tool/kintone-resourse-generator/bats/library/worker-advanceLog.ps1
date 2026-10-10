function Write-ApplyStepResult {
    param(
        [Parameter(Mandatory)][string]$ActionLabel,
        [string]$CountPhrase = "",
        [string[]]$DetailLines = @(),
        [ConsoleColor]$ForegroundColor = "White"
    )
    $headerText = "■$ActionLabel"
    if ($CountPhrase) { $headerText += " ($CountPhrase)" }
    Write-Message $headerText -ForegroundColor $ForegroundColor -Type "Info" -NoHeader
    foreach ($line in $DetailLines) { Write-Message $line -ForegroundColor $ForegroundColor -Type "Info" -NoHeader }
}
