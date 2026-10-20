Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace UiTestDwm {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
  public static class Api {
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, ref Rect rect, int size);
  }
}
"@

$script:ShotNo = 0

function Wait-UiTarget {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Target)
    Wait-Until -Message "部品 $Target" -Condition {
        $element = Find-UiElement -Parent $Window -Props @{ AutomationId = $Target }
        if (!$element) { $element = Find-UiElement -Parent $Window -Props @{ Name = $Target } }
        $element
    }
}

function Get-UiDiagnostics {
    param($Window)
    if (!$Window) { return "" }
    $all = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $items = @()
    foreach ($element in $all) {
        $name = $element.Current.Name
        if ($name) { $items += "$($element.Current.ControlType.ProgrammaticName):$name" }
        if ($items.Count -ge 40) { break }
    }
    return "`n  確認: ウィンドウ名=$($Window.Current.Name) / 部品の数=$($all.Count) / 名前のある部品=[$($items -join ' | ')]"
}

function Save-UiScreenshot {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Path)
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    $frame = New-Object UiTestDwm.Rect
    [void][UiTestDwm.Api]::DwmGetWindowAttribute($handle, 9, [ref]$frame, [System.Runtime.InteropServices.Marshal]::SizeOf([type][UiTestDwm.Rect]))
    $width = $frame.Right - $frame.Left
    $height = $frame.Bottom - $frame.Top
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($frame.Left, $frame.Top, 0, 0, $bitmap.Size)
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Save-UiEvidence {
    param($Context, $Element = $null)
    $script:ShotNo++
    $name = "{0}-{1:D2}.png" -f $Context.ScenarioId, $script:ShotNo
    $target = if ($Element) { $Element } else { $Context.Window }
    Save-UiScreenshot -Window $target -Path (Join-Path $Context.EvidenceDir $name)
    Write-UiLog "    エビデンス: $name"
}

function Invoke-UiStep {
    param($Step, $Context)
    Write-UiLog ("    操作: " + ($Step | ConvertTo-Json -Compress))
    switch ($Step.action) {
        "pressKey" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            Focus-UiWindow -Window $dialog
            Send-UiKeys -Keys $Step.key
            Start-Sleep -Milliseconds 500
            Save-UiEvidence -Context $Context
        }
        "typeAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Send-UiKeys -Keys "^a"
            if ($Step.value) { Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value) } else { Send-UiKeys -Keys "{DEL}" }
        }
        "expectDialogText" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            $text = Get-UiMessageText -Dialog $dialog
            Assert-True ($text.Contains($Step.contains)) "メッセージに「$($Step.contains)」が含まれる（実際: $text）"
            Save-UiEvidence -Context $Context
        }
        "writeFile" {
            $path = Join-Path $Context.Root $Step.path
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $Step.text -Encoding ASCII
        }
        "expectFileContains" {
            $path = Join-Path $Context.Root $Step.path
            Wait-Until -Message "ファイルの内容 $($Step.path)" -Condition { (Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw).Contains($Step.contains)) } | Out-Null
        }
        "deleteFile" {
            Remove-Item -LiteralPath (Join-Path $Context.Root $Step.path) -Force
        }
        "wait" {
            Start-Sleep -Milliseconds ([int]$Step.ms)
        }
        "pasteAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Set-Clipboard -Value $Step.value
            Send-UiKeys -Keys "^a"
            Send-UiKeys -Keys "^v"
        }
        "expectLogContains" {
            $dir = Join-Path $Context.Root $Step.path
            Wait-Until -Message "ログの内容 $($Step.contains)" -Condition {
                @(Get-ChildItem -LiteralPath $dir -Filter $Step.filter -File -ErrorAction SilentlyContinue | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).Contains($Step.contains) }).Count -gt 0
            } | Out-Null
        }
        "expectEditContains" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            Wait-Until -TimeoutSec $timeout -Message "欄に $($Step.text)" -Condition {
                @(Get-UiEditValues -Window $Context.Window | Where-Object { $_.Contains($Step.text) }).Count -gt 0
            } | Out-Null
        }
        "expectEditNotContains" {
            Start-Sleep -Milliseconds 1000
            $found = @(Get-UiEditValues -Window $Context.Window | Where-Object { $_.Contains($Step.text) })
            Assert-True ($found.Count -eq 0) "欄に $($Step.text) が含まれない"
        }
        "wheelAt" {
            Invoke-UiWheel -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y) -Delta ([int]$Step.delta)
        }
        "openFile" {
            Start-Process -FilePath (Join-Path $Context.Root $Step.path)
        }
        "excelWrite" {
            $file = Join-Path $Context.Root $Step.path
            $excel = New-Object -ComObject Excel.Application
            try {
                $excel.DisplayAlerts = $false
                $book = $excel.Workbooks.Open($file)
                $book.Worksheets.Item($Step.sheet).Range($Step.cell).Value2 = $Step.value
                $book.Save()
                $book.Close($false)
            } finally {
                $excel.Quit()
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
            }
        }
        "excelExpect" {
            $file = Join-Path $Context.Root $Step.path
            $excel = New-Object -ComObject Excel.Application
            try {
                $excel.DisplayAlerts = $false
                $book = $excel.Workbooks.Open($file, 0, $true)
                $value = [string]$book.Worksheets.Item($Step.sheet).Range($Step.cell).Value2
                $book.Close($false)
            } finally {
                $excel.Quit()
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
            }
            if ($Step.PSObject.Properties.Name -contains "equals") {
                Assert-Equal $Step.equals $value "セル $($Step.cell) の値"
            } else {
                Assert-True ($value -ne $Step.notEquals) "セル $($Step.cell) の値が $($Step.notEquals) ではない（実際: $value）"
            }
        }
        "keysAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Send-UiKeys -Keys $Step.keys
        }
        "expectTextPattern" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            Wait-Until -TimeoutSec $timeout -Message "表示 $($Step.pattern)" -Condition {
                $all = $Context.Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($element in $all) {
                    $name = $element.Current.Name
                    if ($name -and ($name -match $Step.pattern)) { return $true }
                }
                return $false
            } | Out-Null
        }
        "expectTextAt" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            $tolX = if ($Step.tolX) { [int]$Step.tolX } else { 60 }
            $tolY = if ($Step.tolY) { [int]$Step.tolY } else { 12 }
            Wait-Until -TimeoutSec $timeout -Message "位置 ($($Step.x),$($Step.y)) に $($Step.pattern)" -Condition {
                $top = $Context.Window.Current.BoundingRectangle.Top
                $left = $Context.Window.Current.BoundingRectangle.Left
                $all = $Context.Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($element in $all) {
                    $name = $element.Current.Name
                    if (-not $name -or -not ($name -match $Step.pattern)) { continue }
                    $rect = $element.Current.BoundingRectangle
                    if ($rect.IsEmpty) { continue }
                    $centerX = $rect.Left + $rect.Width / 2 - $left
                    $centerY = $rect.Top + $rect.Height / 2 - $top
                    if ([Math]::Abs($centerX - [int]$Step.x) -le $tolX -and [Math]::Abs($centerY - [int]$Step.y) -le $tolY) { return $true }
                }
                return $false
            } | Out-Null
        }
        "expectCheckedAt" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            $expected = [bool]$Step.checked
            Wait-Until -TimeoutSec $timeout -Message "チェック ($($Step.x),$($Step.y)) = $expected" -Condition {
                $rect = $Context.Window.Current.BoundingRectangle
                $bitmap = New-Object System.Drawing.Bitmap ([int]$rect.Width), ([int]$rect.Height)
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen([int]$rect.Left, [int]$rect.Top, 0, 0, $bitmap.Size)
                $blue = 0
                foreach ($offset in @(@(-5, 0), @(5, 0), @(0, -5), @(0, 5), @(-4, -4), @(4, -4), @(-4, 4), @(4, 4))) {
                    $px = [int]$Step.x + $offset[0]
                    $py = [int]$Step.y + $offset[1]
                    $color = $bitmap.GetPixel($px, $py)
                    if ($color.B -gt 150 -and $color.R -lt 60 -and $color.G -lt 150) { $blue++ }
                }
                $graphics.Dispose()
                $bitmap.Dispose()
                return (($blue -ge 2) -eq $expected)
            } | Out-Null
        }
        "makeDir" {
            New-Item -ItemType Directory -Path (Join-Path $Context.Root $Step.path) -Force | Out-Null
        }
        "copyFile" {
            $from = Join-Path $Context.Root $Step.from
            $to = Join-Path $Context.Root $Step.to
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
        "clickAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Save-UiEvidence -Context $Context
        }
        "shot" {
            Save-UiEvidence -Context $Context
        }
        "click" {
            $element = Wait-UiTarget -Window $Context.Window -Target $Step.target
            Invoke-UiClickElement -Element $element -Window $Context.Window
            Save-UiEvidence -Context $Context
        }
        "selectComboAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            if ($Step.value) { Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value) } else { Send-UiKeys -Keys "{HOME}" }
            Send-UiKeys -Keys "{ENTER}"
            Save-UiEvidence -Context $Context
        }
        "enterDialog" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            Focus-UiWindow -Window $dialog
            Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value)
            Save-UiEvidence -Context $Context
            Send-UiKeys -Keys "{ENTER}"
            Start-Sleep -Milliseconds 500
            Save-UiEvidence -Context $Context
        }
        "expectMessage" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            $text = Get-UiMessageText -Dialog $dialog
            Save-UiEvidence -Context $Context
            Assert-True ($text -like "*$($Step.contains)*") "メッセージに「$($Step.contains)」が含まれる（実際: $text）"
            Close-UiMessageBox -Dialog $dialog
            Start-Sleep -Milliseconds 300
            Save-UiEvidence -Context $Context
        }
        "expectText" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            Wait-Until -TimeoutSec $timeout -Message "表示 $($Step.text)" -Condition {
                Find-UiElement -Parent $Context.Window -Props @{ Name = $Step.text }
            } | Out-Null
        }
        "expectTextGone" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            Wait-Until -TimeoutSec $timeout -Message "消える $($Step.text)" -Condition {
                @(Find-UiElements -Parent $Context.Window -Props @{ Name = $Step.text }).Count -eq 0
            } | Out-Null
        }
        "expectLogFile" {
            $dir = Join-Path $Context.Root $Step.path
            Wait-Until -Message "ログファイル $($Step.path)" -Condition {
                @(Get-ChildItem -LiteralPath $dir -Filter *.log -File -ErrorAction SilentlyContinue).Count -gt 0
            } | Out-Null
        }
        "expectWindow" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            try {
                $found = Wait-Until -TimeoutSec $timeout -Message "ウィンドウ $($Step.title)" -Condition {
                    Find-UiElements -Props @{ ControlType = [System.Windows.Automation.ControlType]::Window } | Where-Object { $_.Current.Name -clike "*$($Step.title)*" } | Select-Object -First 1
                }
                Start-Sleep -Milliseconds 5000
                Write-UiLog ("    ウィンドウ: " + $found.Current.Name + " 位置=" + $found.Current.BoundingRectangle + " 画面外=" + $found.Current.IsOffscreen)
                Save-UiEvidence -Context $Context -Element $found
            } catch {
                $names = @(Find-UiElements -Props @{ ControlType = [System.Windows.Automation.ControlType]::Window } | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
                throw "$($_.Exception.Message) / 画面のウィンドウ=[$($names -join ' | ')]"
            }
        }
        "closeWindow" {
            $window = @(Find-UiElements -Props @{ ControlType = [System.Windows.Automation.ControlType]::Window } | Where-Object { $_.Current.Name -clike "*$($Step.title)*" }) | Select-Object -First 1
            if ($window) {
                Focus-UiWindow -Window $window
                Send-UiKeys -Keys $(if ($Step.keys) { $Step.keys } else { "%{F4}" })
            }
        }
        "expectFile" {
            $path = Join-Path $Context.Root $Step.path
            $expected = [bool]$Step.exists
            Wait-Until -Message "ファイルの有無 $($Step.path)" -Condition { (Test-Path -LiteralPath $path) -eq $expected } | Out-Null
        }
        default { throw "未対応の操作: $($Step.action)" }
    }
}

function Expand-UiStep {
    param($Step, $Vars, [string]$Root)
    $json = $Step | ConvertTo-Json -Compress -Depth 5
    $json = $json.Replace("{{root}}", ([string]$Root).Replace("\", "\\"))
    if ($Vars) {
        foreach ($name in $Vars.PSObject.Properties.Name) { $json = $json.Replace("{{$name}}", ([string]$Vars.$name).Replace("\", "\\")) }
    }
    return ($json | ConvertFrom-Json)
}

function Invoke-UiSetup {
    param($Scenario, [string]$Root)
    $index = 0
    foreach ($step in @($Scenario.setup)) {
        $index++
        $step = Expand-UiStep -Step $step -Vars $Scenario.vars -Root $Root
        try { Invoke-UiStep -Step $step -Context ([pscustomobject]@{ Root = $Root }) } catch { throw "準備 $index : $($_.Exception.Message)" }
    }
}

function Invoke-UiSteps {
    param($Scenario, $Context)
    $index = 0
    foreach ($step in @($Scenario.steps)) {
        $index++
        $step = Expand-UiStep -Step $step -Vars $Scenario.vars -Root $Context.Root
        try { Invoke-UiStep -Step $step -Context $Context } catch {
            $message = $_.Exception.Message
            if ($message -like "タイムアウト*") { $message += Get-UiDiagnostics -Window $Context.Window }
            throw "手順 $index : $message"
        }
    }
}
