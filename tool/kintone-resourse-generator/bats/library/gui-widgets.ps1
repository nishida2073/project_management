# どのGUIツールからでも使い回せる、業務内容に依存しないWinFormsの汎用部品を置く場所。
# 業務固有のデータ（ボタン定義の中身など）や実行フローはgui.ps1側に残す。

# 指定パスをエクスプローラーで開く。URL（http/https）の場合は既定のブラウザで開く。
# 存在しない・未指定の場合は警告ダイアログを出す
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

# コンソールカラー名（Write-Messageが使う[[COLOR:xxx]]タグの中身）をSystem.Drawing.Colorへ変換
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
        "White"       { [System.Drawing.Color]::Black } # 白背景のログ欄では白文字が見えなくなるため黒にする
        default       { [System.Drawing.Color]::Black }
    }
}

# 未捕捉の例外がbat/ps1の外まで伝播すると、PowerShell自身が「発生場所」「CategoryInfo」
# 「FullyQualifiedErrorId」を含む既定のエラー表示をそのまま標準出力に書く。これはWrite-Message
# を経由しないため[[COLOR:xxx]]タグが付かず、無視すると常に無色（黒）になってしまう。
# そこで見た目のパターンから「PowerShell既定のエラー表示らしき行」を検出し、赤で表示する。
# （最初の行だけでなく、後続の"発生場所"や"+ ..."の継続行もまとめて赤くするため状態を持つ）
$script:isInNativeErrorBlock = $false
function Test-NativeErrorLine {
    param([string]$Text)
    return $Text -match '^[A-Za-z][\w.-]*\s*:\s' -or $Text -match '^発生場所' -or $Text -match '^\s*\+'
}

# RichTextBoxへ1行追記する。行頭の"[[COLOR:xxx]]"タグを解釈して色を変え、常に末尾までスクロールする。
# "[[HIDE]]"タグは背景色と同じ色にして、機械可読用の行を視覚的に見えなくする。
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

# ログ表示用に設定済みのRichTextBoxを作る（Dock=Fill、等幅フォント、URLクリックで既定ブラウザを開く）
function New-LogTextBox {
    param(
        # Consolasは日本語グリフを持たずOSの代替フォントへ自動フォールバックするため、
        # 英数字部分と日本語部分でフォントが混在して見える。日本語グリフを持つ固定ピッチフォントに統一する
        [string]$FontFamily = "MS Gothic",
        [int]$FontSize = 9
    )
    $textBox = New-Object System.Windows.Forms.RichTextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $textBox.ReadOnly = $true
    # ReadOnly=$trueのRichTextBoxはOSのテーマによって背景がグレーになることがあるため、明示的に白にする
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.Font = New-Object System.Drawing.Font($FontFamily, $FontSize)
    $textBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $textBox.DetectUrls = $true
    $textBox.Add_LinkClicked({ [System.Diagnostics.Process]::Start($_.LinkText) })
    return $textBox
}

# ボタン群のEnabledを一括切り替え
function Set-ButtonsEnabled {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Button[]]$Buttons,
        [Parameter(Mandatory)][bool]$Enabled
    )
    foreach ($btn in $Buttons) { $btn.Enabled = $Enabled }
}

# ステータス表示用ラベルのテキストと文字色をまとめて設定
function Set-StatusLabelText {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Label]$Label,
        [Parameter(Mandatory)][string]$Text,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::Gray
    )
    $Label.Text = $Text
    $Label.ForeColor = $ForeColor
}

# New-CategoryTabControlのInputControlsから実際の値を取り出す。
# ComboBox（Optionsで作られた選択式の入力）は表示テキストではなく選択された項目のValueを返す
function Get-InputValue {
    param([Parameter(Mandatory)]$Control)
    if ($Control -is [System.Windows.Forms.ComboBox]) {
        if ($Control.SelectedItem) { return "$($Control.SelectedItem.Value)" }
        return ""
    }
    return $Control.Text
}

# WinFormsのDock仕様: 同じDock方向のコントロールは、後からAddしたものほど外側（画面端側）に配置され、
# Dock=Fillは常に他のDockが確定した後に残り全域へ解決される。この2点を踏まえないと、
# 個別にAddした場合にコントロール同士が重なって描画されることがある。
# $ControlsTopToBottomは「画面の上→下」の視覚的な並び順で渡す（最後の要素がDock=Fillで残り全域を埋める想定）。
function Add-StackedDockedControls {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Control]$Container,
        [Parameter(Mandatory)][System.Windows.Forms.Control[]]$ControlsTopToBottom
    )
    $Container.SuspendLayout()

    $fillControls = @($ControlsTopToBottom | Where-Object { $_.Dock -eq [System.Windows.Forms.DockStyle]::Fill })
    $topControls = @($ControlsTopToBottom | Where-Object { $_.Dock -ne [System.Windows.Forms.DockStyle]::Fill })

    foreach ($fillControl in $fillControls) { $Container.Controls.Add($fillControl) }
    # 視覚的に上に来るものほど後にAdd（＝逆順でAdd）することで、意図した上→下の並びになる
    for ($i = $topControls.Count - 1; $i -ge 0; $i--) {
        $Container.Controls.Add($topControls[$i])
    }

    $Container.ResumeLayout($true)
}

# カテゴリ（タブ）ごとにグループ化されたボタン群を持つTabControlを組み立てる。
# $CategoryDefsは [{ Label, ButtonDefs: [{ Label, OpenTarget, Inputs, ... }] }] の形。
# ButtonDefの中身は自由（Tagとしてそのままボタン/リンクに渡すだけで、業務ロジックは持たない）。
# Inputsを指定すると、実行ボタンの上にラベル付きの入力欄を追加できる（その分グループボックスが縦に高くなる）。
# 各Inputsの要素は { Name, Label, Default, LabelWidth, InputWidth, Options, ExistingControl, NewRow } の形
# （LabelWidth/InputWidthは省略可。Optionsを指定すると自由入力のTextBoxの代わりに、
#   Optionsの中から選ぶだけのComboBox（DropDownList）になる。Optionsの要素は { Text, Value } の形。
#   ExistingControlを指定すると、新規作成の代わりにそのコントロール（動的に選択肢を再読み込みする
#   ComboBoxなど、呼び出し側が既に持っているコントロール）をその行へ配置する。
#   NewRow = $trueを指定すると、その入力欄から新しい行に折り返す。1行に収まらないほど
#   入力欄が多いボタンでのみ使う）。
# 実行ボタンクリック時に$OnRunClickへButtonDefを渡す。$OnOpenClickを省略するとOpen-TargetOrWarnを使う。
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

    # 呼び出し側が既存のTabControlを渡した場合はそれに追記する（他のタブを先頭に置くなど、
    # 呼び出し側の都合で並び順を決めたい場合に使う。ps2exeビルドではTabPageCollection.Insert()が
    # NotSupportedExceptionになるため、後から並び替えず、最初から最終的な順序でAddしていく必要がある）
    $tabControl = $TabControl
    if (-not $tabControl) {
        $tabControl = New-Object System.Windows.Forms.TabControl
    }
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Top

    # 実行ボタン一覧はSet-RunButtonsEnabled側で一括enable/disableに使うだけで、Labelで
    # 個別に引く用途が無いため単純な配列にする。ステータスラベルと入力欄コントロールは、
    # Labelがカテゴリをまたいで重複し得るため、Labelをキーにしたハッシュテーブルではなく
    # 各ButtonDefオブジェクト自身にプロパティとして直接ひも付ける（呼び出し側はButtonDefを
    # 既に持っているので、Labelでの引き直しが不要になり取り違えが起きない）
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
                # TextBox/ComboBoxは指定したHeightを無視し、フォントに応じた高さに強制されるため、
                # Labelとの縦の中央を揃えるには生成後の実際のHeightを見て個別にY位置を計算する必要がある
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
                        # 動的に選択肢を再読み込みするComboBoxなど、呼び出し側が既に持っているコントロールを
                        # そのまま使う（新規作成しない）。呼び出し側が引き続き参照を保持できる
                        $inputCtrl = $inputDef.ExistingControl
                        $inputCtrl.Width = $inputWidth
                    } elseif ($inputDef.Options) {
                        # DataSource経由のバインドはコントロールがフォームに追加されBindingContextが
                        # 確定するまで反映されない（初期選択が効かない）ため、Itemsへ直接追加する方式にしている
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
                # OpenTargetは固定のフォルダパス文字列の他に、{ param($groupName) ... } という
                # スクリプトブロックも受け付ける（投稿ボタンのkintoneスレッドURLのように、選択中の
                # 対象グループによって開き先が変わる場合に使う）。後者の場合はここで対象グループの
                # 選択値を渡して実際に開くパス/URLへ解決する
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

    # タブごとにボタン数が異なるため、選択中のタブの実際の内容量に合わせてtabControl自体の高さを変え、
    # 下の（Dock=Fillな）ログ欄の開始位置がタブごとに動的に変わるようにする
    $updateTabHeight = {
        if ($tabControl.SelectedTab -and $tabControl.SelectedTab.Controls.Count -gt 0) {
            $tabControl.Height = $TabHeaderAllowance + $tabControl.SelectedTab.Controls[0].Height
            if ($tabControl.Parent) { $tabControl.Parent.PerformLayout() }
        }
    }.GetNewClosure()
    $tabControl.Add_SelectedIndexChanged($updateTabHeight)
    # 生成直後はまだ親に追加されておらずSelectedTabが解決できないことがあるため、
    # 初期表示分だけは先頭タブの高さを直接計算して設定する
    $tabControl.Height = $TabHeaderAllowance + (Get-CategoryPanelHeight -ButtonDefs $CategoryDefs[0].ButtonDefs)

    # StepStatusLabel/InputControlsは各ButtonDef自身のプロパティとして既に持たせているため、
    # ここでは返さない（呼び出し側は$ButtonDef.StepStatusLabel/$ButtonDef.InputControlsを直接使う）
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

    $logStagePanel = New-Object System.Windows.Forms.Panel
    $logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $logStagePanel.Height = 40 + 24 * $ButtonDefs.Count

    $lblLogExtra = New-Object System.Windows.Forms.Label
    $lblLogExtra.Text = $ExtraLabelText
    $lblLogExtra.AutoSize = $true
    $lblLogExtra.Location = New-Object System.Drawing.Point(20, 17)
    $logStagePanel.Controls.Add($lblLogExtra)

    $cmbLogExtra = New-Object System.Windows.Forms.ComboBox
    $cmbLogExtra.Location = New-Object System.Drawing.Point(100, 14)
    $cmbLogExtra.Size = New-Object System.Drawing.Size($ExtraComboWidth, 24)
    $cmbLogExtra.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $logStagePanel.Controls.Add($cmbLogExtra)

    $btnClearLogs = New-Object System.Windows.Forms.Button
    $btnClearLogs.Text = "ログをすべて削除"
    $btnClearLogs.Location = New-Object System.Drawing.Point((120 + $ExtraComboWidth), 13)
    $btnClearLogs.Size = New-Object System.Drawing.Size(140, 26)
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
        $radio.Location = New-Object System.Drawing.Point(20, (40 + 24 * $i))
        $logStagePanel.Controls.Add($radio)
        $radios += $radio
    }

    $TabPage.Controls.Add($logContentBox)
    $TabPage.Controls.Add($logStagePanel)

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
        [System.Windows.Forms.Panel]$Panel,
        [int]$StartY,
        [string]$RawValue
    )
    $groupName = $cmbSettingsGroupTarget.SelectedItem
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
    $settingsToolTip.SetToolTip($lbl, "MentionUserCodes")
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
        foreach ($opt in $mentionTypeOptions) { $cmbType.Items.Add($opt) | Out-Null }
        $cmbType.SelectedItem = if ($mentionTypeOptions -contains $row.Type) { $row.Type } else { "USER" }
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

function Add-TestPostButton {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [int]$Y,
        [Parameter(Mandatory)][scriptblock]$OnClick
    )
    $btnTestPost = New-Object System.Windows.Forms.Button
    $btnTestPost.Text = "テスト投稿"
    $btnTestPost.Location = New-Object System.Drawing.Point(40, $Y)
    $btnTestPost.Size = New-Object System.Drawing.Size(90, 24)
    $btnTestPost.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnTestPost.Add_Click({ & $OnClick }.GetNewClosure())
    $Panel.Controls.Add($btnTestPost)
}

function Render-SettingsFields {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [array]$Rows,
        [hashtable]$TextBoxes,
        [hashtable]$RadioVars = @{},
        [hashtable]$TrailingButtonVars = @{}
    )
    $Panel.Controls.Clear()
    $TextBoxes.Clear()

    $y = 10
    $lastGroup = ""
    foreach ($field in $Rows) {
        if ($field.Group -ne $lastGroup) {
            if ($lastGroup -ne "") {
                $y += 10
                $separator = New-Object System.Windows.Forms.Panel
                $separator.BackColor = [System.Drawing.Color]::LightGray
                $separator.Location = New-Object System.Drawing.Point(10, $y)
                $separator.Size = New-Object System.Drawing.Size(690, 2)
                $Panel.Controls.Add($separator)
                $y += 14
            }
            $lblGroup = New-Object System.Windows.Forms.Label
            $lblGroup.Text = $settingsGroupLabels[$field.Group]
            $lblGroup.AutoSize = $true
            $lblGroup.Location = New-Object System.Drawing.Point(10, $y)
            $lblGroup.Font = New-Object System.Drawing.Font($lblGroup.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
            $Panel.Controls.Add($lblGroup)
            $y += 28
            $lastGroup = $field.Group
        }

        if ($field.VarName -eq "MentionUserCodes") {
            $y = Add-MentionsEditor -Panel $Panel -StartY $y -RawValue "$($field.Value)"
            continue
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = if ($settingsVarLabels.ContainsKey($field.VarName)) { $settingsVarLabels[$field.VarName] } else { $field.VarName }
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(220, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $settingsToolTip.SetToolTip($lbl, $field.VarName)
        $Panel.Controls.Add($lbl)

        $isMultiline = $settingsMultilineVars -contains $field.VarName

        if ($RadioVars.ContainsKey($field.VarName)) {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = "$($field.Value)"
            $txt.Visible = $false
            $Panel.Controls.Add($txt)

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
                $settingsToolTip.SetToolTip($rbUnset, "空欄にすると共通設定の値を使用します")
                $radioPanel.Controls.Add($rbUnset)
            }

            $Panel.Controls.Add($radioPanel)
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
            if ($settingsMaskedVars -contains $field.VarName) { $txt.UseSystemPasswordChar = $true }
            $Panel.Controls.Add($txt)
        }

        if ($settingsFolderBrowseVars -contains $field.VarName) {
            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(560, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt
            $btnBrowse.Add_Click({
                $targetTxt = $this.Tag
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $startPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $rootPath -Resolver $script:commonEnvResolver
                if ($startPath -and (Test-Path -LiteralPath $startPath)) { $dlg.SelectedPath = $startPath }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetTxt.Text = $dlg.SelectedPath }
            })
            $Panel.Controls.Add($btnBrowse)
        }

        $TextBoxes[$field.Key] = $txt
        $y += if ($isMultiline) { 66 } else { 28 }

        if ($TrailingButtonVars.ContainsKey($field.VarName)) {
            & $TrailingButtonVars[$field.VarName] $Panel $y $field
            $y += 34
        }
    }
    return $y
}
