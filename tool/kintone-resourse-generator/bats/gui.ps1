trap {
    Write-Host "エラー: $_"
    Write-Host $_.ScriptStackTrace
    Write-Host $_.Exception
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$scriptDir = Join-Path $rootPath "bats"

$createSpaceBat = Join-Path $rootPath "create-space-from-template.bat"
$downloadBat = Join-Path $rootPath "download-kintone-resources.bat"
$generateBat = Join-Path $rootPath "generate-config-from-template.bat"
$applyBat = Join-Path $rootPath "apply-kintone-resources.bat"
$checkBat = Join-Path $rootPath "check-kintone-resources.bat"
$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"
$setEnvBat = Join-Path $scriptDir "common.bat"

$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.bat" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

$script:baseTemplateNamePlaceholder = "未選択"

$script:customTemplateNamePlaceholder = "指定なし"

$blankOptions = @([PSCustomObject]@{ Text = ""; Value = "" })
$cmbBaseTemplateName = New-ComboBox -Width 220 -Height 22

$cmbCustomTemplateName = New-ComboBox -Width 180 -Height 22

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "スペース作成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペース作成"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $true }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $createSpaceBat
                ArgsFn = {
                    param($ic)
                    $groupValue = if ($ic.ContainsKey("TargetGroupName")) { Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem } else { "" }
                    @("-TargetGroupName:$groupValue", "-TemplateId:$($ic['SpaceTemplateId'].Text.Trim())", "-SpaceName:$($ic['ConfigName'].Text.Trim())")
                }
                OutputPathFn = $null
                OpenTarget = { $script:createdSpaceUrl }
                InputControls = $null
                StepStatusLabel = $null
                OnSuccessFn = {
                    param($ic, $lastOutputLines)
                    $idLine = $lastOutputLines | Where-Object { $_ -match 'SPACE_ID=(\d+)' } | Select-Object -Last 1
                    if ($idLine -and $idLine -match 'SPACE_ID=(?<id>\d+)') {
                        $bd1 = $categoryDefs[1].ButtonDefs[0]
                        if ($bd1 -and $bd1.InputControls.ContainsKey('SpaceId')) { $bd1.InputControls['SpaceId'].Text = $Matches.id }
                        $groupValue = Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem
                        $groupBatPath = Get-GroupBatPath $groupValue
                        $baseUrl = (Get-ResolvedVar -VarName "KINTONE_BASE_URL" -Path $groupBatPath).TrimEnd('/')
                        if ($baseUrl) { $script:createdSpaceUrl = "$baseUrl/k/#/space/$($Matches.id)" }
                    }
                }
            }
        )
    }
    [PSCustomObject]@{
        Label = "ダウンロード"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "ダウンロード"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceId"; Label = "スペースID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $false }
                )
                BatchPath = $downloadBat
                ArgsFn = {
                    param($ic)
                    $groupValue = if ($ic.ContainsKey("TargetGroupName")) { Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem } else { "" }
                    @("-TargetGroupName:$groupValue", "-SpaceId:$($ic['SpaceId'].Text.Trim())", "-ConfigName:$($ic['ConfigName'].Text.Trim())")
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_DOWNLOAD_PATH" $setEnvBat) "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "設定ファイルの生成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "設定ファイルの生成"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 200; ExistingControl = $cmbBaseTemplateName; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 200; ExistingControl = $cmbCustomTemplateName; NewRow = $true; Require = $false }
                )
                BatchPath = $generateBat
                ArgsFn = {
                    param($ic)
                    $groupValue = if ($ic.ContainsKey("TargetGroupName")) { Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem } else { "" }
                    $stepArgs = @("-TargetGroupName:$groupValue", "-BaseTemplateConfigName:$($ic['BaseTemplateName'].Text.Trim())", "-DownloadConfigName:$($ic['ConfigName'].Text.Trim())")
                    $customTemplateName = $ic['CustomTemplateName'].Text.Trim()
                    if ($customTemplateName -and $customTemplateName -ne $script:customTemplateNamePlaceholder) {
                        $stepArgs += "-CustomTemplateConfigName:$customTemplateName"
                    }
                    $stepArgs
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CONFIG_PATH" $setEnvBat) "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "kintoneへ反映"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "kintoneへ反映"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $applyBat
                ArgsFn = {
                    param($ic)
                    $groupValue = if ($ic.ContainsKey("TargetGroupName")) { Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem } else { "" }
                    @("-TargetGroupName:$groupValue", "-ConfigName:$($ic['ConfigName'].Text.Trim())")
                }
                OutputPathFn = $null
                OpenTarget = { $script:createdSpaceUrl }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "データチェック"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "データチェック"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $checkBat
                ArgsFn = {
                    param($ic)
                    $groupValue = if ($ic.ContainsKey("TargetGroupName")) { Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem } else { "" }
                    @("-TargetGroupName:$groupValue", "-ConfigName:$($ic['ConfigName'].Text.Trim())")
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CHECK_OUTPUT_PATH" $setEnvBat) "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
)

$form = New-Form -Title "kintoneリソース生成ツール" -Width 780 -Height 560 -MinWidth 600 -MinHeight 500 -CenterScreen
$script:currentProc = $null
$script:stepOutputPaths = @{}
$script:createdSpaceUrl = $null

$tabControl = New-TabControl
$tabRun = New-TabPage -Text "実行"


$tabLogs = New-TabPage -Text "ログ"
$tabSettings = New-TabPage -Text "設定"
$settingsSubTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)

$tabSettingsCommon = New-TabPage -Text "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-TabPage -Text "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$tabSettings.Controls.Add($settingsSubTabControl)

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)


$execTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)

$tabBatchRun = New-TabPage -Text "複数実行"
$execTabControl.Controls.Add($tabBatchRun)

$tabBatchAll = New-TabPage -Text "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$cmbRunAllBaseTemplateName = New-ComboBox

$cmbRunAllCustomTemplateName = New-ComboBox

$allStepDefs = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$batchRunAllInputs = @(
    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $true },
    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 200; ExistingControl = $cmbRunAllBaseTemplateName; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 200; ExistingControl = $cmbRunAllCustomTemplateName; NewRow = $true; Require = $false }
)

New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allStepDefs -RunButtonText "実行" -ShowSteps $false `
    -Inputs $batchRunAllInputs | Out-Null

$lblOverallStatus = $script:batchStatusLabel


$tabRun.Controls.Add($execTabControl)

New-CategoryTabControl -CategoryDefs $categoryDefs -TabControl $execTabControl `
    -OnRunClick {
        param($bd)
        $ic = $bd.InputControls

        if ($bd.Inputs) {
            foreach ($inputDef in $bd.Inputs) {
                if ($inputDef.Require) {
                    $ctrl = $ic[$inputDef.Name]
                    $value = if ($ctrl -is [System.Windows.Forms.TextBox]) { $ctrl.Text.Trim() } else { Get-ComboBoxValue -SelectedItem $ctrl.SelectedItem }
                    if (!$value -or ($value -eq $script:customTemplateNamePlaceholder) -or ($value -eq $script:baseTemplateNamePlaceholder)) {
                        [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                        return 1
                    }
                }
            }
        }

        Set-RunButtonsEnabled $false
        $lblOverallStatus.Text = ""

        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label; StepStatusLabel = $bd.StepStatusLabel }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $bd.InputControls } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc) `
            -DisplayLabel $bd.Label -StatusLabel $bd.StepStatusLabel

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $bd.InputControls $lastOutputLines
        }

        Set-RunButtonsEnabled $true
    } | Out-Null


$multipleBatchExcelPanel = New-Panel
$tabBatchRun.Controls.Add($multipleBatchExcelPanel)

$grpMultipleBatchExcel = New-GroupBox -Text "複数実行" -X 10 -Y 10 -Width 730
$multipleBatchExcelPanel.Controls.Add($grpMultipleBatchExcel)

$inputRowHeight = 30
$labelWidth = 150
$inputWidth1 = 200
$inputWidth2 = 200
$inputRowCenterY1 = 15 + ($inputRowHeight * 0) + [int]($inputRowHeight / 2)
$inputRowCenterY2 = 15 + ($inputRowHeight * 1) + [int]($inputRowHeight / 2)
$inputX1 = 15 + $labelWidth + 4

$lblMultipleBatchTargetGroup = New-Label -Text "対象のグループ" -X 15 -Y ($inputRowCenterY1 - 11) -Width $labelWidth -Height 22
$cmbMultipleBatchTargetGroup = New-ComboBox -X $inputX1 -Y ($inputRowCenterY1 - 11) -Width $inputWidth1 -Height 22 -DisplayMember "Text"

$lblMultipleBatchExcelPath = New-Label -Text "実行一覧ファイル" -X 15 -Y ($inputRowCenterY2 - 11) -Width $labelWidth -Height 22
$txtMultipleBatchExcelPath = New-TextBox -X $inputX1 -Y ($inputRowCenterY2 - 11) -Width $inputWidth2 -Height 22
$btnMultipleBatchBrowse = New-Button -Text "参照..." -X ($inputX1 + $inputWidth2 + 5) -Y ($inputRowCenterY2 - 12) -Width 70 -Height 24
$btnRunAllY = 26 + ($inputRowHeight * 1) + 20
$btnMultipleBatchRunAll = New-Button -Text "実行" -X 20 -Y $btnRunAllY -Width 120 -Height 28
$lblMultipleBatchStatus = New-Label -X 154 -Y ($btnRunAllY + 6) -AutoSize $true

$grpMultipleBatchExcel.Controls.AddRange(@(
    $lblMultipleBatchTargetGroup, $cmbMultipleBatchTargetGroup, $lblMultipleBatchExcelPath, $txtMultipleBatchExcelPath, $btnMultipleBatchBrowse, $btnMultipleBatchRunAll, $lblMultipleBatchStatus
))
$y = $btnRunAllY
$grpMultipleBatchExcel.Size = New-Object System.Drawing.Size(730, ($y + 10 + 28 + 16))
$multipleBatchExcelPanel.Height = $grpMultipleBatchExcel.Bottom

$dlgMultipleBatchExcel = New-Object System.Windows.Forms.OpenFileDialog
$dlgMultipleBatchExcel.Filter = "Excelファイル (*.xlsx)|*.xlsx"

$btnMultipleBatchBrowse.Add_Click({
    if ($dlgMultipleBatchExcel.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtMultipleBatchExcelPath.Text = $dlgMultipleBatchExcel.FileName
    }
})

$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)

$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    $allButtonDefs += $cd.ButtonDefs
}

$groupOptions = @()
foreach ($groupName in (Get-GroupNames)) {
    $groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
}

$logTabConditions = @(
    @{ PropertyName = "GroupCombo"; LabelText = "対象のグループ"; LabelWidth = 150; ComboWidth = 200; Options = $blankOptions }
    @{ PropertyName = "ConfigCombo"; LabelText = "スペース識別名"; LabelWidth = 150; ComboWidth = 200; Options = $blankOptions }
)

New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefs `
    -GetLogPathFn { Get-ResolvedVar "COMMON_LOG_PATH" $setEnvBat } `
    -OnUpdateLogView { Update-LogView } -Conditions $logTabConditions | Out-Null


function Update-GroupDropdowns {
    $allOption = [PSCustomObject]@{ Text = "すべて"; Value = "" }
    $groupNames = @(Get-GroupNames)

    $categoryDefs.ButtonDefs | Where-Object { $_.InputControls["TargetGroupName"] } | ForEach-Object {
        Update-ComboBoxItems -ComboBox $_.InputControls["TargetGroupName"] -Items $groupNames
    }

    $logItems = @($allOption) + $groupNames
    Update-ComboBoxItems -ComboBox $script:logTab.GroupCombo -Items $logItems

    $configDir = Join-Path $rootPath "config"
    $configNames = @(Get-ChildItem -LiteralPath $configDir -Filter "*_config.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $basename = $_.BaseName
            $basename -replace '_config$', ''
        } |
        Sort-Object)
    $configItems = @($allOption) + $configNames
    Update-ComboBoxItems -ComboBox $script:logTab.ConfigCombo -Items $configItems
    
    Update-ComboBoxItems -ComboBox $script:batchInputControls["TargetGroupName"] -Items $groupNames

    Update-ComboBoxItems -ComboBox $cmbSettingsGroupTarget -Items $groupNames

    Update-ComboBoxItems -ComboBox $cmbMultipleBatchTargetGroup -Items $groupNames

}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls) {
                foreach ($ctrl in $bd.InputControls.Values) { $ctrl.Enabled = $Enabled }
            }
        }
    }
    $cmbBaseTemplateName.Enabled = $Enabled
    $cmbCustomTemplateName.Enabled = $Enabled
    foreach ($ctrl in $script:batchInputControls.Values) {
        $ctrl.Enabled = $Enabled
    }
    $txtMultipleBatchExcelPath.Enabled = $Enabled
    $btnMultipleBatchBrowse.Enabled = $Enabled
    $btnMultipleBatchRunAll.Enabled = $Enabled
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons $script:batchRunButtons -Enabled $Enabled
}

function Copy-ComboSelection {
    param([System.Windows.Forms.ComboBox]$From, [System.Windows.Forms.ComboBox]$To)
    $value = Get-ComboBoxValue -SelectedItem $From.SelectedItem
    $matchingItem = $To.Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $value } | Select-Object -First 1
    if ($matchingItem) {
        $To.SelectedItem = $matchingItem
    } else {
        $To.Text = $value
    }
}

function Invoke-AllStepsForCurrentInputs {
    $lastExitCode = 0
    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $canProceed = $true

        $ic = $bd.InputControls
        if ($bd.Inputs) {
            foreach ($inputDef in $bd.Inputs) {
                if ($inputDef.Require) {
                    $value = $ic[$inputDef.Name].Text.Trim()
                    if (!$value -or ($value -eq $script:customTemplateNamePlaceholder)) {
                        $canProceed = $false
                        break
                    }
                }
            }
        }

        if (-not $canProceed) { return 1 }
        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $ic } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc)

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $ic $lastOutputLines
        }

        if ($exitCode -eq 2) {
            $lastExitCode = 2
        } elseif ($exitCode -ne 0) {
            return $exitCode
        }
    }
    return $lastExitCode
}

function Invoke-ExecuteAll {
    foreach ($inputDef in $batchRunAllInputs) {
        if (-not $inputDef.Require) { continue }

        $ctrl = $script:batchInputControls[$inputDef.Name]
        $value = if ($ctrl -is [System.Windows.Forms.ComboBox]) {
            Get-ComboBoxValue -SelectedItem $ctrl.SelectedItem
        } else {
            $ctrl.Text.Trim()
        }

        $isValid = if ($ctrl -is [System.Windows.Forms.ComboBox]) {
            $value -and ($value -ne $script:baseTemplateNamePlaceholder) -and ($value -ne $script:customTemplateNamePlaceholder)
        } else {
            $value
        }

        if (-not $isValid) {
            [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return 1
        }
    }

    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        if ($bd.InputControls.ContainsKey("TargetGroupName")) {
            $selectedValue = Get-ComboBoxValue -SelectedItem $script:batchInputControls["TargetGroupName"].SelectedItem
            $matchingItem = $bd.InputControls['TargetGroupName'].Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $selectedValue } | Select-Object -First 1
            if ($matchingItem) {
                $bd.InputControls['TargetGroupName'].SelectedItem = $matchingItem
            }
        }
        $bd.InputControls['ConfigName'].Text = $script:batchInputControls["ConfigName"].Text.Trim()
    }
    $bd0 = $categoryDefs[0].ButtonDefs[0]
    $bd0.InputControls['SpaceTemplateId'].Text = $script:batchInputControls["SpaceTemplateId"].Text.Trim()
    Copy-ComboSelection -From $cmbRunAllBaseTemplateName -To $cmbBaseTemplateName
    Copy-ComboSelection -From $cmbRunAllCustomTemplateName -To $cmbCustomTemplateName

    $lastExitCode = 0
    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $ic = $bd.InputControls
        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $ic } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc) `
            -DisplayLabel $bd.Label -StatusLabel $bd.StepStatusLabel

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $ic $lastOutputLines
        }

        if ($exitCode -eq 2) {
            $lastExitCode = 2
        } elseif ($exitCode -ne 0) {
            return $exitCode
        }
    }
    return $lastExitCode
}

$script:batchRunButton.Add_Click({
    Set-RunButtonsEnabled $false
    Set-StepStatus -Label $lblOverallStatus -Text "実行中..."

    $exitCode = Invoke-ExecuteAll

    if ($exitCode -eq 0) {
        Set-StepStatus -Label $lblOverallStatus -Text "成功" -State "成功"
    } elseif ($exitCode -eq 2) {
        Set-StepStatus -Label $lblOverallStatus -Text "警告" -State "警告"
    } else {
        Set-StepStatus -Label $lblOverallStatus -Text "失敗" -State "失敗"
    }

    Set-RunButtonsEnabled $true
})

$btnMultipleBatchRunAll.Add_Click({
    $excelPath = $txtMultipleBatchExcelPath.Text.Trim()
    try {
        Set-StepStatus -Label $lblMultipleBatchStatus -Text "実行中..."
        if (!$excelPath) {
            throw "実行一覧ファイルを選択してください。"
        }
        if (!(Test-Path -LiteralPath $excelPath)) {
            throw "実行一覧ファイルが存在しません。"
        }

        $rows = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents = $false
            try {
                $workbook = $excel.Workbooks.Open($excelPath)
                $rows = @(Get-RowObjects -Sheet $workbook.Sheets.Item(1))
            }
            finally {
                if ($workbook) { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
                if ($excel)    { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        } catch {
            throw "Excelの読み込みに失敗しました: $($_.Exception.Message)"
        }
        if ($rows.Count -eq 0) {
            throw "Excelに行がありません。"
        }

        Set-RunButtonsEnabled $false

        $resultLines = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $rowConfigName = "$($row.'スペース識別名')".Trim()
            $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
            $rowBaseResourceTemplate = "$($row.'設定テンプレート名（基本）')".Trim()
            $rowCustomResourceTemplate = "$($row.'設定テンプレート名（カスタム）')".Trim()

            Set-StepStatus -Label $lblMultipleBatchStatus -Text "実行中... ($($i + 1)/$($rows.Count): $rowConfigName)" -State "実行中..."
            [System.Windows.Forms.Application]::DoEvents()

            Write-Log "==================== 複数実行 $($i + 1)/$($rows.Count): $rowConfigName ===================="
            
            if (!$rowConfigName -or !$rowTemplateId -or !$rowBaseResourceTemplate) {
                Write-Log "スペース識別名・スペーステンプレートID・設定テンプレート名（基本）のいずれかが空のためスキップします。"
                $resultLines.Add("行$($i + 2) ($rowConfigName): スキップ（必須項目が空）")
                continue
            }

            foreach ($cd in $categoryDefs) {
                $bd = $cd.ButtonDefs[0]
                if ($bd.InputControls.ContainsKey("TargetGroupName")) {
                    $selectedValue = Get-ComboBoxValue -SelectedItem $cmbMultipleBatchTargetGroup.SelectedItem
                    $matchingItem = $bd.InputControls['TargetGroupName'].Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $selectedValue } | Select-Object -First 1
                    if ($matchingItem) {
                        $bd.InputControls['TargetGroupName'].SelectedItem = $matchingItem
                    }
                }
                $bd.InputControls['ConfigName'].Text = $rowConfigName
            }
            $bd0 = $categoryDefs[0].ButtonDefs[0]
            $bd0.InputControls['SpaceTemplateId'].Text = $rowTemplateId
            $bd1 = $categoryDefs[1].ButtonDefs[0]
            $bd1.InputControls['SpaceId'].Text = ""
            $bd2 = $categoryDefs[2].ButtonDefs[0]
            $bd2.InputControls['BaseTemplateName'].Text = $rowBaseResourceTemplate
            $bd2.InputControls['CustomTemplateName'].Text = if ($rowCustomResourceTemplate) { $rowCustomResourceTemplate } else { $script:customTemplateNamePlaceholder }

            $exitCode = Invoke-AllStepsForCurrentInputs
            if ($exitCode -eq 0) {
                $resultLines.Add("行$($i + 2) ($rowConfigName): 成功")
            } elseif ($exitCode -eq 2) {
                $resultLines.Add("行$($i + 2) ($rowConfigName): 警告")
            } else {
                $resultLines.Add("行$($i + 2) ($rowConfigName): 失敗")
            }
        }

        Write-Log "==================== 複数実行 結果 ===================="
        foreach ($line in $resultLines) { Write-Log $line }

        $failedCount = @($resultLines | Where-Object { $_ -match ": 失敗|: スキップ" }).Count
        $warningCount = @($resultLines | Where-Object { $_ -match "警告" }).Count
        $succsessCount = $rows.Count -$failedCount -$warningCount
        $multipleResultMessage = "終了（成功-$($succsessCount)件、警告-$($warningCount)件、失敗/スキップ-$($failedCount)件）"
        if ($failedCount -gt 0) {
            Set-StepStatus -Label $lblMultipleBatchStatus -Text $multipleResultMessage -State "失敗"
        } elseif ($warningCount -gt 0) {
            Set-StepStatus -Label $lblMultipleBatchStatus -Text $multipleResultMessage -State "警告"
        } else {
            Set-StepStatus -Label $lblMultipleBatchStatus -Text $multipleResultMessage -State "成功"
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("$_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Set-StepStatus -Label $lblMultipleBatchStatus -Text "失敗"
    } finally {
        Set-RunButtonsEnabled $true
    }
})

function Get-TemplateFileNames {
    param([string]$EnvVarName)
    $templatePath = Get-ResolvedVar $EnvVarName $setEnvBat
    if (!$templatePath -or !(Test-Path -LiteralPath $templatePath)) { return @() }
    return @(Get-ChildItem -LiteralPath $templatePath -Filter "*.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object)
}

function Set-ComboItems {
    param([System.Windows.Forms.ComboBox]$ComboBox, [string[]]$Names, [string]$Placeholder)
    $selected = Get-ComboBoxValue -SelectedItem $ComboBox.SelectedItem
    $ComboBox.DisplayMember = "Text"
    $ComboBox.ValueMember = "Value"
    $ComboBox.Items.Clear()
    $ComboBox.Items.Add([PSCustomObject]@{ Text = $Placeholder; Value = $Placeholder }) | Out-Null
    foreach ($name in $Names) { $ComboBox.Items.Add([PSCustomObject]@{ Text = $name; Value = $name }) | Out-Null }

    if ($selected) {
        $matchingItem = $ComboBox.Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $selected } | Select-Object -First 1
        if ($matchingItem) {
            $ComboBox.SelectedItem = $matchingItem
        } else {
            $ComboBox.SelectedItem = $ComboBox.Items[0]
        }
    } else {
        $ComboBox.SelectedItem = $ComboBox.Items[0]
    }
}

function Update-BaseTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "COMMON_BASE_TEMPLATE_PATH"
    Set-ComboItems -ComboBox $cmbBaseTemplateName -Names $names -Placeholder $script:baseTemplateNamePlaceholder
    Set-ComboItems -ComboBox $cmbRunAllBaseTemplateName -Names $names -Placeholder $script:baseTemplateNamePlaceholder
}

function Update-CustomTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "COMMON_CUSTOM_TEMPLATE_PATH"
    Set-ComboItems -ComboBox $cmbCustomTemplateName -Names $names -Placeholder $script:customTemplateNamePlaceholder
    Set-ComboItems -ComboBox $cmbRunAllCustomTemplateName -Names $names -Placeholder $script:customTemplateNamePlaceholder
}

$settingsCommonFieldPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }
        Update-CommonSettingsFields
    } `
    -OnReload {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }
        Update-CommonSettingsFields
    }).Panel

$tabSettingsCommon.Controls.Add($settingsCommonFieldPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

$lblSettingsGroupTarget = New-Label -Text "対象のグループ" -Width 150 -Height 24

$cmbSettingsGroupTarget = New-ComboBox -Width 150 -Height 24 -DisplayMember "Text" -ValueMember "Value"

$btnSettingsNewGroup = New-Button -Text "新規作成" -Width 140 -Height 24

$settingsGroupFieldPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "基本設定"
        Vars = [ordered]@{
            "COMMON_DOWNLOAD_PATH"        = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
            "COMMON_BASE_TEMPLATE_PATH"   = @{ Label = "設定テンプレート（基本）ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CUSTOM_TEMPLATE_PATH" = @{ Label = "設定テンプレート（カスタム）ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CONFIG_PATH"          = @{ Label = "設定ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CHECK_OUTPUT_PATH"    = @{ Label = "チェック結果の出力先フォルダ"; Browse = "Folder" }
            "COMMON_LOG_PATH"             = @{ Label = "ログの出力先フォルダ"; Browse = "Folder" }
        }
    }
    "KINTONE" = @{
        Label = "kintoneの接続情報"
        Vars = [ordered]@{
            "KINTONE_SUB_DOMAIN" = @{ Label = "サブドメイン" }
            "KINTONE_LOGIN"      = @{ Label = "ログイン名" }
            "KINTONE_PASSWORD"   = @{ Label = "パスワード"; Masked = $true }
        }
    }
}

$settingsGroupLabels = @{}
$settingsVarLabels = [ordered]@{}
$settingsFolderBrowseVars = @()
$settingsFileBrowseVars = @()
$settingsMaskedVars = @()
$settingsMultilineVars = @()
foreach ($groupKey in $settingsGroups.Keys) {
    $settingsGroupLabels[$groupKey] = $settingsGroups[$groupKey].Label
    foreach ($varKey in $settingsGroups[$groupKey].Vars.Keys) {
        $varDef = $settingsGroups[$groupKey].Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
    }
}

$settingsToolTip = New-ToolTip
$kintoneVars = @($settingsGroups["KINTONE"].Vars.Keys)

$script:commonEnvResolver = { param($name) Get-ResolvedVar $name $setEnvBat }
$script:fieldTextBoxes = @{}

$settingsTrailingButtonVars = @{
    "KINTONE_PASSWORD" = { param($Panel, $Y, $Field)
        $fieldTextBoxes = $script:fieldTextBoxes
        Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
            Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
                $subDomainVal = $fieldTextBoxes["KINTONE_SUB_DOMAIN"].Text.Trim()
                $loginVal = $fieldTextBoxes["KINTONE_LOGIN"].Text
                $passwordVal = $fieldTextBoxes["KINTONE_PASSWORD"].Text
                $baseUrlVal = "https://$subDomainVal.cybozu.com"
                if (!$subDomainVal -or !$loginVal -or !$passwordVal) {
                    throw "サブドメイン・ログイン名・パスワードをすべて入力してください"
                }
                $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${loginVal}:${passwordVal}"))
                Invoke-KintoneRequest -BaseUrl $baseUrlVal -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
            }
        }.GetNewClosure()
    }
}

$script:saveEnvBatGetValueFn = { param($name)
    if ($script:fieldTextBoxes.ContainsKey($name)) {
        $script:fieldTextBoxes[$name].Text
    } else {
        ""
    }
}
$script:saveEnvBatHasValueFn = { param($name) $script:fieldTextBoxes.ContainsKey($name) }

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = (Join-Path $scriptDir "common.bat"); Save = { Save-CommonSettings }; Reload = {} }
    )
}

function Save-CommonSettings {
    $commonBatPath = Join-Path $scriptDir "common.bat"
    $commonVars = @($settingsGroups["COMMON"].Vars.Keys)
    Save-EnvBatFile -Path $commonBatPath -VarNames $commonVars -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn
}

function Update-CommonSettingsFields {
    $commonBatPath = Join-Path $scriptDir "common.bat"
    $commonDefaults = Get-SetEnvDefaults -Path $commonBatPath

    $rows = @()
    $commonVars = @($settingsGroups["COMMON"].Vars.Keys)
    foreach ($varName in $commonVars) {
        $varValue = if ($commonDefaults.ContainsKey($varName)) { $commonDefaults[$varName] } else { $null }
        $rows += [PSCustomObject]@{ Group = "COMMON"; VarName = $varName; Value = $varValue; Key = $varName }
    }
    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows $rows -TargetTextBoxes $script:fieldTextBoxes -TrailingButtonVars @{} `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    if (!$GroupName) { return @() }
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

function Save-GroupSettings {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $groupBatPath = Get-GroupBatPath $GroupName
    if (!(Test-Path -LiteralPath $groupBatPath)) {
        $templatePath = Join-Path $clientsTemplateDir "client.bat"
        if (Test-Path -LiteralPath $templatePath) {
            Copy-Item -LiteralPath $templatePath -Destination $groupBatPath
        }
    }

    Save-EnvBatFile -Path $groupBatPath -VarNames $kintoneVars -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn
}

function Get-GroupSettingsFieldValue {
    param([string]$VarName)
    if ($script:fieldTextBoxes.ContainsKey($VarName)) {
        return $script:fieldTextBoxes[$VarName].Text.Trim()
    }
    return $null
}


function Update-GroupSettingsFields {
    $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
    if (!$target) {
        $settingsGroupFieldPanel.Controls.Clear()
        return
    }

    $templateDefaults = Get-SetEnvDefaults -Path (Join-Path $clientsTemplateDir "client.bat")
    $groupDefaults = Get-SetEnvDefaults -Path (Get-GroupBatPath $target)

    $rows = @()
    foreach ($varName in $kintoneVars) {
        $varValue = if ($groupDefaults.ContainsKey($varName)) { $groupDefaults[$varName] } else { $templateDefaults[$varName] }
        $rows += [PSCustomObject]@{ Group = "KINTONE"; VarName = $varName; Value = $varValue; Key = $varName }
    }
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows $rows -TargetTextBoxes $script:fieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }
        Update-CommonSettingsFields
    } `
    -OnReload {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }
        Update-CommonSettingsFields
    }).Panel

$settingsGroupTopPanel = (New-SettingsTopPanel `
    -ExtraControls @($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsNewGroup) `
    -OnSave {
        $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-GroupSettingsFields
        Update-GroupDropdowns
    } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    }).Panel

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

$btnSettingsNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if ($cmbSettingsGroupTarget.Items.Contains($newName) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsGroupTarget.Items.Add([PSCustomObject]@{ Text = $newName; Value = $newName }) | Out-Null
    $cmbSettingsGroupTarget.SelectedItem = $cmbSettingsGroupTarget.Items[-1]
})

$cmbSettingsGroupTarget.Add_SelectedIndexChanged({
    Update-GroupSettingsFields
})

$settingsSubTabControl.Add_SelectedIndexChanged({
    if ($settingsSubTabControl.SelectedTab -eq $tabSettingsCommon) {
        Update-CommonSettingsFields
    } elseif ($settingsSubTabControl.SelectedTab -eq $tabSettingsGroup) {
        Update-GroupSettingsFields
    }
})

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-BaseTemplateNameList
        Update-CustomTemplateNameList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-GroupDropdowns
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        if ($settingsSubTabControl.SelectedTab -eq $tabSettingsCommon) {
            Update-CommonSettingsFields
        } elseif ($settingsSubTabControl.SelectedTab -eq $tabSettingsGroup) {
            Update-GroupSettingsFields
        }
    }
})

$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-BaseTemplateNameList
    Update-CustomTemplateNameList
    Update-CommonSettingsFields
    Update-GroupSettingsFields
    Update-GroupDropdowns
    
    Adjust-InitialTabHeight -NestedTabControl $execTabControl
})

[System.Windows.Forms.Application]::Run($form)
