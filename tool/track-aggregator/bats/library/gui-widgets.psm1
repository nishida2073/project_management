# どのGUIツールからでも使い回せる、業務内容に依存しないWinFormsの汎用部品を置く場所。
# 業務固有のデータ（ボタン定義の中身など）や実行フローはgui.ps1側に残す。

# 指定パスをエクスプローラーで開く。存在しなければ警告ダイアログを出す
function Open-FolderOrWarn {
    param([string]$Path)
    if (!$Path -or !(Test-Path -LiteralPath $Path)) {
        [System.Windows.Forms.MessageBox]::Show("フォルダが見つかりません:`r`n$Path", "開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
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

# RichTextBoxへ1行追記する。行頭の"[[COLOR:xxx]]"タグを解釈して色を変え、常に末尾までスクロールする
function Write-ColoredLine {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.RichTextBox]$TextBox,
        [string]$Text
    )
    $color = [System.Drawing.Color]::Black
    if ($Text -match '^\[\[COLOR:(?<color>\w+)\]\](?<rest>.*)$') {
        $color = Get-ConsoleColorAsDrawingColor -ConsoleColorName $Matches['color']
        $Text = $Matches['rest']
    }
    $TextBox.SelectionStart = $TextBox.TextLength
    $TextBox.SelectionLength = 0
    $TextBox.SelectionColor = $color
    $TextBox.AppendText("$Text`r`n")
    $TextBox.SelectionStart = $TextBox.TextLength
    $TextBox.ScrollToCaret()
}

# ログ表示用に設定済みのRichTextBoxを作る（Dock=Fill、等幅フォント、URLクリックで既定ブラウザを開く）
function New-LogTextBox {
    param(
        [string]$FontFamily = "Consolas",
        [int]$FontSize = 9
    )
    $textBox = New-Object System.Windows.Forms.RichTextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $textBox.ReadOnly = $true
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
# $CategoryDefsは [{ Label, ButtonDefs: [{ Label, TargetDirPath, ... }] }] の形。
# ButtonDefの中身は自由（Tagとしてそのままボタン/リンクに渡すだけで、業務ロジックは持たない）。
# 実行ボタンクリック時に$OnRunClickへButtonDefを渡す。$OnOpenClickを省略するとOpen-FolderOrWarnを使う。
function New-CategoryTabControl {
    param(
        [Parameter(Mandatory)][array]$CategoryDefs,
        [Parameter(Mandatory)][scriptblock]$OnRunClick,
        [scriptblock]$OnOpenClick,
        [int]$GroupHeight = 60,
        [int]$GroupSpacing = 10,
        [int]$TabHeaderAllowance = 45,
        [string]$RunButtonText = "実行",
        [string]$OpenLinkText = "開く",
        [string]$InitialStatusText = "未実行"
    )

    if (-not $OnOpenClick) {
        $OnOpenClick = { param($path) Open-FolderOrWarn -Path $path }
    }

    $maxButtonCount = ($CategoryDefs | ForEach-Object { $_.ButtonDefs.Count } | Measure-Object -Maximum).Maximum

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Top
    $tabControl.Height = $TabHeaderAllowance + $GroupSpacing + (($GroupHeight + $GroupSpacing) * $maxButtonCount)

    $runButtons = @{}
    $stepStatusLabels = @{}

    foreach ($cd in $CategoryDefs) {
        $tabPage = New-Object System.Windows.Forms.TabPage
        $tabPage.Text = $cd.Label
        $tabControl.Controls.Add($tabPage)

        $buttonPanel = New-Object System.Windows.Forms.Panel
        $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
        $buttonPanel.Height = $GroupSpacing + (($GroupHeight + $GroupSpacing) * $cd.ButtonDefs.Count)
        $tabPage.Controls.Add($buttonPanel)

        $groupY = $GroupSpacing
        foreach ($bd in $cd.ButtonDefs) {
            $grp = New-Object System.Windows.Forms.GroupBox
            $grp.Text = $bd.Label
            $grp.Location = New-Object System.Drawing.Point(10, $groupY)
            $grp.Size = New-Object System.Drawing.Size(730, $GroupHeight)
            $grp.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
            $buttonPanel.Controls.Add($grp)

            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $RunButtonText
            $btn.Size = New-Object System.Drawing.Size(100, 30)
            $btn.Location = New-Object System.Drawing.Point(15, 20)
            $btn.Tag = $bd
            $btn.Add_Click({ & $OnRunClick $this.Tag }.GetNewClosure())
            $grp.Controls.Add($btn)
            $runButtons[$bd.Label] = $btn

            if ($bd.TargetDirPath) {
                $lnkOpen = New-Object System.Windows.Forms.LinkLabel
                $lnkOpen.Text = $OpenLinkText
                $lnkOpen.AutoSize = $false
                $lnkOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $lnkOpen.Size = New-Object System.Drawing.Size(60, 30)
                $lnkOpen.Location = New-Object System.Drawing.Point(125, 20)
                $lnkOpen.Tag = $bd
                $lnkOpen.Add_LinkClicked({ & $OnOpenClick $this.Tag.TargetDirPath }.GetNewClosure())
                $grp.Controls.Add($lnkOpen)
            }

            $lblStepStatus = New-Object System.Windows.Forms.Label
            $lblStepStatus.Text = $InitialStatusText
            $lblStepStatus.AutoSize = $false
            $lblStepStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $lblStepStatus.Size = New-Object System.Drawing.Size(150, 22)
            $lblStepStatus.Location = New-Object System.Drawing.Point(200, 24)
            $lblStepStatus.ForeColor = [System.Drawing.Color]::Gray
            $grp.Controls.Add($lblStepStatus)
            $stepStatusLabels[$bd.Label] = $lblStepStatus

            $groupY += $GroupHeight + $GroupSpacing
        }
    }

    return [PSCustomObject]@{
        TabControl       = $tabControl
        RunButtons       = $runButtons
        StepStatusLabels = $stepStatusLabels
    }
}
