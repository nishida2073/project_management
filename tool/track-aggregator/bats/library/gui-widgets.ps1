function Open-TargetOrWarn {
    param([string]$Path)
    if ($Path -match '^https?://') {
        Start-Process -FilePath $Path
        return
    }
    if (!$Path -or !(Test-Path -LiteralPath $Path)) {
        [System.Windows.Forms.MessageBox]::Show("パスが見つかりません:`r`n$Path", "開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Start-Process -FilePath $Path
}

function Get-ConsoleColorAsDrawingColor {
    param([string]$ConsoleColorName)
    switch ($ConsoleColorName) {
        "Black"       { [System.Drawing.Color]::Black }
        "DarkBlue"    { [System.Drawing.Color]::DarkBlue }
        "DarkGreen"   { [System.Drawing.Color]::DarkGreen }
        "DarkCyan"    { [System.Drawing.Color]::DarkCyan }
        "DarkRed"     { [System.Drawing.Color]::DarkRed }
        "DarkMagenta" { [System.Drawing.Color]::DarkMagenta }
        "DarkYellow"  { [System.Drawing.Color]::Olive }
        "Gray"        { [System.Drawing.Color]::Gray }
        "DarkGray"    { [System.Drawing.Color]::DarkGray }
        "Blue"        { [System.Drawing.Color]::Blue }
        "Green"       { [System.Drawing.Color]::Green }
        "Cyan"        { [System.Drawing.Color]::Cyan }
        "Red"         { [System.Drawing.Color]::Red }
        "Magenta"     { [System.Drawing.Color]::Magenta }
        "Yellow"      { [System.Drawing.Color]::Gold }
        "White"       { [System.Drawing.Color]::Black }
        default       { [System.Drawing.Color]::Black }
    }
}

$script:isInNativeErrorBlock = $false
function Test-NativeErrorLine {
    param([string]$Text)
    return $Text -match '^[A-Za-z][\w.-]*\s*:\s' -or $Text -match '^発生場所' -or $Text -match '^\s*\+'
}

function Write-ColoredLine {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$TextBox,
        [string]$Text
    )
    $color = [System.Drawing.Color]::Black
    if ($Text -match '^\[\[HIDE\]\](?<rest>.*)$') {
        $color = $TextBox.BackColor
        $Text = $Matches['rest']
        $script:isInNativeErrorBlock = $false
    } elseif ($Text -match '^\[\[COLOR:(?<color>\w+)\]\](?<rest>.*)$') {
        $color = Get-ConsoleColorAsDrawingColor -ConsoleColorName $Matches['color']
        $Text = $Matches['rest']
        $script:isInNativeErrorBlock = $false
    } elseif (Test-NativeErrorLine -Text $Text) {
        $color = [System.Drawing.Color]::Red
        $script:isInNativeErrorBlock = $true
    } elseif ($script:isInNativeErrorBlock -and $Text.Trim() -ne "") {
        $color = [System.Drawing.Color]::Red
    } else {
        $script:isInNativeErrorBlock = $false
    }
    $TextBox.SelectionStart = $TextBox.TextLength
    $TextBox.SelectionLength = 0
    $TextBox.SelectionColor = $color
    $TextBox.AppendText("$Text`r`n")
    $TextBox.SelectionStart = $TextBox.TextLength
    $TextBox.ScrollToCaret()
}

function Write-Log {
    param([string]$Text)
    Write-ColoredLine -TextBox $txtLog -Text $Text
}

function New-LogTextBox {
    param(
        [string]$FontFamily = "MS Gothic",
        [int]$FontSize = 9
    )
    $textBox = New-Object System.Windows.Forms.RichTextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $textBox.ReadOnly = $true
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.Font = New-Object System.Drawing.Font($FontFamily, $FontSize)
    $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $textBox.DetectUrls = $true
    $textBox.Add_LinkClicked({ [System.Diagnostics.Process]::Start($_.LinkText) })
    return $textBox
}

function Set-ButtonsEnabled {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Button[]]$Buttons,
        [Parameter(Mandatory)][bool]$Enabled
    )
    foreach ($btn in $Buttons) { $btn.Enabled = $Enabled }
}

function Set-StatusLabelText {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Label]$Label,
        [Parameter(Mandatory)][string]$Text,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::Gray
    )
    $Label.Text = $Text
    $Label.ForeColor = $ForeColor
}

function Get-InputValue {
    param([Parameter(Mandatory)]$Control)
    if ($Control -is [System.Windows.Forms.ComboBox]) {
        if ($Control.SelectedItem) { return "$($Control.SelectedItem.Value)" }
        return ""
    }
    return $Control.Text
}

function Add-StackedDockedControls {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Container,
        [Parameter(Mandatory)][System.Windows.Forms.Control[]]$ControlsTopToBottom,
        [int]$Spacing = 10
    )
    $Container.SuspendLayout()

    $fillControls = @($ControlsTopToBottom | Where-Object { $_.Dock -eq [System.Windows.Forms.DockStyle]::Fill })
    $topControls = @($ControlsTopToBottom | Where-Object { $_.Dock -ne [System.Windows.Forms.DockStyle]::Fill })

    if ($Spacing -gt 0 -and $topControls.Count -gt 0 -and $fillControls.Count -gt 0) {
        $spacer = New-Object System.Windows.Forms.Panel
        $spacer.Height = $Spacing
        $spacer.Dock = [System.Windows.Forms.DockStyle]::Top
        $topControls += $spacer
    }

    foreach ($fillControl in $fillControls) { $Container.Controls.Add($fillControl) }
    for ($i = $topControls.Count - 1; $i -ge 0; $i--) {
        $Container.Controls.Add($topControls[$i])
    }

    $Container.ResumeLayout($true)
}

function New-CategoryTabControl {
    param(
        [Parameter(Mandatory)][array]$CategoryDefs,
        [Parameter(Mandatory)][scriptblock]$OnRunClick,
        [scriptblock]$OnOpenClick,
        [System.Windows.Forms.TabControl]$TabControl,
        [int]$GroupHeight = 60,
        [int]$GroupSpacing = 10,
        [int]$TabHeaderAllowance = 45,
        [int]$InputRowHeight = 30,
        [string]$RunButtonText = "実行",
        [string]$OpenLinkText = "開く",
        [string]$InitialStatusText = "未実行"
    )

    if (-not $OnOpenClick) {
        $OnOpenClick = { param($path) Open-TargetOrWarn -Path $path }
    }

    function Get-InputRowCount {
        param($Inputs)
        if (-not $Inputs) { return 0 }
        $rows = 1
        foreach ($inputDef in $Inputs) {
            if ($inputDef.NewRow) { $rows++ }
        }
        return $rows
    }

    function Get-ButtonGroupHeight {
        param($ButtonDef)
        $rowCount = Get-InputRowCount -Inputs $ButtonDef.Inputs
        if ($rowCount -gt 0) { return $GroupHeight + ($InputRowHeight * $rowCount) }
        return $GroupHeight
    }

    function Get-CategoryPanelHeight {
        param($ButtonDefs)
        $total = $GroupSpacing
        foreach ($bd in $ButtonDefs) {
            $total += (Get-ButtonGroupHeight -ButtonDef $bd) + $GroupSpacing
        }
        return $total
    }

    $tabControl = $TabControl
    if (-not $tabControl) {
        $tabControl = New-Object System.Windows.Forms.TabControl
    }
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Top

    $runButtons = @()

    foreach ($cd in $CategoryDefs) {
        $tabPage = New-Object System.Windows.Forms.TabPage
        $tabPage.Text = $cd.Label
        $tabControl.Controls.Add($tabPage)

        $buttonPanel = New-Object System.Windows.Forms.Panel
        $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
        $buttonPanel.Height = Get-CategoryPanelHeight -ButtonDefs $cd.ButtonDefs
        $tabPage.Controls.Add($buttonPanel)

        $groupY = $GroupSpacing
        foreach ($bd in $cd.ButtonDefs) {
            $bdHeight = Get-ButtonGroupHeight -ButtonDef $bd
            $inputRowCount = Get-InputRowCount -Inputs $bd.Inputs
            $contentY = if ($inputRowCount -gt 0) { 20 + ($InputRowHeight * $inputRowCount) } else { 20 }

            $grp = New-Object System.Windows.Forms.GroupBox
            $grp.Text = $bd.Label
            $grp.Location = New-Object System.Drawing.Point(10, $groupY)
            $grp.Size = New-Object System.Drawing.Size(730, $bdHeight)
            $grp.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
            $buttonPanel.Controls.Add($grp)

            if ($bd.Inputs) {
                $inputMap = @{}
                $inputX = 15
                $currentInputRow = 0
                foreach ($inputDef in $bd.Inputs) {
                    if ($inputDef.NewRow) {
                        $currentInputRow++
                        $inputX = 15
                    }
                    $inputRowCenterY = 15 + ($InputRowHeight * $currentInputRow) + [int]($InputRowHeight / 2)

                    $labelWidth = if ($inputDef.LabelWidth) { $inputDef.LabelWidth } else { 80 }
                    $inputWidth = if ($inputDef.InputWidth) { $inputDef.InputWidth } else { 90 }

                    $lblInput = New-Object System.Windows.Forms.Label
                    $lblInput.Text = "$($inputDef.Label)"
                    $lblInput.AutoSize = $false
                    $lblInput.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                    $lblInput.Size = New-Object System.Drawing.Size($labelWidth, 22)
                    $lblInput.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($lblInput.Height / 2)))
                    $grp.Controls.Add($lblInput)
                    $inputX += $labelWidth + 4

                    if ($inputDef.ExistingControl) {
                        $inputCtrl = $inputDef.ExistingControl
                        $inputCtrl.Width = $inputWidth
                    } elseif ($inputDef.Options) {
                        $inputCtrl = New-Object System.Windows.Forms.ComboBox
                        $inputCtrl.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
                        $inputCtrl.Width = $inputWidth
                        $inputCtrl.DisplayMember = "Text"
                        foreach ($opt in $inputDef.Options) { $inputCtrl.Items.Add($opt) | Out-Null }
                        $selectedOption = $inputDef.Options | Where-Object { "$($_.Value)" -eq "$($inputDef.Default)" } | Select-Object -First 1
                        if ($selectedOption) {
                            $inputCtrl.SelectedItem = $selectedOption
                        } elseif ($inputCtrl.Items.Count -gt 0) {
                            $inputCtrl.SelectedIndex = 0
                        }
                    } else {
                        $inputCtrl = New-Object System.Windows.Forms.TextBox
                        $inputCtrl.Width = $inputWidth
                        $inputCtrl.Text = "$($inputDef.Default)"
                    }
                    $inputCtrl.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($inputCtrl.Height / 2)))
                    $grp.Controls.Add($inputCtrl)
                    $inputMap[$inputDef.Name] = $inputCtrl
                    $inputX += $inputWidth + 15
                }
                $bd | Add-Member -NotePropertyName InputControls -NotePropertyValue $inputMap -Force
            }

            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $RunButtonText
            $btn.Size = New-Object System.Drawing.Size(100, 30)
            $btn.Location = New-Object System.Drawing.Point(15, $contentY)
            $btn.Tag = $bd
            $btn.Add_Click({ & $OnRunClick $this.Tag }.GetNewClosure())
            $grp.Controls.Add($btn)
            $runButtons += $btn

            if ($bd.OpenTarget) {
                $lnkOpen = New-Object System.Windows.Forms.LinkLabel
                $lnkOpen.Text = $OpenLinkText
                $lnkOpen.AutoSize = $false
                $lnkOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $lnkOpen.Size = New-Object System.Drawing.Size(60, 30)
                $lnkOpen.Location = New-Object System.Drawing.Point(125, $contentY)
                $lnkOpen.Tag = $bd
                $lnkOpen.Add_LinkClicked({
                    $target = $this.Tag.OpenTarget
                    if ($target -is [scriptblock]) {
                        $groupValue = if ($this.Tag.InputControls -and $this.Tag.InputControls.ContainsKey("TargetGroupNameFilter")) {
                            Get-InputValue -Control $this.Tag.InputControls["TargetGroupNameFilter"]
                        } else { "" }
                        $target = & $target $groupValue
                    }
                    & $OnOpenClick $target
                }.GetNewClosure())
                $grp.Controls.Add($lnkOpen)
            }

            $lblStepStatus = New-Object System.Windows.Forms.Label
            $lblStepStatus.Text = $InitialStatusText
            $lblStepStatus.AutoSize = $false
            $lblStepStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $lblStepStatus.Size = New-Object System.Drawing.Size(150, 22)
            $lblStepStatus.Location = New-Object System.Drawing.Point(200, ($contentY + 4))
            $lblStepStatus.ForeColor = [System.Drawing.Color]::Gray
            $grp.Controls.Add($lblStepStatus)
            $bd | Add-Member -NotePropertyName StepStatusLabel -NotePropertyValue $lblStepStatus -Force

            $groupY += $bdHeight + $GroupSpacing
        }
    }

    $updateTabHeight = {
        if ($tabControl.SelectedTab -and $tabControl.SelectedTab.Controls.Count -gt 0) {
            $tabControl.Height = $TabHeaderAllowance + $tabControl.SelectedTab.Controls[0].Height
            if ($tabControl.Parent) { $tabControl.Parent.PerformLayout() }
        }
    }.GetNewClosure()
    $tabControl.Add_SelectedIndexChanged($updateTabHeight)
    $tabControl.Height = $TabHeaderAllowance + (Get-CategoryPanelHeight -ButtonDefs $CategoryDefs[0].ButtonDefs)

    return [PSCustomObject]@{
        TabControl = $tabControl
        RunButtons = $runButtons
    }
}

function New-LogTab {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.TabPage]$TabPage,
        [Parameter(Mandatory)][array]$ButtonDefs,
        [scriptblock]$LabelFn = { param($bd) $bd.Label },
        [Parameter(Mandatory)][string]$ExtraLabelText,
        [int]$ExtraComboWidth = 200,
        [Parameter(Mandatory)][scriptblock]$GetLogPathFn,
        [scriptblock]$OnAfterClear = {},
        [Parameter(Mandatory)][scriptblock]$OnUpdateLogView
    )

    $logContentBox = New-LogTextBox

    $logStagePanel = New-Object System.Windows.Forms.GroupBox
    $logStagePanel.Text = "ログ"
    $logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $logStagePanel.AutoSize = $true
    $logStagePanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

    $rowCenterY = 30

    $lblLogExtra = New-Object System.Windows.Forms.Label
    $lblLogExtra.Text = $ExtraLabelText
    $lblLogExtra.AutoSize = $true
    $lblLogExtraWidth = $lblLogExtra.Width
    $lblLogExtra.AutoSize = $false
    $lblLogExtra.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblLogExtra.Size = New-Object System.Drawing.Size($lblLogExtraWidth, 24)
    $lblLogExtra.Location = New-Object System.Drawing.Point(20, ($rowCenterY - [int]($lblLogExtra.Height / 2)))
    $logStagePanel.Controls.Add($lblLogExtra)

    $cmbLogExtra = New-Object System.Windows.Forms.ComboBox
    $cmbLogExtra.Size = New-Object System.Drawing.Size($ExtraComboWidth, 24)
    $cmbLogExtra.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmbLogExtra.Location = New-Object System.Drawing.Point(($lblLogExtra.Right + 10), ($rowCenterY - [int]($cmbLogExtra.Height / 2)))
    $logStagePanel.Controls.Add($cmbLogExtra)

    $btnClearLogs = New-Object System.Windows.Forms.Button
    $btnClearLogs.Text = "ログをすべて削除"
    $btnClearLogs.Size = New-Object System.Drawing.Size(140, 24)
    $btnClearLogs.Location = New-Object System.Drawing.Point(($cmbLogExtra.Right + 20), ($rowCenterY - [int]($btnClearLogs.Height / 2)))
    $btnClearLogs.Add_Click({
        $logPath = & $GetLogPathFn
        if (-not $logPath -or -not (Test-Path -LiteralPath $logPath)) { return }

        $logFiles = @(Get-ChildItem -LiteralPath $logPath -Filter "*.log" -ErrorAction SilentlyContinue)
        if ($logFiles.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("削除対象のログファイルがありません。", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show("ログファイルを削除します。よろしいですか？", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        foreach ($file in $logFiles) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force
            } catch {
                [System.Windows.Forms.MessageBox]::Show("削除に失敗したファイルがあります: $($file.Name)`r`n$($_.Exception.Message)", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
        & $OnAfterClear
        & $OnUpdateLogView
    }.GetNewClosure())
    $logStagePanel.Controls.Add($btnClearLogs)

    $radios = @()
    for ($i = 0; $i -lt $ButtonDefs.Count; $i++) {
        $bd = $ButtonDefs[$i]
        $radio = New-Object System.Windows.Forms.RadioButton
        $radio.Text = & $LabelFn $bd
        $radio.AutoSize = $true
        $radio.Tag = $bd
        $radio.Checked = ($i -eq 0)
        $radio.Location = New-Object System.Drawing.Point(20, (50 + 24 * $i))
        $logStagePanel.Controls.Add($radio)
        $radios += $radio
    }

    Add-StackedDockedControls -Container $TabPage -ControlsTopToBottom @($logStagePanel, $logContentBox)

    return [PSCustomObject]@{
        ContentBox  = $logContentBox
        StagePanel  = $logStagePanel
        Radios      = $radios
        ExtraLabel  = $lblLogExtra
        ExtraCombo  = $cmbLogExtra
        ClearButton = $btnClearLogs
    }
}

function Get-BatchDisplayLabel {
    param($ButtonDef)
    if ($ButtonDef.BatchLabel) { $ButtonDef.BatchLabel } else { $ButtonDef.Label }
}

function New-SettingsTopPanel {
    param(
        [Parameter(Mandatory)][scriptblock]$OnSave,
        [Parameter(Mandatory)][scriptblock]$OnReload,
        [System.Windows.Forms.Control[]]$ExtraControls = @(),
        [string]$Title = "",
        [int]$ExtraControlsHeight = 24,
        [int]$ExtraControlsX = 20,
        [int]$ExtraControlsSpacing = 10,
        [int]$ExtraControlsY = -1,
        [int]$ButtonRowY = -1
    )

    $rowCenterSpacing = 30
    if ($ExtraControls.Count -gt 0) {
        $extraCenterY = if ($ExtraControlsY -eq -1) { $rowCenterSpacing } else { $ExtraControlsY + [int]($ExtraControlsHeight / 2) }
        if ($ButtonRowY -eq -1) { $ButtonRowY = (2 * $rowCenterSpacing) - 12 }
    } else {
        if ($ButtonRowY -eq -1) { $ButtonRowY = $rowCenterSpacing - 12 }
    }

    $panel = New-Object System.Windows.Forms.GroupBox
    $panel.Text = $Title
    $panel.Dock = [System.Windows.Forms.DockStyle]::Top
    $panel.AutoSize = $true
    $panel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "保存"
    $btnSave.Location = New-Object System.Drawing.Point(20, $ButtonRowY)
    $btnSave.Size = New-Object System.Drawing.Size(100, 24)

    $btnReload = New-Object System.Windows.Forms.Button
    $btnReload.Text = "再読込"
    $btnReload.Location = New-Object System.Drawing.Point(130, $ButtonRowY)
    $btnReload.Size = New-Object System.Drawing.Size(100, 24)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = ""
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(244, ($ButtonRowY + 6))
    $lblStatus.Font = New-Object System.Drawing.Font($lblStatus.Font, [System.Drawing.FontStyle]::Bold)

    $panel.Controls.AddRange(@($btnSave, $btnReload, $lblStatus))

    if ($ExtraControls.Count -gt 0) {
        $extraX = $ExtraControlsX
        foreach ($ctrl in $ExtraControls) {
            if ($ctrl -is [System.Windows.Forms.Label] -or $ctrl -is [System.Windows.Forms.LinkLabel]) {
                $ctrl.AutoSize = $true
                $autoWidth = $ctrl.Width
                $ctrl.AutoSize = $false
                $ctrl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $ctrl.Size = New-Object System.Drawing.Size($autoWidth, $ExtraControlsHeight)
            }
            $ctrl.Location = New-Object System.Drawing.Point($extraX, ($extraCenterY - [int]($ctrl.Height / 2)))
            $extraX = $ctrl.Right + $ExtraControlsSpacing
        }
        $panel.Controls.AddRange($ExtraControls)
    }

    $btnSave.Add_Click({
        & $OnSave
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = "保存しました"
    }.GetNewClosure())

    $btnReload.Add_Click({
        & $OnReload
        $lblStatus.ForeColor = [System.Drawing.Color]::Black
        $lblStatus.Text = "再読込しました"
    }.GetNewClosure())

    return [PSCustomObject]@{
        Panel        = $panel
        SaveButton   = $btnSave
        ReloadButton = $btnReload
        StatusLabel  = $lblStatus
    }
}

function New-BatchRunTab {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.TabPage]$TabPage,
        [array]$ButtonDefs = @(),
        [array]$Inputs = @(),
        [string]$RunButtonText = "一括実行",
        [scriptblock]$ShowOpenLink = { param($bd) [bool]$bd.OpenTarget },
        [scriptblock]$OnOpenClick = {}
    )

    $batchPanel = New-Object System.Windows.Forms.Panel
    $batchPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $TabPage.Controls.Add($batchPanel)

    $grpBatchAll = New-Object System.Windows.Forms.GroupBox
    $grpBatchAll.Text = "一括実行"
    $grpBatchAll.Location = New-Object System.Drawing.Point(10, 10)
    $grpBatchAll.Size = New-Object System.Drawing.Size(730, 60)
    $grpBatchAll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $batchPanel.Controls.Add($grpBatchAll)

    $inputRowHeight = 35
    $topControls = @()
    $inputControls = @{}
    $inputX = 20
    $currentInputRow = 0
    foreach ($inputDef in $Inputs) {
        if ($inputDef.NewRow) {
            $currentInputRow++
            $inputX = 20
        }
        $inputRowCenterY = 26 + ($inputRowHeight * $currentInputRow)

        $labelWidth = if ($inputDef.LabelWidth) { $inputDef.LabelWidth } else { 80 }
        $inputWidth = if ($inputDef.InputWidth) { $inputDef.InputWidth } else { 120 }

        $lblInput = New-Object System.Windows.Forms.Label
        $lblInput.Text = $inputDef.Label
        $lblInput.AutoSize = $false
        $lblInput.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lblInput.Size = New-Object System.Drawing.Size($labelWidth, 22)
        $lblInput.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($lblInput.Height / 2)))
        $topControls += $lblInput
        $inputX += $labelWidth + 4

        if ($inputDef.ExistingControl) {
            $inputCtrl = $inputDef.ExistingControl
            $inputCtrl.Width = $inputWidth
        } elseif ($inputDef.Options) {
            $inputCtrl = New-Object System.Windows.Forms.ComboBox
            $inputCtrl.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $inputCtrl.DisplayMember = "Text"
            $inputCtrl.Width = $inputWidth
            foreach ($opt in $inputDef.Options) { $inputCtrl.Items.Add($opt) | Out-Null }
            $selectedOption = $inputDef.Options | Where-Object { "$($_.Value)" -eq "$($inputDef.Default)" } | Select-Object -First 1
            if ($selectedOption) {
                $inputCtrl.SelectedItem = $selectedOption
            } elseif ($inputCtrl.Items.Count -gt 0) {
                $inputCtrl.SelectedIndex = 0
            }
        } else {
            $inputCtrl = New-Object System.Windows.Forms.TextBox
            $inputCtrl.Width = $inputWidth
            $inputCtrl.Text = "$($inputDef.Default)"
        }
        $inputCtrl.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($inputCtrl.Height / 2)))
        $topControls += $inputCtrl
        $inputControls[$inputDef.Name] = $inputCtrl
        $inputX += $inputWidth + 15
    }

    $checkBoxes = @()
    $y = if ($Inputs.Count -gt 0) { 26 + ($inputRowHeight * $currentInputRow) + 20 } else { 20 }
    foreach ($bd in $ButtonDefs) {
        $chk = New-Object System.Windows.Forms.CheckBox
        $chk.Text = Get-BatchDisplayLabel -ButtonDef $bd
        $chk.Checked = if ($null -ne $bd.DefaultChecked) { $bd.DefaultChecked } else { $true }
        $chk.AutoSize = $false
        $chk.AutoEllipsis = $true
        $chk.Size = New-Object System.Drawing.Size(500, 22)
        $chk.Location = New-Object System.Drawing.Point(20, $y)
        $chk.Tag = $bd
        $checkBoxes += $chk
        $topControls += $chk

        if (& $ShowOpenLink $bd) {
            $lnkOpen = New-Object System.Windows.Forms.LinkLabel
            $lnkOpen.Text = "開く"
            $lnkOpen.AutoSize = $false
            $lnkOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $lnkOpen.Size = New-Object System.Drawing.Size(40, $chk.Height)
            $lnkOpen.Location = New-Object System.Drawing.Point(530, $y)
            $lnkOpen.Tag = $bd
            $lnkOpen.Add_LinkClicked({ & $OnOpenClick $this.Tag $inputControls }.GetNewClosure())
            $topControls += $lnkOpen
        }

        $y += 26
    }

    $btnRunAll = New-Object System.Windows.Forms.Button
    $btnRunAll.Text = $RunButtonText
    $btnRunAll.Location = New-Object System.Drawing.Point(20, ($y + 10))
    $btnRunAll.Size = New-Object System.Drawing.Size(120, 28)
    $topControls += $btnRunAll

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = ""
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(154, ($y + 16))
    $lblStatus.Font = New-Object System.Drawing.Font($lblStatus.Font, [System.Drawing.FontStyle]::Bold)
    $topControls += $lblStatus

    $grpBatchAll.Controls.AddRange($topControls)
    $grpBatchAll.Size = New-Object System.Drawing.Size(730, ($y + 10 + 28 + 16))
    $batchPanel.Height = $grpBatchAll.Bottom + 10

    return [PSCustomObject]@{
        Panel         = $batchPanel
        GroupBox      = $grpBatchAll
        InputControls = $inputControls
        CheckBoxes    = $checkBoxes
        RunButton     = $btnRunAll
        StatusLabel   = $lblStatus
    }
}

function Set-StepStatus {
    param([System.Windows.Forms.Label]$Label, [string]$Text, [string]$State)
    if (-not $State) { $State = $Text }
    $color = switch ($State) {
        "実行中..." { [System.Drawing.Color]::Black }
        "成功"      { [System.Drawing.Color]::DarkGreen }
        "警告"      { [System.Drawing.Color]::DarkOrange }
        "失敗"      { [System.Drawing.Color]::DarkRed }
        default     { [System.Drawing.Color]::Gray }
    }
    Set-StatusLabelText -Label $Label -Text $Text -ForeColor $color
}

function Invoke-BatchStep {
    param(
        $ButtonDef,
        [Parameter(Mandatory)][scriptblock]$GetBatArgs,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][scriptblock]$WriteLog,
        [ref]$CurrentProcessRef,
        [string]$DisplayLabel,
        [System.Windows.Forms.Label]$StatusLabel,
        [scriptblock]$OnOutputLine,
        [scriptblock]$IsWarningExitCode = { param($ExitCode) $false },
        [scriptblock]$OnAfterRun = {}
    )

    if (-not $DisplayLabel) { $DisplayLabel = Get-BatchDisplayLabel -ButtonDef $ButtonDef }
    if (-not $OnOutputLine) { $OnOutputLine = { param($line) & $WriteLog $line } }

    if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "実行中..." }

    & $WriteLog ""
    & $WriteLog "--------------- $DisplayLabel 開始 ---------------"

    $batArgs = & $GetBatArgs $ButtonDef
    $exitCode = Invoke-BatProcess -BatPath $ButtonDef.BatchPath -WorkingDirectory $WorkingDirectory -BatArgs $batArgs `
        -OnOutputLine $OnOutputLine `
        -CurrentProcessRef $CurrentProcessRef

    Show-FormInForeground -Form $Form

    $isWarning = ($exitCode -ne 0) -and (& $IsWarningExitCode $exitCode)

    if ($exitCode -ne 0 -and -not $isWarning) {
        & $WriteLog "--------------- $DisplayLabel 失敗（終了コード: $exitCode） ---------------"
        if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "失敗" }
    } elseif ($isWarning) {
        & $WriteLog "--------------- $DisplayLabel 完了（警告あり） ---------------"
        if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "警告" }
    } else {
        & $WriteLog "--------------- $DisplayLabel 完了 ---------------"
        if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "成功" }
    }

    & $OnAfterRun $ButtonDef $exitCode $isWarning

    return $exitCode
}

function Invoke-BatButton {
    param(
        $ButtonDef,
        [Parameter(Mandatory)][scriptblock]$GetBatArgs,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][scriptblock]$WriteLog,
        [Parameter(Mandatory)][scriptblock]$SetRunButtonsEnabled,
        [ref]$CurrentProcessRef
    )

    & $SetRunButtonsEnabled $false
    $exitCode = Invoke-BatchStep -ButtonDef $ButtonDef -GetBatArgs $GetBatArgs -WorkingDirectory $WorkingDirectory `
        -Form $Form -WriteLog $WriteLog -CurrentProcessRef $CurrentProcessRef `
        -DisplayLabel $ButtonDef.Label -StatusLabel $ButtonDef.StepStatusLabel
    & $SetRunButtonsEnabled $true
    return $exitCode
}

function Invoke-BatchRunAll {
    param(
        [Parameter(Mandatory)][array]$ButtonDefs,
        [Parameter(Mandatory)][array]$CheckBoxes,
        [Parameter(Mandatory)][System.Windows.Forms.Label]$StatusLabel,
        [Parameter(Mandatory)][scriptblock]$InvokeStep,
        [Parameter(Mandatory)][scriptblock]$WriteLog,
        [Parameter(Mandatory)][scriptblock]$SetRunButtonsEnabled,
        [array]$ExtraControls = @(),
        [switch]$StopOnFailure,
        [string]$HeaderSuffix = "",
        [scriptblock]$OnComplete
    )

    & $SetRunButtonsEnabled $false
    foreach ($chk in $CheckBoxes) { $chk.Enabled = $false }
    foreach ($ctrl in $ExtraControls) { $ctrl.Enabled = $false }
    Set-StepStatus -Label $StatusLabel -Text "実行中..."

    & $WriteLog ""
    & $WriteLog "==================== 一括実行 開始$HeaderSuffix ===================="

    $anyFailed = $false
    $failedExitCode = 0
    for ($i = 0; $i -lt $ButtonDefs.Count; $i++) {
        $bd = $ButtonDefs[$i]
        if (-not $CheckBoxes[$i].Checked) {
            & $WriteLog "$(Get-BatchDisplayLabel -ButtonDef $bd) はチェックが外れているためスキップします。"
            continue
        }
        $exitCode = & $InvokeStep $bd
        if ($exitCode -ne 0) {
            $anyFailed = $true
            $failedExitCode = $exitCode
            if ($StopOnFailure) { break }
        }
    }

    if ($OnComplete) {
        & $OnComplete $anyFailed $failedExitCode
    } else {
        & $WriteLog "==================== 一括実行 完了$HeaderSuffix ===================="
        if ($anyFailed) {
            Set-StepStatus -Label $StatusLabel -Text "失敗のステップあり" -State "失敗"
        } else {
            Set-StepStatus -Label $StatusLabel -Text "成功"
        }
    }

    foreach ($chk in $CheckBoxes) { $chk.Enabled = $true }
    foreach ($ctrl in $ExtraControls) { $ctrl.Enabled = $true }
    & $SetRunButtonsEnabled $true
}

function Update-LogView {
    $selectedRadio = $script:logTab.Radios | Where-Object { $_.Checked } | Select-Object -First 1
    if (-not $selectedRadio) { return }
    $stagePrefix = [System.IO.Path]::GetFileNameWithoutExtension($selectedRadio.Tag.BatchPath)
    $logPath = $script:commonEnvVars["LOG_DIR"]

    $script:logTab.ContentBox.Text = ""
    if (!($logPath -and (Test-Path -LiteralPath $logPath))) { return }

    $groupValue = if ($cmbLogGroup.SelectedItem) { "$($cmbLogGroup.SelectedItem.Value)" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "$stagePrefix-$groupValue*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    $sections = foreach ($file in $files) {
        try {
            [System.IO.File]::ReadAllText($file.FullName, $script:cp932Encoding)
        } catch {
            "$($file.Name) は他のプロセスで使用中のため表示できません（実行中の可能性があります）。"
        }
    }
    $script:logTab.ContentBox.Text = $sections -join "`r`n`r`n"
}

function Get-CommonSettingsFieldValue {
    param([string]$Key)
    return $script:settingsCommonFieldTextBoxes[$Key].Text
}

function Get-GroupSettingsFieldValue {
    param([string]$Key)
    return $script:settingsGroupFieldTextBoxes[$Key].Text
}

function Update-SettingsGroupList {
    $selected = $cmbSettingsGroupTarget.SelectedItem
    $script:suppressComboSync = $true
    $cmbSettingsGroupTarget.Items.Clear()
    foreach ($groupName in (Get-GroupNames)) {
        $cmbSettingsGroupTarget.Items.Add($groupName) | Out-Null
    }
    if ($selected -and $cmbSettingsGroupTarget.Items.Contains($selected)) {
        $cmbSettingsGroupTarget.SelectedItem = $selected
    } elseif ($cmbSettingsGroupTarget.Items.Count -gt 0) {
        $cmbSettingsGroupTarget.SelectedIndex = 0
    }
    $script:suppressComboSync = $false
}

function Sync-MentionRowsFromControls {
    foreach ($entry in $script:mentionRowControls) {
        $entry.Row.Code = $entry.CodeBox.Text
        $entry.Row.Type = $entry.TypeCombo.SelectedItem
    }
}

function Add-MentionsEditor {
    param(
        [System.Windows.Forms.Control]$Panel,
        [int]$StartY,
        [string]$RawValue,
        [Parameter(Mandatory)][System.Windows.Forms.ComboBox]$GroupCombo,
        [Parameter(Mandatory)][System.Windows.Forms.ToolTip]$ToolTip,
        [Parameter(Mandatory)][string[]]$MentionTypeOptions
    )
    $groupName = $GroupCombo.SelectedItem
    if ($script:mentionRowsGroupName -ne $groupName) {
        $script:mentionRows = @(ConvertFrom-MentionUserCodesText -Text $RawValue)
        $script:mentionRowsGroupName = $groupName
    }
    $script:mentionRowControls = @()

    $y = $StartY
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "メンション対象"
    $lbl.AutoSize = $false
    $lbl.Size = New-Object System.Drawing.Size(220, 20)
    $lbl.Location = New-Object System.Drawing.Point(20, $y)
    $ToolTip.SetToolTip($lbl, "MentionUserCodes")
    $Panel.Controls.Add($lbl)
    $y += 24

    foreach ($row in @($script:mentionRows)) {
        $txtCode = New-Object System.Windows.Forms.TextBox
        $txtCode.Text = "$($row.Code)"
        $txtCode.Location = New-Object System.Drawing.Point(40, $y)
        $txtCode.Size = New-Object System.Drawing.Size(190, 22)
        $Panel.Controls.Add($txtCode)

        $cmbType = New-Object System.Windows.Forms.ComboBox
        $cmbType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        foreach ($opt in $MentionTypeOptions) { $cmbType.Items.Add($opt) | Out-Null }
        $cmbType.SelectedItem = if ($MentionTypeOptions -contains $row.Type) { $row.Type } else { "USER" }
        $cmbType.Location = New-Object System.Drawing.Point(240, $y)
        $cmbType.Size = New-Object System.Drawing.Size(120, 22)
        $Panel.Controls.Add($cmbType)

        $btnDeleteRow = New-Object System.Windows.Forms.Button
        $btnDeleteRow.Text = "削除"
        $btnDeleteRow.Location = New-Object System.Drawing.Point(370, ($y - 1))
        $btnDeleteRow.Size = New-Object System.Drawing.Size(60, 24)
        $btnDeleteRow.Tag = $row
        $btnDeleteRow.Add_Click({
            Sync-MentionRowsFromControls
            $target = $this.Tag
            $script:mentionRows = @($script:mentionRows | Where-Object { $_ -ne $target })
            Update-GroupSettingsFields
        })
        $Panel.Controls.Add($btnDeleteRow)

        $script:mentionRowControls += [PSCustomObject]@{ Row = $row; CodeBox = $txtCode; TypeCombo = $cmbType }
        $y += 28
    }

    $btnAddRow = New-Object System.Windows.Forms.Button
    $btnAddRow.Text = "＋ 追加"
    $btnAddRow.Location = New-Object System.Drawing.Point(40, $y)
    $btnAddRow.Size = New-Object System.Drawing.Size(80, 24)
    $btnAddRow.Add_Click({
        Sync-MentionRowsFromControls
        $script:mentionRows += [PSCustomObject]@{ Code = ""; Type = "USER" }
        Update-GroupSettingsFields
    })
    $Panel.Controls.Add($btnAddRow)
    $y += 34

    return $y
}

function Add-FieldActionButton {
    param(
        [System.Windows.Forms.Control]$Panel,
        [int]$Y,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][scriptblock]$OnClick,
        [int]$Width = 90
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point(20, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, 24)
    $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $btn.Add_Click({ & $OnClick }.GetNewClosure())
    $Panel.Controls.Add($btn)
}

function Render-SettingsFields {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [array]$Rows,
        [hashtable]$TextBoxes,
        [Parameter(Mandatory)][hashtable]$GroupLabels,
        [Parameter(Mandatory)][hashtable]$VarLabels,
        [Parameter(Mandatory)][System.Windows.Forms.ToolTip]$ToolTip,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][scriptblock]$EnvResolver,
        [string[]]$MultilineVars = @(),
        [string[]]$MaskedVars = @(),
        [string[]]$FolderBrowseVars = @(),
        [string[]]$FileBrowseVars = @(),
        [hashtable]$RadioVars = @{},
        [hashtable]$TrailingButtonVars = @{},
        [System.Windows.Forms.ComboBox]$MentionGroupCombo,
        [string[]]$MentionTypeOptions = @()
    )
    $Panel.Controls.Clear()
    $TextBoxes.Clear()

    $groupBoxes = [System.Collections.Generic.List[System.Windows.Forms.GroupBox]]::new()
    $grp = $null
    $lastGroup = $null
    $y = 25

    foreach ($field in $Rows) {
        if ($field.Group -ne $lastGroup) {
            $grp = New-Object System.Windows.Forms.GroupBox
            $grp.Text = $GroupLabels[$field.Group]
            $grp.Dock = [System.Windows.Forms.DockStyle]::Top
            $grp.AutoSize = $true
            $grp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
            $groupBoxes.Add($grp)
            $y = 25
            $lastGroup = $field.Group
        }

        if ($field.VarName -eq "MentionUserCodes") {
            $y = Add-MentionsEditor -Panel $grp -StartY $y -RawValue "$($field.Value)" -GroupCombo $MentionGroupCombo -ToolTip $ToolTip -MentionTypeOptions $MentionTypeOptions
            continue
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = if ($VarLabels.Contains($field.VarName)) { $VarLabels[$field.VarName] } else { $field.VarName }
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(220, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $ToolTip.SetToolTip($lbl, $field.VarName)
        $grp.Controls.Add($lbl)

        $isMultiline = $MultilineVars -contains $field.VarName

        if ($RadioVars.ContainsKey($field.VarName)) {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = "$($field.Value)"
            $txt.Visible = $false
            $grp.Controls.Add($txt)

            $radioPanel = New-Object System.Windows.Forms.Panel
            $radioPanel.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $radioPanel.Size = New-Object System.Drawing.Size(300, 22)
            $radioPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $radioX = 0
            foreach ($opt in $RadioVars[$field.VarName]) {
                $rb = New-Object System.Windows.Forms.RadioButton
                $rb.Text = $opt.Label
                $rb.AutoSize = $true
                $rb.Location = New-Object System.Drawing.Point($radioX, 2)
                $rb.Tag = [PSCustomObject]@{ TextBox = $txt; Value = $opt.Value }
                $rb.Checked = ($field.Value -eq $opt.Value)
                $rb.Add_CheckedChanged({ if ($this.Checked) { $this.Tag.TextBox.Text = $this.Tag.Value } })
                $radioPanel.Controls.Add($rb)
                $radioX += 80
            }

            if ($field.Group -eq "OVERRIDE") {
                $rbUnset = New-Object System.Windows.Forms.RadioButton
                $rbUnset.Text = "未設定"
                $rbUnset.AutoSize = $true
                $rbUnset.Location = New-Object System.Drawing.Point($radioX, 2)
                $rbUnset.Tag = $txt
                $rbUnset.Checked = [string]::IsNullOrEmpty($field.Value)
                $rbUnset.Add_CheckedChanged({ if ($this.Checked) { $this.Tag.Text = "" } })
                $ToolTip.SetToolTip($rbUnset, "空欄にすると共通設定の値を使用します")
                $radioPanel.Controls.Add($rbUnset)
            }

            $grp.Controls.Add($radioPanel)
        } else {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = if ($isMultiline) { "$($field.Value)" -replace '\\n', "`r`n" } else { "$($field.Value)" }
            $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
            if ($isMultiline) {
                $txt.Multiline = $true
                $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
                $txt.Size = New-Object System.Drawing.Size(300, 60)
            } else {
                $txt.Size = New-Object System.Drawing.Size(300, 22)
            }
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            if ($MaskedVars -contains $field.VarName) { $txt.UseSystemPasswordChar = $true }
            $grp.Controls.Add($txt)
        }

        $isFileBrowse = $FileBrowseVars -contains $field.VarName
        if (($FolderBrowseVars -contains $field.VarName) -or $isFileBrowse) {
            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(560, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt

            if ($isFileBrowse) {
                $btnBrowse.Add_Click({
                    $targetTxt = $this.Tag
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    $dlg.Filter = "Excel ファイル (*.xlsx)|*.xlsx|すべてのファイル (*.*)|*.*"
                    $startPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $RootPath -Resolver $EnvResolver -BasePath $RootPath
                    if ($startPath -and (Test-Path -LiteralPath $startPath)) {
                        $dlg.InitialDirectory = Split-Path $startPath -Parent
                        $dlg.FileName = Split-Path $startPath -Leaf
                    }
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetTxt.Text = $dlg.FileName }
                }.GetNewClosure())

                $btnOpen = New-Object System.Windows.Forms.LinkLabel
                $btnOpen.Text = "開く"
                $btnOpen.AutoSize = $false
                $btnOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $btnOpen.Size = New-Object System.Drawing.Size(50, 22)
                $btnOpen.Location = New-Object System.Drawing.Point(640, ($y - 2))
                $btnOpen.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
                $btnOpen.Tag = $txt
                $btnOpen.Add_LinkClicked({
                    $targetTxt = $this.Tag
                    $openPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $RootPath -Resolver $EnvResolver -BasePath $RootPath
                    if (Test-Path -LiteralPath $openPath) {
                        Start-Process -FilePath $openPath
                    } else {
                        [System.Windows.Forms.MessageBox]::Show("ファイルが見つかりません: $openPath", "エラー") | Out-Null
                    }
                }.GetNewClosure())
                $grp.Controls.AddRange(@($btnBrowse, $btnOpen))
            } else {
                $btnBrowse.Add_Click({
                    $targetTxt = $this.Tag
                    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                    $startPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $RootPath -Resolver $EnvResolver -BasePath $RootPath
                    if ($startPath -and (Test-Path -LiteralPath $startPath)) { $dlg.SelectedPath = $startPath }
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetTxt.Text = $dlg.SelectedPath }
                }.GetNewClosure())
                $grp.Controls.Add($btnBrowse)
            }
        }

        $TextBoxes[$field.Key] = $txt
        $y += if ($isMultiline) { 66 } else { 28 }

        if ($TrailingButtonVars.ContainsKey($field.VarName)) {
            & $TrailingButtonVars[$field.VarName] $grp $y $field
            $y += 34
        }
    }

    $controlsToStack = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    for ($i = 0; $i -lt $groupBoxes.Count; $i++) {
        if ($i -gt 0) {
            $spacer = New-Object System.Windows.Forms.Panel
            $spacer.Dock = [System.Windows.Forms.DockStyle]::Top
            $spacer.Height = 10
            $controlsToStack.Add($spacer)
        }
        $controlsToStack.Add($groupBoxes[$i])
    }
    Add-StackedDockedControls -Container $Panel -ControlsTopToBottom @($controlsToStack) -Spacing 0

    $totalHeight = 10
    foreach ($ctrl in $controlsToStack) { $totalHeight += $ctrl.Height }
    return $totalHeight
}

function Invoke-TestAction {
    param(
        [string]$ValidationError,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][scriptblock]$FormatSuccessMessage,
        [scriptblock]$FormatFailureMessage = { param($ErrorRecord) "失敗しました。`r`n$($ErrorRecord.Exception.Message)" },
        [string]$DialogTitle = "テスト"
    )

    if ($ValidationError) {
        [System.Windows.Forms.MessageBox]::Show($ValidationError, $DialogTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    try {
        $response = & $Action
        [System.Windows.Forms.MessageBox]::Show((& $FormatSuccessMessage $response), $DialogTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show((& $FormatFailureMessage $_), $DialogTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}
