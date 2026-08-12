#SingleInstance Force

url := A_Args[1]
dir := A_Args[2]

WinActivate "ahk_exe chrome.exe"
WinWaitActive "ahk_exe chrome.exe"

Sleep 300
Send "^t"
Sleep 1000

Send "^l"
Sleep 500

A_Clipboard := url
Send "^v"
Sleep 300
Send "{Enter}"

Sleep 2000

; チェック
if WinExist("A")
{
    title := WinGetTitle("A")
    if (InStr(title, "403") || InStr(title, "アクセスが拒否") || InStr(title, "nttdata-univ.train.tracks.run"))
    {
        CloseMyTab()
        ExitApp 1
    }
}

; 保存ダイアログ
WinWait "ahk_class #32770",,5
if !WinExist("ahk_class #32770")
{
    CloseMyTab()
    ExitApp 2
}

WinActivate
WinWaitActive "ahk_class #32770"
Sleep 300

Send "!d"
Sleep 300

A_Clipboard := dir
Send "^v"
Sleep 300
Send "{Enter}"

Sleep 300
Send "!s"

Sleep 1000

CloseMyTab()

ExitApp 0


CloseMyTab() {
    WinActivate "ahk_exe chrome.exe"
    WinWaitActive "ahk_exe chrome.exe"
    Sleep 300

    currentTitle := WinGetTitle("A")
    Sleep 200
    if (
        InStr(currentTitle, "新しいタブ")
        || InStr(currentTitle, "新しいシークレット タブ")
        ;  || InStr(currentTitle, "nttdata-univ.train.tracks.run")
    )
    {
        Send "^w"
    }
}