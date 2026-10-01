$script:settingsCommonFieldTextBoxes = @{}
$script:settingsGroupFieldTextBoxes = @{}
$script:batchPanel = $null
$script:batchStatusLabel = $null
$script:getLogPathFn = $null
$script:runButtons = @()
$script:batchInputControls = @{}
$script:logTab = $null

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

function New-OpenLinkHandler {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Control,
        [Parameter(Mandatory)][string]$Pattern,
        [object]$Tag = $null,
        [scriptblock]$OnOpenClick = $null,
        [hashtable]$InputControls = $null
    )

    if ($Tag) { $Control.Tag = $Tag }

    $Control.Add_LinkClicked({
        switch ($Pattern) {
            'external' {
                $target = $this.Tag.OpenTarget
                if ($target -is [scriptblock]) {
                    $target = & $target $InputControls
                }
                & $OnOpenClick $target
            }
            'internal' {
                $openPath = $this.Tag.Text
                if ($OnOpenClick) { $openPath = & $OnOpenClick $openPath }
                Open-TargetOrWarn -Path $openPath
            }
        }
    }.GetNewClosure())
}

function New-OpenLink {
    param(
        [string]$Text = "開く",
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [string]$Pattern = 'external',
        [object]$Tag = $null,
        [scriptblock]$OnOpenClick = $null,
        [hashtable]$InputControls = $null
    )

    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text = $Text
    $lnk.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    if ($Width -gt 0 -and $Height -gt 0) { $lnk.Size = New-Object System.Drawing.Size($Width, $Height) }
    $lnk.Location = New-Object System.Drawing.Point($X, $Y)
    $lnk.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

    New-OpenLinkHandler -Control $lnk -Pattern $Pattern -Tag $Tag -OnOpenClick $OnOpenClick -InputControls $InputControls

    return $lnk
}

function New-Label {
    param(
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [string]$Text = "",
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::Black,
        [bool]$AutoSize = $false
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.AutoSize = $AutoSize
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.ForeColor = $ForeColor
    if ($Width -gt 0 -and $Height -gt 0) { $lbl.Size = New-Object System.Drawing.Size($Width, $Height) }

    return $lbl
}

function Measure-LabelWidth {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Label]$Label,
        [string]$Text = "",
        [int]$FixedHeight = 24,
        [int]$X = 0,
        [int]$CenterY = 0
    )

    $Label.Text = $Text
    $Label.AutoSize = $true
    $labelWidth = $Label.Width
    $Label.AutoSize = $false
    $Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $Label.Size = New-Object System.Drawing.Size($labelWidth, $FixedHeight)
    $Y = $CenterY - [int]($Label.Height / 2)
    $Label.Location = New-Object System.Drawing.Point($X, $Y)

    return $Label
}

function New-Button {
    param(
        [string]$Text = "",
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    if ($Width -gt 0 -and $Height -gt 0) { $btn.Size = New-Object System.Drawing.Size($Width, $Height) }
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

    return $btn
}

function New-GroupBox {
    param(
        [string]$Text = "",
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [System.Windows.Forms.DockStyle]$Dock = [System.Windows.Forms.DockStyle]::None,
        [bool]$AutoSize = $false,
        [System.Windows.Forms.AutoSizeMode]$AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowOnly
    )

    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = $Text
    if ($Dock -ne [System.Windows.Forms.DockStyle]::None) {
        $grp.Dock = $Dock
    } else {
        $grp.Location = New-Object System.Drawing.Point($X, $Y)
        $grp.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    }
    if ($Width -gt 0 -and $Height -gt 0) { $grp.Size = New-Object System.Drawing.Size($Width, $Height) }
    if ($AutoSize) {
        $grp.AutoSize = $true
        $grp.AutoSizeMode = $AutoSizeMode
    }

    return $grp
}

function New-CheckBox {
    param(
        [string]$Text = "",
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [bool]$Checked = $true,
        [bool]$AutoEllipsis = $false
    )

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $Text
    $chk.AutoSize = $false
    $chk.AutoEllipsis = $AutoEllipsis
    if ($Width -gt 0 -and $Height -gt 0) { $chk.Size = New-Object System.Drawing.Size($Width, $Height) }
    $chk.Location = New-Object System.Drawing.Point($X, $Y)
    $chk.Checked = $Checked

    return $chk
}

function New-Panel {
    param(
        [int]$Height = 0,
        [System.Windows.Forms.DockStyle]$Dock = [System.Windows.Forms.DockStyle]::Top
    )

    $pnl = New-Object System.Windows.Forms.Panel
    if ($Height -gt 0) { $pnl.Height = $Height }
    $pnl.Dock = $Dock

    return $pnl
}

function New-ComboBox {
    param(
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [object[]]$Items = @(),
        [object]$SelectedItem = $null,
        [string]$DisplayMember = "Text"
    )

    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmb.DisplayMember = $DisplayMember
    if ($Width -gt 0 -and $Height -gt 0) { $cmb.Size = New-Object System.Drawing.Size($Width, $Height) } else {
        if ($Width -gt 0) { $cmb.Width = $Width }
    }
    $cmb.Location = New-Object System.Drawing.Point($X, $Y)
    foreach ($item in $Items) { $cmb.Items.Add($item) | Out-Null }
    if ($SelectedItem -ne $null) { $cmb.SelectedItem = $SelectedItem }

    return $cmb
}

function New-TextBox {
    param(
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 0, [int]$Height = 0,
        [string]$Text = "",
        [bool]$Multiline = $false,
        [bool]$Visible = $true
    )

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $Text
    if ($Width -gt 0 -and $Height -gt 0) { $txt.Size = New-Object System.Drawing.Size($Width, $Height) } else {
        if ($Width -gt 0) { $txt.Width = $Width }
    }
    $txt.Location = New-Object System.Drawing.Point($X, $Y)
    $txt.Multiline = $Multiline
    $txt.Visible = $Visible

    return $txt
}

function New-RadioButton {
    param(
        [int]$X = 0, [int]$Y = 0,
        [string]$Text = "",
        [object]$Tag = $null,
        [bool]$Checked = $false
    )

    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $Text
    $rb.AutoSize = $true
    $rb.Location = New-Object System.Drawing.Point($X, $Y)
    $rb.Checked = $Checked
    if ($Tag -ne $null) { $rb.Tag = $Tag }

    return $rb
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
    $textBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Both
    $textBox.WordWrap = $false
    $textBox.ReadOnly = $true
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.Font = New-Object System.Drawing.Font($FontFamily, $FontSize)
    $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $textBox.DetectUrls = $true
    $textBox.Add_MouseClick(({
        $urlPattern = [regex]'https?://\S+'
        $charIndex = $this.GetCharIndexFromPosition($_.Location)
        if ($charIndex -ge 0 -and $charIndex -lt $this.Text.Length) {
            $urlMatches = $urlPattern.Matches($this.Text)
            foreach ($match in $urlMatches) {
                if ($charIndex -ge $match.Index -and $charIndex -lt $match.Index + $match.Length) {
                    [System.Diagnostics.Process]::Start($match.Value)
                    break
                }
            }
        }
    }).GetNewClosure())
    return $textBox
}

function Set-ButtonsEnabled {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Button[]]$Buttons,
        [Parameter(Mandatory)][bool]$Enabled
    )
    foreach ($btn in $Buttons) { $btn.Enabled = $Enabled }
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons $script:batchRunButtons -Enabled $Enabled
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
        $spacer = New-Panel -Height $Spacing
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

        $buttonPanel = New-Panel -Height (Get-CategoryPanelHeight -ButtonDefs $cd.ButtonDefs)
        $tabPage.Controls.Add($buttonPanel)

        $groupY = $GroupSpacing
        foreach ($bd in $cd.ButtonDefs) {
            $bdHeight = Get-ButtonGroupHeight -ButtonDef $bd
            $inputRowCount = Get-InputRowCount -Inputs $bd.Inputs
            $contentY = if ($inputRowCount -gt 0) { 20 + ($InputRowHeight * $inputRowCount) } else { 20 }

            $grp = New-GroupBox -Text $bd.Label -X 10 -Y $groupY -Width 730 -Height $bdHeight
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

                    $lblInput = New-Label -X $inputX -Y ($inputRowCenterY - 11) -Width $labelWidth -Height 22 -Text "$($inputDef.Label)"
                    $grp.Controls.Add($lblInput)
                    $inputX += $labelWidth + 4

                    if ($inputDef.ExistingControl) {
                        $inputCtrl = $inputDef.ExistingControl
                        $inputCtrl.Width = $inputWidth
                    } elseif ($inputDef.Options) {
                        $selectedOption = $inputDef.Options | Where-Object { "$($_.Value)" -eq "$($inputDef.Default)" } | Select-Object -First 1
                        $inputCtrl = New-ComboBox -Width $inputWidth -Items $inputDef.Options -SelectedItem $selectedOption -DisplayMember "Text"
                        if ($selectedOption) {
                        } elseif ($inputCtrl.Items.Count -gt 0) {
                            $inputCtrl.SelectedIndex = 0
                        }
                    } else {
                        $inputCtrl = New-TextBox -Width $inputWidth -Text "$($inputDef.Default)"
                    }
                    $inputCtrl.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($inputCtrl.Height / 2)))
                    $grp.Controls.Add($inputCtrl)
                    $inputMap[$inputDef.Name] = $inputCtrl
                    $inputX += $inputWidth + 15
                }
                $bd | Add-Member -NotePropertyName InputControls -NotePropertyValue $inputMap -Force
            }

            $btn = New-Button -Text $RunButtonText -X 15 -Y $contentY -Width 100 -Height 30
            $btn.Tag = $bd
            $btn.Add_Click({ & $OnRunClick $this.Tag }.GetNewClosure())
            $grp.Controls.Add($btn)
            $runButtons += $btn

            if ($bd.OpenTarget) {
                $lnkOpen = New-OpenLink -Text $OpenLinkText -X 125 -Y $contentY -Width 60 -Height 30 -Pattern 'external' -Tag $bd -OnOpenClick $OnOpenClick -InputControls $bd.InputControls
                $grp.Controls.Add($lnkOpen)
            }

            $lblStepStatus = New-Label -X 200 -Y ($contentY + 4) -Width 150 -Height 22 -Text $InitialStatusText -ForeColor ([System.Drawing.Color]::Gray)
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

    $script:runButtons = $runButtons

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

    $logStagePanel = New-GroupBox -Text "ログ" -Dock Top -AutoSize $true -AutoSizeMode GrowAndShrink

    $rowCenterY = 30

    $lblLogExtra = New-Label
    Measure-LabelWidth -Label $lblLogExtra -Text $ExtraLabelText -FixedHeight 24 -X 20 -CenterY $rowCenterY | Out-Null
    $logStagePanel.Controls.Add($lblLogExtra)

    $cmbLogExtra = New-ComboBox -Width $ExtraComboWidth -Height 24
    $cmbLogExtra.Location = New-Object System.Drawing.Point(($lblLogExtra.Right + 10), ($rowCenterY - [int]($cmbLogExtra.Height / 2)))
    $logStagePanel.Controls.Add($cmbLogExtra)

    $btnClearLogs = New-Button -Text "ログをすべて削除" -X ($cmbLogExtra.Right + 20) -Y ($rowCenterY - [int](24 / 2)) -Width 140 -Height 24
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
        $radio = New-RadioButton -X 20 -Y (50 + 24 * $i) -Text (& $LabelFn $bd) -Tag $bd -Checked ($i -eq 0)
        $logStagePanel.Controls.Add($radio)
        $radios += $radio
    }

    Add-StackedDockedControls -Container $TabPage -ControlsTopToBottom @($logStagePanel, $logContentBox)

    $script:getLogPathFn = $GetLogPathFn
    $script:logTab = [PSCustomObject]@{
        ContentBox  = $logContentBox
        StagePanel  = $logStagePanel
        Radios      = $radios
        ExtraLabel  = $lblLogExtra
        ExtraCombo  = $cmbLogExtra
        ClearButton = $btnClearLogs
    }
    return $script:logTab
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

    $btnSave = New-Button -Text "保存" -X 20 -Y $ButtonRowY -Width 100 -Height 24

    $btnReload = New-Button -Text "再読込" -X 130 -Y $ButtonRowY -Width 100 -Height 24

    $lblStatus = New-Label -X 244 -Y ($ButtonRowY + 6) -AutoSize $true

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
        [scriptblock]$OnOpenClick = {},
        [string]$InitialStatusText = "未実行"
    )

    $batchPanel = New-Panel
    $TabPage.Controls.Add($batchPanel)

    $grpBatchAll = New-GroupBox -Text "一括実行" -X 10 -Y 10 -Width 730 -Height 60
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

        $lblInput = New-Label -X $inputX -Y ($inputRowCenterY - 11) -Width $labelWidth -Height 22 -Text $inputDef.Label
        $topControls += $lblInput
        $inputX += $labelWidth + 4

        if ($inputDef.ExistingControl) {
            $inputCtrl = $inputDef.ExistingControl
            $inputCtrl.Width = $inputWidth
        } elseif ($inputDef.Options) {
            $selectedOption = $inputDef.Options | Where-Object { "$($_.Value)" -eq "$($inputDef.Default)" } | Select-Object -First 1
            $inputCtrl = New-ComboBox -Width $inputWidth -Items $inputDef.Options -SelectedItem $selectedOption -DisplayMember "Text"
            if (!$selectedOption -and $inputCtrl.Items.Count -gt 0) {
                $inputCtrl.SelectedIndex = 0
            }
        } else {
            $inputCtrl = New-TextBox -Width $inputWidth -Text "$($inputDef.Default)"
        }
        $inputCtrl.Location = New-Object System.Drawing.Point($inputX, ($inputRowCenterY - [int]($inputCtrl.Height / 2)))
        $topControls += $inputCtrl
        $inputControls[$inputDef.Name] = $inputCtrl
        $inputX += $inputWidth + 15
    }

    $checkBoxes = @()
    $statusLabels = @()
    $y = if ($Inputs.Count -gt 0) { 26 + ($inputRowHeight * $currentInputRow) + 20 } else { 20 }
    foreach ($bd in $ButtonDefs) {
        $isChecked = if ($null -ne $bd.DefaultChecked) { $bd.DefaultChecked } else { $true }
        $chk = New-CheckBox -Text (Get-BatchDisplayLabel -ButtonDef $bd) -X 20 -Y $y -Width 360 -Height 22 -Checked $isChecked -AutoEllipsis $true
        $chk.Tag = $bd
        $checkBoxes += $chk
        $topControls += $chk

        if (& $ShowOpenLink $bd) {
            $lnkOpen = New-OpenLink -X 390 -Y $y -Width 40 -Height $chk.Height -Pattern 'external' -Tag $bd -OnOpenClick $OnOpenClick -InputControls $inputControls
            $topControls += $lnkOpen
        }

        $lblStepStatus = New-Label -X 440 -Y $y -Width 150 -Height 22 -Text $InitialStatusText -ForeColor ([System.Drawing.Color]::Gray)
        $statusLabels += $lblStepStatus
        $topControls += $lblStepStatus

        $y += 26
    }

    $btnRunAll = New-Button -Text $RunButtonText -X 20 -Y ($y + 10) -Width 120 -Height 28
    $topControls += $btnRunAll

    $lblStatus = New-Label -X 154 -Y ($y + 16) -AutoSize $true
    $topControls += $lblStatus

    $grpBatchAll.Controls.AddRange($topControls)
    $grpBatchAll.Size = New-Object System.Drawing.Size(730, ($y + 10 + 28 + 16))
    $batchPanel.Height = $grpBatchAll.Bottom + 10

    $script:batchPanel = $batchPanel
    $script:batchInputControls = $inputControls
    $script:batchStepCheckboxes = $checkBoxes
    $script:batchStatusLabels = $statusLabels
    $script:batchStatusLabel = $lblStatus
    $script:batchRunButton = $btnRunAll
    $script:batchRunButtons = @($btnRunAll)

    return [PSCustomObject]@{
        Panel          = $batchPanel
        GroupBox       = $grpBatchAll
        InputControls  = $inputControls
        CheckBoxes     = $checkBoxes
        StatusLabels   = $statusLabels
        RunButton      = $btnRunAll
        StatusLabel    = $lblStatus
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

function Invoke-ActionWithUpdateStatus {
    param(
        [System.Windows.Forms.Label]$StatusLabel,
        [scriptblock]$Action,
        [string]$SuccessMessage = "成功",
        [string]$WarnMessage = "警告",
        [string]$FailureMessage = "失敗" 
    )
    Set-StepStatus -Label $StatusLabel -Text "実行中..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $result = & $Action
        if($result -eq 0 -or $null -eq $result){
            Set-StepStatus -Label $StatusLabel -Text $SuccessMessage
        } elseif ($result -eq 2) {
            Set-StepStatus -Label $StatusLabel -Text $WarnMessage
        } else {
            Set-StepStatus -Label $StatusLabel -Text $FailureMessage
        }
        return $result
    } catch {
        Set-StepStatus -Label $StatusLabel -Text $FailureMessage
        throw $_.Exception.Message
    }
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
        [scriptblock]$OnAfterRun = {}
    )

    if (-not $DisplayLabel) { $DisplayLabel = Get-BatchDisplayLabel -ButtonDef $ButtonDef }
    if (-not $OnOutputLine) { $OnOutputLine = { param($line) & $WriteLog $line } }

    if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "実行中..." }

    & $WriteLog "--------------- $DisplayLabel 開始 ---------------"

    $batArgs = & $GetBatArgs $ButtonDef
    $exitCode = Invoke-BatProcess -BatPath $ButtonDef.BatchPath -WorkingDirectory $WorkingDirectory -BatArgs $batArgs `
        -OnOutputLine $OnOutputLine `
        -CurrentProcessRef $CurrentProcessRef

    Show-FormInForeground -Form $Form

    $isWarning = $exitCode -eq 2

    if ($exitCode -ne 0 -and -not $isWarning) {
        & $WriteLog "--------------- $DisplayLabel 失敗（終了コード: $exitCode） ---------------"
        if ($StatusLabel) { Set-StepStatus -Label $StatusLabel -Text "失敗" }
    } elseif ($isWarning) {
        & $WriteLog "--------------- $DisplayLabel 警告 ---------------"
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
        [array]$StatusLabels = @(),
        [switch]$StopOnFailure,
        [string]$HeaderSuffix = "",
        [scriptblock]$OnComplete
    )

    & $SetRunButtonsEnabled $false
    foreach ($chk in $CheckBoxes) { $chk.Enabled = $false }
    foreach ($ctrl in $ExtraControls) { $ctrl.Enabled = $false }
    for ($i = 0; $i -lt $CheckBoxes.Count; $i++) {
        if ($CheckBoxes[$i].Checked -and $i -lt $StatusLabels.Count) {
            $StatusLabels[$i].Text = ""
            $StatusLabels[$i].ForeColor = [System.Drawing.Color]::Gray
        }
    }
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
        if ($i -lt $StatusLabels.Count) {
            Set-StepStatus -Label $StatusLabels[$i] -Text "実行中..."
        }
        $exitCode = & $InvokeStep $bd
        if ($i -lt $StatusLabels.Count) {
            if ($exitCode -eq 0) {
                Set-StepStatus -Label $StatusLabels[$i] -Text "成功" -State "成功"
            } elseif ($exitCode -eq 2) {
                Set-StepStatus -Label $StatusLabels[$i] -Text "警告" -State "警告"
            } else {
                Set-StepStatus -Label $StatusLabels[$i] -Text "失敗" -State "失敗"
            }
        }
        if ($exitCode -eq 2) {
            $hasWarnings = $true
        } elseif ($exitCode -ne 0) {
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
            Set-StepStatus -Label $StatusLabel -Text "失敗" -State "失敗"
        } elseif ($hasWarnings) {
            Set-StepStatus -Label $StatusLabel -Text "警告" -State "警告"
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
    $logPath = & $script:getLogPathFn

    $script:logTab.ContentBox.Text = ""
    if (!($logPath -and (Test-Path -LiteralPath $logPath))) { return }

    $groupValue = if ($cmbLogGroup.SelectedItem) { "$($cmbLogGroup.SelectedItem.Value)" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "$stagePrefix`_$groupValue`_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
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
    if ($script:settingsCommonFieldTextBoxes.ContainsKey($Key)) {
        return $script:settingsCommonFieldTextBoxes[$Key].Text
    }
    return ""
}

function Get-GroupSettingsFieldValue {
    param([string]$Key)
    if ($script:settingsGroupFieldTextBoxes.ContainsKey($Key)) {
        return $script:settingsGroupFieldTextBoxes[$Key].Text
    }
    return ""
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
    $lbl = New-Label -X 20 -Y $y -Width 220 -Height 20 -Text "メンション対象"
    $ToolTip.SetToolTip($lbl, "MentionUserCodes")
    $Panel.Controls.Add($lbl)
    $y += 24

    foreach ($row in @($script:mentionRows)) {
        $txtCode = New-TextBox -X 40 -Y $y -Width 190 -Height 22 -Text "$($row.Code)"
        $Panel.Controls.Add($txtCode)

        $selectedType = if ($MentionTypeOptions -contains $row.Type) { $row.Type } else { "USER" }
        $cmbType = New-ComboBox -X 240 -Y $y -Width 120 -Height 22 -Items $MentionTypeOptions -SelectedItem $selectedType
        $Panel.Controls.Add($cmbType)

        $btnDeleteRow = New-Button -Text "削除" -X 370 -Y ($y - 1) -Width 60 -Height 24
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

    $btnAddRow = New-Button -Text "＋ 追加" -X 40 -Y $y -Width 80 -Height 24
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
        [int]$Width = 90,
        [switch]$AddStatusLabel,
        [string]$InitialStatusText = "未実行"
    )
    $btn = New-Button -Text $Text -X 20 -Y $Y -Width $Width -Height 24
    $btn.Add_Click({ & $OnClick }.GetNewClosure()) | Out-Null
    $Panel.Controls.Add($btn) | Out-Null

    if ($AddStatusLabel) {
        $lbl = New-Label -Text $InitialStatusText -ForeColor ([System.Drawing.Color]::Gray) -AutoSize $true
        $lbl.Location = New-Object System.Drawing.Point(($btn.Right + 10), ($btn.Top + 6))
        $Panel.Controls.Add($lbl) | Out-Null
        return $lbl
    }
}

function Render-SettingsFields {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [array]$Rows,
        [hashtable]$TargetTextBoxes,
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
        [string[]]$MentionTypeOptions = @(),
        [scriptblock]$OnOpenClick
    )
    $Panel.Controls.Clear()
    $TargetTextBoxes.Clear()

    $groupBoxes = [System.Collections.Generic.List[System.Windows.Forms.GroupBox]]::new()
    $grp = $null
    $lastGroup = $null
    $y = 25

    foreach ($field in $Rows) {
        if ($field.Group -ne $lastGroup) {
            $grp = New-Object System.Windows.Forms.GroupBox
            $grp.Text = $GroupLabels[$field.Group]
            $grp.Padding = New-Object System.Windows.Forms.Padding(10, 35, 10, 10)
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

        $labelText = if ($VarLabels.Contains($field.VarName)) { $VarLabels[$field.VarName] } else { $field.VarName }
        $lbl = New-Label -X 20 -Y $y -Width 220 -Height 20 -Text $labelText
        $ToolTip.SetToolTip($lbl, $field.VarName)
        $grp.Controls.Add($lbl)

        $isMultiline = $MultilineVars -contains $field.VarName

        if ($RadioVars.ContainsKey($field.VarName)) {
            $txt = New-TextBox -Text "$($field.Value)" -Visible $false
            $grp.Controls.Add($txt)

            $radioPanel = New-Object System.Windows.Forms.Panel
            $radioPanel.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $radioPanel.Size = New-Object System.Drawing.Size(300, 22)
            $radioPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $radioX = 0
            foreach ($opt in $RadioVars[$field.VarName]) {
                $rbTag = [PSCustomObject]@{ TextBox = $txt; Value = $opt.Value }
                $rb = New-RadioButton -X $radioX -Y 2 -Text $opt.Label -Tag $rbTag -Checked ($field.Value -eq $opt.Value)
                $rb.Add_CheckedChanged({ if ($this.Checked) { $this.Tag.TextBox.Text = $this.Tag.Value } })
                $radioPanel.Controls.Add($rb)
                $radioX += 80
            }

            if ($field.Group -eq "OVERRIDE") {
                $rbUnset = New-RadioButton -X $radioX -Y 2 -Text "未設定" -Tag $txt -Checked ([string]::IsNullOrEmpty($field.Value))
                $rbUnset.Add_CheckedChanged({ if ($this.Checked) { $this.Tag.Text = "" } })
                $ToolTip.SetToolTip($rbUnset, "空欄にすると共通設定の値を使用します")
                $radioPanel.Controls.Add($rbUnset)
            }

            $grp.Controls.Add($radioPanel)
        } else {
            $txtValue = if ($isMultiline) { "$($field.Value)" -replace '\\n', "`r`n" } else { "$($field.Value)" }
            $txtSize = if ($isMultiline) { @(300, 60) } else { @(300, 22) }
            $txt = New-TextBox -X 250 -Y ($y - 2) -Width $txtSize[0] -Height $txtSize[1] -Text $txtValue -Multiline $isMultiline
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            if ($isMultiline) { $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical }
            if ($MaskedVars -contains $field.VarName) { $txt.UseSystemPasswordChar = $true }
            $grp.Controls.Add($txt)
        }

        $isFileBrowse = $FileBrowseVars -contains $field.VarName
        if (($FolderBrowseVars -contains $field.VarName) -or $isFileBrowse) {
            $btnBrowse = New-Button -Text "参照..." -X 560 -Y ($y - 3) -Width 70 -Height 24
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

                $lnkOpen = New-OpenLink -Text "開く" -X 640 -Y ($y - 2) -Width 40 -Height 22 -Pattern 'internal' -Tag $txt -OnOpenClick $OnOpenClick
                $grp.Controls.AddRange(@($btnBrowse, $lnkOpen))
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

        $TargetTextBoxes[$field.Key] = $txt
        $y += if ($isMultiline) { 66 } else { 28 }

        if ($TrailingButtonVars.ContainsKey($field.VarName)) {
            $result = & $TrailingButtonVars[$field.VarName] $grp $y $field
            if ($result) {
                $field | Add-Member -NotePropertyName StatusLabel -NotePropertyValue $result -Force
            }
            $y += 34
        }
    }

    $controlsToStack = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    for ($i = 0; $i -lt $groupBoxes.Count; $i++) {
        if ($i -gt 0) {
            $spacer = New-Panel -Height 10
            $controlsToStack.Add($spacer)
        }
        $controlsToStack.Add($groupBoxes[$i])
    }
    if ($controlsToStack.Count -gt 0) {
        Add-StackedDockedControls -Container $Panel -ControlsTopToBottom @($controlsToStack) -Spacing 0
    }

    $totalHeight = 10
    foreach ($ctrl in $controlsToStack) { $totalHeight += $ctrl.Height }
    return $totalHeight
}

