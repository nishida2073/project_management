
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$createSpaceBat = Join-Path $rootPath "create-space-from-template.bat"
$downloadBat = Join-Path $rootPath "download-kintone-resources.bat"
$generateBat = Join-Path $rootPath "generate-config-from-template.bat"
$applyBat = Join-Path $rootPath "apply-kintone-resources.bat"
$checkBat = Join-Path $rootPath "check-kintone-resources.bat"
$clientsDir = Join-Path $rootPath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$setKintoneBat = Join-Path $clientsDir "set-kintone.bat"

$libraryDir = Join-Path $rootPath "bats\library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$script:baseTemplateNamePlaceholder = "未選択"

$script:customTemplateNamePlaceholder = "指定なし"

$cmbBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbBaseTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbCustomTemplateName.Size = New-Object System.Drawing.Size(180, 22)
$cmbCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$configNameInputDef = [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200 }
$spaceTemplateIdInputDef = [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 151; InputWidth = 200; NewRow = $true }
$spaceIdInputDef = [PSCustomObject]@{ Name = "SpaceId"; Label = "スペースID"; LabelWidth = 151; InputWidth = 200; NewRow = $true }
$baseTemplateNameInputDef = [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 151; ExistingControl = $cmbBaseTemplateName; NewRow = $true }
$customTemplateNameInputDef = [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 151; ExistingControl = $cmbCustomTemplateName; NewRow = $true }

$stepMeta = @(
    [PSCustomObject]@{
        Id = 0; Label = "スペース作成"; StageKey = "createspace"; Bat = $createSpaceBat
        Inputs = @($configNameInputDef, $spaceTemplateIdInputDef)
        ArgsFn = { param($ic) @("-TemplateId", $ic['SpaceTemplateId'].Text.Trim(), "-SpaceName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = $null
        OpenTargetFn = { $script:createdSpaceUrl }
        OnSuccessFn = {
            param($ic, $lastOutputLines)
            $idLine = $lastOutputLines | Where-Object { $_ -match 'SPACE_ID=(\d+)' } | Select-Object -Last 1
            if ($idLine -and $idLine -match 'SPACE_ID=(?<id>\d+)') {
                $nextIc = $script:stepInputControls[1]
                if ($nextIc -and $nextIc.ContainsKey('SpaceId')) { $nextIc['SpaceId'].Text = $Matches.id }
                $baseUrl = (Get-ResolvedVar -VarName "KINTONE_BASE_URL" -Path $setKintoneBat).TrimEnd('/')
                if ($baseUrl) { $script:createdSpaceUrl = "$baseUrl/k/#/space/$($Matches.id)" }
            }
        }
    }
    [PSCustomObject]@{
        Id = 1; Label = "ダウンロード"; StageKey = "download"; Bat = $downloadBat
        Inputs = @($configNameInputDef, $spaceIdInputDef)
        ArgsFn = { param($ic) @("-SpaceId", $ic['SpaceId'].Text.Trim(), "-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_DOWNLOAD_PATH") "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
        OnSuccessFn = {
            param($ic, $lastOutputLines)
            $configLine = $lastOutputLines | Where-Object { $_ -match 'CONFIG_NAME=(.+)$' } | Select-Object -Last 1
            if ($configLine -and $configLine -match 'CONFIG_NAME=(?<name>.+)$') {
                $ic['ConfigName'].Text = $Matches.name.Trim()
            }
        }
    }
    [PSCustomObject]@{
        Id = 2; Label = "設定ファイルの生成"; StageKey = "generate"; Bat = $generateBat
        Inputs = @($configNameInputDef, $baseTemplateNameInputDef, $customTemplateNameInputDef)
        ArgsFn = {
            param($ic)
            $stepArgs = @("-BaseTemplateConfigName", $ic['BaseTemplateName'].Text.Trim(), "-DownloadConfigName", $ic['ConfigName'].Text.Trim())
            $customTemplateName = $ic['CustomTemplateName'].Text.Trim()
            if ($customTemplateName -and $customTemplateName -ne $script:customTemplateNamePlaceholder) {
                $stepArgs += @("-CustomTemplateConfigName", $customTemplateName)
            }
            $stepArgs
        }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CONFIG_PATH") "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
    }
    [PSCustomObject]@{
        Id = 3; Label = "kintoneへ反映"; StageKey = "apply"; Bat = $applyBat
        Inputs = @($configNameInputDef)
        ArgsFn = { param($ic) @("-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = $null
        OpenTargetFn = { $script:createdSpaceUrl }
    }
    [PSCustomObject]@{
        Id = 4; Label = "データチェック"; StageKey = "check"; Bat = $checkBat
        Inputs = @($configNameInputDef)
        ArgsFn = { param($ic) @("-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CHECK_OUTPUT_PATH") "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
    }
)
$script:stepMetaById = @{}
foreach ($sm in $stepMeta) { $script:stepMetaById[$sm.Id] = $sm }

$categoryDefs = @($stepMeta | ForEach-Object {
    $stepId = $_.Id
    [PSCustomObject]@{
        Label = $_.Label
        ButtonDefs = @(
            [PSCustomObject]@{
                Label      = $_.Label
                Id         = $stepId
                Inputs     = $_.Inputs
                OpenTarget = if ($_.OpenTargetFn) { $_.OpenTargetFn } elseif ($_.OutputPathFn) { { $script:stepOutputPaths[$stepId] }.GetNewClosure() } else { $null }
            }
        )
    }
})

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneリソース生成ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 500)

$script:currentProc = $null
$script:stepOutputPaths = @{}
$script:runHadWarning = $false
$script:createdSpaceUrl = $null
$form.Add_FormClosing({
    if ($script:currentProc -and !$script:currentProc.HasExited) {
        & taskkill.exe /T /F /PID $script:currentProc.Id 2>&1 | Out-Null
    }
})

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "実行"

$innerRunTabControl = New-Object System.Windows.Forms.TabControl
$innerRunTabControl.Dock = [System.Windows.Forms.DockStyle]::Top
$innerRunTabControl.Height = 404

$tabSingleRun = New-Object System.Windows.Forms.TabPage
$tabSingleRun.Text = "単体実行"

$tabBatchRun = New-Object System.Windows.Forms.TabPage
$tabBatchRun.Text = "複数実行"

$innerRunTabControl.Controls.AddRange(@($tabBatchRun, $tabSingleRun))
$innerRunTabControl.Add_Selecting({
    if ($script:isRunning) { $_.Cancel = $true }
})

$innerRunTabControl.Add_SelectedIndexChanged({ Update-InnerRunTabHeight })

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "ログ"

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)

$script:isRunning = $false
$tabControl.Add_Selecting({
    if ($script:isRunning -and $_.TabPage -ne $tabRun) {
        $_.Cancel = $true
    }
})

$runTopPanel = New-Object System.Windows.Forms.Panel
$runTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top

$execTabControl = New-Object System.Windows.Forms.TabControl

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$cmbRunAllBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbRunAllCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs @() -RunButtonText "実行" `
    -Inputs @(
        [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200 }
        [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true }
        [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 220; ExistingControl = $cmbRunAllBaseTemplateName; NewRow = $true }
        [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 180; ExistingControl = $cmbRunAllCustomTemplateName; NewRow = $true }
    )

$batchPanel = $batchTab.Panel
$txtRunAllConfigName = $batchTab.InputControls["ConfigName"]
$txtRunAllSpaceTemplateId = $batchTab.InputControls["SpaceTemplateId"]
$btnRunAll = $batchTab.RunButton
$lblOverallStatus = $batchTab.StatusLabel

$tabResult = New-CategoryTabControl -CategoryDefs $categoryDefs -TabControl $execTabControl `
    -OnRunClick { param($bd) Invoke-SingleStep -Id $bd.Id }

$script:stepStatusLabels = @{}
$script:stepInputControls = @{}
foreach ($cd in $categoryDefs) {
    $bd = $cd.ButtonDefs[0]
    $script:stepStatusLabels[$bd.Id] = $bd.StepStatusLabel
    $script:stepInputControls[$bd.Id] = $bd.InputControls
}

$execTabControl.Dock = [System.Windows.Forms.DockStyle]::None
$execTabControl.Location = New-Object System.Drawing.Point(0, 0)
$execTabControl.Width = 760
$runTopPanel.Controls.Add($execTabControl)

$execTabControl.Height = 45 + $batchPanel.Height

$execTabControl.Add_SelectedIndexChanged({
    $runTopPanel.Height = $execTabControl.Top + $execTabControl.Height
    Update-InnerRunTabHeight
})
$runTopPanel.Height = $execTabControl.Top + $execTabControl.Height

function Update-InnerRunTabHeight {
    if ($innerRunTabControl.SelectedTab -eq $tabBatchRun) {
        $innerRunTabControl.Height = $batchExcelPanel.Height + 30
    } else {
        $innerRunTabControl.Height = $runTopPanel.Height + 30
    }
    $tabRun.PerformLayout()
}

$batchExcelPanel = New-Object System.Windows.Forms.Panel
$batchExcelPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$batchExcelPanel.Height = 90

$lblBatchExcelPath = New-Object System.Windows.Forms.Label
$lblBatchExcelPath.Text = "実行一覧ファイル"
$lblBatchExcelPath.AutoSize = $true
$lblBatchExcelPath.Location = New-Object System.Drawing.Point(20, 17)

$txtBatchExcelPath = New-Object System.Windows.Forms.TextBox
$txtBatchExcelPath.Location = New-Object System.Drawing.Point(140, 14)
$txtBatchExcelPath.Size = New-Object System.Drawing.Size(250, 22)
$txtBatchExcelPath.ReadOnly = $true

$btnBatchBrowse = New-Object System.Windows.Forms.Button
$btnBatchBrowse.Text = "参照..."
$btnBatchBrowse.Location = New-Object System.Drawing.Point(400, 13)
$btnBatchBrowse.Size = New-Object System.Drawing.Size(70, 24)

$btnBatchRunAll = New-Object System.Windows.Forms.Button
$btnBatchRunAll.Text = "実行"
$btnBatchRunAll.Location = New-Object System.Drawing.Point(20, 50)
$btnBatchRunAll.Size = New-Object System.Drawing.Size(100, 26)

$lblBatchStatus = New-Object System.Windows.Forms.Label
$lblBatchStatus.Text = ""
$lblBatchStatus.AutoSize = $true
$lblBatchStatus.Location = New-Object System.Drawing.Point(130, 56)
$lblBatchStatus.Font = New-Object System.Drawing.Font($lblBatchStatus.Font, [System.Drawing.FontStyle]::Bold)

$batchExcelPanel.Controls.AddRange(@(
    $lblBatchExcelPath, $txtBatchExcelPath, $btnBatchBrowse, $btnBatchRunAll, $lblBatchStatus
))

$dlgBatchExcel = New-Object System.Windows.Forms.OpenFileDialog
$dlgBatchExcel.Filter = "Excelファイル (*.xlsx)|*.xlsx"

$btnBatchBrowse.Add_Click({
    if ($dlgBatchExcel.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtBatchExcelPath.Text = $dlgBatchExcel.FileName
    }
})

$tabSingleRun.Controls.Add($runTopPanel)
$tabBatchRun.Controls.Add($batchExcelPanel)

$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($innerRunTabControl, $txtLog)

$script:logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $stepMeta `
    -ExtraLabelText "スペース識別名" -ExtraComboWidth 220 `
    -GetLogPathFn { Get-ResolvedVar "COMMON_LOG_PATH" } `
    -OnAfterClear { Update-LogConfigNameList } `
    -OnUpdateLogView { Update-LogView }
foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogConfigName = $script:logTab.ExtraCombo

function Update-LogConfigNameList {
    $selected = $cmbLogConfigName.SelectedItem
    $cmbLogConfigName.Items.Clear()
    $cmbLogConfigName.Items.Add("すべて") | Out-Null

    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $stageKeyPattern = ($stepMeta.StageKey -join '|')
        $stagePrefixPattern = "^(?:$stageKeyPattern)_(?<config>.+)_\d{8}_\d{6}$"
        $configNames = Get-ChildItem -LiteralPath $logPath -Filter "*.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($_.Name), $stagePrefixPattern)
                if ($m.Success) { $m.Groups["config"].Value }
            } | Sort-Object -Unique
        foreach ($name in $configNames) {
            $cmbLogConfigName.Items.Add($name) | Out-Null
        }
    }

    $cmbLogConfigName.SelectedIndex = if ($selected -and $cmbLogConfigName.Items.Contains($selected)) { $cmbLogConfigName.Items.IndexOf($selected) } else { 0 }
}

function Update-LogView {
    $selectedRadio = $script:logTab.Radios | Where-Object { $_.Checked } | Select-Object -First 1
    if (-not $selectedRadio) { return }
    $stage = $selectedRadio.Tag.StageKey
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"

    $script:logTab.ContentBox.Text = ""

    if (!($logPath -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logConfigName = $cmbLogConfigName.SelectedItem
    $configFilter = if ($logConfigName -and $logConfigName -ne "すべて") { "$logConfigName" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "${stage}_$configFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

    $sections = foreach ($file in $files) {
        try {
            [System.IO.File]::ReadAllText($file.FullName, $script:cp932Encoding)
        } catch {
            "$($file.Name) は他のプロセスで使用中のため表示できません（実行中の可能性があります）。"
        }
    }
    $script:logTab.ContentBox.Text = $sections -join "`r`n`r`n"
}

$cmbLogConfigName.Add_SelectedIndexChanged({ Update-LogView })

Update-LogConfigNameList
Update-LogView

function Get-StepArgs {
    param([int]$Id)
    return & $script:stepMetaById[$Id].ArgsFn $script:stepInputControls[$Id]
}

function Get-StepOutputPath {
    param([int]$Id)
    $sm = $script:stepMetaById[$Id]
    if (!$sm.OutputPathFn) { return $null }
    return & $sm.OutputPathFn $script:stepInputControls[$Id]
}

function Test-StepPrereq {
    param([int]$Id)
    $ic = $script:stepInputControls[$Id]
    if ($Id -ne 1 -and !$ic['ConfigName'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペース識別名を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 0 -and !$ic['SpaceTemplateId'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペーステンプレートIDを設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 1 -and !$ic['SpaceId'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペースIDを設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 2 -and (!$ic['BaseTemplateName'].Text.Trim() -or $ic['BaseTemplateName'].Text.Trim() -eq $script:baseTemplateNamePlaceholder)) {
        [System.Windows.Forms.MessageBox]::Show("設定テンプレート名（基本）を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    return $true
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($ic in $script:stepInputControls.Values) {
        foreach ($ctrl in $ic.Values) { $ctrl.Enabled = $Enabled }
    }
    $cmbBaseTemplateName.Enabled = $Enabled
    $cmbCustomTemplateName.Enabled = $Enabled
    $txtRunAllConfigName.Enabled = $Enabled
    $txtRunAllSpaceTemplateId.Enabled = $Enabled
    $cmbRunAllBaseTemplateName.Enabled = $Enabled
    $cmbRunAllCustomTemplateName.Enabled = $Enabled
    $btnRunAll.Enabled = $Enabled
    $btnBatchBrowse.Enabled = $Enabled
    $btnBatchRunAll.Enabled = $Enabled
    foreach ($btn in $tabResult.RunButtons) { $btn.Enabled = $Enabled }
}

function Sync-NextStepConfigName {
    param([int]$CompletedId)
    $curIc = $script:stepInputControls[$CompletedId]
    $nextIc = $script:stepInputControls[($CompletedId + 1)]
    if (!$curIc -or !$nextIc -or !$curIc.ContainsKey('ConfigName') -or !$nextIc.ContainsKey('ConfigName')) { return }
    $nextIc['ConfigName'].Text = $curIc['ConfigName'].Text.Trim()
}

function Invoke-Step {
    param([int]$Id)

    $sm = $script:stepMetaById[$Id]
    $script:lastStepOutputLines = New-Object System.Collections.Generic.List[string]

    $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $sm.Bat }) `
        -GetBatArgs { param($bd) Get-StepArgs -Id $Id } `
        -WorkingDirectory $rootPath -Form $form `
        -WriteLog { param($msg) Write-Log $msg } `
        -OnOutputLine { param($line) Write-Log $line; $script:lastStepOutputLines.Add($line) } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -DisplayLabel $sm.Label -StatusLabel $script:stepStatusLabels[$Id] `
        -IsWarningExitCode { param($ExitCode) $ExitCode -eq 2 }

    $outputPath = Get-StepOutputPath -Id $Id
    if ($outputPath -and (Test-Path -LiteralPath $outputPath)) {
        $script:stepOutputPaths[$Id] = $outputPath
    }

    if ($exitCode -ne 0 -and $exitCode -ne 2) {
        return $false
    }

    if ($exitCode -eq 2) { $script:runHadWarning = $true }

    if ($sm.OnSuccessFn) { & $sm.OnSuccessFn $script:stepInputControls[$Id] $script:lastStepOutputLines }
    Sync-NextStepConfigName -CompletedId $Id
    return $true
}

function Invoke-SingleStep {
    param([int]$Id)

    if (!(Test-StepPrereq -Id $Id)) { return }

    $script:isRunning = $true
    Set-RunButtonsEnabled $false
    $lblOverallStatus.Text = ""

    Invoke-Step -Id $Id | Out-Null

    Set-RunButtonsEnabled $true
    $script:isRunning = $false
}

function Invoke-AllStepsForCurrentInputs {
    $script:runHadWarning = $false
    foreach ($sm in $stepMeta) {
        if (!(Test-StepPrereq -Id $sm.Id)) {
            return $sm.Label
        }
        if (!(Invoke-Step -Id $sm.Id)) {
            return $sm.Label
        }
    }
    return $null
}

function Copy-ComboSelection {
    param([System.Windows.Forms.ComboBox]$From, [System.Windows.Forms.ComboBox]$To)
    $value = "$($From.SelectedItem)"
    if ($To.Items.Contains($value)) {
        $To.SelectedItem = $value
    } else {
        $To.Text = $value
    }
}

function Invoke-SeededAllSteps {
    foreach ($sm in $stepMeta) {
        $script:stepInputControls[$sm.Id]['ConfigName'].Text = $txtRunAllConfigName.Text.Trim()
    }
    $script:stepInputControls[0]['SpaceTemplateId'].Text = $txtRunAllSpaceTemplateId.Text.Trim()
    Copy-ComboSelection -From $cmbRunAllBaseTemplateName -To $cmbBaseTemplateName
    Copy-ComboSelection -From $cmbRunAllCustomTemplateName -To $cmbCustomTemplateName
    return Invoke-AllStepsForCurrentInputs
}

$btnRunAll.Add_Click({
    $seedConfigName = $txtRunAllConfigName.Text.Trim()
    if (!$seedConfigName) {
        [System.Windows.Forms.MessageBox]::Show("スペース識別名を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $seedBaseTemplateName = "$($cmbRunAllBaseTemplateName.SelectedItem)".Trim()
    if (!$seedBaseTemplateName -or $seedBaseTemplateName -eq $script:baseTemplateNamePlaceholder) {
        [System.Windows.Forms.MessageBox]::Show("設定テンプレート名（基本）を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunButtonsEnabled $false
    Set-StepStatus -Label $lblOverallStatus -Text "実行中..."

    $failedLabel = Invoke-SeededAllSteps

    if ($failedLabel) {
        Set-StepStatus -Label $lblOverallStatus -Text "エラーが発生しました（$failedLabel）" -State "失敗"
    } elseif ($script:runHadWarning) {
        Set-StepStatus -Label $lblOverallStatus -Text "完了しました（警告あり、要確認）" -State "警告"
    } else {
        Set-StepStatus -Label $lblOverallStatus -Text "完了しました" -State "成功"
    }

    Set-RunButtonsEnabled $true
    $script:isRunning = $false
})

$btnBatchRunAll.Add_Click({
    $excelPath = $txtBatchExcelPath.Text.Trim()
    if (!$excelPath -or !(Test-Path -LiteralPath $excelPath)) {
        [System.Windows.Forms.MessageBox]::Show("実行一覧ファイルを選択してください。", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
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
        [System.Windows.Forms.MessageBox]::Show("Excelの読み込みに失敗しました: $($_.Exception.Message)", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Excelに行がありません。", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunButtonsEnabled $false

    $origConfigNames = @{}
    foreach ($sm in $stepMeta) { $origConfigNames[$sm.Id] = $script:stepInputControls[$sm.Id]['ConfigName'].Text }
    $origSpaceTemplateId = $script:stepInputControls[0]['SpaceTemplateId'].Text
    $origSpaceId = $script:stepInputControls[1]['SpaceId'].Text
    $origBaseTemplateSelectedItem = $cmbBaseTemplateName.SelectedItem
    $origBaseTemplateText = $cmbBaseTemplateName.Text
    $origCustomTemplateSelectedItem = $cmbCustomTemplateName.SelectedItem
    $origCustomTemplateText = $cmbCustomTemplateName.Text

    $resultLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowConfigName = "$($row.'スペース識別名')".Trim()
        $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
        $rowBaseResourceTemplate = "$($row.'設定テンプレート名（基本）')".Trim()
        $rowCustomResourceTemplate = "$($row.'設定テンプレート名（カスタム）')".Trim()

        Set-StepStatus -Label $lblBatchStatus -Text "実行中... ($($i + 1)/$($rows.Count): $rowConfigName)" -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()

        Write-Log ""
        Write-Log "==================== 複数実行 $($i + 1)/$($rows.Count): $rowConfigName ===================="

        if (!$rowConfigName -or !$rowTemplateId -or !$rowBaseResourceTemplate) {
            Write-Log "スペース識別名・スペーステンプレートID・設定テンプレート名（基本）のいずれかが空のためスキップします。"
            $resultLines.Add("行$($i + 2) ($rowConfigName): スキップ（必須項目が空）")
            continue
        }

        $script:stepInputControls[0]['ConfigName'].Text = $rowConfigName
        $script:stepInputControls[0]['SpaceTemplateId'].Text = $rowTemplateId
        $script:stepInputControls[1]['SpaceId'].Text = ""
        if ($cmbBaseTemplateName.Items.Contains($rowBaseResourceTemplate)) {
            $cmbBaseTemplateName.SelectedItem = $rowBaseResourceTemplate
        } else {
            $cmbBaseTemplateName.Text = $rowBaseResourceTemplate
        }
        if (!$rowCustomResourceTemplate) {
            $cmbCustomTemplateName.SelectedItem = $script:customTemplateNamePlaceholder
        } elseif ($cmbCustomTemplateName.Items.Contains($rowCustomResourceTemplate)) {
            $cmbCustomTemplateName.SelectedItem = $rowCustomResourceTemplate
        } else {
            $cmbCustomTemplateName.Text = $rowCustomResourceTemplate
        }

        $failedLabel = Invoke-AllStepsForCurrentInputs
        if ($failedLabel) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 失敗（$failedLabel）")
        } elseif ($script:runHadWarning) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功（警告あり、要確認）")
        } else {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功")
        }
    }

    Write-Log ""
    Write-Log "==================== 複数実行 結果 ===================="
    foreach ($line in $resultLines) { Write-Log $line }

    $failedCount = @($resultLines | Where-Object { $_ -match ": 失敗|: スキップ" }).Count
    $warningCount = @($resultLines | Where-Object { $_ -match "警告あり" }).Count
    if ($failedCount -gt 0) {
        Set-StepStatus -Label $lblBatchStatus -Text "完了（$($rows.Count)件中$failedCount件が失敗/スキップ）" -State "失敗"
    } elseif ($warningCount -gt 0) {
        Set-StepStatus -Label $lblBatchStatus -Text "完了しました（$($rows.Count)件中$warningCount件で警告あり、要確認）" -State "警告"
    } else {
        Set-StepStatus -Label $lblBatchStatus -Text "完了しました（全$($rows.Count)件成功）" -State "成功"
    }

    foreach ($sm in $stepMeta) { $script:stepInputControls[$sm.Id]['ConfigName'].Text = $origConfigNames[$sm.Id] }
    $script:stepInputControls[0]['SpaceTemplateId'].Text = $origSpaceTemplateId
    $script:stepInputControls[1]['SpaceId'].Text = $origSpaceId
    if ($origBaseTemplateSelectedItem -and $cmbBaseTemplateName.Items.Contains($origBaseTemplateSelectedItem)) {
        $cmbBaseTemplateName.SelectedItem = $origBaseTemplateSelectedItem
    } else {
        $cmbBaseTemplateName.Text = $origBaseTemplateText
    }
    if ($origCustomTemplateSelectedItem -and $cmbCustomTemplateName.Items.Contains($origCustomTemplateSelectedItem)) {
        $cmbCustomTemplateName.SelectedItem = $origCustomTemplateSelectedItem
    } else {
        $cmbCustomTemplateName.Text = $origCustomTemplateText
    }

    Set-RunButtonsEnabled $true
    $script:isRunning = $false
})

function Get-TemplateFileNames {
    param([string]$EnvVarName)
    $templatePath = Get-ResolvedVar $EnvVarName
    if (!$templatePath -or !(Test-Path -LiteralPath $templatePath)) { return @() }
    return @(Get-ChildItem -LiteralPath $templatePath -Filter "*.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object)
}

function Set-ComboItems {
    param([System.Windows.Forms.ComboBox]$ComboBox, [string[]]$Names, [string]$Placeholder)
    $selected = $ComboBox.SelectedItem
    $ComboBox.Items.Clear()
    $ComboBox.Items.Add($Placeholder) | Out-Null
    foreach ($name in $Names) { $ComboBox.Items.Add($name) | Out-Null }

    if ($selected -and $ComboBox.Items.Contains($selected)) {
        $ComboBox.SelectedItem = $selected
    } else {
        $ComboBox.SelectedItem = $Placeholder
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

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)

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
            "KINTONE_BASE_URL" = @{ Label = "kintoneのサイトURL" }
            "KINTONE_LOGIN"    = @{ Label = "ログイン名" }
            "KINTONE_PASSWORD" = @{ Label = "パスワード"; Masked = $true }
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

$settingsToolTip = New-Object System.Windows.Forms.ToolTip
$kintoneVars = @($settingsGroups["KINTONE"].Vars.Keys)

$script:commonEnvResolver = { param($name) Get-ResolvedVar $name }
$script:fieldTextBoxes = @{}

function Get-SettingsFieldRows {
    $defaults = Get-SetEnvDefaults -Path $setEnvBat
    $kintoneDefaults = Get-SetEnvDefaults -Path $setKintoneBat
    foreach ($varName in $settingsVarLabels.Keys) {
        if ($kintoneVars -contains $varName) {
            $varValue = if ($kintoneDefaults.ContainsKey($varName)) { $kintoneDefaults[$varName] } else { "" }
            $group = "KINTONE"
        } else {
            if (!$defaults.ContainsKey($varName)) { continue }
            $varValue = $defaults[$varName]
            $group = "COMMON"
        }
        [PSCustomObject]@{ Group = $group; VarName = $varName; Value = $varValue; Key = $varName }
    }
}

$settingsTrailingButtonVars = @{
    "KINTONE_PASSWORD" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -OnClick {
        $baseUrlVal = $script:fieldTextBoxes["KINTONE_BASE_URL"].Text.Trim()
        $loginVal = $script:fieldTextBoxes["KINTONE_LOGIN"].Text
        $passwordVal = $script:fieldTextBoxes["KINTONE_PASSWORD"].Text
        $validationError = if (!$baseUrlVal -or !$loginVal -or !$passwordVal) { "kintoneのサイトURL・ログイン名・パスワードをすべて入力してください" } else { $null }
        Invoke-TestAction -DialogTitle "テスト接続" -ValidationError $validationError `
            -Action {
                $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${loginVal}:${passwordVal}"))
                Invoke-KintoneRequest -BaseUrl $baseUrlVal -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
            }.GetNewClosure() `
            -FormatSuccessMessage { param($response) "成功しました" }
    } }
}

function Update-SettingsFields {
    Render-SettingsFields -Panel $fieldPanel -Rows (Get-SettingsFieldRows) -TextBoxes $script:fieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

$script:saveEnvBatGetValueFn = { param($name) $script:fieldTextBoxes[$name].Text }
$script:saveEnvBatHasValueFn = { param($name) $script:fieldTextBoxes.ContainsKey($name) }

function Get-SettingsFiles {
    return @(
        [PSCustomObject]@{ Path = $setEnvBat; Save = { Save-EnvBatFile -Path $setEnvBat -VarNames @($settingsVarLabels.Keys | Where-Object { $kintoneVars -notcontains $_ }) -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn }; Reload = {} }
        [PSCustomObject]@{ Path = $setKintoneBat; Save = { Save-EnvBatFile -Path $setKintoneBat -VarNames $kintoneVars -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn }; Reload = {} }
    )
}

$settingsTopPanel = New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-SettingsFiles)) { & $f.Save } } `
    -OnReload { foreach ($f in (Get-SettingsFiles)) { & $f.Reload }; Update-SettingsFields }
$topPanel = $settingsTopPanel.Panel
$tabSettings.Controls.Add($topPanel)

Update-SettingsFields

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-BaseTemplateNameList
        Update-CustomTemplateNameList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogConfigNameList
        Update-LogView
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsFields
    }
})

Update-BaseTemplateNameList
Update-CustomTemplateNameList

$form.Add_Shown({
    Update-InnerRunTabHeight
    Update-SettingsFields
})
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
